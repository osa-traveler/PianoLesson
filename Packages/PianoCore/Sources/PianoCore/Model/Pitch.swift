/// 音名（幹音）。C=0 … B=6。
public enum Step: Int, CaseIterable, Sendable, Codable {
    case c = 0, d, e, f, g, a, b

    public var semitone: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }
    public var letter: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }

    public init?(letter: String) {
        guard let i = ["C", "D", "E", "F", "G", "A", "B"].firstIndex(of: letter.uppercased()) else { return nil }
        self.init(rawValue: i)
    }
}

/// 譜面上の表記（MusicXML の step / alter / octave）。
public struct Spelling: Hashable, Sendable, Codable {
    public var step: Step
    public var alter: Int
    public var octave: Int

    public init(step: Step, alter: Int = 0, octave: Int) {
        self.step = step
        self.alter = alter
        self.octave = octave
    }

    /// 60 = C4
    public var midi: Int { (octave + 1) * 12 + step.semitone + alter }

    /// 全音階番号（オクターブ×7＋音名番号）。E4 = 30、G2 = 18。
    public var diatonic: Int { octave * 7 + step.rawValue }

    /// 調の情報が無いときの既定の表記（C♯ E♭ F♯ A♭ B♭）。
    public init(midi: Int) {
        let pc = ((midi % 12) + 12) % 12
        let table: [(Step, Int)] = [
            (.c, 0), (.c, 1), (.d, 0), (.e, -1), (.e, 0), (.f, 0),
            (.f, 1), (.g, 0), (.a, -1), (.a, 0), (.b, -1), (.b, 0),
        ]
        let (step, alter) = table[pc]
        self.init(step: step, alter: alter, octave: midi / 12 - 1)
    }
}

public enum Pitch {
    public static let middleC = 60
    public static let lowest = 21   // A0
    public static let highest = 108 // C8

    public static func isBlack(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12)
    }
}
