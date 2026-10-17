import CoreText
import PianoCore
import SwiftUI

/// SMuFL（Bravura）のグリフ。パスは「1 = 五線の1間隔」の単位、y は下向き、原点はグリフの基準点。
enum SMuFL {
    static let brace: UInt32 = 0xE000
    static let gClef: UInt32 = 0xE050
    static let cClef: UInt32 = 0xE05C
    static let fClef: UInt32 = 0xE062
    static func timeSigDigit(_ d: Int) -> UInt32 { 0xE080 + UInt32(d) }

    static let flag8thUp: UInt32 = 0xE240
    static func flag(count: Int, up: Bool) -> UInt32 {
        0xE240 + UInt32((min(max(count, 1), 4) - 1) * 2) + (up ? 0 : 1)
    }

    static let flat: UInt32 = 0xE260
    static let natural: UInt32 = 0xE261
    static let sharp: UInt32 = 0xE262
    static let doubleSharp: UInt32 = 0xE263
    static let doubleFlat: UInt32 = 0xE264

    static let restWhole: UInt32 = 0xE4E3
    static let restHalf: UInt32 = 0xE4E4
    static let restQuarter: UInt32 = 0xE4E5
    static let rest8th: UInt32 = 0xE4E6
    static let rest16th: UInt32 = 0xE4E7
    static let rest32nd: UInt32 = 0xE4E8
    static let rest64th: UInt32 = 0xE4E9

    static let all: [UInt32] = [brace, gClef, cClef, fClef, flat, natural, sharp, doubleSharp, doubleFlat,
                                restWhole, restHalf, restQuarter, rest8th, rest16th, rest32nd, rest64th]
        + (0...9).map(timeSigDigit) + (0..<8).map { 0xE240 + UInt32($0) }
}

final class MusicGlyphs: Sendable {
    static let shared = MusicGlyphs()

    private let paths: [UInt32: Path]

    private init() {
        // em = 4 間隔なので、サイズ 4 で作ると 1 単位 = 1 間隔
        let font = CTFontCreateWithName("Bravura" as CFString, 4, nil)
        var result: [UInt32: Path] = [:]
        for code in SMuFL.all {
            var chars = [UniChar(code)]
            var glyph = CGGlyph()
            guard CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1), glyph != 0,
                  let cg = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
            result[code] = Path(cg).applying(CGAffineTransform(scaleX: 1, y: -1))
        }
        paths = result
    }

    var isAvailable: Bool { !paths.isEmpty }

    func bounds(_ code: UInt32) -> CGRect { paths[code]?.boundingRect ?? .zero }

    /// 基準点を origin に置き、space（1間隔の pt）倍して描く
    func draw(_ code: UInt32, at origin: CGPoint, space: CGFloat, color: Color,
              scaleY: CGFloat = 1, in context: inout GraphicsContext) {
        guard let path = paths[code] else { return }
        let t = CGAffineTransform(a: space, b: 0, c: 0, d: space * scaleY, tx: origin.x, ty: origin.y)
        context.fill(path.applying(t), with: .color(color))
    }
}

extension Accidental {
    var glyph: UInt32 {
        switch self {
        case .sharp: SMuFL.sharp
        case .flat: SMuFL.flat
        case .natural: SMuFL.natural
        case .doubleSharp: SMuFL.doubleSharp
        case .doubleFlat: SMuFL.doubleFlat
        }
    }
}
