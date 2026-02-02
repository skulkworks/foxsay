import SwiftUI

extension Color {
    static let secondaryAccent = Color("SecondaryAccentColor")
    static let tertiaryAccent = Color("TertiaryAccentColor")

    // MARK: - Dashboard Colors

    /// Primary dashboard color - Orange (#f97316)
    static let dashboardOrange = Color(red: 0.976, green: 0.451, blue: 0.086)

    /// Secondary dashboard color - System blue
    static let dashboardBlue = Color.accentColor

    /// Accent color for AI/voice features - Purple (used sparingly)
    static let dashboardPurple = Color(red: 0.659, green: 0.333, blue: 0.969)

    /// Status color - Ready/Success
    static let dashboardGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

    /// Status color - Warning/Attention
    static let dashboardAmber = Color(red: 0.961, green: 0.620, blue: 0.043)
}
