import Foundation
import FluidAudio

/// Parakeet TDT engine via FluidAudio (CoreML/ANE)
/// This engine provides extremely fast transcription using NVIDIA's Parakeet model
/// accelerated by Apple's Neural Engine.
public actor ParakeetEngine: TranscriptionEngine {
    /// The model version this engine uses
    public let version: AsrModelVersion

    public nonisolated var name: String {
        switch version {
        case .v2: return "Parakeet V2"
        case .v3: return "Parakeet V3"
        case .tdtCtc110m: return "Parakeet TDT-CTC 110M"
        case .tdtJa: return "Parakeet Japanese"
        @unknown default: return "Parakeet"
        }
    }

    public nonisolated var identifier: String {
        switch version {
        case .v2: return "parakeet-v2"
        case .v3: return "parakeet-v3"
        case .tdtCtc110m: return "parakeet-tdt-ctc-110m"
        case .tdtJa: return "parakeet-ja"
        @unknown default: return "parakeet"
        }
    }

    public nonisolated var modelSize: Int64 {
        switch version {
        case .v2: return 450_000_000  // ~450MB for V2
        case .v3: return 480_000_000  // ~480MB for V3
        case .tdtCtc110m: return 230_000_000  // fused preprocessor+encoder, much smaller
        case .tdtJa: return 620_000_000
        @unknown default: return 480_000_000
        }
    }

    /// Short label used in log messages ("V2", "110M", ...)
    private nonisolated var versionLabel: String {
        switch version {
        case .v2: return "V2"
        case .v3: return "V3"
        case .tdtCtc110m: return "TDT-CTC 110M"
        case .tdtJa: return "Japanese"
        @unknown default: return "unknown"
        }
    }

    /// Directory FluidAudio downloads this version into, under
    /// ~/Library/Application Support/FluidAudio/Models/.
    /// These must track FluidAudio's `Repo.folderName`, which is NOT the repo name:
    /// it strips the "-coreml" suffix by default and overrides some versions outright.
    private nonisolated var modelDirectoryName: String {
        switch version {
        case .v2: return "parakeet-tdt-0.6b-v2"
        case .v3: return "parakeet-tdt-0.6b-v3"
        case .tdtCtc110m: return "parakeet-tdt-ctc-110m"
        case .tdtJa: return "parakeet-ja"
        @unknown default: return "parakeet-tdt-0.6b-v2"
        }
    }

    /// Vocabulary file whose presence indicates a complete download. The Japanese
    /// repo ships vocab.json where the others ship parakeet_vocab.json.
    private nonisolated var vocabFileName: String {
        switch version {
        case .tdtJa: return "vocab.json"
        default: return "parakeet_vocab.json"
        }
    }

    // Using nonisolated(unsafe) because AsrManager handles its own thread safety
    // and FluidAudio is designed to be called from any context
    private nonisolated(unsafe) var asrManager: AsrManager?
    private var models: AsrModels?
    // nonisolated so progress polling doesn't block on actor
    private nonisolated let progress = ModelDownloadProgress()

    /// How much of our bar the fetch is worth. The rest covers compiling and
    /// loading the CoreML models, which is a few seconds of work against the
    /// minutes the bytes take.
    private static let fetchShareOfBar = 0.90

    /// FluidAudio reports each step it runs on that step's own 0…1 scale, and
    /// splits the scale evenly: fetching bytes fills the first half, compiling
    /// the models the second.
    private static let fetchShareOfFluidAudioScale = 0.5
    private var transcriptionTask: Task<TranscriptionResult, Error>?
    private var isCancelled = false

    /// Where to look for downloaded models. Tests point this at a temporary
    /// directory; the app leaves it nil and gets FluidAudio's real cache.
    private nonisolated let modelsRootOverride: URL?

    public init(version: AsrModelVersion = .v2, modelsRoot: URL? = nil) {
        self.version = version
        self.modelsRootOverride = modelsRoot
    }

    /// FluidAudio keeps its models in ~/Library/Application Support/FluidAudio/Models/.
    /// FoxSay is not sandboxed, so this is the real home directory for both the
    /// released app and a debug build, and they share one copy of every model.
    private nonisolated var modelsRoot: URL? {
        if let modelsRootOverride { return modelsRootOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio")
            .appendingPathComponent("Models")
    }

    private nonisolated var modelDirectory: URL? {
        modelsRoot?.appendingPathComponent(modelDirectoryName)
    }

    /// The folder FoxSay 1.0.x downloaded this model into.
    ///
    /// 1.0.x shipped FluidAudio 0.10.0, which stored each model under its full
    /// HuggingFace repository name; 0.15.5 strips the trailing "-coreml". Only
    /// V2 and V3 existed back then — the other versions arrived with 2.0.0 and
    /// have nothing to adopt.
    private nonisolated var legacyModelDirectory: URL? {
        switch version {
        case .v2, .v3:
            return modelsRoot?.appendingPathComponent("\(modelDirectoryName)-coreml")
        default:
            return nil
        }
    }

    public var isModelDownloaded: Bool {
        get async {
            guard let modelDir = modelDirectory else { return false }

            // Check if the vocab file exists (indicates complete download)
            let vocabPath = modelDir.appendingPathComponent(vocabFileName)
            return FileManager.default.fileExists(atPath: vocabPath.path)
        }
    }

    /// Take over a model downloaded by FoxSay 1.0.x, so that updating doesn't
    /// silently cost the user a model they already have.
    ///
    /// Because of the folder rename above, a 1.0.x user updating to 2.x finds
    /// nothing where the app now looks: the model reads as "Not downloaded", and
    /// re-fetching it pulls down several hundred megabytes that are already on
    /// the disk a folder away. The old copy is never cleaned up either, so the
    /// user pays for it twice, in bandwidth and in space.
    ///
    /// The old folder is moved into place and then handed to FluidAudio to
    /// judge, because nothing short of trying it can tell whether the files
    /// inside are still the ones this build wants. V2's did not change across
    /// those versions, so it adopts cleanly. V3's did — 0.15.5 wants a
    /// precision-specific encoder and a JointDecisionv3 that the 0.10.0 layout
    /// has no copy of — so V3 fails the check and is put back exactly where it
    /// was, leaving the re-download as the only way forward. Nothing here
    /// deletes a model: an old copy this build cannot use is still the user's.
    public func adoptLegacyDownload() async {
        let fileManager = FileManager.default
        guard let legacy = legacyModelDirectory, let current = modelDirectory,
            fileManager.fileExists(atPath: legacy.path)
        else { return }

        // Never move onto an existing download.
        guard !fileManager.fileExists(atPath: current.path) else { return }

        do {
            try fileManager.moveItem(at: legacy, to: current)
        } catch {
            print("FoxSay: Could not adopt the Parakeet \(versionLabel) model from FoxSay 1.x: \(error)")
            return
        }

        if AsrModels.modelsExist(at: current, version: version) {
            print("FoxSay: Adopted the Parakeet \(versionLabel) model downloaded by FoxSay 1.x")
        } else {
            try? fileManager.moveItem(at: current, to: legacy)
            print("FoxSay: Parakeet \(versionLabel) model from FoxSay 1.x has the old layout and can't be adopted")
        }
    }

    public var downloadProgress: Double {
        get async {
            progress.value
        }
    }

    /// Translate one of FluidAudio's progress reports into a position on our bar.
    ///
    /// FluidAudio runs a model as a series of steps, one per CoreML file, and
    /// reports each on its own 0…1 scale. Only the first step fetches anything:
    /// when any file is missing it pulls the whole repository in one pass, so
    /// that step's fetch half carries the entire download and every later step
    /// is a cache hit that returns immediately. Taking the fetch half of
    /// whichever step is reporting and stretching it across our bar therefore
    /// tracks the real bytes, and `ModelDownloadProgress` keeps the per-step
    /// restarts from walking the bar backwards.
    private nonisolated func record(_ update: DownloadProgress) {
        switch update.phase {
        case .listing:
            // A step is starting and its fraction has restarted at zero. Nothing
            // has happened yet, so the bar holds where it is.
            break
        case .downloading:
            let fetched = min(update.fractionCompleted / Self.fetchShareOfFluidAudioScale, 1.0)
            progress.advance(to: fetched * Self.fetchShareOfBar)
        case .compiling:
            // Compiling only begins once every byte is on disk — including on the
            // path where the files were already cached and nothing was fetched.
            progress.advance(to: Self.fetchShareOfBar)
        @unknown default:
            break
        }
    }

    public func downloadModel() async throws {
        progress.reset()

        print("FoxSay: Starting Parakeet \(versionLabel) model download via FluidAudio...")

        do {
            // Real progress, straight from FluidAudio. This used to be a timer
            // animating the bar to 80% over 20 seconds and then holding there
            // until the download finished, which on a 450 MB model meant minutes
            // of a bar that looked wedged.
            models = try await AsrModels.downloadAndLoad(version: version) { [weak self] update in
                self?.record(update)
            }

            print("FoxSay: Parakeet \(versionLabel) models downloaded, initializing...")

            // Initialize ASR manager
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models!)
            asrManager = manager

            progress.advance(to: 1.0)
            print("FoxSay: Parakeet \(versionLabel) model download complete")
        } catch {
            print("FoxSay: Parakeet \(versionLabel) download failed: \(error)")
            throw TranscriptionError.transcriptionFailed("Failed to download Parakeet \(versionLabel) model: \(error.localizedDescription)")
        }
    }

    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        isCancelled = false

        // Ensure model is loaded
        if asrManager == nil {
            guard await isModelDownloaded else {
                throw TranscriptionError.modelNotDownloaded
            }

            // Load existing model
            print("FoxSay: Loading Parakeet \(versionLabel) model...")
            models = try await AsrModels.downloadAndLoad(version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models!)
            asrManager = manager
        }

        guard let manager = asrManager else {
            throw TranscriptionError.engineNotAvailable
        }

        if isCancelled {
            throw TranscriptionError.cancelled
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // WORKAROUND: Pad short audio to > 240,000 samples to trigger ChunkProcessor
        // which properly handles isLastChunk for trailing punctuation (question marks)
        // See: FluidAudio bug where single-chunk path doesn't set isLastChunk: true
        var paddedBuffer = audioBuffer
        if audioBuffer.count <= 240_000 {
            let targetLength = 240_001
            paddedBuffer = audioBuffer + Array(repeating: 0, count: targetLength - audioBuffer.count)
        }
        // FoxSay transcribes one complete utterance per call, so each transcription
        // starts from a fresh decoder state. Carrying state across calls is only
        // useful for streaming, where chunks continue a single utterance.
        // decoderLayers varies by version (tdtCtc110m uses 1, the rest use 2).
        var decoderState = try TdtDecoderState(decoderLayers: version.decoderLayers)
        let result = try await manager.transcribe(paddedBuffer, decoderState: &decoderState)

        if isCancelled {
            throw TranscriptionError.cancelled
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return TranscriptionResult(
            text: result.text,
            confidence: nil,
            processingTime: processingTime
        )
    }

    public func cancel() async {
        isCancelled = true
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    public func preload() async throws {
        guard asrManager == nil else {
            // Already loaded
            return
        }

        guard await isModelDownloaded else {
            throw TranscriptionError.modelNotDownloaded
        }

        print("FoxSay: Preloading Parakeet \(versionLabel) model...")
        let startTime = CFAbsoluteTimeGetCurrent()

        models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models!)
        asrManager = manager

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("FoxSay: Parakeet \(versionLabel) model preloaded in \(String(format: "%.2f", loadTime))s")
    }
}
