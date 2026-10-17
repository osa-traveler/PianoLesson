/// 拍（四分音符=1.0）と原曲時間（秒）の相互変換。テンポは四分音符/分。
public struct TempoMap: Sendable {
    public struct Point: Sendable {
        public var beat: Double
        public var bpm: Double
        public var seconds: Double
    }

    public private(set) var points: [Point]

    /// changes: (拍, bpm)。空なら ♩=120。最初の変化点より前は最初のテンポで延長する。
    public init(changes: [(beat: Double, bpm: Double)]) {
        var sorted = changes.filter { $0.bpm > 0 }.sorted { $0.beat < $1.beat }
        if sorted.isEmpty { sorted = [(0, 120)] }
        if sorted[0].beat > 0 { sorted.insert((0, sorted[0].bpm), at: 0) }
        var pts: [Point] = []
        for c in sorted {
            if let last = pts.last {
                let s = last.seconds + (c.beat - last.beat) * 60 / last.bpm
                if c.beat == last.beat { pts[pts.count - 1].bpm = c.bpm; continue }
                pts.append(Point(beat: c.beat, bpm: c.bpm, seconds: s))
            } else {
                pts.append(Point(beat: c.beat, bpm: c.bpm, seconds: 0))
            }
        }
        points = pts
    }

    public init(bpm: Double) { self.init(changes: [(0, bpm)]) }

    public var initialBPM: Double { points[0].bpm }

    public func bpm(atBeat beat: Double) -> Double { point(where: { $0.beat <= beat }).bpm }

    public func seconds(atBeat beat: Double) -> Double {
        let p = point(where: { $0.beat <= beat })
        return p.seconds + (beat - p.beat) * 60 / p.bpm
    }

    public func beat(atSeconds seconds: Double) -> Double {
        let p = point(where: { $0.seconds <= seconds })
        return p.beat + (seconds - p.seconds) * p.bpm / 60
    }

    /// 条件を満たす最後の点。どれも満たさなければ最初の点。
    private func point(where isBefore: (Point) -> Bool) -> Point {
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if isBefore(points[mid]) { lo = mid } else { hi = mid - 1 }
        }
        return points[lo]
    }
}
