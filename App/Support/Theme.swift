import PianoCore
import SwiftUI

/// 仕様 4.1 のカラートークン
enum Theme {
    static let bg = Color(hex: 0xF4F5F7)
    static let panel = Color.white
    static let ink = Color(hex: 0x1B1D21)
    static let staff = Color(hex: 0x40444B)
    static let sub = Color(hex: 0x5A606B)
    static let subLight = Color(hex: 0x8A909A)
    static let rule = Color(hex: 0xD9DCE1)
    static let ruleStrong = Color(hex: 0xC9CDD3)
    static let played = Color(hex: 0xB7BCC4)
    static let handR = Color(hex: 0x2D6CDF)
    static let handL = Color(hex: 0xD2691E)
    static let tintR = Color(hex: 0xD9E5FB)
    static let tintL = Color(hex: 0xFADFC8)
    static let measureHi = Color(hex: 0xFFF3C4)
    static let midC = Color(hex: 0x9AA0A8)
    static let miss = Color(hex: 0xD92D20)
    static let button = Color(hex: 0xF0F1F3)
    static let keyName = Color(hex: 0x6B717C)
    static let blackKeyUpcoming = Color(hex: 0x3A3E46)

    static func hand(_ hand: Hand) -> Color { hand == .right ? handR : handL }
    static func tint(_ hand: Hand) -> Color { hand == .right ? tintR : tintL }
}

/// 落下レーンの色（ダーク表示を切り替えられる）
struct LanePalette {
    let dark: Bool

    var background: Color { dark ? Color(hex: 0x15171B) : Color(hex: 0xFBFBFC) }
    var blackColumn: Color { dark ? Color(hex: 0x1E2128) : Color(hex: 0xEFF1F4) }
    var beatLine: Color { dark ? Color(hex: 0x23262D) : Color(hex: 0xE7E9EC) }
    var barLine: Color { dark ? Color(hex: 0x4A4F5A) : Color(hex: 0xB9BEC6) }
    var judgeLine: Color { dark ? .white : Theme.ink }
    var barLabel: Color { dark ? Color(hex: 0x8A909A) : Theme.subLight }
    var guideOpacity: Double { dark ? 0.8 : 0.55 }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// UI フォント。IBM Plex Sans JP を同梱するまではシステムフォント（日本語はヒラギノ）。
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
