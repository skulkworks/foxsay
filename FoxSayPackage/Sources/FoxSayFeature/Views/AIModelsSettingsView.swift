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

/// AI Models settings view for managing local LLM models and remote providers
public struct AIModelsSettingsView: View {
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared
    @State private var selectedFilter: AIModelFilter = .all
    @State private var editingProvider: RemoteProvider?
    @State private var showingAddProvider = false

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

                Text("Select a provider for AI-powered text transformation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Unified active provider/model indicator (above the picker)
                unifiedActiveIndicator

                // Provider type picker
                Picker("Provider", selection: $providerManager.providerType) {
                    Text("Local Models").tag(LLMProviderType.local)
                    Text("Remote API").tag(LLMProviderType.remote)
                }
                .pickerStyle(.segmented)

                // Conditional content based on provider type
                if providerManager.providerType == .local {
                    localModelsContent
                } else {
                    remoteProvidersContent
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingProvider) { provider in
            RemoteProviderEditSheet(provider: provider) { updated in
                providerManager.updateProvider(updated)
                editingProvider = nil
            } onCancel: {
                editingProvider = nil
            }
        }
        .sheet(isPresented: $showingAddProvider) {
            RemoteProviderEditSheet(
                provider: RemoteProvider(name: "", baseURL: ""),
                isNew: true
            ) { newProvider in
                providerManager.addProvider(newProvider)
                showingAddProvider = false
            } onCancel: {
                showingAddProvider = false
            }
        }
    }

    // MARK: - Local Models Content

    @ViewBuilder
    private var localModelsContent: some View {
        Text("These models run locally using Apple Silicon's Neural Engine.")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Filter chips
        HStack(spacing: 8) {
            ForEach(AIModelFilter.allCases) { filter in
                filterChip(filter)
            }
            Spacer()
        }

        // Model Cards
        VStack(spacing: 12) {
            ForEach(filteredModels) { model in
                AIModelCardView(model: model)
            }
        }
    }

    // MARK: - Remote Providers Content

    @ViewBuilder
    private var remoteProvidersContent: some View {
        Text("Connect to OpenAI-compatible APIs like LM Studio or Ollama.")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Provider Cards
        VStack(spacing: 12) {
            ForEach(providerManager.remoteProviders) { provider in
                RemoteProviderCard(
                    provider: provider,
                    isSelected: provider.id == providerManager.selectedRemoteProviderId,
                    testResult: providerManager.connectionTestResults[provider.id] ?? .idle,
                    onActivate: {
                        providerManager.selectProvider(provider)
                    },
                    onDeactivate: {
                        providerManager.deactivate()
                    },
                    onTest: {
                        Task {
                            await providerManager.testConnection(for: provider)
                        }
                    },
                    onEdit: {
                        editingProvider = provider
                    },
                    onDelete: {
                        providerManager.deleteProvider(provider)
                    }
                )
            }
        }

        // Add provider button
        Button {
            showingAddProvider = true
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Custom Provider")
            }
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helper Views

    /// Check if a local model is actually active (regardless of tab selection)
    private var isLocalModelActive: Bool {
        aiModelManager.isModelReady && aiModelManager.selectedModel != nil
    }

    /// Check if a remote provider is actually active (regardless of tab selection)
    private var isRemoteProviderActive: Bool {
        if let selectedId = providerManager.selectedRemoteProviderId,
           let provider = providerManager.remoteProviders.first(where: { $0.id == selectedId }),
           provider.isEnabled {
            return true
        }
        return false
    }

    /// Unified indicator showing current active model or provider (displayed above the picker)
    @ViewBuilder
    private var unifiedActiveIndicator: some View {
        if isLocalModelActive, let model = aiModelManager.selectedModel {
            // Local model is active
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(model.name)
                                .font(.headline)

                            // Local badge
                            Text("Local")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(Capsule())

                            // Status indicator
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
                        providerManager.deactivate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
            }
        } else if isRemoteProviderActive, let provider = providerManager.selectedRemoteProvider {
            // Remote provider is active
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(provider.name)
                                .font(.headline)

                            // Remote badge
                            Text("Remote")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .clipShape(Capsule())

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.secondaryAccent)
                        }
                    }

                    Spacer()

                    Button("Deactivate") {
                        providerManager.deactivate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
            }
        } else {
            // No model/provider selected warning
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No AI Provider Active")
                        .font(.headline)
                    Text("Select a local model or remote provider below to enable AI-powered text transformations.")
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

}

