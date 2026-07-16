import AppKit
import SwiftUI

struct SmartisanGradientToken {
    let fillStartHex: UInt32
    let fillEndHex: UInt32
    let borderStartHex: UInt32
    let borderEndHex: UInt32

    var fillStart: Color { SmartisanColorTokens.color(fillStartHex) }
    var fillEnd: Color { SmartisanColorTokens.color(fillEndHex) }
    var borderStart: Color { SmartisanColorTokens.color(borderStartHex) }
    var borderEnd: Color { SmartisanColorTokens.color(borderEndHex) }
    var representative: Color { fillEnd }

    var fill: LinearGradient {
        LinearGradient(
            colors: [fillStart, fillEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var border: LinearGradient {
        LinearGradient(
            colors: [borderStart, borderEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

enum SmartisanColorTokens {
    enum Neutral {
        static let n100 = color(0xFAFAFA)
        static let n200 = color(0xF2F2F2)
        static let n300 = color(0xEEEEEE)
        static let n400 = color(0xE2E2E2)
        static let n500 = color(0xBABABA)
        static let n600 = color(0x9D9D9D)
        static let n700 = color(0x7F7F7F)
        static let n800 = color(0x636363)
        static let n900 = color(0x333333)
        static let white = color(0xFFFFFF)
    }

    enum Brand {
        static let b100 = color(0xE7EDFD)
        static let b200 = color(0x6190FF)
        static let b300 = color(0x5985EB)
        static let b400 = color(0x5079D9)
        static let b500 = color(0x3F68E2)
        static let b600 = color(0x2F54D7)
    }

    enum Success {
        static let s100 = color(0xDBF6C0)
        static let s500 = color(0x86D917)
    }

    enum Warning {
        static let w100 = color(0xFFFAE0)
        static let w500 = color(0xFFD633)
    }

    enum Danger {
        static let d100 = color(0xFFE7E5)
        static let d200 = color(0xF0948D)
        static let d300 = color(0xE66157)
        static let d400 = color(0xDF4F46)
        static let d500 = color(0xE13F36)
        static let d600 = color(0xC5423B)
    }

    enum Surface {
        static let sectionFill = color(0xF5F5F5)
        static let headerEdge = color(0x222325)
        static let headerCenter = color(0x3B3C3F)
        static let appBarWhiteBorder = color(0xD8D8D8)

        static let headerGradient = LinearGradient(
            stops: [
                .init(color: headerEdge, location: 0),
                .init(color: headerCenter, location: 0.49),
                .init(color: headerEdge, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    enum Theme {
        static let cyan = gradient(0x6DEAF4, 0x3FDCED, 0x3FDCEC, 0x1CC6E0)
        static let green = gradient(0xC8E000, 0xA9CD00, 0xA8CC00, 0x7EAD00)
        static let yellow = gradient(0xFFDA2E, 0xFFC211, 0xFFC212, 0xFFA005)
        static let orange = gradient(0xFFB32E, 0xFF8C11, 0xFF8B12, 0xFF5D05)
        static let purple = gradient(0xBD6AF1, 0x993BE6, 0x983CE7, 0x6C1AD5)

        static let enshuNezumi = gradient(0xC7B8A9, 0xA7927F, 0xA6927E, 0x7D634F)
        static let ochikuri = gradient(0xB2998B, 0x8A6C5C, 0x8A6B5C, 0x5B3F31)
        static let suoh = gradient(0xC0696C, 0x9D3A3E, 0x9D3B3F, 0x6F191C)
        static let sekichiku = gradient(0xEBB9B8, 0xDD9392, 0xDE9392, 0xC76663)
        static let karekusa = gradient(0xF1CD7C, 0xE6B04C, 0xE7AF4C, 0xD58825)
        static let yanagisuTakecha = gradient(0x9EA67E, 0x727B50, 0x727B50, 0x444C27)
        static let sabiseiji = gradient(0x9FC6BD, 0x73A599, 0x73A598, 0x457B6C)
        static let hatobaMurasaki = gradient(0x8E899E, 0x5F5A71, 0x5F5A71, 0x333043)
    }

    enum Button {
        static let primaryEnabled = gradient(0x5B87EB, 0x5883EB, 0x3F68E2, 0x3F68E2)
        static let primaryPressed = gradient(0x4772E6, 0x4772E6, 0x2F54D7, 0x2F54D7)
        static let greenEnabled = gradient(0x8DC046, 0x88BD41, 0x81B73B, 0x81B73B)
        static let greenPressed = gradient(0x77AC30, 0x82B43B, 0x7BA848, 0x7BA848)
        static let redEnabled = gradient(0xE5645A, 0xE55F55, 0xDA463E, 0xDA463E)
        static let redPressed = gradient(0xDF4F46, 0xDF4F46, 0xD1352E, 0xD1352E)
        static let greyEnabled = gradient(0xBBBCC0, 0xB8B9BD, 0xA3A4A9, 0xA3A4A9)
        static let greyPressed = gradient(0xABADB1, 0xA8A9AE, 0x929398, 0x929398)
        static let whiteEnabled = gradient(0xFFFFFF, 0xFCFCFC, 0xEEEEEE, 0xEEEEEE)
        static let whitePressed = gradient(0xEBEBEB, 0xF2F2F2, 0xDDDDDD, 0xDDDDDD)
    }

    enum AppBar {
        static let white = gradient(0xFFFFFF, 0xFFFFFF, 0xD8D8D8, 0xD8D8D8)
        static let red = gradient(0xCD3F3A, 0xC83530, 0xB7241F, 0xB7241F)
        static let blue = gradient(0x4993EA, 0x428CE8, 0x357AE1, 0x357AE1)
        static let brown = gradient(0x7A6455, 0x705B4C, 0x5F4A3C, 0x5F4A3C)
        static let purple = gradient(0x9348B6, 0x843FAF, 0x732A9B, 0x732A9B)
    }

    static func color(_ hex: UInt32) -> Color {
        Color(nsColor: .smartisan(hex: hex))
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return .smartisan(hex: match == .darkAqua ? dark : light)
            }
        )
    }

    private static func gradient(
        _ fillStart: UInt32,
        _ fillEnd: UInt32,
        _ borderStart: UInt32,
        _ borderEnd: UInt32
    ) -> SmartisanGradientToken {
        SmartisanGradientToken(
            fillStartHex: fillStart,
            fillEndHex: fillEnd,
            borderStartHex: borderStart,
            borderEndHex: borderEnd
        )
    }
}

private extension NSColor {
    static func smartisan(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
