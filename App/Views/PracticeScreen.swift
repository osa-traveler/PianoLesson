import PianoCore
import QuartzCore
import SwiftUI

/// 練習画面（上から トップバー／譜面／落下レーン／鍵盤）
struct PracticeScreen: View {
    @Bindable var model: PracticeModel

    static let topBarHeight: CGFloat = 56
    static let keyboardHeight: CGFloat = 150
    /// 譜面：レーン = 248：380（基準 1194×834）
    static let scoreShare: CGFloat = 248.0 / (248 + 380)

    var body: some View {
        GeometryReader { geo in
            let rest = geo.size.height - Self.topBarHeight - Self.keyboardHeight
            let scoreHeight = (rest * Self.scoreShare).rounded()
            let laneHeight = rest - scoreHeight
            let layout = KeyboardLayout(range: KeyboardLayout.autoRange(for: model.score.midiRange),
                                        width: geo.size.width)

            VStack(spacing: 0) {
                TopBar(model: model)
                    .frame(height: Self.topBarHeight)
                TimelineView(.animation(paused: !model.isPlaying)) { context in
                    let _ = model.seekRevision
                    let beat = model.clock.beat(atHost: Self.hostTime(for: context.date))
                    PlayField(model: model, layout: layout, beat: beat,
                              scoreHeight: scoreHeight, laneHeight: laneHeight)
                }
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: model.isPlaying) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = playing
        }
    }

    /// TimelineView の表示予定時刻をホスト時刻（CACurrentMediaTime）に直す
    static func hostTime(for date: Date) -> Double {
        CACurrentMediaTime() + date.timeIntervalSinceNow
    }
}

/// 1フレームぶんの譜面・レーン・鍵盤。現在の拍は1回だけ求めて全部に渡す。
private struct PlayField: View {
    let model: PracticeModel
    let layout: KeyboardLayout
    let beat: Double
    let scoreHeight: CGFloat
    let laneHeight: CGFloat

    var body: some View {
        let settings = model.settings
        let highlights = KeyStates.compute(score: model.score, beat: beat, hands: settings.hands)
        VStack(spacing: 0) {
            ScoreCanvas(score: model.score, engraving: model.engraving, beat: beat, settings: settings)
                .frame(height: scoreHeight)
            LaneCanvas(score: model.score, layout: layout, beat: beat, settings: settings)
                .frame(height: laneHeight)
                .overlay(alignment: .topTrailing) {
                    NextChip(notes: KeyStates.nextNotes(score: model.score, beat: beat, hands: settings.hands),
                             naming: settings.naming)
                        .padding(.top, 28)
                        .padding(.trailing, 16)
                }
                .overlay(alignment: .bottomLeading) {
                    if settings.showStaffGuides {
                        GuideLegend()
                            .padding(.leading, 12)
                            .padding(.bottom, 14)
                    }
                }
            KeyboardCanvas(layout: layout, highlights: highlights,
                           showGuides: settings.showStaffGuides, naming: settings.naming)
                .frame(height: PracticeScreen.keyboardHeight)
        }
    }
}
