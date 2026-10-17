import PianoCore
import SwiftUI

/// 落下レーン（仕様 6章）。下端が判定ライン。
struct LaneCanvas: View {
    let score: Score
    let layout: KeyboardLayout
    let beat: Double
    let settings: PracticeSettings
    var judge = JudgeSnapshot()

    var body: some View {
        Canvas { context, size in
            let lane = LaneMetrics(height: size.height, lookaheadBeats: settings.lookaheadBeats)
            let palette = LanePalette(dark: settings.darkLane)
            drawBackground(&context, size: size, lane: lane, palette: palette)
            drawNotes(&context, lane: lane)
            if settings.showStaffGuides {
                drawGuides(&context, size: size, palette: palette)
            }
            drawJudgements(&context, lane: lane)
            // 判定ライン
            context.fill(Path(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3)),
                         with: .color(palette.judgeLine))
        }
    }

    private func drawBackground(_ context: inout GraphicsContext, size: CGSize, lane: LaneMetrics,
                                palette: LanePalette) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

        for midi in layout.blackKeys {
            let x = layout.keyCenterX(midi: midi) - layout.blackKeyWidth / 2
            context.fill(Path(CGRect(x: x, y: 0, width: layout.blackKeyWidth, height: size.height)),
                         with: .color(palette.blackColumn))
        }

        let top = beat + settings.lookaheadBeats
        for measure in score.measures {
            let start = score.startBeat(of: measure)
            let end = score.endBeat(of: measure)
            guard end >= beat, start <= top else { continue }
            var b = start + measure.time.beatUnit
            while b < end - 1e-6 {
                let y = lane.y(beat: b, now: beat)
                context.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)),
                             with: .color(palette.beatLine))
                b += measure.time.beatUnit
            }
            let y = lane.y(beat: start, now: beat)
            context.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 2)),
                         with: .color(palette.barLine))
            context.draw(Text("\(measure.number)小節").font(.ui(11, .bold)).foregroundStyle(palette.barLabel),
                         at: CGPoint(x: 8, y: y - 3), anchor: .bottomLeading)
        }
    }

    private func drawNotes(_ context: inout GraphicsContext, lane: LaneMetrics) {
        let height = lane.height
        for note in score.playNotes(overlapping: beat, beat + settings.lookaheadBeats) {
            guard layout.contains(note.midi) else { continue }
            let bottom = min(lane.y(beat: note.startBeat, now: beat), height)
            let top = lane.y(beat: note.endBeat, now: beat) + 3
            guard bottom - top > 1 else { continue }

            let black = Pitch.isBlack(note.midi)
            let width = black ? layout.blackKeyWidth - 6 : layout.whiteKeyWidth - 10
            let rect = CGRect(x: layout.keyCenterX(midi: note.midi) - width / 2, y: top,
                              width: width, height: bottom - top)
            let sounding = note.startBeat <= beat && beat < note.endBeat

            var c = context
            c.opacity = settings.hands.practices(note.hand) ? 1 : 0.35
            if sounding {
                c.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 10),
                       with: .color(Theme.tint(note.hand)))
            }
            c.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(Theme.hand(note.hand)))
            if rect.height >= 22 {
                let name = NoteNaming.laneName(note.spelling, settings.naming)
                let fontSize: CGFloat = name.count > 2 && black ? 11 : 13
                c.draw(Text(name).font(.ui(fontSize, .bold)).foregroundStyle(.white),
                       at: CGPoint(x: rect.midX, y: rect.maxY - 4), anchor: .bottom)
            }
        }
    }

    /// 判定結果: ノーツが判定ラインで消えるときに短く表示（OK は手の色で光る、ミスは赤い縁）
    private func drawJudgements(_ context: inout GraphicsContext, lane: LaneMetrics) {
        guard !judge.results.isEmpty else { return }
        let fade = 0.75  // 拍
        for note in score.playNotes(overlapping: beat - fade, beat + 0.5) {
            guard let result = judge.results[note.id], layout.contains(note.midi) else { continue }
            let age = beat - note.startBeat
            guard age > -0.5, age < fade else { continue }
            let alpha = min(1, max(0, 1 - max(age, 0) / fade))
            let black = Pitch.isBlack(note.midi)
            let width = (black ? layout.blackKeyWidth - 6 : layout.whiteKeyWidth - 10) + 8
            let rect = CGRect(x: layout.keyCenterX(midi: note.midi) - width / 2, y: lane.height - 26,
                              width: width, height: 22)
            var c = context
            c.opacity = alpha
            switch result.judgement {
            case .ok:
                c.fill(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 10),
                       with: .color(Theme.tint(note.hand)))
                c.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Theme.hand(note.hand)))
                c.draw(Text("OK").font(.ui(12, .bold)).foregroundStyle(.white),
                       at: CGPoint(x: rect.midX, y: rect.midY))
            case .early, .late, .missed:
                c.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(Theme.miss), lineWidth: 3)
                let label = result.judgement == Judgement.early ? "早い" : result.judgement == Judgement.late ? "遅い" : "ミス"
                c.draw(Text(label).font(.ui(11, .bold)).foregroundStyle(Theme.miss),
                       at: CGPoint(x: rect.midX, y: rect.minY - 9))
            }
        }
    }

    /// 五線ガイド。ノーツより手前に描き、線上の音はノーツを貫いて見えるようにする。
    private func drawGuides(_ context: inout GraphicsContext, size: CGSize, palette: LanePalette) {
        for (midis, hand) in [(StaffGuides.treble, Hand.right), (StaffGuides.bass, Hand.left)] {
            for midi in midis where layout.contains(midi) {
                let x = layout.keyCenterX(midi: midi)
                let color = Theme.hand(hand)
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)),
                             with: .color(color.opacity(palette.guideOpacity)))
                context.draw(Text(NoteNaming.keyName(midi: midi, settings.naming))
                                .font(.ui(11, .bold)).foregroundStyle(color),
                             at: CGPoint(x: x + 4, y: 6), anchor: .topLeading)
            }
        }
        let c = StaffGuides.middleC
        if layout.contains(c) {
            let x = layout.keyCenterX(midi: c)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(Theme.midC),
                           style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            context.draw(Text(NoteNaming.keyName(midi: c, settings.naming))
                            .font(.ui(11, .bold)).foregroundStyle(Theme.midC),
                         at: CGPoint(x: x + 4, y: 6), anchor: .topLeading)
        }
    }
}

