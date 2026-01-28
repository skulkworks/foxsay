import SwiftUI

/// Filter options for AI models
enum AIModelFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case fast = "Fast"
    case balanced = "Balanced"
    case general = "General"
    case coding = "Coding"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// AI Models settings view for managing local LLM models
public struct AIModelsSettingsView: View {
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @State private var selectedFilter: AIModelFilter = .all

    public init() {}

    private var filteredModels: [AIModel] {
        switch selectedFilter {
        case .all:
            return AIModel.registry
        case .fast:
            return AIModel.registry.filter { $0.sizeBytes < 1_500_000_000 }
        case .balanced:
            return AIModel.registry.filter { $0.sizeBytes >= 1_500_000_000 && $0.sizeBytes <= 2_000_000_000 }
        case .general:
            return AIModel.registry.filter { $0.capabilities.contains("general") }
        case .coding:
            return AIModel.registry.filter { $0.capabilities.contains("coding") }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("AI Models")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select a model for AI-powered text transformation. These models run locally using Apple Silicon's Neural Engine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Active model indicator
                if let selectedModel = aiModelManager.selectedModel {
                    activeModelIndicator(selectedModel)
                }

                // Filter chips
                HStack(spacing: 8) {
                    ForEach(AIModelFilter.allCases) { filter in
                        filterChip(filter)
                    }
                    Spacer()
                }

                // No model selected guidance
                if aiModelManager.selectedModelId == nil {
                    noModelSelectedView
                }

                // Model Cards
                ForEach(filteredModels) { model in
                    AIModelCardView(model: model)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func filterChip(_ filter: AIModelFilter) -> some View {
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

    private func activeModelIndicator(_ model: AIModel) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.headline)
                        if aiModelManager.isPreloading {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if aiModelManager.isModelLoaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.secondaryAccent)
                        }
                    }
                }

                Spacer()

                Button("Deactivate") {
                    aiModelManager.deactivateModel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
        }
    }

    private var noModelSelectedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("No AI Model Selected")
                    .font(.headline)
                Text("Download and select a model below to enable AI-powered text transformations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Rich AI model card view
struct AIModelCardView: View {
    let model: AIModel
    @ObservedObject private var aiModelManager = AIModelManager.shared

    private var isSelected: Bool {
        aiModelManager.selectedModelId == model.id
    }

    private var isDownloaded: Bool {
        aiModelManager.isDownloaded(model.id)
    }

    private var isDownloading: Bool {
        aiModelManager.downloadingModelId == model.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                // Icon
                modelIcon
                    .frame(width: 44, height: 44)

                // Title and badges
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.headline)

                        if isSelected && aiModelManager.isModelLoaded {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondaryAccent)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                        } else if isSelected && aiModelManager.isPreloading {
                            Text("Loading")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                        }
                    }

                    // Capability badges
                    HStack(spacing: 4) {
                        ForEach(model.capabilities, id: \.self) { capability in
                            capabilityBadge(capability)
                        }
                    }
                }

                Spacer()

                // Status / Action
                statusView
            }

            // Description
            Text(model.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Metrics row
            HStack(spacing: 16) {
                // Quality rating (based on size)
                metricView(
                    label: "Quality",
                    value: qualityRating,
                    color: .secondaryAccent
                )

                // Speed rating (inverse of size)
                metricView(
                    label: "Speed",
                    value: speedRating,
                    color: .accentColor
                )

                Spacer()

                // Size
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.formattedSize)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Size")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Quantization
                VStack(alignment: .trailing, spacing: 2) {
                    Text("4-bit")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Precision")
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
        .contentShape(Rectangle())
        .onTapGesture {
            // Only allow selection if downloaded
            if isDownloaded {
                aiModelManager.selectModel(model)
                Task {
                    try? await aiModelManager.preload()
                }
            }
        }
    }

    private var qualityRating: Int {
        // Larger models = better quality
        if model.sizeBytes >= 1_800_000_000 { return 5 }
        if model.sizeBytes >= 1_400_000_000 { return 4 }
        return 3
    }

    private var speedRating: Int {
        // Smaller models = faster
        if model.sizeBytes <= 1_000_000_000 { return 5 }
        if model.sizeBytes <= 1_500_000_000 { return 4 }
        if model.sizeBytes <= 1_800_000_000 { return 3 }
        return 2
    }

    private var modelIcon: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))

            Image(systemName: "brain")
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
    }

    private func capabilityBadge(_ capability: String) -> some View {
        let color: Color = {
            switch capability {
            case "general": return .secondaryAccent
            case "coding": return .purple
            case "creative": return .orange
            default: return .gray
            }
        }()

        return Text(capability.capitalized)
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
        if isDownloading {
            VStack(spacing: 4) {
                ProgressView(value: aiModelManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .tint(.secondaryAccent)
                    .frame(width: 70)
                HStack(spacing: 4) {
                    Text("\(Int(aiModelManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Cancel") {
                        aiModelManager.cancelDownload()
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
            }
        } else if isSelected && aiModelManager.isPreloading {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.secondaryAccent)
                Text("Loading...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if isSelected && aiModelManager.isModelLoaded {
            // Active model - show deactivate and delete buttons
            HStack(spacing: 8) {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondaryAccent)

                Button {
                    aiModelManager.deactivateModel()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
                .help("Deactivate model")

                Button(role: .destructive) {
                    aiModelManager.deleteModel(model)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete model")
            }
        } else if isDownloaded {
            // Downloaded but not active - show activate and delete buttons
            HStack(spacing: 8) {
                Button("Activate") {
                    aiModelManager.selectModel(model)
                    Task {
                        try? await aiModelManager.preload()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    aiModelManager.deleteModel(model)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete model")
            }
        } else {
            Button("Download") {
                Task {
                    try? await aiModelManager.downloadModel(model)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

#Preview {
    AIModelsSettingsView()
        .frame(width: 500, height: 600)
}
