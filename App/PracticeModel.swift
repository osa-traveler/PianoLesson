import Foundation
import Observation
import PianoCore
import QuartzCore

/// 練習画面の状態。毎フレーム変わる再生位置は clock から直接読み、ここでは監視しない。
@MainActor @Observable
final class PracticeModel {
    let score: Score
    let engraving: EngravedScore
    @ObservationIgnored let clock: PracticeClock

    var settings = PracticeSettings() {
        didSet {
            if settings.tempoRatio != oldValue.tempoRatio {
                clock.setRate(settings.tempoRatio, atHost: CACurrentMediaTime())
            }
        }
    }

    private(set) var isPlaying = false
    /// 停止中に位置が変わったとき、画面を描き直させるためのカウンタ
    private(set) var seekRevision = 0

    init(score: Score) {
        self.score = score
        engraving = EngravedScore(score: score)
        clock = PracticeClock(tempoMap: score.tempoMap)
        clock.setRate(settings.tempoRatio, atHost: CACurrentMediaTime())
        clock.setLoop(beats: preRollStart..<score.lengthBeats)
        clock.seek(toBeat: preRollStart, atHost: CACurrentMediaTime())
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// 確認用: `-startBeat 5.5` で位置を指定、`-autoplay YES` で再生開始、`-hands left` など
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let beat = defaults.object(forKey: "startBeat") as? String, let b = Double(beat) {
            clock.seek(toBeat: b, atHost: CACurrentMediaTime())
        }
        if let hands = defaults.string(forKey: "hands"), let mode = HandsMode(rawValue: hands) {
            settings.hands = mode
        }
        if defaults.string(forKey: "naming") == "doremi" { settings.naming = .doremi }
        if defaults.bool(forKey: "darkLane") { settings.darkLane = true }
        if defaults.bool(forKey: "autoplay") { togglePlay() }
    }
    #endif

    /// 先頭の1小節前から始めて、最初の音が上から落ちてくるようにする
    var preRollStart: Double {
        -(score.measures.first?.time.measureLength ?? 4)
    }

    func togglePlay() {
        let now = CACurrentMediaTime()
        if isPlaying { clock.pause(atHost: now) } else { clock.start(atHost: now) }
        isPlaying.toggle()
    }

    func rewind() {
        clock.seek(toBeat: preRollStart, atHost: CACurrentMediaTime())
        seekRevision += 1
    }

    func changeTempo(steps: Int) {
        let r = settings.tempoRatio + Double(steps) * PracticeSettings.tempoRatioStep
        let range = PracticeSettings.tempoRatioRange
        settings.tempoRatio = (min(max(r, range.lowerBound), range.upperBound) * 100).rounded() / 100
    }

    var tempoPercent: Int { Int((settings.tempoRatio * 100).rounded()) }
    var displayBPM: Int { Int((score.tempoMap.initialBPM * settings.tempoRatio).rounded()) }

    var metaText: String {
        let first = score.measures.first
        let time = first.map { "\($0.time.beats)/\($0.time.beatType)" } ?? "4/4"
        let key = first?.key.japaneseMajorName ?? "ハ長調"
        return "MusicXML · \(key) · \(time) · \(score.measures.count)小節"
    }

    var loopText: String {
        if let r = settings.loopRange { return "\(r.lowerBound + 1)–\(r.upperBound + 1)小節" }
        return "1–\(score.measures.count)小節"
    }
}
