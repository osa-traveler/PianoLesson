/// 読み込んだ1曲。時間は tick で持ち、拍（四分音符=1.0）へは ticksPerQuarter で換算する。
public struct Score: Sendable {
    public var title: String
    public var composer: String?
    public var ticksPerQuarter: Int
    public var tempoMap: TempoMap
    public var measures: [Measure]
    /// 譜面に書かれた全音符・休符（開始 tick 順）
    public private(set) var notes: [Note]
    /// 鳴らす音（開始拍順、同時なら低い順）
    public private(set) var playNotes: [PlayNote]
    /// playNotes の最長の長さ（範囲検索に使う）
    public private(set) var maxPlayLength: Double

    public init(title: String, composer: String? = nil, ticksPerQuarter: Int,
                tempoMap: TempoMap, measures: [Measure], notes: [Note]) {
        self.title = title
        self.composer = composer
        self.ticksPerQuarter = ticksPerQuarter
        self.tempoMap = tempoMap
        self.measures = measures
        self.notes = notes.sorted { ($0.startTick, $0.id) < ($1.startTick, $1.id) }
        self.playNotes = []
        self.maxPlayLength = 0
        self.playNotes = Self.makePlayNotes(self.notes, tpq: ticksPerQuarter)
        self.maxPlayLength = playNotes.map(\.lengthBeats).max() ?? 0
    }

    public func beat(ofTick tick: Int) -> Double { Double(tick) / Double(ticksPerQuarter) }

    public var lengthBeats: Double {
        guard let last = measures.last else { return 0 }
        return beat(ofTick: last.startTick + last.lengthTicks)
    }

    public func startBeat(of measure: Measure) -> Double { beat(ofTick: measure.startTick) }
    public func endBeat(of measure: Measure) -> Double { beat(ofTick: measure.startTick + measure.lengthTicks) }

    /// 拍位置を含む小節の index。曲の前なら 0、後なら最後の小節。
    public func measureIndex(atBeat beat: Double) -> Int {
        guard !measures.isEmpty else { return 0 }
        let tick = beat * Double(ticksPerQuarter)
        var lo = 0, hi = measures.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Double(measures[mid].startTick) <= tick { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public var midiRange: ClosedRange<Int>? {
        guard let lo = playNotes.map(\.midi).min(), let hi = playNotes.map(\.midi).max() else { return nil }
        return lo...hi
    }

    /// [from, to) と重なる音。
    public func playNotes(overlapping from: Double, _ to: Double) -> ArraySlice<PlayNote> {
        let earliest = from - maxPlayLength
        var lo = 0, hi = playNotes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if playNotes[mid].startBeat < earliest { lo = mid + 1 } else { hi = mid }
        }
        var end = lo
        while end < playNotes.count, playNotes[end].startBeat < to { end += 1 }
        return playNotes[lo..<end]
    }

    private static func makePlayNotes(_ notes: [Note], tpq: Int) -> [PlayNote] {
        // タイの続き（tieStop）を、同じ手・同じ音高で直前に終わる音へつなぐ
        struct Open { var index: Int; var endTick: Int }
        var result: [PlayNote] = []
        var openTies: [Int: Open] = [:]  // key: midi * 2 + hand
        let q = Double(tpq)
        for n in notes {
            guard let sp = n.spelling, n.durationTicks > 0 else { continue }
            let key = sp.midi * 2 + (n.hand == .right ? 0 : 1)
            if n.tieStop, let open = openTies[key], open.endTick == n.startTick {
                result[open.index].lengthBeats += Double(n.durationTicks) / q
                openTies[key] = n.tieStart ? Open(index: open.index, endTick: n.startTick + n.durationTicks) : nil
                continue
            }
            result.append(PlayNote(id: n.id, startBeat: Double(n.startTick) / q,
                                   lengthBeats: Double(n.durationTicks) / q, spelling: sp, hand: n.hand))
            if n.tieStart {
                openTies[key] = Open(index: result.count - 1, endTick: n.startTick + n.durationTicks)
            }
        }
        return result.sorted { ($0.startBeat, $0.midi) < ($1.startBeat, $1.midi) }
    }
}
