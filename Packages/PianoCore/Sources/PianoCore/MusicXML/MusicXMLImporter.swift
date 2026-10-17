import Foundation

public enum MusicXMLError: Error, LocalizedError {
    case invalidXML(String)
    case unsupported(String)
    case noParts

    public var errorDescription: String? {
        switch self {
        case .invalidXML(let m): "MusicXML として読めません。\(m)"
        case .unsupported(let m): m
        case .noParts: "楽譜にパートがありません。"
        }
    }
}

/// 読み込み結果。読み飛ばした内容は warnings にまとめ、画面に一度だけ出す。
public struct ImportResult: Sendable {
    public var score: Score
    public var warnings: [String]
}

/// MusicXML（score-partwise）を仕様 9.1 の範囲で読む。不整合があっても止めない。
public enum MusicXMLImporter {
    public static let ticksPerQuarter = 480

    /// .musicxml / .xml / .mxl を拡張子に関係なく中身で判定して読む
    public static func load(data: Data, fallbackTitle: String) throws -> ImportResult {
        if data.starts(with: [0x50, 0x4B]) {
            let zip = try ZipArchive(data: data)
            let rootPath = try rootFilePath(in: zip)
            return try parse(xml: zip.contents(of: rootPath), fallbackTitle: fallbackTitle)
        }
        return try parse(xml: data, fallbackTitle: fallbackTitle)
    }

    static func rootFilePath(in zip: ZipArchive) throws -> String {
        if let container = try? zip.contents(of: "META-INF/container.xml"),
           let root = try? XMLElementNode.parse(container),
           let path = root.descendant("rootfiles/rootfile")?.attributes["full-path"] {
            return path
        }
        if let entry = zip.entries.first(where: {
            !$0.path.hasPrefix("META-INF/") && ($0.path.hasSuffix(".xml") || $0.path.hasSuffix(".musicxml"))
        }) {
            return entry.path
        }
        throw MusicXMLError.unsupported(".mxl の中に楽譜が見つかりません。")
    }

    public static func parse(xml: Data, fallbackTitle: String) throws -> ImportResult {
        let root = try XMLElementNode.parse(xml)
        if root.name == "score-timewise" {
            throw MusicXMLError.unsupported("score-timewise 形式には対応していません。")
        }
        guard root.name == "score-partwise" else {
            throw MusicXMLError.unsupported("MusicXML の楽譜ではありません（\(root.name)）。")
        }
        let parts = root.children("part")
        guard !parts.isEmpty else { throw MusicXMLError.noParts }

        var warnings: [String] = []
        // staves=2 の最初のパート（ピアノ）。無ければ最初のパート
        let pianoPart = parts.first { part in
            part.children("measure").prefix(1).flatMap { $0.children("attributes") }.contains { $0.int("staves") == 2 }
        }
        let part = pianoPart ?? parts[0]
        if parts.count > 1 {
            let name = partName(root, id: part.attributes["id"]) ?? part.attributes["id"] ?? ""
            warnings.append("パートが\(parts.count)つあります。「\(name)」だけを使います。")
        }

        var builder = PartBuilder()
        builder.read(part)
        warnings += builder.warnings

        let title = root.descendant("work/work-title")?.text.trimmed.nonEmpty
            ?? root.string("movement-title")?.nonEmpty
            ?? fallbackTitle
        let composer = root.child("identification")?.children("creator")
            .first { $0.attributes["type"] == "composer" }?.text.trimmed.nonEmpty
        let tempo = TempoMap(changes: builder.tempoChanges.map {
            (Double($0.tick) / Double(ticksPerQuarter), $0.bpm)
        })
        let score = Score(title: title, composer: composer, ticksPerQuarter: ticksPerQuarter,
                          tempoMap: tempo, measures: builder.measures, notes: builder.notes)
        return ImportResult(score: score, warnings: warnings)
    }

    private static func partName(_ root: XMLElementNode, id: String?) -> String? {
        root.child("part-list")?.children("score-part").first { $0.attributes["id"] == id }?.string("part-name")
    }
}

/// 1パートを小節ごとに読む
private struct PartBuilder {
    let tpq = MusicXMLImporter.ticksPerQuarter
    var measures: [Measure] = []
    var notes: [Note] = []
    var tempoChanges: [(tick: Int, bpm: Double)] = []
    var warnings: [String] = []

    private var divisions = 1
    private var time = TimeSignature.fourFour
    private var key = KeySignature(fifths: 0)
    private var staves = 1
    private var measureStart = 0
    private var irregular: [String] = []
    private var graceCount = 0
    private var hasRepeats = false

    mutating func read(_ part: XMLElementNode) {
        for (index, m) in part.children("measure").enumerated() {
            readMeasure(m, index: index)
        }
        if !irregular.isEmpty {
            let list = irregular.prefix(8).joined(separator: "、") + (irregular.count > 8 ? " ほか" : "")
            warnings.append("拍子と長さが合わない小節があります（\(list)）。")
        }
        if graceCount > 0 { warnings.append("装飾音 \(graceCount)個は読み飛ばしました。") }
        if hasRepeats { warnings.append("繰り返し記号は展開せず、書かれている順に並べました。") }
    }

    private func ticks(_ duration: Int) -> Int {
        Int((Double(duration) * Double(tpq) / Double(max(divisions, 1))).rounded())
    }

