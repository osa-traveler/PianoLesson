import PianoCore
import SwiftUI

/// トップバー（仕様 3.1）
struct TopBar: View {
    @Bindable var model: PracticeModel

    var body: some View {
        HStack(spacing: 10) {
            IconButton(systemName: "chevron.left") {}
                .disabled(true)  // 曲ライブラリは Phase 4

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

            Button {} label: {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                    Text(model.loopText).font(.ui(13, .medium))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.button, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(true)  // ループ範囲のシートは Phase 6
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
