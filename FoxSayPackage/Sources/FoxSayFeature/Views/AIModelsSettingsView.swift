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
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "AI Models",
                    description: "Pick the model that powers prompts, vocal corrections, and text transforms."
                )

                // Unified active provider/model indicator (above the picker)
                unifiedActiveIndicator

                // Provider type picker
                Picker("Provider", selection: $providerManager.providerType) {
                    Text("Local Models").tag(LLMProviderType.local)
                    Text("Remote API").tag(LLMProviderType.remote)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)

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
                let credentialsChanged = providerManager.updateProvider(updated)
                editingProvider = nil
                // Auto-test if credentials changed and API key is set
                if credentialsChanged && updated.apiKey != nil && !updated.apiKey!.isEmpty {
                    Task {
                        // Get the updated provider from the manager
                        if let current = providerManager.remoteProviders.first(where: { $0.id == updated.id }) {
                            await providerManager.testConnection(for: current)
                        }
                    }
                }
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
                // Auto-test new provider if API key is set
                if newProvider.apiKey != nil && !newProvider.apiKey!.isEmpty {
                    Task {
                        await providerManager.testConnection(for: newProvider)
                    }
                }
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

        // Filters
        HStack(spacing: 6) {
            ForEach(AIModelFilter.allCases) { filter in
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
            ForEach(filteredModels) { model in
                AIModelCardView(model: model)
            }
        }
    }

    // MARK: - Remote Providers Content

    @ViewBuilder
    private var remoteProvidersContent: some View {
        Text("Connect to OpenAI or compatible APIs like LM Studio and Ollama.")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Provider Cards
        VStack(spacing: 10) {
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
            Label("Add Custom Provider", systemImage: "plus")
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
            activeSummary(
                icon: "cpu",
                name: model.name,
                kind: "Local",
                isLoading: aiModelManager.isPreloading,
                isLoaded: aiModelManager.isModelLoaded
            )
        } else if isRemoteProviderActive, let provider = providerManager.selectedRemoteProvider {
            activeSummary(
                icon: "network",
                name: provider.name,
                kind: "Remote",
                isLoading: false,
                isLoaded: true
            )
        } else {
            SettingsWarningBanner(
                title: "No AI provider active",
                message: "Select a local model or remote provider below to enable AI-powered text transformations."
            )
        }
    }

    private func activeSummary(
        icon: String,
        name: String,
        kind: String,
        isLoading: Bool,
        isLoaded: Bool
    ) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, isActive: true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(name)
                        .font(.headline)

                    ChipLabel(text: kind)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else if isLoaded {
                        StatusCaption(text: "Loaded", color: .statusOK)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        VStack(alignment: .leading, spacing: 10) {
            // Header row with icon, title, badges, and action buttons
            HStack(spacing: 12) {
                IconTile(systemName: "network", isActive: isSelected, size: 40)

                // Title and badges
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.headline)

                        if isSelected {
                            ChipLabel(text: "Active", tinted: true)
                        }

                        if provider.isVerified && !isSelected {
                            StatusCaption(text: "Ready", color: .statusOK)
                        }

                        if !provider.isEnabled {
                            ChipLabel(text: "Disabled")
                        }
                    }

                    // Model name (prominent, like description in local cards)
                    if let modelName = provider.modelName, !modelName.isEmpty {
                        Text(modelName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                // Action buttons
                actionButtons
            }

            // Footer: URL and connection status
            HStack {
                Text(provider.baseURL)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                connectionTestResultView
            }
        }
        .selectableCard(isSelected: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if provider.isEnabled && !isSelected {
                onActivate()
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 2) {
            if isSelected {
                RowActionButton("stop.circle", help: "Deactivate provider", action: onDeactivate)
            }

            if provider.isEnabled {
                RowActionButton("arrow.triangle.2.circlepath", help: "Test connection", action: onTest)
                    .disabled(testResult == .testing)
            }

            RowActionButton("pencil", help: "Edit provider", action: onEdit)

            if !provider.isBuiltIn {
                RowActionButton("trash", help: "Delete provider", role: .destructive, action: onDelete)
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
                    .controlSize(.small)
                Text("Testing connection…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let models):
            StatusCaption(
                text: "Connected — \(models.count) model\(models.count == 1 ? "" : "s") available",
                color: .statusOK
            )
        case .failure(let error):
            HStack(spacing: 6) {
                StatusDot(color: .statusError)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFilter: String = ""
    @State private var showModelPicker = false
    @State private var showHelp = false
    @State private var fetchError: String?

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
        // Load cached models if available
        let cached = LLMProviderManager.shared.cachedModels[provider.id] ?? []
        _availableModels = State(initialValue: cached)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canFetchModels: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isNew ? "Add Provider" : "Edit Provider",
                subtitle: "Any OpenAI-compatible endpoint works here."
            )

            Divider()

            Form {
                Section("Connection") {
                    TextField("Name", text: $name, prompt: Text("e.g., OpenAI"))
                    TextField("Base URL", text: $baseURL, prompt: Text("e.g., https://api.openai.com/v1"))
                    SecureField("API Key", text: $apiKey)
                }

                Section("Model") {
                    LabeledContent("Model Name") {
                        HStack(spacing: 8) {
                            if availableModels.isEmpty {
                                TextField("Model Name", text: $modelName, prompt: Text("e.g., gpt-5-chat-latest"))
                                    .labelsHidden()
                            } else {
                                Button {
                                    modelFilter = ""
                                    showModelPicker = true
                                } label: {
                                    StyledMenuLabel(modelName.isEmpty ? "Select a model" : modelName)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                fetchModels()
                            } label: {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canFetchModels || isFetchingModels)
                            .help("Fetch available models")
                        }
                    }

                    if let error = fetchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.statusError)
                    }

                    if !availableModels.isEmpty {
                        Text("\(availableModels.count) models available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section {
                    DisclosureGroup("Help", isExpanded: $showHelp) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The base URL should point to an OpenAI-compatible API endpoint.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• OpenAI: https://api.openai.com/v1")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("• Anthropic: https://api.anthropic.com/v1")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("• Google: https://generativelanguage.googleapis.com/v1beta/openai")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("• OpenRouter: https://openrouter.ai/api/v1")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("• LM Studio: http://localhost:1234/v1")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("• Ollama: http://localhost:11434/v1")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            SheetFooter(
                confirmTitle: isNew ? "Add" : "Save",
                isConfirmDisabled: !isValid,
                onCancel: onCancel
            ) {
                let updated = RemoteProvider(
                    id: originalProvider.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    modelName: modelName.isEmpty ? nil : modelName,
                    isEnabled: isEnabled,
                    isBuiltIn: originalProvider.isBuiltIn,
                    isVerified: originalProvider.isVerified
                )
                onSave(updated)
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 460)
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(
                models: availableModels,
                selectedModel: modelName,
                filter: $modelFilter
            ) { selected in
                modelName = selected
                showModelPicker = false
            } onCancel: {
                showModelPicker = false
            }
        }
    }

    private func fetchModels() {
        guard canFetchModels else { return }

        isFetchingModels = true
        fetchError = nil

        let tempProvider = RemoteProvider(
            name: "temp",
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            apiKey: apiKey.isEmpty ? nil : apiKey,
            modelName: nil,
            isEnabled: true
        )

        Task {
            let service = RemoteLLMService(provider: tempProvider)
            let result = await service.testConnection()

            await MainActor.run {
                isFetchingModels = false
                switch result {
                case .success(let models):
                    let sortedModels = models.sorted()
                    availableModels = sortedModels
                    // Cache the models for this provider
                    LLMProviderManager.shared.cachedModels[originalProvider.id] = sortedModels
                    if modelName.isEmpty, let first = sortedModels.first {
                        modelName = first
                    }
                case .failure(let error):
                    fetchError = error.localizedDescription
                    availableModels = []
                }
            }
        }
    }
}

/// Sheet for picking a model with search/filter
struct ModelPickerSheet: View {
    let models: [String]
    let selectedModel: String
    @Binding var filter: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    private var filteredModels: [String] {
        if filter.isEmpty {
            return models
        }
        return models.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Select Model",
                subtitle: "\(filteredModels.count) of \(models.count) models"
            )

            Divider()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Filter models…", text: $filter)
                    .textFieldStyle(.plain)

                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Model list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredModels, id: \.self) { model in
                        Button {
                            onSelect(model)
                        } label: {
                            HStack {
                                Text(model)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if model == selectedModel {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(model == selectedModel ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 460)
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
                IconTile(systemName: "cpu", isActive: isSelected, size: 40)

                // Title and badges
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.headline)

                        if isSelected && aiModelManager.isModelLoaded {
                            ChipLabel(text: "Active", tinted: true)
                        } else if isSelected && aiModelManager.isPreloading {
                            ChipLabel(text: "Loading")
                        }
                    }

                    // Capability badges
                    HStack(spacing: 4) {
                        if model.isRecommended {
                            ChipLabel(text: "Recommended", tinted: true)
                        }
                        ForEach(model.capabilities, id: \.self) { capability in
                            ChipLabel(text: capability.capitalized)
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
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metrics row
            HStack(spacing: 18) {
                RatingDots(label: "Quality", value: qualityRating)
                RatingDots(label: "Speed", value: speedRating)

                Spacer()

                metricValue(model.formattedSize, label: "Size")
                metricValue("4-bit", label: "Precision")
            }
        }
        .selectableCard(isSelected: isSelected)
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
        // Unload any currently loaded model first
        aiModelManager.unload()
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
        if isDownloading {
            VStack(spacing: 4) {
                ProgressView(value: aiModelManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 70)
                HStack(spacing: 6) {
                    Text("\(Int(aiModelManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Cancel") {
                        aiModelManager.cancelDownload()
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
            }
        } else if isSelected && aiModelManager.isPreloading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if isSelected && aiModelManager.isModelLoaded {
            // Active model — the "Active" chip already names the state
            HStack(spacing: 2) {
                RowActionButton("stop.circle", help: "Deactivate model") {
                    providerManager.deactivate()
                }
                RowActionButton("trash", help: "Delete model", role: .destructive) {
                    aiModelManager.deleteModel(model)
                }
            }
        } else if isDownloaded {
            HStack(spacing: 2) {
                RowActionButton("trash", help: "Delete model", role: .destructive) {
                    aiModelManager.deleteModel(model)
                }
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
