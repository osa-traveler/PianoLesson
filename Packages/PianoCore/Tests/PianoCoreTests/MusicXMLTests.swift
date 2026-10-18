import Foundation
import Testing
@testable import PianoCore

@Suite struct MusicXMLTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func check(_ result: ImportResult) {
        let score = result.score
        #expect(score.title == "Test Piece")
        #expect(score.composer == "PianoPractice")
        #expect(score.tempoMap.initialBPM == 90)
        // 弱起（1拍）＋ 3/4 が2小節
        #expect(score.measures.map(\.lengthTicks) == [480, 1440, 1440])
        #expect(score.measures[0].key.fifths == 1)
        #expect(score.measures[1].time == TimeSignature(beats: 3, beatType: 4))
        // 2つ目のパート（Piano, staves=2）を使う
        #expect(score.notes.contains { $0.hand == .left })
        // タイは1本: G3 が 6 拍
        let g3 = score.playNotes.filter { $0.midi == 55 }
        #expect(g3.count == 1)
        #expect(g3.first?.lengthBeats == 6)
        #expect(g3.first?.hand == .left)
        // 和音 C5+E5 は同時
        let chord = score.playNotes.filter { $0.startBeat == 3 }
        #expect(chord.map(\.midi) == [72, 76])
        // 明記された臨時記号・連桁・符幹・指番号
        let f = score.notes.first { $0.spelling?.step == .f }
        #expect(f?.accidental == .natural)
        #expect(f?.fingering == 2)
        #expect(score.notes.first { $0.spelling?.step == .g && $0.staff == 1 }?.beams[1] == .begin)
        // 休符の表示位置 D3
        #expect(score.notes.first { $0.isRest }?.restDiatonic == 22)
        // 装飾音は読み飛ばし、警告を出す
        #expect(!score.notes.contains { $0.spelling?.step == .a && $0.durationTicks == 0 })
        #expect(result.warnings.contains { $0.contains("装飾音") })
        #expect(result.warnings.contains { $0.contains("繰り返し") })
        #expect(result.warnings.contains { $0.contains("Piano") })
    }

    @Test func plainXML() throws {
        check(try MusicXMLImporter.load(data: fixture("test-piece.musicxml"), fallbackTitle: "x"))
    }

    @Test func compressedMXL() throws {
        check(try MusicXMLImporter.load(data: fixture("test-piece.mxl"), fallbackTitle: "x"))
    }

    @Test func engravesImportedScore() throws {
        let score = try MusicXMLImporter.load(data: fixture("test-piece.musicxml"), fallbackTitle: "x").score
        let e = EngravedScore(score: score)
        #expect(e.measures[1].beams.count == 1)
        #expect(e.measures[1].ties.first?.toChord != nil)
        // ト長調で F♮ に明記のナチュラル
        #expect(e.measures[2].chords.first { $0.staff == 1 }?.heads.first?.accidental == .natural)
    }

    @Test func rejectsTimewise() {
        let xml = Data("<score-timewise><part-list/></score-timewise>".utf8)
        #expect(throws: MusicXMLError.self) { try MusicXMLImporter.load(data: xml, fallbackTitle: "x") }
    }

    /// 手元にある実際の楽譜（git 管理外）を、止まらずに読めるか確認する
    @Test func localSampleIfPresent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../../private/sample.mxl").standardized
        guard let data = try? Data(contentsOf: url) else { return }
        let result = try MusicXMLImporter.load(data: data, fallbackTitle: "sample")
        #expect(result.score.measures.count == 16)
        #expect(result.score.notes.contains { $0.hand == .left })
        _ = EngravedScore(score: result.score)
        print("sample warnings:", result.warnings)
    }
}
