public enum PlaybackEvent: Equatable, Sendable {
    case noteOff(midi: Int, hand: Hand)
    case noteOn(midi: Int, hand: Hand)
    case click(accent: Bool)
}

/// 拍の区間 (from, to] で起きる発音・消音・メトロノーム。同じ拍では消音を先にする。
public enum PlaybackPlanner {
    public static func events(score: Score, from: Double, to: Double, settings: PracticeSettings) -> [PlaybackEvent] {
        guard to > from else { return [] }
        var timed: [(beat: Double, order: Int, event: PlaybackEvent)] = []
        for n in score.playNotes(overlapping: from, to + 1e-9) where settings.appPlays(n.hand) {
            if n.endBeat > from, n.endBeat <= to {
                timed.append((n.endBeat, 0, .noteOff(midi: n.midi, hand: n.hand)))
            }
            if n.startBeat > from, n.startBeat <= to {
                timed.append((n.startBeat, 1, .noteOn(midi: n.midi, hand: n.hand)))
            }
        }
        if settings.metronomeOn {
            for (beat, accent) in clickBeats(score: score, from: from, to: to) {
                timed.append((beat, 2, .click(accent: accent)))
            }
        }
        return timed.sorted { ($0.beat, $0.order) < ($1.beat, $1.order) }.map(\.event)
    }

    /// メトロノームの拍（拍子記号の1拍ごと、小節の頭は強拍）。曲の前は最初の小節の拍子で数える。
    public static func clickBeats(score: Score, from: Double, to: Double) -> [(Double, Bool)] {
        guard let first = score.measures.first, to > from else { return [] }
        var result: [(Double, Bool)] = []
        let start0 = score.startBeat(of: first)
        if from < start0 {
            let unit = first.time.beatUnit
            let length = first.time.measureLength
            var k = Int(((start0 - from) / unit).rounded(.down))
            while k >= 1 {
                let b = start0 - Double(k) * unit
                if b > from, b <= to {
                    let fromStart = Double(k) * unit
                    let accent = abs(fromStart / length - (fromStart / length).rounded()) < 1e-6
                    result.append((b, accent))
                }
                k -= 1
            }
        }
        let firstIndex = score.measureIndex(atBeat: max(from, start0))
        for m in score.measures[firstIndex...] {
            let s = score.startBeat(of: m)
            if s > to { break }
            let e = score.endBeat(of: m)
            var b = s
            var i = 0
            while b < e - 1e-6 {
                if b > from, b <= to { result.append((b, i == 0)) }
                b += m.time.beatUnit
                i += 1
            }
        }
        return result
    }
}
