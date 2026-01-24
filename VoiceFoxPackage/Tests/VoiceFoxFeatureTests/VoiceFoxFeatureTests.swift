import Testing
@testable import VoiceFoxFeature

@Suite("VoiceFox Tests")
struct VoiceFoxFeatureTests {

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

    @Test("DevAppConfig defaults")
    func testDevAppConfigDefaults() {
        let defaults = DevAppConfig.defaultApps

        #expect(defaults.count > 0)
        #expect(defaults.contains { $0.bundleId == "com.microsoft.VSCode" })
        #expect(defaults.contains { $0.bundleId == "com.apple.dt.Xcode" })
        #expect(defaults.contains { $0.bundleId == "com.googlecode.iterm2" })
    }

    @Test("EngineType properties")
    func testEngineTypeProperties() {
        #expect(EngineType.whisperKit.displayName == "WhisperKit")
        #expect(EngineType.parakeet.displayName == "Parakeet MLX")
        #expect(EngineType.whisperKit.rawValue == "whisperkit")
        #expect(EngineType.parakeet.rawValue == "parakeet")
    }
}
