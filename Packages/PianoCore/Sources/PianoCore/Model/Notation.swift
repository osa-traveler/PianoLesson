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

    private static let sharpOrder: [Step] = [.f, .c, .g, .d, .a, .e, .b]

    /// 調号でその音名に付く変化（♯=+1、♭=-1）
    public func alter(for step: Step) -> Int {
        if fifths > 0 { return Self.sharpOrder.prefix(fifths).contains(step) ? 1 : 0 }
        if fifths < 0 { return Self.sharpOrder.reversed().prefix(-fifths).contains(step) ? -1 : 0 }
        return 0
    }

    /// 調号の記号を置く位置（全音階番号）。順番どおり。
    public func accidentalDiatonics(clef: Clef) -> [Int] {
        // ト音譜表（第1線 = 30）での位置
        let sharps = [38, 35, 39, 36, 33, 37, 34]
        let flats = [34, 37, 33, 36, 32, 35, 31]
        let shift: Int
        switch clef.sign {
        case .f: shift = -2
        case .c: shift = -1
        default: shift = 0
        }
        let delta = clef.bottomLineDiatonic - 30 + shift
        let list = fifths >= 0 ? sharps.prefix(fifths) : flats.prefix(-fifths)
        return list.map { $0 + delta }
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

    /// 第1線（一番下の線）の全音階番号。ト音 E4 = 30、ヘ音 G2 = 18。
    public var bottomLineDiatonic: Int {
        switch sign {
        case .g: 32 - (line - 1) * 2   // G4 の線
        case .f: 24 - (line - 1) * 2   // F3 の線
        case .c: 28 - (line - 1) * 2   // C4 の線
        case .percussion: 30
        }
    }
}

public enum NoteType: String, Codable, Sendable, CaseIterable {
    case breve, whole, half, quarter, eighth
    case sixteenth = "16th", thirtySecond = "32nd", sixtyFourth = "64th"

    /// 旗・連桁の本数
    public var beamCount: Int {
        switch self {
        case .eighth: 1
        case .sixteenth: 2
        case .thirtySecond: 3
        case .sixtyFourth: 4
        default: 0
        }
    }

    public var hasStem: Bool { self != .whole && self != .breve }
    public var isHollow: Bool { self == .half || self == .whole || self == .breve }

    /// 長さ（四分音符=1.0）から音価と付点の数を推定する
    public static func infer(beats: Double) -> (NoteType, Int) {
        let types: [(NoteType, Double)] = [
            (.breve, 8), (.whole, 4), (.half, 2), (.quarter, 1),
            (.eighth, 0.5), (.sixteenth, 0.25), (.thirtySecond, 0.125), (.sixtyFourth, 0.0625),
        ]
        for (type, base) in types {
            if abs(beats - base * 1.75) < 1e-6 { return (type, 2) }
            if abs(beats - base * 1.5) < 1e-6 { return (type, 1) }
            if abs(beats - base) < 1e-6 { return (type, 0) }
        }
        // 割り切れない長さは、それ以下で最も長い音価
        return (types.first { $0.1 <= beats + 1e-6 }?.0 ?? .sixtyFourth, 0)
    }
}

/// 表示する臨時記号
public enum Accidental: String, Codable, Sendable {
    case sharp, flat, natural, doubleSharp, doubleFlat

    public init(alter: Int) {
        switch alter {
        case 2: self = .doubleSharp
        case 1: self = .sharp
        case -1: self = .flat
        case -2: self = .doubleFlat
        default: self = .natural
        }
    }
}

/// MusicXML の <beam> の値
public enum BeamValue: String, Codable, Sendable {
    case begin, `continue`, end
    case forwardHook = "forward hook", backwardHook = "backward hook"
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
    /// 楽譜に明記された臨時記号（無ければ調号と小節内の状態から決める）
    public var accidental: Accidental?
    /// 楽譜に明記された符幹の向き
    public var stemUp: Bool?
    /// 連桁（番号 → 値）。1 が主連桁
    public var beams: [Int: BeamValue]
    /// 休符の表示位置（全音階番号）
    public var restDiatonic: Int?
    /// 小節全体の休符
    public var isMeasureRest: Bool

    public init(id: Int, startTick: Int, durationTicks: Int, spelling: Spelling?, hand: Hand,
                staff: Int, voice: Int = 1, noteType: NoteType? = nil, dots: Int = 0,
                tieStart: Bool = false, tieStop: Bool = false, fingering: Int? = nil,
                accidental: Accidental? = nil, stemUp: Bool? = nil, beams: [Int: BeamValue] = [:],
                restDiatonic: Int? = nil, isMeasureRest: Bool = false) {
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
        self.accidental = accidental
        self.stemUp = stemUp
        self.beams = beams
        self.restDiatonic = restDiatonic
        self.isMeasureRest = isMeasureRest
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
