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

    @Test("Repeated-word commas collapse, real commas survive")
    func testRepeatedWordCommas() {
        // The case the old blanket strip was written for
        #expect(CorrectionPipeline.collapseRepeatedWordCommas("no, no, no") == "no no no")
        #expect(CorrectionPipeline.collapseRepeatedWordCommas("wait, wait a second") == "wait wait a second")

        // The cases the blanket strip destroyed
        #expect(CorrectionPipeline.collapseRepeatedWordCommas("testing, one, two, three.") == "testing, one, two, three.")
        #expect(CorrectionPipeline.collapseRepeatedWordCommas("Hey, how's it going?") == "Hey, how's it going?")
        #expect(CorrectionPipeline.collapseRepeatedWordCommas("Ship it, then tell the team, please.")
            == "Ship it, then tell the team, please.")
    }

    @Test("Spoken punctuation attaches to the correct side")
    func testSpokenPunctuationSpacing() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("hello comma there") == "hello, there")
        #expect(corrector.correctSpokenPunctuation("are we done question mark") == "are we done?")
        #expect(corrector.correctSpokenPunctuation("ship it exclamation point") == "ship it!")
        #expect(corrector.correctSpokenPunctuation("that's it period next up") == "that's it. next up")
        #expect(corrector.correctSpokenPunctuation("one semicolon two") == "one; two")
        #expect(corrector.correctSpokenPunctuation("well hyphen known") == "well-known")
    }

    @Test("Spoken quotes wrap the phrase between them")
    func testSpokenQuotes() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("he said quote we're done unquote and left")
            == "he said \"we're done\" and left")
        #expect(corrector.correctSpokenPunctuation("open quote hello close quote") == "\"hello\"")
        #expect(corrector.correctSpokenPunctuation("she said open quote maybe end quote") == "she said \"maybe\"")
    }

    @Test("Spoken brackets attach to their contents")
    func testSpokenBrackets() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("the total open paren before tax close paren is fine")
            == "the total (before tax) is fine")
        #expect(corrector.correctSpokenPunctuation("see open bracket 3 close bracket") == "see [3]")
    }

    @Test("Spoken line breaks keep surrounding text tight")
    func testSpokenLineBreaks() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("first line new line second line") == "first line\nsecond line")
        #expect(corrector.correctSpokenPunctuation("intro new paragraph body") == "intro\n\nbody")
    }

    @Test("Punctuation rules leave ordinary prose alone")
    func testPunctuationRulesLeaveProseAlone() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("nothing to convert here") == "nothing to convert here")
        // Word-boundary matching must not fire inside longer words
        #expect(corrector.correctSpokenPunctuation("the commanding officer") == "the commanding officer")
        #expect(corrector.correctSpokenPunctuation("a colonial house") == "a colonial house")
    }

    @Test("A spoken mark overrides the punctuation the engine added for the same pause")
    func testSpokenPunctuationOverridesEnginePunctuation() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        // What the engines actually hand over: the mark for the pause AND the word.
        // Saying "Testing comma period" transcribes as "Testing, comma, period."
        #expect(corrector.correctSpokenPunctuation("Testing, comma, period.") == "Testing,.")
        #expect(corrector.correctSpokenPunctuation("Testing, comma.") == "Testing,")

        // The engine also punctuates from context — a question gets its own "?"
        #expect(corrector.correctSpokenPunctuation("What is the name of the game, question mark?")
            == "What is the name of the game?")

        // Multiple engine marks around one spoken word all collapse into it
        #expect(corrector.correctSpokenPunctuation("Nearly done, period. Next up") == "Nearly done. Next up")
    }

    @Test("Spoken quotes survive the engine's own commas")
    func testSpokenQuotesWithEnginePunctuation() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("He said, quote, we're done, unquote, and left.")
            == "He said \"we're done\" and left.")
        #expect(corrector.correctSpokenPunctuation("The total, open paren, before tax, close paren, is fine.")
            == "The total (before tax) is fine.")
    }

    @Test("Parentheses match singular and plural spoken forms")
    func testSpokenParenthesesVariants() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        for open in ["open paren", "open parens", "open parenthesis", "open parentheses",
                     "left paren", "left parenthesis"] {
            for close in ["close paren", "close parens", "close parenthesis", "close parentheses",
                          "right paren", "right parenthesis"] {
                #expect(corrector.correctSpokenPunctuation("total \(open) net \(close) fine")
                    == "total (net) fine")
            }
        }

        // The engine's own comma inside the phrase must not break the match
        #expect(corrector.correctSpokenPunctuation("The total, open parentheses, net, close parentheses, is fine.")
            == "The total (net) is fine.")
    }

    @Test("Dashes: single is a hyphen, doubled is an em dash")
    func testSpokenDashes() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        #expect(corrector.correctSpokenPunctuation("well dash known") == "well - known")
        #expect(corrector.correctSpokenPunctuation("well hyphen known") == "well-known")
        #expect(corrector.correctSpokenPunctuation("wait dash dash then go") == "wait \u{2014} then go")
        #expect(corrector.correctSpokenPunctuation("wait double dash then go") == "wait \u{2014} then go")
        #expect(corrector.correctSpokenPunctuation("wait em dash then go") == "wait \u{2014} then go")
        #expect(corrector.correctSpokenPunctuation("pages 3 en dash 7") == "pages 3\u{2013}7")

        // "em dash" must not be shredded by the bare "dash" rule
        #expect(corrector.correctSpokenPunctuation("an em dash here").contains("-") == false)

        // The engine's comma between the two words still resolves to one em dash
        #expect(corrector.correctSpokenPunctuation("wait, dash, dash, then go") == "wait \u{2014} then go")
    }

    @Test("Paren homophones the speech models actually produce")
    func testParenHomophones() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        // Verbatim from history.json — what Parakeet returned for spoken parens
        #expect(corrector.correctSpokenPunctuation("Hello, close Perrin.") == "Hello).")
        #expect(corrector.correctSpokenPunctuation("Hello, Princess. What's your name? Clothes Princess.")
            == "Hello, Princess. What's your name?).")
        #expect(corrector.correctSpokenPunctuation(
            "This is a test and I'm going to add a parentheses, hello, close parentheses, and continue on.")
            == "This is a test and I'm going to add (hello) and continue on.")
    }

    @Test("A bare quote alternates between opening and closing")
    func testAlternatingQuote() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        // Verbatim from history.json — saying "quote" at both ends
        #expect(corrector.correctSpokenPunctuation(
            "What about, quote, and I want to say this important question here, quote, and continue on with the rest of the sentence.")
            == "What about \"and I want to say this important question here\" and continue on with the rest of the sentence.")

        // Parity is per utterance, so an explicit pair still behaves
        #expect(corrector.correctSpokenPunctuation("he said quote we're done unquote and left")
            == "he said \"we're done\" and left")
    }

    @Test("Bare bracket words alternate when the engine drops the opener")
    func testBareBracketWordsAlternate() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        // Verbatim from history.json — "open" never made it through
        #expect(corrector.correctSpokenPunctuation("What about something parentheses, something else, parentheses?")
            == "What about something (something else)?")
        #expect(corrector.correctSpokenPunctuation("Something parenthesis, something else parenthesis.")
            == "Something (something else).")

        // A surviving "close braces" is still claimed as a closer, so the bare
        // word before it opens the pair
        #expect(corrector.correctSpokenPunctuation("Something braces. Hello, close braces. Hello there.")
            == "Something {Hello}. Hello there.")

        // Explicit openers keep working
        #expect(corrector.correctSpokenPunctuation("Something open bracket, hello, close bracket, hello.")
            == "Something [hello] hello.")
    }

    @Test("Open and close resolve from whether the pair is already open")
    func testBracketDepthTracking() {
        let corrector = RuleBasedCorrector(rules: RuleBasedCorrector.punctuationRules)

        // Explicit opener, bare closer
        #expect(corrector.correctSpokenPunctuation("total open parentheses net parentheses fine")
            == "total (net) fine")
        // Bare opener, explicit closer
        #expect(corrector.correctSpokenPunctuation("total parentheses net close parentheses fine")
            == "total (net) fine")
        // Bare at both ends
        #expect(corrector.correctSpokenPunctuation("total parentheses net parentheses fine")
            == "total (net) fine")

        // Nesting, and a third pair reopening after the first closes
        #expect(corrector.correctSpokenPunctuation("one parentheses b parentheses c parentheses d parentheses e")
            == "one (b) c (d) e")

        // Each pair keeps its own depth
        #expect(corrector.correctSpokenPunctuation("one parentheses b brackets c brackets d parentheses e")
            == "one (b [c] d) e")

        // A stray closer must not push the depth negative and flip the next one
        #expect(corrector.correctSpokenPunctuation("close parentheses then parentheses x parentheses y")
            == ") then (x) y")
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
