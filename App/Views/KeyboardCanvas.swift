import PianoCore
import SwiftUI

/// 鍵盤（仕様 7章）
struct KeyboardCanvas: View {
    let layout: KeyboardLayout
    let highlights: [Int: KeyHighlight]
    let showGuides: Bool
    let naming: Naming
    /// 実際に押している鍵（MIDI・タッチ）
    var pressed: [Int: PressedKey] = [:]
    /// 離したばかりの間違いの鍵（ホスト時刻）
    var recentWrong: [Int: Double] = [:]
    var host: Double = 0

    static let blackKeyLength: CGFloat = 92

    /// 押した鍵の色。正解は手の色、違う鍵は赤（離した後 0.3 秒で消える）
    private func pressColor(_ midi: Int) -> Color? {
        if let key = pressed[midi] {
            switch key.feedback {
            case .correct(let hand): return Theme.hand(hand)
            case .wrong: return Theme.miss
            }
        }
        if let t = recentWrong[midi], host - t < 0.3 {
            return Theme.miss.opacity(1 - (host - t) / 0.3)
        }
        return nil
    }

    /// 押している間は少し沈んだ表現（上端に影）
    private func drawSunk(_ context: inout GraphicsContext, rect: CGRect) {
        let shadow = CGRect(x: rect.minX, y: 0, width: rect.width, height: 10)
        context.fill(Path(shadow), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.35), .black.opacity(0)]),
            startPoint: CGPoint(x: rect.midX, y: 0), endPoint: CGPoint(x: rect.midX, y: 10)))
    }

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
            if let color = pressColor(midi) {
                context.fill(shape.path(in: rect), with: .color(color))
                nameColor = .white
                nameWeight = .bold
            }
            if pressed[midi] != nil { drawSunk(&context, rect: rect) }
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
        let length = Self.blackKeyLength * height / PracticeScreen.keyboardHeight
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
            if let color = pressColor(midi) {
                context.fill(shape.path(in: rect), with: .color(color))
            }
            if pressed[midi] != nil { drawSunk(&context, rect: rect) }
        }
    }
}