/// 「次」チップ（レーン右上）
struct NextChip: View {
    let notes: [PlayNote]
    let naming: Naming

    var body: some View {
        HStack(spacing: 8) {
            Text("次").font(.ui(13, .bold)).foregroundStyle(Theme.sub)
            if notes.isEmpty {
                Text("—").font(.ui(13, .bold)).foregroundStyle(Theme.subLight)
            }
            ForEach(notes) { note in
                Text(NoteNaming.name(note.spelling, naming, includeOctave: true))
                    .font(.ui(14, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Theme.hand(note.hand), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

/// 五線ガイドと手の凡例（レーン左下）
struct GuideLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(Theme.handR, dashed: false, "ト音記号の5本線（右手）")
            row(Theme.handL, dashed: false, "ヘ音記号の5本線（左手）")
            row(Theme.midC, dashed: true, "真ん中のド（加線）")
            Text("線の上に落ちる音＝譜面でも線の上")
                .font(.ui(11))
                .foregroundStyle(Theme.sub)
        }
        .padding(10)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ color: Color, dashed: Bool, _ label: String) -> some View {
        HStack(spacing: 6) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: 18, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
            .frame(width: 18, height: 2)
            Text(label).font(.ui(11, .medium)).foregroundStyle(Theme.ink)
        }
    }
}

/// 今回の通しの正確さ
struct AccuracyChip: View {
    let hits: Int
    let judged: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("正確さ").font(.ui(12, .bold)).foregroundStyle(Theme.sub)
            Text("\(Int((Double(hits) / Double(max(judged, 1)) * 100).rounded()))%")
                .font(.ui(15, .bold).monospacedDigit()).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}
