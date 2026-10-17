import PianoCore
import SwiftUI

/// 鍵盤（仕様 7章）
struct KeyboardCanvas: View {
    let layout: KeyboardLayout
    let highlights: [Int: KeyHighlight]
    let showGuides: Bool
    let naming: Naming

    var body: some View {
        Canvas { context, size in
            drawWhiteKeys(&context, height: size.height)
            drawBlackKeys(&context, height: size.height)
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 1)), with: .color(Theme.ruleStrong))
        }
        .background(Theme.bg)
    }

    private func drawWhiteKeys(_ context: inout GraphicsContext, height: CGFloat) {
        let kw = layout.whiteKeyWidth
        for midi in layout.whiteKeys {
            let rect = CGRect(x: layout.keyCenterX(midi: midi) - kw / 2, y: 0, width: kw, height: height)
            let shape = UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)

            var nameColor = Theme.keyName
            var nameWeight: Font.Weight = .regular
            switch highlights[midi] {
            case .sounding(let hand):
                context.fill(shape.path(in: rect), with: .color(Theme.hand(hand)))
                nameColor = .white
                nameWeight = .bold
            case .upcoming(let hand):
                context.fill(shape.path(in: rect), with: .color(Theme.tint(hand)))
                let inner = UnevenRoundedRectangle(bottomLeadingRadius: 4.5, bottomTrailingRadius: 4.5)
                context.stroke(inner.path(in: rect.insetBy(dx: 1.5, dy: 1.5)),
                               with: .color(Theme.hand(hand)), lineWidth: 3)
                nameWeight = .bold
            case nil:
                context.fill(shape.path(in: rect), with: .color(.white))
            }
            context.fill(Path(CGRect(x: rect.maxX - 1, y: 0, width: 1, height: height)),
                         with: .color(Theme.ruleStrong))

            // 五線の線の鍵の印
            if showGuides, let hand = StaffGuides.hand(ofGuide: midi) {
                let band = CGRect(x: rect.minX + 5, y: 0, width: kw - 10, height: 6)
                context.fill(UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3).path(in: band),
                             with: .color(Theme.hand(hand)))
            }

            let isC = midi % 12 == 0
            if isC, highlights[midi] == nil {
                nameColor = Theme.ink
                nameWeight = .bold
            }
            context.draw(Text(NoteNaming.keyName(midi: midi, naming))
                            .font(.ui(13, nameWeight)).foregroundStyle(nameColor),
                         at: CGPoint(x: rect.midX, y: height - 10), anchor: .bottom)

            if midi == StaffGuides.middleC {
                let dot = CGRect(x: rect.midX - 3, y: height - 40, width: 6, height: 6)
                context.fill(Path(ellipseIn: dot), with: .color(nameColor == .white ? .white : Theme.midC))
            }
        }
    }

    private func drawBlackKeys(_ context: inout GraphicsContext, height: CGFloat) {
        let bw = layout.blackKeyWidth
        let length = 92 * height / PracticeScreen.keyboardHeight
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
        for midi in layout.blackKeys {
            let rect = CGRect(x: layout.keyCenterX(midi: midi) - bw / 2, y: 0, width: bw, height: length)
            switch highlights[midi] {
            case .sounding(let hand):
                context.fill(shape.path(in: rect), with: .color(Theme.hand(hand)))
            case .upcoming(let hand):
                context.fill(shape.path(in: rect), with: .color(Theme.blackKeyUpcoming))
                context.stroke(UnevenRoundedRectangle(bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5)
                                .path(in: rect.insetBy(dx: 1.5, dy: 1.5)),
                               with: .color(Theme.hand(hand)), lineWidth: 3)
            case nil:
                context.fill(shape.path(in: rect), with: .color(Theme.ink))
            }
        }
    }
}
