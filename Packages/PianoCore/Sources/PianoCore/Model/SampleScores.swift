public enum SampleScores {
    /// デザインの仮データ「歓喜の歌」冒頭4小節（4/4、ハ長調）。
    public static let odeToJoy: Score = {
        // [開始拍, 長さ(拍), MIDI]
        let right: [(Double, Double, Int)] = [
            (0, 1, 64), (1, 1, 64), (2, 1, 65), (3, 1, 67),
            (4, 1, 67), (5, 1, 65), (6, 1, 64), (7, 1, 62),
            (8, 1, 60), (9, 1, 60), (10, 1, 62), (11, 1, 64),
            (12, 1.5, 64), (13.5, 0.5, 62), (14, 2, 62),
        ]
        let left: [(Double, Double, Int)] = [
            (0, 4, 48), (0, 4, 55), (4, 4, 47), (4, 4, 55),
            (8, 4, 48), (8, 4, 55), (12, 4, 47), (12, 4, 55),
        ]
        let tpq = 480
        var notes: [Note] = []
        for (hand, list) in [(Hand.right, right), (Hand.left, left)] {
            for (start, length, midi) in list {
                let (type, dots) = NoteType.infer(beats: length)
                notes.append(Note(id: notes.count, startTick: Int(start * Double(tpq)),
                                  durationTicks: Int(length * Double(tpq)), spelling: Spelling(midi: midi),
                                  hand: hand, staff: hand == .right ? 1 : 2,
                                  noteType: type, dots: dots))
            }
        }
        let measures = (0..<4).map {
            Measure(index: $0, number: String($0 + 1), startTick: $0 * 4 * tpq, lengthTicks: 4 * tpq,
                    time: .fourFour, key: KeySignature(fifths: 0),
                    clefs: $0 == 0 ? [1: .treble, 2: .bass] : [:])
        }
        return Score(title: "歓喜の歌", composer: "L. v. Beethoven", ticksPerQuarter: tpq,
                     tempoMap: TempoMap(bpm: 120), measures: measures, notes: notes)
    }()
}
