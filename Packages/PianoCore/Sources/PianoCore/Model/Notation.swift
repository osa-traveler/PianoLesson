public enum Hand: String, Codable, Sendable {
    case right, left
}

public struct TimeSignature: Hashable, Sendable, Codable {
    public var beats: Int
    public var beatType: Int

    public init(beats: Int, beatType: Int) {
        self.beats = beats
        self.beatType = beatType
    }

    public static let fourFour = TimeSignature(beats: 4, beatType: 4)

    /// 拍子記号の1拍の長さ（四分音符=1.0）。6/8 なら 0.5。
    public var beatUnit: Double { 4.0 / Double(beatType) }
    /// 1小節の長さ（四分音符=1.0）。
    public var measureLength: Double { Double(beats) * beatUnit }
}

public struct KeySignature: Hashable, Sendable, Codable {
    public var fifths: Int

    public init(fifths: Int) { self.fifths = fifths }

    public var japaneseMajorName: String {
        let names = ["変ハ", "変ト", "変ニ", "変イ", "変ホ", "変ロ", "ヘ",
                     "ハ", "ト", "ニ", "イ", "ホ", "ロ", "嬰ヘ", "嬰ハ"]
        let i = max(-7, min(7, fifths)) + 7
        return names[i] + "長調"
    }
}

public enum ClefSign: String, Codable, Sendable {
    case g = "G", f = "F", c = "C", percussion
}

public struct Clef: Hashable, Sendable, Codable {
    public var sign: ClefSign
    public var line: Int

    public init(sign: ClefSign, line: Int) {
        self.sign = sign
        self.line = line
    }

    public static let treble = Clef(sign: .g, line: 2)
    public static let bass = Clef(sign: .f, line: 4)
}

public enum NoteType: String, Codable, Sendable, CaseIterable {
    case breve, whole, half, quarter, eighth
    case sixteenth = "16th", thirtySecond = "32nd", sixtyFourth = "64th"
}

public struct Measure: Sendable {
    /// 0 始まり
    public var index: Int
    /// 表示用の小節番号（MusicXML の number）
    public var number: String
    public var startTick: Int
    public var lengthTicks: Int
    public var time: TimeSignature
    public var key: KeySignature
    /// staff 番号 → 音部記号（変更がある小節のみ）
    public var clefs: [Int: Clef]

    public init(index: Int, number: String, startTick: Int, lengthTicks: Int,
                time: TimeSignature, key: KeySignature, clefs: [Int: Clef] = [:]) {
        self.index = index
        self.number = number
        self.startTick = startTick
        self.lengthTicks = lengthTicks
        self.time = time
        self.key = key
        self.clefs = clefs
    }
}

/// 譜面に書かれた音符・休符。
public struct Note: Identifiable, Sendable {
    public let id: Int
    public var startTick: Int
    /// 書かれた長さ
    public var durationTicks: Int
    /// nil なら休符
    public var spelling: Spelling?
    public var hand: Hand
    public var staff: Int
    public var voice: Int
    public var noteType: NoteType?
    public var dots: Int
    public var tieStart: Bool
    public var tieStop: Bool
    public var fingering: Int?

    public init(id: Int, startTick: Int, durationTicks: Int, spelling: Spelling?, hand: Hand,
                staff: Int, voice: Int = 1, noteType: NoteType? = nil, dots: Int = 0,
                tieStart: Bool = false, tieStop: Bool = false, fingering: Int? = nil) {
        self.id = id
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.spelling = spelling
        self.hand = hand
        self.staff = staff
        self.voice = voice
        self.noteType = noteType
        self.dots = dots
        self.tieStart = tieStart
        self.tieStop = tieStop
        self.fingering = fingering
    }

    public var isRest: Bool { spelling == nil }
    public var midi: Int? { spelling?.midi }
}

/// 鳴らす音（レーン・鍵盤・発音・判定で使う）。タイは1本にまとめてある。
public struct PlayNote: Identifiable, Sendable, Hashable {
    /// 元になった Note の id（タイの先頭）
    public let id: Int
    public var startBeat: Double
    public var lengthBeats: Double
    public var spelling: Spelling
    public var hand: Hand

    public var midi: Int { spelling.midi }
    public var endBeat: Double { startBeat + lengthBeats }
}
