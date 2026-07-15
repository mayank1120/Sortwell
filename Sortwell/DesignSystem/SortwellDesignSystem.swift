import AppKit
import SwiftUI

enum SortwellPalette {
    static let canvas = adaptive(light: 0xF3F5F1, dark: 0x171C19)
    static let sidebar = adaptive(light: 0xE9EDE8, dark: 0x1A211D)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1F2622)
    static let raisedSurface = adaptive(light: 0xF9FAF8, dark: 0x252E28)
    static let primaryText = adaptive(light: 0x202823, dark: 0xEDF2EE)
    static let secondaryText = adaptive(light: 0x667069, dark: 0xA7B1AA)
    static let border = adaptive(light: 0xD6DDD7, dark: 0x354139)
    static let sage = adaptive(light: 0x376B58, dark: 0x76B697)
    static let sageForeground = adaptive(light: 0xFFFFFF, dark: 0x102119)
    static let sageSoft = adaptive(light: 0xE3F0E9, dark: 0x253B31)
    static let amber = adaptive(light: 0xA8681D, dark: 0xE0A653)
    static let amberSoft = adaptive(light: 0xFFF1DC, dark: 0x42331F)
    static let red = adaptive(light: 0xAE4646, dark: 0xEC8585)
    static let redSoft = adaptive(light: 0xFBE9E8, dark: 0x422727)
    static let blue = adaptive(light: 0x426D89, dark: 0x79A9C7)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: match == .darkAqua ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

enum SortwellSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

struct SortwellPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SortwellPalette.sageForeground.opacity(isEnabled ? 1 : 0.6))
            .padding(.horizontal, 18)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SortwellPalette.sage.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.38))
            )
    }
}

struct SortwellSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SortwellPalette.primaryText.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 15)
            .frame(minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed && isEnabled ? SortwellPalette.sageSoft : SortwellPalette.raisedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SortwellPalette.border, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? 1 : 0.65)
    }
}

struct SortwellChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? SortwellPalette.sage : SortwellPalette.primaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? SortwellPalette.sageSoft : SortwellPalette.raisedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? SortwellPalette.sage.opacity(0.65) : SortwellPalette.border, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct SortwellIconMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(SortwellPalette.sage)

            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                    .fill(SortwellPalette.sageForeground.opacity(0.7 + Double(index) * 0.14))
                    .frame(width: size * 0.46, height: size * 0.42)
                    .offset(x: CGFloat(index - 1) * size * 0.11, y: CGFloat(1 - index) * size * 0.09)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let title: String
    let icon: String
    var tint: Color = SortwellPalette.sage
    var background: Color = SortwellPalette.sageSoft

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(SortwellSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SortwellPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SortwellPalette.border, lineWidth: 1)
                    )
            )
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(SortwellPalette.border)
            .frame(height: 1)
    }
}
