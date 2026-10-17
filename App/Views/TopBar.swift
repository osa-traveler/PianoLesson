import PianoCore
import SwiftUI

/// トップバー（仕様 3.1）
struct TopBar: View {
    @Bindable var model: PracticeModel
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconButton(systemName: "chevron.left") { onBack() }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.score.title).font(.ui(15, .bold)).foregroundStyle(Theme.ink)
                Text(model.metaText).font(.ui(11)).foregroundStyle(Theme.sub)
            }
            .lineLimit(1)

            Spacer(minLength: 10)

            IconButton(systemName: "backward.end.fill") { model.rewind() }

            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 44)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10))
            }

            tempo
            HandsPicker(selection: $model.settings.hands)
            GuideToggle(isOn: $model.settings.showStaffGuides)
            WaitToggle(isOn: $model.settings.waitForCorrectKey, isAvailable: model.isWaitAvailable)
            SettingsButton(settings: $model.settings)
            LoopButton(model: model)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }

    private var tempo: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "minus") { model.changeTempo(steps: -1) }
            VStack(spacing: 0) {
                Text("♩ = \(model.displayBPM)").font(.ui(15, .bold).monospacedDigit())
                Text("原曲の\(model.tempoPercent)%").font(.ui(10).monospacedDigit()).foregroundStyle(Theme.sub)
            }
            .foregroundStyle(Theme.ink)
            .frame(width: 76)
            IconButton(systemName: "plus") { model.changeTempo(steps: 1) }
        }
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.button, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// 右手／両手／左手のセグメント
private struct HandsPicker: View {
    @Binding var selection: HandsMode

    var body: some View {
        HStack(spacing: 2) {
            segment(.right, "右手", Theme.handR)
            segment(.both, "両手", Theme.ink)
            segment(.left, "左手", Theme.handL)
        }
        .padding(3)
        .background(Theme.button, in: RoundedRectangle(cornerRadius: 10))
    }

    private func segment(_ mode: HandsMode, _ label: String, _ color: Color) -> some View {
        Button { selection = mode } label: {
            Text(label)
                .font(.ui(13, .bold))
                .foregroundStyle(color)
                .frame(width: 52, height: 38)
                .background {
                    if selection == mode {
                        RoundedRectangle(cornerRadius: 8).fill(.white)
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    }
                }
        }
    }
}

