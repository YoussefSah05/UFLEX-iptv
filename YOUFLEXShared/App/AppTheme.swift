import SwiftUI

enum AppTheme {
    enum Colors {
        static let background = Color(hex: 0x0B1016)
        static let surface = Color(hex: 0x121A24)
        static let surfaceElevated = Color(hex: 0x1B2836)
        static let accent = Color(hex: 0xE50914)
        static let onBackground = Color.white
        static let onSurface = Color.white
        static let muted = Color(hex: 0x9DB0C4)
        static let border = Color.white.opacity(0.08)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Corner {
        static let card: CGFloat = 12
        static let sheet: CGFloat = 16
        static let button: CGFloat = 8
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
