import CoreGraphics
import Testing
@testable import PianoCore

@Suite struct PitchTests {
    @Test func midiAndDiatonic() {
        #expect(Spelling(step: .c, octave: 4).midi == 60)
        #expect(Spelling(step: .e, octave: 4).diatonic == 30)
        #expect(Spelling(step: .g, octave: 2).diatonic == 18)
        #expect(Spelling(step: .b, alter: -1, octave: 3).midi == 58)
        #expect(Spelling(midi: 61) == Spelling(step: .c, alter: 1, octave: 4))
        #expect(Spelling(midi: 70) == Spelling(step: .b, alter: -1, octave: 4))
    }

    @Test func naming() {
        #expect(NoteNaming.name(Spelling(step: .e, alter: -1, octave: 4), .cde) == "E♭")
        #expect(NoteNaming.name(Spelling(step: .f, alter: 1, octave: 4), .doremi) == "ファ♯")
        #expect(NoteNaming.keyName(midi: 60, .cde) == "C4")
        #expect(NoteNaming.keyName(midi: 48, .doremi) == "ド3")
        #expect(NoteNaming.keyName(midi: 64, .cde) == "E")
        #expect(NoteNaming.keyName(midi: 68, .doremi) == "ソ♯")
        #expect(NoteNaming.name(Spelling(step: .g, octave: 4), .cde, includeOctave: true) == "G4")
    }
}

@Suite struct KeyboardLayoutTests {
    @Test func defaultRangeMatchesDesign() {
        let range = KeyboardLayout.autoRange(for: SampleScores.odeToJoy.midiRange)
        #expect(range == 43...84)  // G2–C6
        let layout = KeyboardLayout(range: range, width: 1194)
        #expect(layout.whiteKeyCount == 25)
        #expect(abs(layout.whiteKeyWidth - 1194.0 / 25) < 0.001)
    }

    @Test func centers() {
        let layout = KeyboardLayout(range: 43...84, width: 1376)
        let kw = layout.whiteKeyWidth
        // 最初の白鍵 G2 の中心
        #expect(abs(layout.keyCenterX(midi: 43) - kw / 2) < 0.001)
        // 白鍵は隣と KW ずつ離れる
        let whites = layout.whiteKeys
        for (a, b) in zip(whites, whites.dropFirst()) {
            #expect(abs(layout.keyCenterX(midi: b) - layout.keyCenterX(midi: a) - kw) < 0.001)
        }
        // 黒鍵は左隣の白鍵 + KW/2
        for m in layout.blackKeys {
            #expect(abs(layout.keyCenterX(midi: m) - layout.keyCenterX(midi: m - 1) - kw / 2) < 0.001)
        }
        // 最後の白鍵の右端 = 幅
        #expect(abs(layout.keyCenterX(midi: 84) + kw / 2 - 1376) < 0.001)
    }

    @Test func autoRangeExpands() {
        // 低い音がある曲：E2 の白鍵2本下 = C2
        #expect(KeyboardLayout.autoRange(for: 40...72).lowerBound == 36)
        // 黒鍵の最高音 F♯6 → G6 から2本上 = B6
        #expect(KeyboardLayout.autoRange(for: 50...90).upperBound == 95)
        #expect(KeyboardLayout.autoRange(for: 21...108) == 21...108)
    }

    @Test func lane() {
        let lane = LaneMetrics(height: 380, lookaheadBeats: 6)
        #expect(lane.y(beat: 2, now: 2) == 380)
        #expect(abs(lane.y(beat: 8, now: 2)) < 0.001)
    }
}

@Suite struct TimingTests {
    @Test func tempoMapRoundTrip() {
        let map = TempoMap(changes: [(0, 120), (8, 60)])
        #expect(map.seconds(atBeat: 4) == 2)
        #expect(map.seconds(atBeat: 10) == 6)
        #expect(map.beat(atSeconds: 6) == 10)
        #expect(map.beat(atSeconds: -1) == -2)
        #expect(map.bpm(atBeat: 9) == 60)
    }

    @Test func clock() {
        let clock = PracticeClock(tempoMap: TempoMap(bpm: 120))
        clock.seek(toBeat: 0, atHost: 100)
        clock.start(atHost: 100)
        #expect(clock.beat(atHost: 101) == 2)
        clock.setRate(0.5, atHost: 101)
        #expect(clock.beat(atHost: 103) == 4)
        clock.pause(atHost: 103)
        #expect(clock.beat(atHost: 200) == 4)
    }

    @Test func clockLoops() {
        let clock = PracticeClock(tempoMap: TempoMap(bpm: 60))
        clock.setLoop(beats: -4..<16)
        clock.seek(toBeat: -4, atHost: 0)
        clock.start(atHost: 0)
        #expect(clock.beat(atHost: 19) == 15)
        #expect(clock.beat(atHost: 21) == -3)
    }
}

@Suite struct ScoreTests {
    @Test func ties() {
        let notes = [
            Note(id: 0, startTick: 0, durationTicks: 480, spelling: Spelling(midi: 60), hand: .right, staff: 1, tieStart: true),
            Note(id: 1, startTick: 480, durationTicks: 480, spelling: Spelling(midi: 60), hand: .right, staff: 1, tieStart: true, tieStop: true),
            Note(id: 2, startTick: 960, durationTicks: 240, spelling: Spelling(midi: 60), hand: .right, staff: 1, tieStop: true),
            Note(id: 3, startTick: 0, durationTicks: 480, spelling: nil, hand: .left, staff: 2),
        ]
        let score = Score(title: "t", ticksPerQuarter: 480, tempoMap: TempoMap(bpm: 120), measures: [], notes: notes)
        #expect(score.playNotes.count == 1)
        #expect(score.playNotes[0].lengthBeats == 2.5)
    }

    @Test func keyStates() {
        let score = SampleScores.odeToJoy
        let states = KeyStates.compute(score: score, beat: 0.5, hands: .both)
        #expect(states[64] == .sounding(.right))
        #expect(states[48] == .sounding(.left))
        let right = KeyStates.compute(score: score, beat: 1.5, hands: .right)
        #expect(right[65] == .upcoming(.right))
        #expect(right[48] == .sounding(.left))  // 自動演奏の手も発音中は出す
        let next = KeyStates.nextNotes(score: score, beat: 3.5, hands: .both)
        #expect(next.map(\.midi) == [47, 55, 67])
        #expect(KeyStates.nextNotes(score: score, beat: 3.5, hands: .right).map(\.midi) == [67])
    }

    @Test func measureLookup() {
        let score = SampleScores.odeToJoy
        #expect(score.lengthBeats == 16)
        #expect(score.measureIndex(atBeat: -2) == 0)
        #expect(score.measureIndex(atBeat: 4) == 1)
        #expect(score.measureIndex(atBeat: 99) == 3)
    }
}