private struct GuideToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .rotationEffect(.degrees(90))
                Text("五線ガイド").font(.ui(13, .medium))
            }
            .foregroundStyle(isOn ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(isOn ? Theme.handR : Theme.button, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// 設定（表示・判定・音）
private struct SettingsButton: View {
    @Binding var settings: PracticeSettings
    @State private var showing = false
    @State private var showingBluetooth = false

    var body: some View {
        IconButton(systemName: "gearshape.fill") { showing = true }
            .sheet(isPresented: $showingBluetooth) {
                BluetoothMIDIView { showingBluetooth = false }
            }
            .popover(isPresented: $showing) {
                Form {
                    Section("MIDI キーボード") {
                        let names = MIDIInput.shared.sourceNames
                        if names.isEmpty {
                            Text("つながっていません").foregroundStyle(Theme.sub)
                        }
                        ForEach(names, id: \.self) { name in
                            Label(name, systemImage: "pianokeys").foregroundStyle(Theme.ink)
                        }
                        Button("Bluetooth MIDI を接続…") {
                            showing = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                showingBluetooth = true
                            }
                        }
                    }
                    Section("表示") {
                        Picker("音名", selection: $settings.naming) {
                            Text("C D E").tag(Naming.cde)
                            Text("ド レ ミ").tag(Naming.doremi)
                        }
                        .pickerStyle(.segmented)
                        Stepper("先読み \(Int(settings.lookaheadBeats)) 拍", value: $settings.lookaheadBeats,
                                in: PracticeSettings.lookaheadRange, step: 1)
                        Toggle("レーンを暗くする", isOn: $settings.darkLane)
                    }
                    Section {
                        LabeledContent("判定の幅") {
                            Text("±\(Int((settings.judgeWindow * 1000).rounded())) ms").monospacedDigit()
                        }
                        Slider(value: $settings.judgeWindow, in: 0.05...0.25, step: 0.01)
                    } header: {
                        Text("判定")
                    } footer: {
                        Text("この幅の中で押せば OK、外なら「早い」「遅い」になります。")
                    }
                    Section("音") {
                        slider("右手", $settings.rightVolume, Theme.handR)
                        slider("左手", $settings.leftVolume, Theme.handL)
                        slider("メトロノーム", $settings.metronomeVolume, Theme.ink)
                        Toggle("メトロノーム", isOn: $settings.metronomeOn)
                        Toggle(isOn: $settings.playInputSound) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("弾いた音をアプリで鳴らす")
                                Text("音の出る電子ピアノならオフに").font(.ui(11)).foregroundStyle(Theme.sub)
                            }
                        }
                        Toggle(isOn: $settings.playPracticedHands) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("練習する手もお手本の音を鳴らす")
                                Text("MIDI キーボードで弾くときはオフに").font(.ui(11)).foregroundStyle(Theme.sub)
                            }
                        }
                    }
                }
                .font(.ui(14))
                .frame(width: 400, height: 640)
            }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ color: Color) -> some View {
        HStack {
            Text(label).frame(width: 96, alignment: .leading).foregroundStyle(color)
            Slider(value: value, in: 0...1).tint(color)
        }
    }
}

/// ループ範囲（開始小節〜終了小節）
private struct LoopButton: View {
    let model: PracticeModel
    @State private var showing = false
    @State private var start = 0
    @State private var end = 0

    var body: some View {
        Button {
            start = model.loopMeasures.lowerBound
            end = model.loopMeasures.upperBound
            showing = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                Text(model.loopText).font(.ui(13, .medium))
            }
            .foregroundStyle(model.settings.loopRange == nil ? Theme.ink : .white)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(model.settings.loopRange == nil ? Theme.button : Theme.handR,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .popover(isPresented: $showing) {
            let count = model.score.measures.count
            VStack(alignment: .leading, spacing: 16) {
                Text("ループ範囲").font(.ui(15, .bold))
                Stepper("開始 \(number(start))小節", value: $start, in: 0...max(0, count - 1))
                    .onChange(of: start) { _, v in if end < v { end = v } }
                Stepper("終了 \(number(end))小節", value: $end, in: 0...max(0, count - 1))
                    .onChange(of: end) { _, v in if start > v { start = v } }
                HStack {
                    Button("曲全体") {
                        model.settings.loopRange = nil
                        showing = false
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("この範囲で練習") {
                        model.settings.loopRange = (start == 0 && end == count - 1) ? nil : start...end
                        showing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.ui(14))
            .padding(20)
            .frame(width: 320)
        }
    }

    private func number(_ index: Int) -> String {
        model.score.measures[safe: index]?.number ?? String(index + 1)
    }
}

/// 正しい鍵まで待つ（MIDI キーボードが無いときは使えない）
private struct WaitToggle: View {
    @Binding var isOn: Bool
    let isAvailable: Bool

    var body: some View {
        let active = isOn && isAvailable
        Button { isOn.toggle() } label: {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fill")
                    Text("待つ").font(.ui(13, .medium))
                }
                if !isAvailable {
                    Text("MIDIなし").font(.ui(9)).foregroundStyle(Theme.subLight)
                }
            }
            .foregroundStyle(active ? .white : (isAvailable ? Theme.ink : Theme.subLight))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(active ? Theme.handR : Theme.button, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!isAvailable)
        .accessibilityHint(isAvailable ? "正しい鍵を押すまで止まります" : "MIDI キーボードをつなぐと使えます")
    }
}
