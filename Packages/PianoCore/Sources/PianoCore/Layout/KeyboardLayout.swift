import CoreGraphics

/// 鍵盤の横方向の配置。レーンと鍵盤は必ずここの keyCenterX(midi:) を使う。
public struct KeyboardLayout: Sendable, Equatable {
    /// 両端は白鍵
    public let range: ClosedRange<Int>
    public let width: CGFloat
    public let whiteKeyWidth: CGFloat
    public let blackKeyWidth: CGFloat

    public init(range: ClosedRange<Int>, width: CGFloat) {
        let lo = Pitch.isBlack(range.lowerBound) ? range.lowerBound - 1 : range.lowerBound
        let hi = Pitch.isBlack(range.upperBound) ? range.upperBound + 1 : range.upperBound
        self.range = lo...hi
        self.width = width
        let whites = Self.whiteOrdinal(hi) - Self.whiteOrdinal(lo) + 1
        whiteKeyWidth = width / CGFloat(whites)
        blackKeyWidth = whiteKeyWidth * 0.6
    }

    public var whiteKeyCount: Int { Self.whiteOrdinal(range.upperBound) - Self.whiteOrdinal(range.lowerBound) + 1 }
    public var whiteKeys: [Int] { range.filter { !Pitch.isBlack($0) } }
    public var blackKeys: [Int] { range.filter { Pitch.isBlack($0) } }

    public func contains(_ midi: Int) -> Bool { range.contains(midi) }

    /// 鍵の中心の x。黒鍵は左隣の白鍵の中心 + KW/2（簡易配置）。
    public func keyCenterX(midi: Int) -> CGFloat {
        let base = Self.whiteOrdinal(range.lowerBound)
        if Pitch.isBlack(midi) {
            return (CGFloat(Self.whiteOrdinal(midi - 1) - base) + 1) * whiteKeyWidth
        }
        return (CGFloat(Self.whiteOrdinal(midi) - base) + 0.5) * whiteKeyWidth
    }

    public func keyWidth(midi: Int) -> CGFloat {
        Pitch.isBlack(midi) ? blackKeyWidth : whiteKeyWidth
    }

    /// 白鍵の通し番号（C-1 = 0）。黒鍵には使わない。
    static func whiteOrdinal(_ midi: Int) -> Int {
        let octave = Int((Double(midi) / 12).rounded(.down))
        let pc = midi - octave * 12
        let inOctave = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][pc]
        return octave * 7 + inOctave
    }

    /// 曲の音域から表示範囲を決める。前後に白鍵 margin 本の余白を取り、
    /// 五線ガイドの鍵（G2〜F5）と既定の範囲 G2–C6 は必ず含める。
    public static func autoRange(for notes: ClosedRange<Int>?, marginWhites: Int = 2) -> ClosedRange<Int> {
        var lo = StaffGuides.defaultKeyboardRange.lowerBound
        var hi = StaffGuides.defaultKeyboardRange.upperBound
        if let notes {
            lo = min(lo, stepWhite(from: notes.lowerBound, by: -marginWhites))
            hi = max(hi, stepWhite(from: notes.upperBound, by: marginWhites))
        }
        return max(Pitch.lowest, lo)...min(Pitch.highest, hi)
    }

    /// 白鍵を n 本ずらした鍵（負なら下へ）。黒鍵から始めた場合はその隣の白鍵から数える。
    static func stepWhite(from midi: Int, by n: Int) -> Int {
        var m = midi
        if Pitch.isBlack(m) { m += n < 0 ? -1 : 1 }
        for _ in 0..<abs(n) {
            m += n < 0 ? -1 : 1
            if Pitch.isBlack(m) { m += n < 0 ? -1 : 1 }
        }
        return m
    }
}

/// B案の五線ガイド
public enum StaffGuides {
    /// ト音記号の5本線 E4 G4 B4 D5 F5
    public static let treble = [64, 67, 71, 74, 77]
    /// ヘ音記号の5本線 G2 B2 D3 F3 A3
    public static let bass = [43, 47, 50, 53, 57]
    /// 真ん中のド（加線）
    public static let middleC = 60

    public static let defaultKeyboardRange = 43...84  // G2–C6

    public static func hand(ofGuide midi: Int) -> Hand? {
        if treble.contains(midi) { return .right }
        if bass.contains(midi) { return .left }
        return nil
    }
}

/// 落下レーンの縦方向。下端が判定ライン（今）、上へ行くほど未来。
public struct LaneMetrics: Sendable {
    public var height: CGFloat
    public var lookaheadBeats: Double

    public init(height: CGFloat, lookaheadBeats: Double) {
        self.height = height
        self.lookaheadBeats = lookaheadBeats
    }

    /// 1拍あたりの pt
    public var pointsPerBeat: CGFloat { height / CGFloat(lookaheadBeats) }

    public func y(beat: Double, now: Double) -> CGFloat {
        height - CGFloat(beat - now) * pointsPerBeat
    }
}
