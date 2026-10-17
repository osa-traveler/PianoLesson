public enum KeyHighlight: Equatable, Sendable {
    /// 1拍以内に弾く
    case upcoming(Hand)
    /// 譜面上で発音中
    case sounding(Hand)
}

public enum KeyStates {
    /// 各鍵の表示状態。発音中は予告より優先する。
    /// 練習しない手（自動演奏）は発音中だけ表示する。
    public static func compute(score: Score, beat: Double, hands: HandsMode,
                               upcomingWindow: Double = 1) -> [Int: KeyHighlight] {
        var result: [Int: KeyHighlight] = [:]
        for n in score.playNotes(overlapping: beat, beat + upcomingWindow + 1e-9) {
            if n.startBeat <= beat, beat < n.endBeat {
                if case .sounding = result[n.midi] { continue }
                result[n.midi] = .sounding(n.hand)
            } else if n.startBeat > beat, hands.practices(n.hand), result[n.midi] == nil {
                result[n.midi] = .upcoming(n.hand)
            }
        }
        return result
    }

    /// 次に弾く音（同時に複数あれば全部）。練習する手の音だけ。
    public static func nextNotes(score: Score, beat: Double, hands: HandsMode) -> [PlayNote] {
        let eps = 1e-6
        var first: Double?
        var result: [PlayNote] = []
        for n in score.playNotes(overlapping: beat, score.lengthBeats + 1) {
            guard n.startBeat > beat + eps, hands.practices(n.hand) else { continue }
            if let f = first {
                if n.startBeat > f + eps { break }
            } else {
                first = n.startBeat
            }
            result.append(n)
        }
        return result
    }
}
