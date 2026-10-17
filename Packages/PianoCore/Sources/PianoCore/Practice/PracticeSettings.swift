public enum HandsMode: String, Codable, Sendable, CaseIterable {
    case right, both, left

    /// この手を練習するか（しない手はアプリが自動演奏する）
    public func practices(_ hand: Hand) -> Bool {
        switch self {
        case .both: true
        case .right: hand == .right
        case .left: hand == .left
        }
    }
}

public struct PracticeSettings: Codable, Sendable, Equatable {
    public var tempoRatio: Double = 1.0      // 0.25...1.5
    public var hands: HandsMode = .both
    public var waitForCorrectKey = true
    /// 小節の index（0 始まり）
    public var loopRange: ClosedRange<Int>?
    public var lookaheadBeats: Double = 6
    public var showStaffGuides = true
    public var naming: Naming = .cde
    public var darkLane = false

    // 音（0…1）
    public var rightVolume = 0.8
    public var leftVolume = 0.8
    public var metronomeVolume = 0.5
    public var metronomeOn = true
    /// 練習する手の音もアプリが鳴らす（お手本）。MIDI キーボードで弾くときはオフにする
    public var playPracticedHands = true

    /// 打鍵判定の許容幅（秒）
    public var judgeWindow = 0.12

    public init() {}

    public static let tempoRatioRange = 0.25...1.5
    public static let tempoRatioStep = 0.05
    public static let lookaheadRange = 4.0...8.0

    public func volume(for hand: Hand) -> Double { hand == .right ? rightVolume : leftVolume }

    /// アプリがこの手の音を鳴らすか
    public func appPlays(_ hand: Hand) -> Bool { playPracticedHands || !hands.practices(hand) }

    // 項目を増やしても古い保存データを読めるように、無い項目は既定値にする
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PracticeSettings()
        tempoRatio = try c.decodeIfPresent(Double.self, forKey: .tempoRatio) ?? d.tempoRatio
        hands = try c.decodeIfPresent(HandsMode.self, forKey: .hands) ?? d.hands
        waitForCorrectKey = try c.decodeIfPresent(Bool.self, forKey: .waitForCorrectKey) ?? d.waitForCorrectKey
        loopRange = try c.decodeIfPresent(ClosedRange<Int>.self, forKey: .loopRange)
        lookaheadBeats = try c.decodeIfPresent(Double.self, forKey: .lookaheadBeats) ?? d.lookaheadBeats
        showStaffGuides = try c.decodeIfPresent(Bool.self, forKey: .showStaffGuides) ?? d.showStaffGuides
        naming = try c.decodeIfPresent(Naming.self, forKey: .naming) ?? d.naming
        darkLane = try c.decodeIfPresent(Bool.self, forKey: .darkLane) ?? d.darkLane
        rightVolume = try c.decodeIfPresent(Double.self, forKey: .rightVolume) ?? d.rightVolume
        leftVolume = try c.decodeIfPresent(Double.self, forKey: .leftVolume) ?? d.leftVolume
        metronomeVolume = try c.decodeIfPresent(Double.self, forKey: .metronomeVolume) ?? d.metronomeVolume
        metronomeOn = try c.decodeIfPresent(Bool.self, forKey: .metronomeOn) ?? d.metronomeOn
        playPracticedHands = try c.decodeIfPresent(Bool.self, forKey: .playPracticedHands) ?? d.playPracticedHands
        judgeWindow = try c.decodeIfPresent(Double.self, forKey: .judgeWindow) ?? d.judgeWindow
    }
}
