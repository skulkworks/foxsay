import Testing
@testable import FoxSayFeature

@Suite("AIModel registry")
struct AIModelRegistryTests {
    @Test("registry is not empty")
    func registryNotEmpty() {
        #expect(!AIModel.registry.isEmpty)
    }

    @Test("model ids are unique")
    func uniqueIds() {
        let ids = AIModel.registry.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("huggingFaceId has org/name shape expected by the model cache")
    func huggingFaceIdShape() {
        for model in AIModel.registry {
            let parts = model.huggingFaceId.split(separator: "/")
            #expect(parts.count == 2, "\(model.id): \(model.huggingFaceId)")
            #expect(parts.allSatisfy { !$0.isEmpty })
        }
    }

    @Test("sizes and capabilities are plausible")
    func sizesAndCapabilities() {
        for model in AIModel.registry {
            #expect(model.sizeBytes > 100_000_000, "\(model.id)")
            #expect(!model.capabilities.isEmpty, "\(model.id)")
            #expect(!model.formattedSize.isEmpty)
        }
    }

    @Test("lookup by id round-trips, unknown id returns nil")
    func lookup() {
        // AIModel isn't Equatable, so round-trip on the identity instead
        for model in AIModel.registry {
            #expect(AIModel.model(withId: model.id)?.id == model.id)
            #expect(AIModel.model(withId: model.id)?.huggingFaceId == model.huggingFaceId)
        }
        #expect(AIModel.model(withId: "no-such-model") == nil)
    }

    @Test("exactly one model carries the Recommended badge")
    func singleRecommendation() {
        let recommended = AIModel.registry.filter(\.isRecommended)
        #expect(recommended.count == 1, "got \(recommended.map(\.id))")
        // Chosen by benchmarking the vocal-corrections prompt; see the note in AIModel.swift.
        #expect(recommended.first?.id == "qwen-1.5b-instruct")
    }

    @Test("newest-generation models are present")
    func newestGenerationPresent() {
        // These need the qwen3_5 and gemma4 architectures, which only exist from
        // mlx-swift-lm 3.31.4 onwards. Whether a given architecture is registered
        // isn't introspectable at build time, so this can't verify loadability. It
        // does catch the entries being dropped, e.g. by a careless dependency revert.
        #expect(AIModel.model(withId: "qwen3.5-2b") != nil)
        #expect(AIModel.model(withId: "gemma-4-e2b-instruct") != nil)
    }
}

@Suite("Transcription model registry")
struct TranscriptionModelRegistryTests {
    @Test("every selectable model type has metadata")
    func allTypesCovered() {
        for type in ModelType.allCases {
            #expect(ModelRegistry.info(for: type) != nil, "\(type)")
        }
    }

    @Test("legacy whisperKit alias maps to Whisper Base")
    func legacyAlias() {
        #expect(ModelRegistry.info(for: .whisperKit)?.type == .whisperBase)
    }

    @Test("ratings are within 1...5")
    func ratingsInRange() {
        for info in ModelRegistry.allModels {
            #expect((1...5).contains(info.accuracyRating), "\(info.id)")
            #expect((1...5).contains(info.speedRating), "\(info.id)")
        }
    }

    @Test("ids are unique")
    func uniqueIds() {
        let ids = ModelRegistry.allModels.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
