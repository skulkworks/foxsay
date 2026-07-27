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
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "Speech Models",
                    description: "Choose the model that transcribes your speech, trading speed against accuracy and language coverage."
                )

                // Active model indicator
                if let modelInfo = ModelRegistry.info(for: modelManager.currentModelType) {
                    activeModelIndicator(modelInfo)
                }

                // Filters
                HStack(spacing: 6) {
                    ForEach(ModelFilter.allCases) { filter in
                        SettingsFilterPill(
                            title: filter.title,
                            isSelected: selectedFilter == filter
                        ) {
                            selectedFilter = filter
                        }
                    }
                    Spacer()
                }

                // Model Cards
                VStack(spacing: 10) {
                    ForEach(filteredModels) { modelInfo in
                        ModelCardView(modelInfo: modelInfo)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeModelIndicator(_ modelInfo: TranscriptionModelInfo) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: "waveform", isActive: true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Active Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(modelInfo.displayName)
                        .font(.headline)

                    if modelManager.isPreloading {
                        ProgressView()
                            .controlSize(.small)
                    } else if modelManager.isModelLoaded {
                        StatusCaption(text: "Loaded", color: .statusOK)
                    } else if !modelManager.isModelReady {
                        StatusCaption(text: "Not downloaded", color: .statusWarning)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
                    IconTile(systemName: iconName, isActive: isSelected, size: 40)

                    // Title and badges
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(modelInfo.displayName)
                                .font(.headline)

                            if isSelected && modelManager.isModelLoaded {
                                ChipLabel(text: "Active", tinted: true)
                            } else if isSelected {
                                ChipLabel(text: "Selected", tinted: true)
                            }
                        }

                        // Badges
                        HStack(spacing: 4) {
                            ForEach(modelInfo.badges, id: \.self) { badge in
                                ChipLabel(text: badge.rawValue, tinted: badge == .recommended)
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Metrics row
                HStack(spacing: 18) {
                    RatingDots(label: "Accuracy", value: modelInfo.accuracyRating)
                    RatingDots(label: "Speed", value: modelInfo.speedRating)

                    Spacer()

                    metricValue(modelInfo.formattedSize, label: "Size")
                    metricValue(modelInfo.languageSupport.rawValue, label: "Languages")
                }
            }
            .selectableCard(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch modelInfo.type {
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperKit:
            return "waveform.badge.mic"
        case .whisperLargeTurbo:
            return "waveform.badge.magnifyingglass"
        case .parakeetV2:
            return "waveform"
        case .parakeetV3:
            return "globe"
        case .parakeetTdtCtc110m:
            return "waveform"
        case .parakeetJa:
            return "character.bubble"
        }
    }

    private func metricValue(_ value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
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
                    .monospacedDigit()
            }
        } else if isCurrentModel && modelManager.isPreloading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if isCurrentModel && modelManager.isModelLoaded {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.statusOK)
                .labelStyle(.titleAndIcon)
        } else if isCurrentModel && modelManager.isModelReady {
            Label("Downloaded", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
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
