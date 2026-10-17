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

    public init() {}

    public static let tempoRatioRange = 0.25...1.5
    public static let tempoRatioStep = 0.05
}
