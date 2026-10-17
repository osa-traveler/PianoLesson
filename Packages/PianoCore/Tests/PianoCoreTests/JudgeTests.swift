import CoreGraphics
import Testing
@testable import PianoCore

/// 歓喜の歌（♩=120、1拍 = 0.5秒）で判定と待機を確かめる
@Suite struct JudgeTests {
    private func make(wait: Bool, hands: HandsMode = .right) -> (PracticeJudge, PracticeClock) {
        let score = SampleScores.odeToJoy
        let clock = PracticeClock(tempoMap: score.tempoMap)
        clock.seek(toBeat: -4, atHost: 0)
        let judge = PracticeJudge(score: score, clock: clock)
        var s = PracticeSettings()
        s.hands = hands
        judge.configure(settings: s, waitEnabled: wait, loop: -4..<16, atHost: 0)
        clock.start(atHost: 0)
        return (judge, clock)
    }

    @Test func okEarlyLateWrong() {
        let (judge, _) = make(wait: false)
        // 拍0 = 2.0秒。E4 を 2.05秒に押す → OK
        #expect(judge.noteOn(midi: 64, atHost: 2.05) == .correct(.right))
        #expect(judge.snapshot().results.values.first?.judgement == .ok)
        // 拍1 = 2.5秒。E4 を 2.3秒（0.2秒早い）→ 早い
        judge.noteOn(midi: 64, atHost: 2.3)
        #expect(judge.snapshot().results.values.contains { $0.judgement == .early })
        // 違う鍵
        #expect(judge.noteOn(midi: 70, atHost: 2.6) == .wrong)
        #expect(judge.snapshot().pressed[70]?.feedback == .wrong)
    }

    @Test func missedAfterWindow() {
        let (judge, _) = make(wait: false)
        judge.update(atHost: 2.0)
        judge.update(atHost: 2.2)  // 拍0 の音を 0.2秒過ぎた
        let r = judge.snapshot().results
        #expect(r.values.contains { $0.judgement == .missed })
    }

    @Test func waitModeHoldsUntilCorrectKey() {
        let (judge, clock) = make(wait: true)
        // 拍0 で止まる
        #expect(clock.beat(atHost: 3.0) == 0)
        judge.update(atHost: 3.0)
        #expect(judge.snapshot().isWaiting)
        // 違う鍵では進まない
        judge.noteOn(midi: 65, atHost: 3.1)
        #expect(clock.beat(atHost: 3.2) == 0)
        // 正しい鍵で進み、その時刻から動き出す
        judge.noteOn(midi: 64, atHost: 3.2)
        #expect(abs(clock.beat(atHost: 3.4) - 0.4) < 1e-9)
        // 次の拍1でまた止まる
        #expect(clock.beat(atHost: 4.0) == 1)
    }

    @Test func chordNeedsAllKeys() {
        let (judge, clock) = make(wait: true, hands: .left)
        judge.noteOn(midi: 48, atHost: 2.5)
        #expect(clock.beat(atHost: 2.6) == 0)
        judge.noteOn(midi: 55, atHost: 2.6)
        #expect(clock.beat(atHost: 2.7) > 0)
    }

    @Test func passIsRecordedOnLoop() {
        let (judge, _) = make(wait: false, hands: .left)
        // 左手 8音のうち最初の2音（C3 G3）だけ OK
        judge.noteOn(midi: 48, atHost: 2.0)
        judge.noteOn(midi: 55, atHost: 2.0)
        judge.update(atHost: 9.0)
        judge.reset(toBeat: -4, atHost: 9.5)
        let passes = judge.takeCompletedPasses()
        #expect(passes == [PassResult(accuracy: 0.25, hits: 2, total: 8)])
    }

    @Test func keyHitTest() {
        let layout = KeyboardLayout(range: 43...84, width: 1250)  // 白鍵 25本、1本 50pt
        #expect(layout.key(at: CGPoint(x: 25, y: 140), blackLength: 92) == 43)       // G2
        #expect(layout.key(at: CGPoint(x: 50, y: 40), blackLength: 92) == 44)        // G♯2（黒鍵）
        #expect(layout.key(at: CGPoint(x: 50, y: 120), blackLength: 92) == 45)       // 黒鍵の下は A2
    }
}
