import Synchronization

/// 再生位置の時計。ホスト時刻（秒、単調増加）から現在の拍を求める。
/// 内部では「原曲時間（秒）」を進め、テンポ％はその進む速さ（rate）として扱う。
/// 描画・オーディオ・MIDI のどのスレッドから読んでもよい。
public final class PracticeClock: Sendable {
    private struct State {
        var running = false
        var anchorHost: Double = 0
        var anchorSeconds: Double = 0
        var rate: Double = 1
        /// ループ範囲（原曲時間の秒）。終端に来たら始端へ戻る。
        var loop: Range<Double>?
        /// ゲート（原曲時間の秒）。ここで時計が止まり、解除されるまで進まない（待機モード）
        var gate: Double?
    }

    public let tempoMap: TempoMap
    private let state = Mutex(State())

    public init(tempoMap: TempoMap) {
        self.tempoMap = tempoMap
    }

    public var isRunning: Bool { state.withLock { $0.running } }
    public var rate: Double { state.withLock { $0.rate } }

    public func scoreSeconds(atHost host: Double) -> Double {
        state.withLock { Self.seconds(in: $0, host: host) }
    }

    public func beat(atHost host: Double) -> Double {
        tempoMap.beat(atSeconds: scoreSeconds(atHost: host))
    }

    public func start(atHost host: Double) {
        state.withLock { s in
            guard !s.running else { return }
            s.anchorHost = host
            s.running = true
        }
    }

    public func pause(atHost host: Double) {
        state.withLock { s in
            guard s.running else { return }
            s.anchorSeconds = Self.seconds(in: s, host: host)
            s.anchorHost = host
            s.running = false
        }
    }

    public func seek(toBeat beat: Double, atHost host: Double) {
        let seconds = tempoMap.seconds(atBeat: beat)
        state.withLock { s in
            s.anchorSeconds = seconds
            s.anchorHost = host
        }
    }

    public func setRate(_ rate: Double, atHost host: Double) {
        state.withLock { s in
            s.anchorSeconds = Self.seconds(in: s, host: host)
            s.anchorHost = host
            s.rate = rate
        }
    }

    /// 待機モードのゲート。時計はこの拍を越えない。nil で解除（解除した時刻から進み直す）
    public func setGate(beat: Double?, atHost host: Double) {
        let gate = beat.map { tempoMap.seconds(atBeat: $0) }
        state.withLock { s in
            guard s.gate != gate else { return }
            s.anchorSeconds = Self.seconds(in: s, host: host)
            s.anchorHost = host
            s.gate = gate
        }
    }

    public var gateBeat: Double? {
        state.withLock { $0.gate }.map { tempoMap.beat(atSeconds: $0) }
    }

    /// ゲートで止まっているか
    public func isHeld(atHost host: Double) -> Bool {
        state.withLock { s in
            guard let gate = s.gate, s.running else { return false }
            return s.anchorSeconds + (host - s.anchorHost) * s.rate >= gate
        }
    }

    /// 拍で指定したループ範囲。nil で解除。
    public func setLoop(beats: Range<Double>?) {
        let loop = beats.map { tempoMap.seconds(atBeat: $0.lowerBound)..<tempoMap.seconds(atBeat: $0.upperBound) }
        state.withLock { $0.loop = loop }
    }

    private static func seconds(in s: State, host: Double) -> Double {
        var t = s.anchorSeconds
        if s.running { t += (host - s.anchorHost) * s.rate }
        if let gate = s.gate, t > gate, s.anchorSeconds <= gate { t = gate }
        if let loop = s.loop, t >= loop.upperBound, loop.upperBound > loop.lowerBound {
            let span = loop.upperBound - loop.lowerBound
            t = loop.lowerBound + (t - loop.lowerBound).truncatingRemainder(dividingBy: span)
        }
        return t
    }
}