    private mutating func readMeasure(_ m: XMLElementNode, index: Int) {
        var pos = 0
        var maxPos = 0
        var lastStart = 0
        var clefs: [Int: Clef] = [:]
        var measureTime = time
        let number = m.attributes["number"] ?? String(index + 1)

        for e in m.children {
            switch e.name {
            case "attributes":
                if let d = e.int("divisions"), d > 0 { divisions = d }
                if let s = e.int("staves") { staves = s }
                if let k = e.child("key")?.int("fifths") { key = KeySignature(fifths: k) }
                if let t = e.child("time"), let beats = t.string("beats"), let type = t.int("beat-type") {
                    // 「3+2」のような複合拍子は合計する
                    let total = beats.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
                    if total > 0 {
                        time = TimeSignature(beats: total, beatType: type)
                        if pos == 0 { measureTime = time }
                    }
                }
                for c in e.children("clef") {
                    let staff = Int(c.attributes["number"] ?? "1") ?? 1
                    let sign = ClefSign(rawValue: c.string("sign") ?? "G") ?? .g
                    let line = c.int("line") ?? (sign == .f ? 4 : sign == .c ? 3 : 2)
                    clefs[staff] = Clef(sign: sign, line: line)
                }
            case "note":
                if e.has("grace") { graceCount += 1; continue }
                if e.has("cue") { continue }
                let duration = ticks(e.int("duration") ?? 0)
                let start: Int
                if e.has("chord") {
                    start = lastStart
                } else {
                    start = pos
                    lastStart = pos
                    pos += duration
                    maxPos = max(maxPos, pos)
                }
                appendNote(e, start: measureStart + start, duration: duration)
            case "backup":
                pos = max(0, pos - ticks(e.int("duration") ?? 0))
            case "forward":
                pos += ticks(e.int("duration") ?? 0)
                maxPos = max(maxPos, pos)
            case "direction":
                for s in e.children("sound") { readTempo(s, at: measureStart + pos) }
                if e.child("sound")?.attributes["tempo"] == nil,
                   let metronome = e.descendant("direction-type/metronome"),
                   let perMinute = metronome.double("per-minute"),
                   let unit = metronome.string("beat-unit") {
                    let factor: Double = ["half": 2, "quarter": 1, "eighth": 0.5, "whole": 4][unit] ?? 1
                    let dotted = metronome.has("beat-unit-dot") ? 1.5 : 1
                    addTempo(perMinute * factor * dotted, at: measureStart + pos)
                }
            case "sound":
                readTempo(e, at: measureStart + pos)
            case "barline":
                if e.has("repeat") || e.has("ending") { hasRepeats = true }
            default:
                break
            }
        }

        // 小節の長さ: 実際に書かれた長さと拍子を比べて決める
        let nominal = Int((measureTime.measureLength * Double(tpq)).rounded())
        var length = nominal
        if maxPos > nominal {
            length = maxPos
            irregular.append(number)
        } else if maxPos < nominal, maxPos > 0 {
            if index == 0 || m.attributes["implicit"] == "yes" {
                length = maxPos  // 弱起
            } else {
                irregular.append(number)
            }
        }
        if index == 0 {
            if clefs[1] == nil { clefs[1] = .treble }
            if staves >= 2, clefs[2] == nil { clefs[2] = .bass }
        }
        measures.append(Measure(index: index, number: number, startTick: measureStart, lengthTicks: length,
                                time: measureTime, key: key, clefs: clefs))
        measureStart += length
    }

    private mutating func readTempo(_ sound: XMLElementNode, at tick: Int) {
        if let t = sound.attributes["tempo"].flatMap(Double.init) { addTempo(t, at: tick) }
    }

    private mutating func addTempo(_ bpm: Double, at tick: Int) {
        guard bpm > 0 else { return }
        if let last = tempoChanges.last, last.tick == tick { tempoChanges.removeLast() }
        tempoChanges.append((tick, bpm))
    }

    private mutating func appendNote(_ e: XMLElementNode, start: Int, duration: Int) {
        let staff = e.int("staff") ?? 1
        let hand: Hand = staves >= 2 && staff >= 2 ? .left : .right
        var spelling: Spelling?
        var restDiatonic: Int?
        if let p = e.child("pitch"), let step = Step(letter: p.string("step") ?? ""), let octave = p.int("octave") {
            let alter = Int((p.double("alter") ?? 0).rounded())
            spelling = Spelling(step: step, alter: alter, octave: octave)
        } else if let r = e.child("rest") {
            if let step = Step(letter: r.string("display-step") ?? ""), let octave = r.int("display-octave") {
                restDiatonic = octave * 7 + step.rawValue
            }
        } else {
            return  // unpitched など
        }

        let ties = e.children("tie").map { $0.attributes["type"] }
            + (e.child("notations")?.children("tied").map { $0.attributes["type"] } ?? [])
        var beams: [Int: BeamValue] = [:]
        for b in e.children("beam") {
            if let value = BeamValue(rawValue: b.text.trimmed) {
                beams[Int(b.attributes["number"] ?? "1") ?? 1] = value
            }
        }
        let stem = e.string("stem")
        notes.append(Note(
            id: notes.count, startTick: start, durationTicks: duration, spelling: spelling, hand: hand,
            staff: staff, voice: e.int("voice") ?? 1,
            noteType: e.string("type").flatMap { NoteType(rawValue: $0 == "long" ? "breve" : $0) },
            dots: e.children("dot").count,
            tieStart: ties.contains("start"), tieStop: ties.contains("stop"),
            fingering: e.descendant("notations/technical/fingering").flatMap { Int($0.text.trimmed) },
            accidental: e.string("accidental").flatMap(Self.accidental),
            stemUp: stem == "up" ? true : stem == "down" ? false : nil,
            beams: beams, restDiatonic: restDiatonic,
            isMeasureRest: e.child("rest")?.attributes["measure"] == "yes"))
    }

    private static func accidental(_ text: String) -> Accidental? {
        switch text {
        case "sharp": .sharp
        case "flat": .flat
        case "natural": .natural
        case "double-sharp", "sharp-sharp": .doubleSharp
        case "flat-flat", "double-flat": .doubleFlat
        default: nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
