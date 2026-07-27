import SwiftUI

// MARK: - Styled Menu Label

/// Pop-up button label used inside settings rows. Mirrors the native macOS
/// pull-down look with a neutral fill that reads correctly in both appearances.
struct StyledMenuLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Pane Structure

/// Standard settings pane header: title plus a single line of context.
struct SettingsPaneHeader: View {
    let title: String
    let description: String

    init(_ title: String, description: String) {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section title inside a card. The symbol stays monochrome secondary so the
/// text carries the hierarchy.
struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 15)

            Text(title)
                .font(.headline)
        }
    }
}

// MARK: - Controls

/// Filter chip used by the model panes. Selected reads as the one accent fill;
/// everything else stays a neutral chip.
struct SettingsFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

/// Quiet monochrome tile behind a row icon. Picks up a subtle accent tint when
/// the row it belongs to is active.
struct IconTile: View {
    let systemName: String
    var isActive = false
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .regular))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            )
    }
}

/// Five-dot rating used for model speed/accuracy metrics.
struct RatingDots: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < value ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A dot plus short caption — the only way status color enters a pane.
struct StatusCaption: View {
    let text: String
    var color: Color = .secondary
    var emphasized = false

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: color)
            Text(text)
                .font(.caption)
                .foregroundStyle(emphasized
                    ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                    : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        }
    }
}

/// Trailing row action. Icon-only, always secondary, always with a tooltip.
struct RowActionButton: View {
    let systemName: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ systemName: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Banners

/// Inline warning. Status color is limited to the symbol and a 10% wash.
struct SettingsWarningBanner: View {
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.statusWarning)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.statusWarning.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.statusWarning.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Sheets

/// Sheet title bar. Sheets carry their actions in the footer, macOS-style.
struct SheetHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// Sheet footer: Cancel then the confirming action, bottom-trailing.
struct SheetFooter: View {
    let cancelTitle: String
    let confirmTitle: String
    var isConfirmDisabled = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    init(
        cancelTitle: String = "Cancel",
        confirmTitle: String,
        isConfirmDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.isConfirmDisabled = isConfirmDisabled
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            Button(cancelTitle, action: onCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

            Button(confirmTitle, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isConfirmDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Selection

/// Card treatment for a selectable row: same geometry as `.cardSurface()`, with
/// an accent border and faint wash when selected.
struct SelectableCard: ViewModifier {
    var isSelected: Bool
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
    }
}

extension View {
    func selectableCard(isSelected: Bool, padding: CGFloat = 16) -> some View {
        modifier(SelectableCard(isSelected: isSelected, padding: padding))
    }
}
