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

    @Test("every registry model has an architecture the pinned mlx-swift-lm supports")
    func architecturesAreSupported() {
        // mlx-swift-lm is pinned (see Package.swift), so a model whose architecture
        // landed upstream after that revision would download and then fail to load.
        // qwen3_5 and gemma4 are the two known-unsupported ones at this pin.
        for model in AIModel.registry {
            let repo = model.huggingFaceId.lowercased()
            #expect(!repo.contains("qwen3.5"), "\(model.id) needs a newer mlx-swift-lm")
            #expect(!repo.contains("gemma-4"), "\(model.id) needs a newer mlx-swift-lm")
        }
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
