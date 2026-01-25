import SwiftUI

/// Models settings view with rich model cards
public struct ModelsSettingsView: View {
    @ObservedObject private var modelManager = ModelManager.shared
    @State private var selectedFilter: ModelFilter = .all

    public init() {}

    private var filteredModels: [TranscriptionModelInfo] {
        switch selectedFilter {
        case .all:
            return ModelRegistry.allModels
        case .fast:
            return ModelRegistry.allModels.filter { $0.speedRating >= 4 }
        case .accurate:
            return ModelRegistry.allModels.filter { $0.accuracyRating >= 5 }
        case .english:
            return ModelRegistry.allModels.filter { $0.languageSupport == .englishOnly }
        case .multilingual:
            return ModelRegistry.allModels.filter { $0.languageSupport == .multilingual }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Speech Models")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select a model for speech-to-text transcription. Different models offer trade-offs between speed, accuracy, and language support.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Filter chips
                HStack(spacing: 8) {
                    ForEach(ModelFilter.allCases) { filter in
                        filterChip(filter)
                    }
                    Spacer()
                }

                // Model Cards
                ForEach(filteredModels) { modelInfo in
                    ModelCardView(modelInfo: modelInfo)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func filterChip(_ filter: ModelFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedFilter == filter ? Color.accentColor : Color(.textBackgroundColor))
                .foregroundColor(selectedFilter == filter ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Filter options for models
enum ModelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case fast = "Fast"
    case accurate = "Accurate"
    case english = "English"
    case multilingual = "Multilingual"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// Rich model card view
struct ModelCardView: View {
    let modelInfo: TranscriptionModelInfo
    @ObservedObject private var modelManager = ModelManager.shared

    private var isSelected: Bool {
        modelManager.currentModelType == modelInfo.type
    }

    var body: some View {
        Button {
            Task {
                await modelManager.selectModel(modelInfo.type)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack(spacing: 12) {
                    // Icon
                    modelIcon
                        .frame(width: 44, height: 44)

                    // Title and badges
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(modelInfo.displayName)
                                .font(.headline)

                            if isSelected && modelManager.isModelLoaded {
                                Text("Active")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            } else if isSelected {
                                Text("Selected")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }

                        // Badges
                        HStack(spacing: 4) {
                            ForEach(modelInfo.badges, id: \.self) { badge in
                                badgeView(badge)
                            }
                        }
                    }

                    Spacer()

                    // Status / Action
                    statusView
                }

                // Description
                Text(modelInfo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Metrics row
                HStack(spacing: 16) {
                    // Accuracy
                    metricView(
                        label: "Accuracy",
                        value: modelInfo.accuracyRating,
                        color: .green
                    )

                    // Speed
                    metricView(
                        label: "Speed",
                        value: modelInfo.speedRating,
                        color: .blue
                    )

                    Spacer()

                    // Size
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(modelInfo.formattedSize)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Size")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Language
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(modelInfo.languageSupport.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Languages")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var modelIcon: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))

            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
    }

    private var iconName: String {
        switch modelInfo.type {
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperKit:
            return "waveform.badge.mic"
        case .whisperLargeTurbo:
            return "waveform.badge.magnifyingglass"
        case .parakeetV2:
            return "bolt.fill"
        case .parakeetV3:
            return "globe"
        }
    }

    private func badgeView(_ badge: TranscriptionModelInfo.ModelBadge) -> some View {
        let color: Color = {
            switch badge {
            case .recommended: return .orange
            case .fastest: return .blue
            case .mostAccurate: return .green
            case .multilingual: return .purple
            case .compact: return .gray
            }
        }()

        return Text(badge.rawValue)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func metricView(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < value ? color : color.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        let isCurrentModel = isSelected

        if isCurrentModel && modelManager.isDownloading {
            VStack(spacing: 4) {
                ProgressView(value: modelManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 70)
                Text("\(Int(modelManager.downloadProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if isCurrentModel && modelManager.isPreloading {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if isCurrentModel && modelManager.isModelLoaded {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else if isCurrentModel && modelManager.isModelReady {
            Label("Downloaded", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundColor(.blue)
        } else if isCurrentModel && !modelManager.isModelReady {
            Button("Download") {
                Task {
                    try? await modelManager.downloadCurrentModel()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    ModelsSettingsView()
        .frame(width: 450, height: 600)
}
