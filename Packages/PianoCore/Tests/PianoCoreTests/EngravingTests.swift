import CoreGraphics
import Testing
@testable import PianoCore

@Suite struct EngravingTests {
    private func score(_ notes: [Note], key: Int = 0) -> Score {
        let m = Measure(index: 0, number: "1", startTick: 0, lengthTicks: 4 * 480,
                        time: .fourFour, key: KeySignature(fifths: key), clefs: [1: .treble, 2: .bass])
        return Score(title: "t", ticksPerQuarter: 480, tempoMap: TempoMap(bpm: 120), measures: [m], notes: notes)
    }

    private func note(_ id: Int, _ tick: Int, _ dur: Int, _ sp: Spelling, staff: Int = 1, voice: Int = 1,
                      type: NoteType = .quarter, tieStart: Bool = false, tieStop: Bool = false) -> Note {
        Note(id: id, startTick: tick, durationTicks: dur, spelling: sp, hand: staff == 1 ? .right : .left,
             staff: staff, voice: voice, noteType: type, tieStart: tieStart, tieStop: tieStop)
    }

    @Test func odeToJoy() {
        let e = EngravedScore(score: SampleScores.odeToJoy)
        #expect(e.measures.count == 4)
        let m0 = e.measures[0]
        // 右手4つ＋左手の和音1つ
        #expect(m0.chords.count == 5)
        let left = m0.chords.first { $0.staff == 2 }!
        #expect(left.heads.map(\.diatonic) == [21, 25])  // C3, G3
        #expect(left.noteType == .whole)
        // E4（d=30）は上向き
        #expect(m0.chords.first { $0.staff == 1 }!.stemUp)
        // 4小節目: 付点4分＋8分（旗）＋2分
        let m3 = e.measures[3].chords.filter { $0.staff == 1 }
        #expect(m3.map(\.dots) == [1, 0, 0])
        #expect(m3[1].flagCount == 1)
        #expect(m3[1].isBeamed == false)
    }

    @Test func stemRule() {
        #expect(EngravedScore.naturalStemUp(diatonics: [33], middle: 34))   // A4 上向き
        #expect(!EngravedScore.naturalStemUp(diatonics: [34], middle: 34))  // B4 下向き
        #expect(!EngravedScore.naturalStemUp(diatonics: [30, 40], middle: 34))
    }

    @Test func accidentalsFollowKeyAndMeasure() {
        // ト長調: F♯ は無印、F♮ にはナチュラル、同じ小節の2回目の F♮ は無印
        let fs = Spelling(step: .f, alter: 1, octave: 4)
        let fn = Spelling(step: .f, octave: 4)
        let e = EngravedScore(score: score([note(0, 0, 480, fs), note(1, 480, 480, fn), note(2, 960, 480, fn)], key: 1))
        let acc = e.measures[0].chords.map { $0.heads[0].accidental }
        #expect(acc == [nil, .natural, nil])
    }

    @Test func secondsAreShifted() {
        let e = EngravedScore(score: score([note(0, 0, 480, Spelling(step: .c, octave: 4)),
                                            note(1, 0, 480, Spelling(step: .d, octave: 4))]))
        let c = e.measures[0].chords[0]
        #expect(c.stemUp)
        #expect(c.heads.map(\.shifted) == [false, true])
    }

    @Test func autoBeamsByBeat() {
        let g = Spelling(step: .g, octave: 4)
        let notes = (0..<4).map { note($0, $0 * 240, 240, g, type: .eighth) }
        let e = EngravedScore(score: score(notes))
        #expect(e.measures[0].beams.count == 2)
        #expect(e.measures[0].chords.allSatisfy { $0.isBeamed })
    }

    @Test func explicitBeams() {
        let g = Spelling(step: .g, octave: 4)
        var notes = (0..<3).map { note($0, $0 * 240, 240, g, type: .eighth) }
        notes[0].beams = [1: .begin]; notes[1].beams = [1: .continue]; notes[2].beams = [1: .end]
        let e = EngravedScore(score: score(notes))
        #expect(e.measures[0].beams.map(\.chordIDs) == [[0, 1, 2]])
    }

    @Test func ties() {
        let c = Spelling(step: .c, octave: 5)
        let e = EngravedScore(score: score([note(0, 0, 960, c, type: .half, tieStart: true),
                                            note(1, 960, 960, c, type: .half, tieStop: true)]))
        #expect(e.measures[0].ties.count == 1)
        #expect(e.measures[0].ties[0].toChord == 1)
    }

    @Test func keySignaturePositions() {
        #expect(KeySignature(fifths: 1).accidentalDiatonics(clef: .treble) == [38])  // F5
        #expect(KeySignature(fifths: 1).accidentalDiatonics(clef: .bass) == [24])    // F3
        #expect(KeySignature(fifths: -2).accidentalDiatonics(clef: .bass) == [20, 23])  // B2 E3
        #expect(KeySignature(fifths: 2).alter(for: .c) == 1)
        #expect(KeySignature(fifths: -1).alter(for: .b) == -1)
    }

    @Test func paging() {
        let score = SampleScores.odeToJoy
        #expect(ScorePaging.state(score: score, beat: -2, rate: 1).page == 0)
        #expect(ScorePaging.state(score: score, beat: 15, rate: 1).page == 0)
    }

    @Test func geometryMatchesSpec() {
        let g = ScoreGeometry(size: ScoreGeometry.baseSize)
        #expect(g.bottomLineY(staff: 1) == 98)   // 画面座標 154 − 56
        #expect(g.bottomLineY(staff: 2) == 210)
        #expect(g.y(diatonic: 32, staff: 1, bottomDiatonic: 30) == 87)  // G4 = 第2線
        #expect(abs(g.measureWidth - 257.5) < 0.001)
        #expect(abs(g.x(slot: 0, fraction: 0.25) - (146 + 18 + (257.5 - 26) / 4)) < 0.001)
    }
}
