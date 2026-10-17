import Testing
@testable import PianoCore

@Suite struct PlaybackTests {
    @Test func noteOnAndOff() {
        var s = PracticeSettings()
        s.metronomeOn = false
        let score = SampleScores.odeToJoy
        // 拍 0 ちょうど: 右手 E4、左手 C3+G3
        let start = PlaybackPlanner.events(score: score, from: -0.01, to: 0, settings: s)
        #expect(start == [.noteOn(midi: 48, hand: .left), .noteOn(midi: 55, hand: .left), .noteOn(midi: 64, hand: .right)])
        // 拍 1: E4 を止めてから E4 を鳴らす
        let next = PlaybackPlanner.events(score: score, from: 0.99, to: 1.0, settings: s)
        #expect(next == [.noteOff(midi: 64, hand: .right), .noteOn(midi: 64, hand: .right)])
    }

    @Test func practicedHandIsSilentWhenGuideOff() {
        var s = PracticeSettings()
        s.metronomeOn = false
        s.playPracticedHands = false
        s.hands = .right
        let events = PlaybackPlanner.events(score: SampleScores.odeToJoy, from: -0.01, to: 0, settings: s)
        #expect(events == [.noteOn(midi: 48, hand: .left), .noteOn(midi: 55, hand: .left)])
    }

    @Test func metronomeCountsInBeforeFirstMeasure() {
        let clicks = PlaybackPlanner.clickBeats(score: SampleScores.odeToJoy, from: -4.5, to: 4)
        #expect(clicks.map(\.0) == [-4, -3, -2, -1, 0, 1, 2, 3, 4])
        #expect(clicks.map(\.1) == [true, false, false, false, true, false, false, false, true])
    }
}
