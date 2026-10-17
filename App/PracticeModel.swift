import CoreGraphics
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
    @ObservationIgnored let judge: PracticeJudge
    @ObservationIgnored private var updateTimer: Timer?
    /// 通し練習が終わったときに呼ぶ（ライブラリへの記録）
    @ObservationIgnored var onPassCompleted: ((PassResult, PracticeSettings) -> Void)?

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
            if settings.hands != oldValue.hands || settings.waitForCorrectKey != oldValue.waitForCorrectKey
                || settings.judgeWindow != oldValue.judgeWindow || settings.loopRange != oldValue.loopRange {
                configureJudge()
            }
            if settings.playInputSound != oldValue.playInputSound { configureInput() }
        }
    }

    /// 入力があったときに画面を描き直させる（停止中でも押した鍵を表示する）
    private(set) var inputRevision = 0
    /// 待機モードは MIDI キーボードがつながっているときだけ使える
    var isWaitAvailable: Bool { MIDIInput.shared.isConnected }

    private(set) var isPlaying = false
    /// 停止中に位置が変わったとき、画面を描き直させるためのカウンタ
    private(set) var seekRevision = 0

    init(score: Score, songID: UUID, settings: PracticeSettings = PracticeSettings(), lastBeat: Double? = nil) {
        self.score = score
        self.songID = songID
        self.settings = settings
        engraving = EngravedScore(score: score)
        clock = PracticeClock(tempoMap: score.tempoMap)
        judge = PracticeJudge(score: score, clock: clock)
        if let range = settings.loopRange, range.upperBound >= score.measures.count {
            self.settings.loopRange = nil
        }
        clock.setRate(self.settings.tempoRatio, atHost: CACurrentMediaTime())
        applyLoop()
        AudioEngine.shared.attach(score: score, clock: clock, settings: self.settings)
        configureJudge()
        configureInput()
        if let lastBeat, lastBeat > 0, lastBeat < score.lengthBeats {
            seek(toMeasure: score.measureIndex(atBeat: lastBeat))
        } else {
            rewind()
        }
        startUpdates()
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
        // ループ範囲: `-loop 1,2`（小節 index）
        if let loop = defaults.string(forKey: "loop")?.split(separator: ",").compactMap({ Int($0) }), loop.count == 2 {
            settings.loopRange = loop[0]...loop[1]
        }
        if defaults.bool(forKey: "darkLane") { settings.darkLane = true }
        if defaults.bool(forKey: "autoplay") { togglePlay() }
        // 譜面のドラッグの再現: `-demoScrubX 700`（13インチの譜面パネルの座標）
        if let x = defaults.string(forKey: "demoScrubX").flatMap(Double.init) {
            let geometry = ScoreGeometry(size: CGSize(width: 1376, height: 326))
            scrub(toX: x, geometry: geometry)
            endScrub()
        }
        // レーンのドラッグの再現: `-demoLaneDrag 160`（pt、下向きが正）
        if let dy = defaults.string(forKey: "demoLaneDrag").flatMap(Double.init) {
            scrubLane(translation: dy, pointsPerBeat: 500 / CGFloat(settings.lookaheadBeats))
            endScrub()
        }
        // 打鍵の再現: `-demoPress 64,70`
        if let list = defaults.string(forKey: "demoPress") {
            let now = CACurrentMediaTime()
            for midi in list.split(separator: ",").compactMap({ Int($0) }) {
                handleTouch(.down(midi: midi, velocity: 90, host: now))
            }
        }
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

    // MARK: - 判定・入力

    func configureJudge() {
        // 判定するのはループ範囲の小節だけ（助走の1小節は除く）
        let range = loopMeasures
        let judged = score.measures[safe: range.lowerBound].flatMap { first in
            score.measures[safe: range.upperBound].map { score.startBeat(of: first)..<score.endBeat(of: $0) }
        }
        judge.configure(settings: settings, waitEnabled: isWaitAvailable, loop: judged, atHost: CACurrentMediaTime())
    }

    /// MIDI と画面の鍵盤の入力を判定と音へつなぐ（MIDI スレッドから直接呼ばれる）
    private func configureInput() {
        let judge = self.judge
        let playSound = settings.playInputSound
        MIDIInput.shared.handler.set { [weak self] event in
            Self.route(event, judge: judge, playSound: playSound)
            Task { @MainActor in self?.inputRevision += 1 }
        }
    }

    nonisolated private static func route(_ event: KeyEvent, judge: PracticeJudge, playSound: Bool) {
        switch event {
        case .down(let midi, let velocity, let host):
            judge.noteOn(midi: midi, atHost: host)
            if playSound { AudioEngine.shared.playLive(midi: midi, velocity: velocity) }
        case .up(let midi, let host):
            judge.noteOff(midi: midi, atHost: host)
            if playSound { AudioEngine.shared.stopLive(midi: midi) }
        }
    }

    /// 画面の鍵盤のタッチ
    func handleTouch(_ event: KeyEvent) {
        Self.route(event, judge: judge, playSound: settings.playInputSound)
        inputRevision += 1
    }

    /// 見逃しの判定・ループの検出・通し練習の記録
    private func startUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        judge.update(atHost: CACurrentMediaTime())
        for pass in judge.takeCompletedPasses() { onPassCompleted?(pass, settings) }
    }

    func close() {
        updateTimer?.invalidate()
        updateTimer = nil
        MIDIInput.shared.handler.set(nil)
    }

    func midiConnectionChanged() {
        configureJudge()
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
        seek(toBeat: preRollStart(measure: index))
    }

    func seek(toBeat beat: Double) {
        let now = CACurrentMediaTime()
        clock.setGate(beat: nil, atHost: now)
        clock.seek(toBeat: beat, atHost: now)
        judge.reset(toBeat: beat, atHost: now, recordPass: false)
        seekRevision += 1
        AudioEngine.shared.resetPosition()
    }

    // MARK: - 譜面・レーンのドラッグで位置を変える

    /// 譜面のドラッグ中に表示を固定するページ
    private(set) var scrubPage: Int?
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var resumeAfterScrub = false
    /// レーンのドラッグを始めたときの拍
    @ObservationIgnored private var laneScrubStartBeat: Double?

    /// 動かせる範囲（ループ範囲と、その前の助走の1小節）
    private var scrubRange: ClosedRange<Double> {
        let range = loopMeasures
        let start = preRollStart(measure: range.lowerBound)
        let end = score.measures[safe: range.upperBound].map { score.endBeat(of: $0) } ?? score.lengthBeats
        return start...max(start, end - 1e-6)
    }

    /// ドラッグを始める（再生中なら一時停止し、離したら再開する）
    private func beginScrub() {
        guard !isScrubbing else { return }
        isScrubbing = true
        resumeAfterScrub = isPlaying
        if isPlaying { togglePlay() }
    }

    private func clampedSeek(_ beat: Double) {
        seek(toBeat: min(max(beat, scrubRange.lowerBound), scrubRange.upperBound))
    }

    /// 譜面: 触れた x の位置へ（ドラッグ中はページを固定する）
    func scrub(toX x: CGFloat, geometry: ScoreGeometry) {
        if scrubPage == nil {
            beginScrub()
            scrubPage = ScorePaging.state(score: score, beat: currentBeat, rate: settings.tempoRatio).page
        }
        guard let page = scrubPage else { return }
        clampedSeek(ScorePaging.beat(atX: x, page: page, score: score, geometry: geometry))
    }

    /// レーン: 下へドラッグすると先へ進む（ノーツが指についてくる）。1拍の高さで1拍
    func scrubLane(translation dy: CGFloat, pointsPerBeat: CGFloat) {
        if laneScrubStartBeat == nil {
            beginScrub()
            laneScrubStartBeat = currentBeat
        }
        guard let start = laneScrubStartBeat, pointsPerBeat > 0 else { return }
        clampedSeek(start + Double(dy / pointsPerBeat))
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        laneScrubStartBeat = nil
        let snapped = ScorePaging.snapToBeat(currentBeat, score: score)
        seek(toBeat: min(max(snapped, scrubRange.lowerBound), scrubRange.upperBound))
        scrubPage = nil
        if resumeAfterScrub { togglePlay() }
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
