import Synchronization

public enum Judgement: Equatable, Sendable {
    case ok, early, late, missed

    public var isHit: Bool { self != .missed }
}

/// 押した鍵の表示用
public enum PressFeedback: Equatable, Sendable {
    case correct(Hand)
    case wrong
}

public struct PressedKey: Equatable, Sendable {
    public var feedback: PressFeedback
    /// 押した時刻（ホスト時刻）
    public var host: Double
}

public struct NoteResult: Equatable, Sendable {
    public var judgement: Judgement
    /// ずれ（実時間の秒、負なら早い）
    public var offset: Double
}

/// 1回の通し練習の結果
public struct PassResult: Equatable, Sendable {
    public var accuracy: Double
    public var hits: Int
    public var total: Int
}

public struct JudgeSnapshot: Sendable {
    public var pressed: [Int: PressedKey] = [:]
    /// 直近に離した間違いの鍵（一瞬光らせる）
    public var recentWrong: [Int: Double] = [:]
    public var results: [Int: NoteResult] = [:]
    public var hits = 0
    public var judged = 0
    public var isWaiting = false

    public init() {}
}

/// 打鍵判定と待機モード（仕様 8.3・8.5）。どのスレッドから呼んでもよい。
public final class PracticeJudge: Sendable {
    private struct State {
        var settings = PracticeSettings()
        var waitEnabled = false
        var snapshot = JudgeSnapshot()
        /// 練習する手の音の開始拍（重複なし、昇順）と、その拍の音
        var groups: [(beat: Double, notes: [PlayNote])] = []
        var nextGroup = 0
        var lastBeat: Double?
        var passStartBeat: Double?
        var completed: [PassResult] = []
        var loopRange: Range<Double>?
    }

    public let score: Score
    public let clock: PracticeClock
    private let state = Mutex(State())

    public init(score: Score, clock: PracticeClock) {
        self.score = score
        self.clock = clock
    }

    /// 設定を反映する。waitEnabled は MIDI 入力があるときだけ true にする
    public func configure(settings: PracticeSettings, waitEnabled: Bool, loop: Range<Double>?, atHost host: Double) {
        let groups = Self.makeGroups(score: score, hands: settings.hands)
        state.withLock { s in
            let handsChanged = s.settings.hands != settings.hands
            s.settings = settings
            s.waitEnabled = waitEnabled && settings.waitForCorrectKey
            s.loopRange = loop
            if handsChanged || s.groups.isEmpty {
                s.groups = groups
                s.snapshot.results = [:]
                s.snapshot.hits = 0
                s.snapshot.judged = 0
            }
        }
        reset(toBeat: clock.beat(atHost: host), atHost: host, recordPass: false)
    }

    private static func makeGroups(score: Score, hands: HandsMode) -> [(beat: Double, notes: [PlayNote])] {
        var groups: [(beat: Double, notes: [PlayNote])] = []
        for n in score.playNotes where hands.practices(n.hand) {
            if let last = groups.last, abs(last.beat - n.startBeat) < 1e-6 {
                groups[groups.count - 1].notes.append(n)
            } else {
                groups.append((n.startBeat, [n]))
            }
        }
        return groups
    }

    /// 位置が飛んだとき（先頭へ・ループで戻った）
    public func reset(toBeat beat: Double, atHost host: Double, recordPass: Bool = true) {
        let gate: Double? = state.withLock { s in
            if recordPass { Self.finishPass(&s) }
            s.snapshot.results = [:]
            s.snapshot.hits = 0
            s.snapshot.judged = 0
            s.snapshot.isWaiting = false
            s.nextGroup = s.groups.firstIndex { $0.beat >= beat - 1e-6 } ?? s.groups.count
            s.lastBeat = beat
            s.passStartBeat = beat
            return Self.gateBeat(s)
        }
        clock.setGate(beat: gate, atHost: host)
    }

    private static func gateBeat(_ s: State) -> Double? {
        guard s.waitEnabled, s.groups.indices.contains(s.nextGroup) else { return nil }
        return s.groups[s.nextGroup].beat
    }

    /// 通し練習の結果を記録する（ループ範囲の最初の音から通したときだけ）
    private static func finishPass(_ s: inout State) {
        guard let loop = s.loopRange, let start = s.passStartBeat else { return }
        let inLoop = s.groups.filter { loop.contains($0.beat) }
        guard let firstBeat = inLoop.first?.beat, start <= firstBeat + 1e-6 else { return }
        let total = inLoop.reduce(0) { $0 + $1.notes.count }
        guard total > 0, s.snapshot.judged > 0 else { return }
        s.completed.append(PassResult(accuracy: Double(s.snapshot.hits) / Double(total),
                                      hits: s.snapshot.hits, total: total))
    }

