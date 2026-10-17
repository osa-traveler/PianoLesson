import CoreGraphics

/// 譜面パネルの座標（仕様 5.1）。基準 1194×248pt の値を、パネルの大きさに合わせて伸縮する。
public struct ScoreGeometry: Sendable {
    public static let baseSize = CGSize(width: 1194, height: 248)
    public static let measuresPerPage = 4

    public let size: CGSize
    /// 横方向の倍率
    public let sx: CGFloat
    /// 記号の大きさの倍率（縦横で小さい方）
    public let scale: CGFloat
    private let yOffset: CGFloat

    public init(size: CGSize) {
        self.size = size
        sx = size.width / Self.baseSize.width
        scale = min(sx, size.height / Self.baseSize.height)
        yOffset = (size.height - Self.baseSize.height * scale) / 2
    }

    /// 五線の間隔 G
    public var space: CGFloat { 11 * scale }
    /// 半間隔 S
    public var halfSpace: CGFloat { space / 2 }

    public var staffLeft: CGFloat { 36 * sx }
    public var staffRight: CGFloat { 1176 * sx }
    /// 1小節目の開始 X0
    public var firstMeasureX: CGFloat { 146 * sx }
    public var measureWidth: CGFloat { (staffRight - firstMeasureX) / CGFloat(Self.measuresPerPage) }

    /// staff 1（ト音）・2（ヘ音）の第1線の y
    public func bottomLineY(staff: Int) -> CGFloat {
        yOffset + (staff == 1 ? 98 : 210) * scale
    }

    public func topLineY(staff: Int) -> CGFloat { bottomLineY(staff: staff) - 4 * space }

    public func y(diatonic: Int, staff: Int, bottomDiatonic: Int) -> CGFloat {
        bottomLineY(staff: staff) - CGFloat(diatonic - bottomDiatonic) * halfSpace
    }

    public func measureX(slot: Int) -> CGFloat { firstMeasureX + CGFloat(slot) * measureWidth }

    /// 小節内の位置（0…1）の x
    public func x(slot: Int, fraction: Double) -> CGFloat {
        measureX(slot: slot) + 18 * sx + CGFloat(fraction) * (measureWidth - 26 * sx)
    }

    /// 現在小節ハイライトと再生位置線の縦の範囲（五線の上下に 1.6G はみ出す）
    public var systemTop: CGFloat { topLineY(staff: 1) - 1.6 * space }
    public var systemBottom: CGFloat { bottomLineY(staff: 2) + 1.6 * space }
}

/// 譜めくり（4小節ごとのページ。切り替え時は 0.25 秒で横にスライド）
public enum ScorePaging {
    public static let slideSeconds = 0.25

    public static func page(ofMeasure index: Int) -> Int { index / ScoreGeometry.measuresPerPage }

    /// 表示するページと、前のページからのスライドの進み具合（0…1、スライド中でなければ nil）
    public static func state(score: Score, beat: Double, rate: Double) -> (page: Int, slide: Double?) {
        guard !score.measures.isEmpty else { return (0, nil) }
        let measure = beat < 0 ? 0 : score.measureIndex(atBeat: beat)
        let page = page(ofMeasure: measure)
        guard page > 0, rate > 0 else { return (page, nil) }
        let boundary = score.startBeat(of: score.measures[page * ScoreGeometry.measuresPerPage])
        let elapsed = (score.tempoMap.seconds(atBeat: beat) - score.tempoMap.seconds(atBeat: boundary)) / rate
        guard elapsed >= 0, elapsed < slideSeconds else { return (page, nil) }
        return (page, elapsed / slideSeconds)
    }
}

extension ScorePaging {
    /// 譜面の x 座標（そのページ上）に当たる拍。ページの外は前後の小節へ続ける
    public static func beat(atX x: CGFloat, page: Int, score: Score, geometry g: ScoreGeometry) -> Double {
        guard !score.measures.isEmpty else { return 0 }
        let slot = Int(((x - g.firstMeasureX) / g.measureWidth).rounded(.down))
        let index = page * ScoreGeometry.measuresPerPage + slot
        if index < 0 { return score.startBeat(of: score.measures[0]) }
        if index >= score.measures.count { return score.lengthBeats }
        let m = score.measures[index]
        let inner = g.measureWidth - 26 * g.sx
        let local = x - g.measureX(slot: slot) - 18 * g.sx
        let fraction = min(max(Double(local / inner), 0), 0.999)
        return score.startBeat(of: m) + fraction * score.beat(ofTick: m.lengthTicks)
    }

    /// 一番近い拍（拍子記号の1拍）にそろえる
    public static func snapToBeat(_ beat: Double, score: Score) -> Double {
        guard !score.measures.isEmpty, beat >= 0 else { return beat }
        let m = score.measures[score.measureIndex(atBeat: beat)]
        let start = score.startBeat(of: m)
        let unit = m.time.beatUnit
        let snapped = start + ((beat - start) / unit).rounded() * unit
        return min(snapped, score.endBeat(of: m))
    }
}
