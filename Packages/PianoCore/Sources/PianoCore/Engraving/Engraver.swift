/// 譜面に描くための組版結果。座標は持たず、拍位置と全音階番号で表す（大きさに依存しない）。
public struct EngravedScore: Sendable {
    public private(set) var measures: [EngravedMeasure]
    /// 和音 id → 小節 index（タイの行き先を探すため）
    public private(set) var measureOfChord: [Int: Int]

    public init(score: Score) {
        measures = []
        measureOfChord = [:]
        let q = Double(score.ticksPerQuarter)

        var buckets = Array(repeating: [Note](), count: score.measures.count)
        for n in score.notes where !score.measures.isEmpty {
            buckets[score.measureIndex(atBeat: Double(n.startTick) / q)].append(n)
        }

        // タイの行き先: (staff, midi, 開始 tick) → note id
        var tieTargets: [TieKey: Int] = [:]
        for n in score.notes where n.tieStop {
            if let midi = n.midi { tieTargets[TieKey(staff: n.staff, midi: midi, tick: n.startTick)] = n.id }
        }

        var clefs: [Int: Clef] = [1: .treble, 2: .bass]
        var previousKey: KeySignature?
        var previousTime: TimeSignature?
        var chordOfNote: [Int: Int] = [:]
        var pendingTies: [(measure: Int, tie: EngravedTie, toNote: Int?)] = []

        for (mi, measure) in score.measures.enumerated() {
            var changed = Set<Int>()
            for (staff, clef) in measure.clefs where clefs[staff] != clef || mi == 0 {
                clefs[staff] = clef
                changed.insert(staff)
            }
            var em = EngravedMeasure(
                index: mi, number: measure.number,
                startBeat: Double(measure.startTick) / q, lengthBeats: Double(measure.lengthTicks) / q,
                clefs: clefs, clefChanged: changed,
                key: measure.key, keyChanged: previousKey != measure.key,
                time: measure.time, timeChanged: previousTime != measure.time)
            previousKey = measure.key
            previousTime = measure.time

            let notes = buckets[mi]
            Self.engrave(notes: notes, into: &em, q: q)
            for chord in em.chords {
                measureOfChord[chord.id] = mi
                for h in chord.heads { chordOfNote[h.noteId] = chord.id }
            }
            for n in notes where n.tieStart {
                guard let sp = n.spelling, let chordId = chordOfNote[n.id] else { continue }
                let target = tieTargets[TieKey(staff: n.staff, midi: sp.midi, tick: n.startTick + n.durationTicks)]
                let up = em.chords.first { $0.id == chordId }?.stemUp ?? true
                pendingTies.append((mi, EngravedTie(fromChord: chordId, toChord: nil, diatonic: sp.diatonic,
                                                    staff: n.staff, curveDown: up), target))
            }
            measures.append(em)
        }

        for item in pendingTies {
            var tie = item.tie
            tie.toChord = item.toNote.flatMap { chordOfNote[$0] }
            measures[item.measure].ties.append(tie)
        }
    }

    private struct TieKey: Hashable {
        var staff: Int
        var midi: Int
        var tick: Int
    }

    // MARK: - 1小節ぶんの組版

