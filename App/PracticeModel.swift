import Foundation
import Observation
import PianoCore
import QuartzCore

/// 練習画面の状態。毎フレーム変わる再生位置は clock から直接読み、ここでは監視しない。
@MainActor @Observable
final class PracticeModel {
    let score: Score
    let engraving: EngravedScore
    let songID: UUID
    @ObservationIgnored let clock: PracticeClock

    var settings: PracticeSettings {
        didSet {
            AudioEngine.shared.update(settings: settings)
            if settings.tempoRatio != oldValue.tempoRatio {
                clock.setRate(settings.tempoRatio, atHost: CACurrentMediaTime())
            }
            if settings.loopRange != oldValue.loopRange {
                applyLoop()
                rewind()
            }
        }
    }

    private(set) var isPlaying = false
    /// 停止中に位置が変わったとき、画面を描き直させるためのカウンタ
    private(set) var seekRevision = 0

    init(score: Score, songID: UUID, settings: PracticeSettings = PracticeSettings(), lastBeat: Double? = nil) {
        self.score = score
        self.songID = songID
        self.settings = settings
        engraving = EngravedScore(score: score)
        clock = PracticeClock(tempoMap: score.tempoMap)
        if let range = settings.loopRange, range.upperBound >= score.measures.count {
            self.settings.loopRange = nil
        }
        clock.setRate(self.settings.tempoRatio, atHost: CACurrentMediaTime())
        applyLoop()
        AudioEngine.shared.attach(score: score, clock: clock, settings: self.settings)
        if let lastBeat, lastBeat > 0, lastBeat < score.lengthBeats {
            seek(toMeasure: score.measureIndex(atBeat: lastBeat))
        } else {
            rewind()
        }
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

    /// ループ範囲（小節 index）。未設定なら曲全体
    var loopMeasures: ClosedRange<Int> {
        settings.loopRange ?? 0...max(0, score.measures.count - 1)
    }

    private func leadIn(before measureIndex: Int) -> Double {
        score.measures.indices.contains(measureIndex) ? score.measures[measureIndex].time.measureLength : 4
    }

    /// 指定した小節の1小節前から始めて、最初の音が上から落ちてくるようにする
    private func preRollStart(measure: Int) -> Double {
        guard score.measures.indices.contains(measure) else { return -4 }
        return score.startBeat(of: score.measures[measure]) - leadIn(before: measure)
    }

    private func applyLoop() {
        let range = loopMeasures
        guard score.measures.indices.contains(range.lowerBound),
              score.measures.indices.contains(range.upperBound) else {
            clock.setLoop(beats: nil)
            return
        }
        let start = preRollStart(measure: range.lowerBound)
        let end = score.endBeat(of: score.measures[range.upperBound])
        clock.setLoop(beats: start..<end)
    }

    func togglePlay() {
        let now = CACurrentMediaTime()
        if isPlaying { clock.pause(atHost: now) } else { clock.start(atHost: now) }
        isPlaying.toggle()
        AudioEngine.shared.resetPosition()
    }

    func pause() {
        if isPlaying { togglePlay() }
    }

    func rewind() {
        seek(toMeasure: loopMeasures.lowerBound)
    }

    func seek(toMeasure index: Int) {
        clock.seek(toBeat: preRollStart(measure: index), atHost: CACurrentMediaTime())
        seekRevision += 1
        AudioEngine.shared.resetPosition()
    }

    var currentBeat: Double { clock.beat(atHost: CACurrentMediaTime()) }

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
        let r = loopMeasures
        return "\(score.measures[safe: r.lowerBound]?.number ?? "1")–\(score.measures[safe: r.upperBound]?.number ?? "")小節"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
