import Testing
@testable import FoxSayFeature

@Suite("FoxSay Tests")
struct FoxSayFeatureTests {

    @Test("TranscriptionResult creation")
    func testTranscriptionResultCreation() {
        let result = TranscriptionResult(
            text: "Hello world",
            confidence: 0.95,
            processingTime: 0.150
        )

        #expect(result.text == "Hello world")
        #expect(result.confidence == 0.95)
        #expect(result.processingTime == 0.150)
        #expect(result.wasDevCorrected == false)
        #expect(result.originalText == nil)
    }

    @Test("TranscriptionResult with correction")
    func testTranscriptionResultWithCorrection() {
        let original = TranscriptionResult(text: "git status dash dash short")
        let corrected = original.withCorrection("git status --short")

        #expect(corrected.text == "git status --short")
        #expect(corrected.wasDevCorrected == true)
        #expect(corrected.originalText == "git status dash dash short")
    }

    @Test("RuleBasedCorrector dash replacement")
    func testDashCorrection() {
        let corrector = RuleBasedCorrector()
        // Note: RuleBasedCorrector replaces words but preserves spaces
        // The CorrectionPipeline's postProcess removes extra spaces
        let result = corrector.correct("git status dash dash short")
        #expect(result == "git status - - short")
    }

    @Test("RuleBasedCorrector symbol corrections")
    func testSymbolCorrections() {
        let corrector = RuleBasedCorrector()

        // Note: RuleBasedCorrector replaces words but preserves spaces
        #expect(corrector.correct("dot js") == ". js")
        #expect(corrector.correct("underscore foo") == "_ foo")
        #expect(corrector.correct("equals equals") == "= =")
        #expect(corrector.correct("at sign example") == "@ example")
    }

    @Test("RuleBasedCorrector bracket corrections")
    func testBracketCorrections() {
        let corrector = RuleBasedCorrector()

        // Note: RuleBasedCorrector replaces words but preserves spaces
        #expect(corrector.correct("open paren close paren") == "( )")
        #expect(corrector.correct("open bracket close bracket") == "[ ]")
        #expect(corrector.correct("open brace close brace") == "{ }")
    }

    @Test("EngineType properties")
    func testEngineTypeProperties() {
        // .whisperKit is the legacy alias and displays as Whisper Base
        #expect(EngineType.whisperKit.displayName == "Whisper Base")
        #expect(EngineType.whisperKit.rawValue == "whisperkit")
        // .parakeetV2 keeps the bare "parakeet" raw value for backward compatibility
        #expect(EngineType.parakeetV2.displayName == "Parakeet V2")
        #expect(EngineType.parakeetV2.rawValue == "parakeet")
    }

    @Test("every ModelType has speech-model registry metadata")
    func testModelRegistryCoversEveryType() {
        for type in ModelType.allCases {
            #expect(ModelRegistry.info(for: type) != nil, "\(type) is missing from ModelRegistry.allModels")
        }
    }

    @Test("registry ids are unique and match their model type")
    func testModelRegistryIdsConsistent() {
        let ids = ModelRegistry.allModels.map(\.id)
        #expect(Set(ids).count == ids.count)
        // id is what the UI keys off, so it must track the enum's raw value
        for info in ModelRegistry.allModels {
            #expect(info.id == info.type.rawValue || info.type == .parakeetV2,
                    "\(info.id) does not match \(info.type.rawValue)")
        }
    }
}