    private static func engrave(notes: [Note], into em: inout EngravedMeasure, q: Double) {
        let sorted = notes.sorted { ($0.startTick, $0.staff, $0.spelling?.diatonic ?? 0) < ($1.startTick, $1.staff, $1.spelling?.diatonic ?? 0) }
        let measureStart = em.startBeat

        // 譜表ごとの声部（複数あれば上の声部は符幹上向き）
        var voicesByStaff: [Int: Set<Int>] = [:]
        for n in sorted { voicesByStaff[n.staff, default: []].insert(n.voice) }
        func multiVoice(_ staff: Int) -> Bool { (voicesByStaff[staff]?.count ?? 0) > 1 }
        func isUpperVoice(_ n: Note) -> Bool { n.voice == voicesByStaff[n.staff]?.min() }

        // 臨時記号: 譜表ごとに 全音階番号 → 現在の変化
        var accidentalState: [Int: [Int: Int]] = [:]
        var accidentals: [Int: Accidental] = [:]
        for n in sorted {
            guard let sp = n.spelling else { continue }
            let current = accidentalState[n.staff]?[sp.diatonic] ?? em.key.alter(for: sp.step)
            if n.tieStop {
                // タイの続きには付けない
            } else if let explicit = n.accidental {
                accidentals[n.id] = explicit
            } else if sp.alter != current {
                accidentals[n.id] = Accidental(alter: sp.alter)
            }
            accidentalState[n.staff, default: [:]][sp.diatonic] = sp.alter
        }

        // 和音: 同じ譜表・声部・開始位置の音
        struct ChordKey: Hashable { var staff: Int; var voice: Int; var tick: Int }
        var chordNotes: [ChordKey: [Note]] = [:]
        var chordOrder: [ChordKey] = []
        for n in sorted {
            if n.isRest {
                let bottom = em.clefs[n.staff]?.bottomLineDiatonic ?? 30
                var d = n.restDiatonic ?? bottom + 4
                if n.restDiatonic == nil, multiVoice(n.staff) { d += isUpperVoice(n) ? 4 : -4 }
                em.rests.append(EngravedRest(
                    id: n.id, staff: n.staff, voice: n.voice, hand: n.hand,
                    offsetBeats: Double(n.startTick) / q - measureStart,
                    startBeat: Double(n.startTick) / q, endBeat: Double(n.startTick + n.durationTicks) / q,
                    noteType: n.noteType ?? NoteType.infer(beats: Double(n.durationTicks) / q).0,
                    dots: n.dots, diatonic: d, isMeasureRest: n.isMeasureRest))
                continue
            }
            let key = ChordKey(staff: n.staff, voice: n.voice, tick: n.startTick)
            if chordNotes[key] == nil { chordOrder.append(key) }
            chordNotes[key, default: []].append(n)
        }

        for key in chordOrder {
            let group = chordNotes[key]!
            let first = group[0]
            let bottom = em.clefs[key.staff]?.bottomLineDiatonic ?? 30
            let (inferredType, inferredDots) = NoteType.infer(beats: Double(first.durationTicks) / q)
            let heads = group.compactMap { n -> EngravedHead? in
                guard let sp = n.spelling else { return nil }
                return EngravedHead(noteId: n.id, diatonic: sp.diatonic, accidental: accidentals[n.id],
                                    startBeat: Double(n.startTick) / q,
                                    endBeat: Double(n.startTick + n.durationTicks) / q)
            }.sorted { $0.diatonic < $1.diatonic }

            let stemUp: Bool
            if let explicit = group.compactMap(\.stemUp).first {
                stemUp = explicit
            } else if multiVoice(key.staff) {
                stemUp = isUpperVoice(first)
            } else {
                stemUp = Self.naturalStemUp(diatonics: heads.map(\.diatonic), middle: bottom + 4)
            }
            em.chords.append(EngravedChord(
                id: group.map(\.id).min()!, staff: key.staff, voice: key.voice, hand: first.hand,
                offsetBeats: Double(key.tick) / q - measureStart,
                startBeat: Double(key.tick) / q, endBeat: Double(key.tick + first.durationTicks) / q,
                noteType: first.noteType ?? inferredType,
                dots: first.noteType == nil ? inferredDots : first.dots,
                heads: heads, stemUp: stemUp, hasExplicitStem: group.contains { $0.stemUp != nil },
                beamValue: first.beams[1]))
        }

        makeBeams(&em)
        for i in em.chords.indices { layoutHeads(&em.chords[i]) }
    }

    /// 符幹の向き: 中央線から一番遠い音が中央線より下なら上向き（同じなら下向き）
    static func naturalStemUp(diatonics: [Int], middle: Int) -> Bool {
        guard let lo = diatonics.min(), let hi = diatonics.max() else { return true }
        let below = middle - lo
        let above = hi - middle
        if below == above { return lo < middle && hi < middle }
        return below > above
    }

    /// 連桁のまとまりを決める。<beam> があればそれに従い、無ければ拍単位でまとめる。
    private static func makeBeams(_ em: inout EngravedMeasure) {
        var byVoice: [[Int]] = []  // chords の index
        var keyIndex: [String: Int] = [:]
        for (i, c) in em.chords.enumerated() {
            let k = "\(c.staff)-\(c.voice)"
            if let j = keyIndex[k] { byVoice[j].append(i) } else { keyIndex[k] = byVoice.count; byVoice.append([i]) }
        }
        let beatUnit: Double = {
            let t = em.time
            if t.beatType == 8, t.beats % 3 == 0, t.beats > 3 { return 1.5 }
            return t.beatUnit
        }()

        var groups: [[Int]] = []
        for indices in byVoice {
            let explicit = indices.contains { em.chords[$0].beamValue != nil }
            var current: [Int] = []
            func close() {
                if current.count >= 2 { groups.append(current) }
                current = []
            }
            for i in indices {
                let c = em.chords[i]
                if explicit {
                    switch c.beamValue {
                    case .begin?: close(); current = [i]
                    case .continue?: if !current.isEmpty { current.append(i) }
                    case .end?: if !current.isEmpty { current.append(i) }; close()
                    default: close()
                    }
                } else {
                    guard c.noteType.beamCount > 0 else { close(); continue }
                    if let last = current.last {
                        let p = em.chords[last]
                        let sameBeat = Int((p.offsetBeats / beatUnit + 1e-6).rounded(.down))
                            == Int((c.offsetBeats / beatUnit + 1e-6).rounded(.down))
                        if !(sameBeat && abs(p.endBeat - c.startBeat) < 1e-6) { close() }
                    }
                    current.append(i)
                }
            }
            close()
        }

        for g in groups {
            let ids = g.map { em.chords[$0].id }
            let up: Bool
            if let e = g.first(where: { em.chords[$0].hasExplicitStem }) {
                up = em.chords[e].stemUp
            } else {
                let staff = em.chords[g[0]].staff
                let middle = (em.clefs[staff]?.bottomLineDiatonic ?? 30) + 4
                up = naturalStemUp(diatonics: g.flatMap { em.chords[$0].heads.map(\.diatonic) }, middle: middle)
            }
            for i in g {
                em.chords[i].stemUp = up
                em.chords[i].isBeamed = true
            }
            em.beams.append(BeamGroup(chordIDs: ids, stemUp: up))
        }
    }