/// Card view for a remote provider (unified style with local model cards)
struct RemoteProviderCard: View {
    let provider: RemoteProvider
    let isSelected: Bool
    let testResult: ConnectionTestResult
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: "network")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }

                // Title and URL
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.headline)

                        // Show Active badge in title only when active (matches local model style)
                        if isSelected {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondaryAccent)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                        }

                        if !provider.isEnabled {
                            Text("Disabled")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text(provider.baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Status / Action buttons (unified with local model style)
                statusView
            }

            // Connection test result
            connectionTestResultView
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
            if provider.isEnabled && !isSelected {
                onActivate()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if isSelected {
            // Active provider - show deactivate and action buttons (Active badge is already in title)
            HStack(spacing: 8) {
                Button {
                    onDeactivate()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
                .help("Deactivate provider")

                Button {
                    onTest()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Test connection")
                .disabled(testResult == .testing)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit provider")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete provider")
            }
        } else if provider.isEnabled {
            // Not active - just show borderless icons (clicking card activates)
            HStack(spacing: 8) {
                Button {
                    onTest()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Test connection")
                .disabled(testResult == .testing)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit provider")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete provider")
            }
        } else {
            // Disabled provider - borderless icons only
            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit provider")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete provider")
            }
        }
    }

    @ViewBuilder
    private var connectionTestResultView: some View {
        switch testResult {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Testing connection...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let models):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.secondaryAccent)
                Text("Connected - \(models.count) model\(models.count == 1 ? "" : "s") available")
                    .font(.caption)
                    .foregroundColor(.secondaryAccent)
            }
        case .failure(let error):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
    }
}

/// Sheet for editing or adding a remote provider
struct RemoteProviderEditSheet: View {
    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var modelName: String
    @State private var isEnabled: Bool

    let originalProvider: RemoteProvider
    let isNew: Bool
    let onSave: (RemoteProvider) -> Void
    let onCancel: () -> Void

    init(provider: RemoteProvider, isNew: Bool = false, onSave: @escaping (RemoteProvider) -> Void, onCancel: @escaping () -> Void) {
        self.originalProvider = provider
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: provider.name)
        _baseURL = State(initialValue: provider.baseURL)
        _apiKey = State(initialValue: provider.apiKey ?? "")
        _modelName = State(initialValue: provider.modelName ?? "")
        _isEnabled = State(initialValue: provider.isEnabled)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "Add Provider" : "Edit Provider")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g., LM Studio"))
                    TextField("Base URL", text: $baseURL, prompt: Text("e.g., http://localhost:1234/v1"))
                    SecureField("API Key (optional)", text: $apiKey, prompt: Text("Leave empty if not required"))
                    TextField("Model Name (optional)", text: $modelName, prompt: Text("Leave empty for default"))
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section {
                    Text("The base URL should point to an OpenAI-compatible API endpoint. Common examples:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("- LM Studio: http://localhost:1234/v1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("- Ollama: http://localhost:11434/v1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    let updated = RemoteProvider(
                        id: originalProvider.id,
                        name: name.trimmingCharacters(in: .whitespaces),
                        baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                        apiKey: apiKey.isEmpty ? nil : apiKey,
                        modelName: modelName.isEmpty ? nil : modelName,
                        isEnabled: isEnabled
                    )
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}

/// Rich AI model card view
struct AIModelCardView: View {
    let model: AIModel
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared

    private var isSelected: Bool {
        aiModelManager.selectedModelId == model.id && providerManager.providerType == .local
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
                activateModel()
            }
        }
    }

    /// Activate this local model (also switches to local mode and deactivates remote provider)
    private func activateModel() {
        // Clear remote provider selection
        providerManager.activateLocalMode()
        // Select and preload this model
        aiModelManager.selectModel(model)
        Task {
            try? await aiModelManager.preload()
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
            // Active model - show deactivate and delete buttons (Active badge is already in title)
            HStack(spacing: 8) {
                Button {
                    providerManager.deactivate()
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
            // Downloaded but not active - just show delete button (clicking card activates)
            HStack(spacing: 8) {
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