    /// 毎フレーム（または定期的に）呼ぶ。見逃しの判定、ループで戻ったことの検出
    public func update(atHost host: Double) {
        let beat = clock.beat(atHost: host)
        let rate = max(clock.rate, 0.01)
        let wrapped: Bool = state.withLock { s in
            if let last = s.lastBeat, beat < last - 1e-6 { return true }
            s.lastBeat = beat
            let nowSeconds = score.tempoMap.seconds(atBeat: beat)
            // 判定幅を過ぎても押されなかった音は見逃し
            var i = s.nextGroup
            while i < s.groups.count, s.groups[i].beat <= beat {
                for n in s.groups[i].notes where s.snapshot.results[n.id] == nil {
                    let late = (nowSeconds - score.tempoMap.seconds(atBeat: n.startBeat)) / rate
                    if late > s.settings.judgeWindow {
                        s.snapshot.results[n.id] = NoteResult(judgement: .missed, offset: late)
                        s.snapshot.judged += 1
                    }
                }
                i += 1
            }
            Self.advance(&s)
            s.snapshot.isWaiting = s.waitEnabled && clock.isHeld(atHost: host)
            return false
        }
        if wrapped {
            reset(toBeat: beat, atHost: host)
        } else {
            clock.setGate(beat: state.withLock { Self.gateBeat($0) }, atHost: host)
        }
    }

    /// 全部の音に結果が付いた拍を進める
    private static func advance(_ s: inout State) {
        while s.groups.indices.contains(s.nextGroup),
              s.groups[s.nextGroup].notes.allSatisfy({ s.snapshot.results[$0.id] != nil }) {
            s.nextGroup += 1
        }
    }

    /// 鍵を押した。結果を返す
    @discardableResult
    public func noteOn(midi: Int, atHost host: Double) -> PressFeedback {
        let pressSeconds = clock.scoreSeconds(atHost: host)
        let rate = max(clock.rate, 0.01)
        let (feedback, gate) = state.withLock { s -> (PressFeedback, Double?) in
            let window = s.settings.judgeWindow
            let catchWindow = max(0.35, window * 2.5)
            var best: (note: PlayNote, offset: Double)?
            // まだ結果の無い近くの音から、ずれの一番小さいものを選ぶ
            var i = max(0, s.nextGroup - 4)
            while i < s.groups.count {
                let g = s.groups[i]
                let offset = (pressSeconds - score.tempoMap.seconds(atBeat: g.beat)) / rate
                if offset < -catchWindow { break }
                if offset <= catchWindow {
                    for n in g.notes where n.midi == midi && s.snapshot.results[n.id] == nil {
                        if best == nil || abs(offset) < abs(best!.offset) { best = (n, offset) }
                    }
                }
                i += 1
            }
            let feedback: PressFeedback
            if let best {
                let j: Judgement = abs(best.offset) <= window ? .ok : (best.offset < 0 ? .early : .late)
                s.snapshot.results[best.note.id] = NoteResult(judgement: j, offset: best.offset)
                s.snapshot.judged += 1
                if j == .ok { s.snapshot.hits += 1 }
                feedback = .correct(best.note.hand)
                Self.advance(&s)
            } else {
                feedback = .wrong
            }
            s.snapshot.pressed[midi] = PressedKey(feedback: feedback, host: host)
            return (feedback, Self.gateBeat(s))
        }
        clock.setGate(beat: gate, atHost: host)
        return feedback
    }

    public func noteOff(midi: Int, atHost host: Double) {
        state.withLock { s in
            if let key = s.snapshot.pressed.removeValue(forKey: midi), key.feedback == .wrong {
                s.snapshot.recentWrong[midi] = host
            }
            s.snapshot.recentWrong = s.snapshot.recentWrong.filter { host - $0.value < 0.5 }
        }
    }

    public func snapshot() -> JudgeSnapshot { state.withLock { $0.snapshot } }

    /// 記録済みの通し練習の結果を取り出す
    public func takeCompletedPasses() -> [PassResult] {
        state.withLock { s in
            let r = s.completed
            s.completed = []
            return r
        }
    }
}
