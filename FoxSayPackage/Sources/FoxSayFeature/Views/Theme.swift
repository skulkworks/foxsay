import AppKit
import SwiftUI

// MARK: - FoxSay Theme
//
// Brand language derived from the app icon: a single coral accent over quiet
// slate neutrals. Interactive elements pick up the accent automatically via
// the AccentColor asset; everything here is for the few places that need the
// brand colors explicitly (the overlay HUD, gradients, status dots).

extension Color {
    // MARK: Brand

    /// Coral gradient endpoints from the app icon's speech bubble.
    static let brandCoralLight = Color(red: 1.0, green: 0.478, blue: 0.361)   // #FF7A5C
    static let brandCoralDeep = Color(red: 0.894, green: 0.267, blue: 0.235)  // #E4443C

    /// Slate neutrals from the app icon's background. Reserved for brand
    /// moments (overlay HUD, hero panels) — regular surfaces use system colors.
    static let brandSlate = Color(red: 0.235, green: 0.278, blue: 0.361)      // #3C475C
    static let brandSlateDeep = Color(red: 0.078, green: 0.098, blue: 0.141)  // #141924

    // MARK: Status
    //
    // Status colors appear only as small dots or short labels — never as
    // large tinted fills.

    static let statusOK = Color(nsColor: .systemGreen)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let statusError = Color(nsColor: .systemRed)
}

extension LinearGradient {
    /// The icon's bubble gradient, for the rare hero/brand moment.
    static let brandCoral = LinearGradient(
        colors: [.brandCoralLight, .brandCoralDeep],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - System chrome

enum SystemChrome {
    /// Corner radius of standard titled windows on this OS, so floating panels
    /// match the main window (Tahoe rounds windows more than earlier releases).
    /// AppKit has no public API for this; read it from a real window's frame
    /// view, with per-OS fallbacks if that ever stops working.
    @MainActor
    static var windowCornerRadius: CGFloat {
        if let cached = cachedWindowCornerRadius { return cached }
        var radius: CGFloat
        let key = "_cornerRadius"
        if let frameView = NSApp.windows.first(where: { $0.styleMask.contains(.titled) })?
            .contentView?.superview,
            frameView.responds(to: NSSelectorFromString(key)),
            let value = frameView.value(forKey: key) as? CGFloat,
            value > 0 {
            radius = value
        } else if #available(macOS 26.0, *) {
            radius = 16
        } else {
            radius = 11
        }
        cachedWindowCornerRadius = radius
        return radius
    }

    @MainActor
    private static var cachedWindowCornerRadius: CGFloat?
}

// MARK: - Shared Surfaces

/// The one card treatment used across every pane: subtle fill, hairline
/// stroke, continuous 10pt corners.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(padding: CGFloat = 16) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

/// Quiet capsule chip for metadata badges. Tinted only for the one badge that
/// matters (e.g. "Recommended"); everything else stays neutral.
struct ChipLabel: View {
    let text: String
    var tinted = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tinted ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(tinted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
            )
    }
}

/// Small status dot with consistent sizing.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}