    /// 2度でぶつかる符頭を符幹の反対側へずらし、臨時記号の列を決める
    private static func layoutHeads(_ chord: inout EngravedChord) {
        var heads = chord.heads
        let order = chord.stemUp ? Array(heads.indices) : Array(heads.indices.reversed())
        var previous: Int?
        for i in order {
            if let p = previous, abs(heads[i].diatonic - heads[p].diatonic) == 1, !heads[p].shifted {
                heads[i].shifted = true
            }
            previous = i
        }
        // 臨時記号: 上から順に、近い（6度以内）記号と重ならない列へ
        var columns: [[Int]] = []
        for i in heads.indices.reversed() where heads[i].accidental != nil {
            let d = heads[i].diatonic
            var col = 0
            while col < columns.count, columns[col].contains(where: { abs($0 - d) < 6 }) { col += 1 }
            if col == columns.count { columns.append([]) }
            columns[col].append(d)
            heads[i].accidentalColumn = col
        }
        chord.heads = heads
    }
}

public struct EngravedMeasure: Sendable {
    public var index: Int
    public var number: String
    public var startBeat: Double
    public var lengthBeats: Double
    /// 小節の始めで有効な音部記号（staff → clef）
    public var clefs: [Int: Clef]
    public var clefChanged: Set<Int>
    public var key: KeySignature
    public var keyChanged: Bool
    public var time: TimeSignature
    public var timeChanged: Bool
    public var chords: [EngravedChord] = []
    public var rests: [EngravedRest] = []
    public var beams: [BeamGroup] = []
    /// この小節から始まるタイ
    public var ties: [EngravedTie] = []

    public var endBeat: Double { startBeat + lengthBeats }
}

public struct EngravedHead: Sendable {
    public var noteId: Int
    public var diatonic: Int
    public var accidental: Accidental?
    public var startBeat: Double
    public var endBeat: Double
    /// 符幹の反対側にずらす（2度の音）
    public var shifted = false
    /// 臨時記号の列（0 が符頭に一番近い）
    public var accidentalColumn = 0
}

public struct EngravedChord: Sendable, Identifiable {
    public let id: Int
    public var staff: Int
    public var voice: Int
    public var hand: Hand
    /// 小節の始めからの拍
    public var offsetBeats: Double
    public var startBeat: Double
    public var endBeat: Double
    public var noteType: NoteType
    public var dots: Int
    /// 低い順
    public var heads: [EngravedHead]
    public var stemUp: Bool
    public var hasExplicitStem: Bool
    var beamValue: BeamValue?
    public var isBeamed = false

    public var flagCount: Int { isBeamed ? 0 : noteType.beamCount }
}

public struct EngravedRest: Sendable, Identifiable {
    public let id: Int
    public var staff: Int
    public var voice: Int
    public var hand: Hand
    public var offsetBeats: Double
    public var startBeat: Double
    public var endBeat: Double
    public var noteType: NoteType
    public var dots: Int
    /// 表示位置（中央線基準。全休符・2分休符の位置合わせは描画側で行う）
    public var diatonic: Int
    public var isMeasureRest: Bool
}

public struct BeamGroup: Sendable {
    public var chordIDs: [Int]
    public var stemUp: Bool
}

public struct EngravedTie: Sendable {
    public var fromChord: Int
    /// nil なら行き先が見つからない（小節の終わりまで描く）
    public var toChord: Int?
    public var diatonic: Int
    public var staff: Int
    /// 符幹が上向きなら弧は下へ
    public var curveDown: Bool
}
