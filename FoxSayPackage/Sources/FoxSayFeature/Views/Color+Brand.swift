import SwiftUI

extension Color {
    static let secondaryAccent = Color("SecondaryAccentColor")
    static let tertiaryAccent = Color("TertiaryAccentColor")

    // MARK: - Legacy dashboard palette (deprecated)
    //
    // The old multi-color dashboard palette now maps onto the single-accent
    // theme (see Theme.swift). Prefer .accentColor / status colors directly;
    // these aliases exist only until remaining call sites are migrated.

    static let dashboardOrange = Color.accentColor
    static let dashboardBlue = Color.accentColor
    static let dashboardPurple = Color.accentColor
    static let dashboardGreen = Color.statusOK
    static let dashboardAmber = Color.statusWarning
}
