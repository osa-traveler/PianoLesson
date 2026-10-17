import AVFoundation
import PianoCore
import Synchronization

/// 音を鳴らす（右手・左手の Sampler と、メトロノームのクリック）。
/// 再生中の発音は専用キューのタイマーで行い、出力レイテンシのぶん早めに鳴らして画面と揃える。
final class AudioEngine: @unchecked Sendable {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let samplers: [Hand: AVAudioUnitSampler] = [.right: AVAudioUnitSampler(), .left: AVAudioUnitSampler()]
    private let clickPlayer = AVAudioPlayerNode()
    private let clickBuffers: (accent: AVAudioPCMBuffer, normal: AVAudioPCMBuffer)?
    private let queue = DispatchQueue(label: "PianoPractice.audio", qos: .userInteractive)

    private struct Session {
        var score: Score?
        var clock: PracticeClock?
        var settings = PracticeSettings()
        var lastBeat: Double?
        var sounding: Set<NoteKey> = []
    }

    private struct NoteKey: Hashable {
        var midi: Int
        var hand: Hand
    }

    private let state = Mutex(Session())
    private let timer: Mutex<DispatchSourceTimer?> = Mutex(nil)
    private let clickFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    /// オーディオキュー上でだけ触る
    nonisolated(unsafe) private var isSetUp = false

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        clickBuffers = Self.makeClick(format: format, frequency: 1_800).flatMap { accent in
            Self.makeClick(format: format, frequency: 1_200).map { (accent, $0) }
        }
    }

    /// セッション設定・グラフ構築・音源の読み込み（重いのでオーディオキューで行う）
    private func setUpIfNeeded() {
        guard !isSetUp else { return }
        isSetUp = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("オーディオセッションを設定できません: \(error)")
        }
        for sampler in samplers.values {
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        }
        engine.attach(clickPlayer)
        engine.connect(clickPlayer, to: engine.mainMixerNode, format: clickFormat)
        loadPiano()
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: nil) { [weak self] _ in self?.restart() }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: nil) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended { self?.restart() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                               queue: nil) { [weak self] _ in
            self?.queue.async { self?.updateLatency() }
        }
    }

    /// 同梱の SF2 を読む。無ければ Sampler の既定の音（サイン波）のまま
    private func loadPiano() {
        guard let url = Bundle.main.url(forResource: "UprightPianoKW", withExtension: "sf2") else {
            print("ピアノ音源がありません。scripts/fetch-soundfont.sh を実行してください")
            return
        }
        for sampler in samplers.values {
            do {
                try sampler.loadSoundBankInstrument(at: url, program: 0,
                                                    bankMSB: 0x79, bankLSB: 0)  // メロディ楽器のバンク
            } catch {
                print("音源を読み込めません: \(error)")
            }
        }
    }

    func start() {
        #if DEBUG
        // 確認用: `-noAudio YES`（この Mac の iOS 26.5 シミュレータは CoreAudio が RPC タイムアウトで落ちるため）
        if UserDefaults.standard.bool(forKey: "noAudio") { return }
        #endif
        queue.async { [self] in
            setUpIfNeeded()
            do {
                if !engine.isRunning { try engine.start() }
                clickPlayer.play()
            } catch {
                print("オーディオを開始できません: \(error)")
            }
            updateLatency()
            startTimer()
        }
    }

    private func restart() {
        queue.async { [self] in
            guard isSetUp else { return }
            allNotesOff()
            if !engine.isRunning { try? engine.start() }
            clickPlayer.play()
        }
    }

    // MARK: - 練習中の曲

    func attach(score: Score, clock: PracticeClock, settings: PracticeSettings) {
        queue.async { [self] in
            allNotesOff()
            state.withLock { $0 = Session(score: score, clock: clock, settings: settings) }
        }
        apply(settings)
    }

    func detach() {
        queue.async { [self] in
            allNotesOff()
            state.withLock { $0 = Session() }
        }
    }

    func update(settings: PracticeSettings) {
        state.withLock { $0.settings = settings }
        apply(settings)
    }

    private func apply(_ settings: PracticeSettings) {
        queue.async { [self] in
            samplers[.right]?.volume = Float(settings.rightVolume)
            samplers[.left]?.volume = Float(settings.leftVolume)
            clickPlayer.volume = Float(settings.metronomeVolume)
        }
    }

    /// 位置が飛んだとき（先頭へ・ループ・一時停止）に鳴っている音を止める
    func resetPosition() {
        queue.async { [self] in
            allNotesOff()
            state.withLock { $0.lastBeat = nil }
        }
    }

    // MARK: - 鍵盤のタッチ・MIDI 入力

    /// 弾いた音は、その音域の手の Sampler で鳴らす（チャンネル 1 を使い、自動演奏の音と分ける）
    func playLive(midi: Int, velocity: UInt8 = 90) {
        queue.async { [self] in
            samplers[midi >= 60 ? .right : .left]?.startNote(UInt8(midi), withVelocity: velocity, onChannel: 1)
        }
    }

    func stopLive(midi: Int) {
        queue.async { [self] in
            samplers[midi >= 60 ? .right : .left]?.stopNote(UInt8(midi), onChannel: 1)
        }
    }

    // MARK: - スケジューラ

    private func startTimer() {
        timer.withLock { t in
            guard t == nil else { return }
            let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            source.setEventHandler { [weak self] in self?.tick() }
            source.resume()
            t = source
        }
    }

    /// 出力レイテンシ（秒）。問い合わせはオーディオサーバとの通信になるので、経路が変わったときだけ更新する
    private let outputLatency = Mutex(0.0)

    private func updateLatency() {
        let session = AVAudioSession.sharedInstance()
        let value = session.outputLatency + session.ioBufferDuration
        outputLatency.withLock { $0 = value }
    }

    private func tick() {
        let snapshot = state.withLock { $0 }
        guard let score = snapshot.score, let clock = snapshot.clock else { return }
        guard clock.isRunning else {
            if !snapshot.sounding.isEmpty { allNotesOff() }
            state.withLock { $0.lastBeat = nil }
            return
        }
        var beat = clock.beat(atHost: CACurrentMediaTime() + outputLatency.withLock { $0 })
        // 待機モードで止まっている拍の音（自動演奏の手）は、正しい鍵が押されて進むまで鳴らさない
        if let gate = clock.gateBeat, beat >= gate - 1e-9 { beat = gate - 1e-6 }
        guard let last = snapshot.lastBeat, beat >= last, beat - last < 2 else {
            // 開始直後・ループ・シーク
            if snapshot.lastBeat != nil { allNotesOff() }
            state.withLock { $0.lastBeat = beat - 1e-6 }
            return
        }
        let events = PlaybackPlanner.events(score: score, from: last, to: beat, settings: snapshot.settings)
        var sounding = snapshot.sounding
        for event in events {
            switch event {
            case .noteOff(let midi, let hand):
                if sounding.remove(NoteKey(midi: midi, hand: hand)) != nil {
                    samplers[hand]?.stopNote(UInt8(midi), onChannel: 0)
                }
            case .noteOn(let midi, let hand):
                samplers[hand]?.startNote(UInt8(midi), withVelocity: 80, onChannel: 0)
                sounding.insert(NoteKey(midi: midi, hand: hand))
            case .click(let accent):
                if let buffers = clickBuffers {
                    clickPlayer.scheduleBuffer(accent ? buffers.accent : buffers.normal, at: nil, options: [])
                }
            }
        }
        state.withLock {
            $0.lastBeat = beat
            $0.sounding = sounding
        }
    }

    private func allNotesOff() {
        let sounding = state.withLock { s -> Set<NoteKey> in
            let v = s.sounding
            s.sounding = []
            return v
        }
        for key in sounding { samplers[key.hand]?.stopNote(UInt8(key.midi), onChannel: 0) }
    }

    private static func makeClick(format: AVAudioFormat, frequency: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * 0.04)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            data[i] = Float(sin(2 * .pi * frequency * t) * exp(-t * 90) * 0.8)
        }
        return buffer
    }
}
