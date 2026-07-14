// ABOUTME: Regression tests for prose preprocessing before synthesis.
// ABOUTME: Covers section breaks, markup emphasis, dialogue dashes, and substitutions.

import Testing
@testable import YapperKit

@Suite(.serialized)
struct ProsePreprocessorTests {
    @Test("RT-34.1: asterisk section break becomes metadata, not spoken text")
    func asteriskSectionBreakBecomesMetadata() {
        let result = ProsePreprocessor.preprocess("First paragraph.\n\n***\n\nSecond paragraph.")

        #expect(result.text == "First paragraph.\n\nSecond paragraph.")
        #expect(result.sectionBreaks == [
            ProseSectionBreak(lineIndex: 2, pause: .section)
        ])
        #expect(result.diagnostics.contains {
            $0.kind == .sectionBreak && $0.original == "***" && $0.replacement == ""
        })
    }

    @Test("RT-34.2 and RT-34.20: standalone triple hyphen is a section break")
    func tripleHyphenSectionBreakBecomesMetadata() {
        let result = ProsePreprocessor.preprocess("Before.\n---\nAfter.")

        #expect(result.text == "Before.\n\nAfter.")
        #expect(result.sectionBreaks == [
            ProseSectionBreak(lineIndex: 1, pause: .section)
        ])
        #expect(!result.text.contains("---"))
    }

    @Test("RT-34.3 and RT-34.4: markdown and org emphasis become quoted prose")
    func emphasisMarkupBecomesQuotedProse() {
        let input = "This is *italic*, _also italic_, **bold**, __also bold__, and /org italic/."
        let result = ProsePreprocessor.preprocess(input)

        #expect(result.text == "This is \"italic\", \"also italic\", \"bold\", \"also bold\", and \"org italic\".")
        #expect(result.diagnostics.filter { $0.kind == .emphasis }.count == 5)
    }

    @Test("RT-34.5 through RT-34.8 and RT-39.2: malformed and structural markers are preserved")
    func malformedAndStructuralMarkersArePreserved() {
        let input = """
        This *does not close.
        * list item
        A 10-20 range stays together.
        A --option flag stays together.
        A --- B stays together.
        """
        let result = ProsePreprocessor.preprocess(input)

        #expect(result.text.contains("This *does not close."))
        #expect(result.text.contains("* list item"))
        #expect(result.text.contains("10-20 range"))
        #expect(result.text.contains("--option flag"))
        #expect(result.text.contains("A --- B stays together."))
        #expect(result.sectionBreaks.isEmpty)
    }

    @Test("RT-39.1: ASCII-letter intra-word hyphens become spaces")
    func intraWordHyphensBecomeSpaces() {
        let result = ProsePreprocessor.preprocess("sea-holly, ice-cream, and car-park.")

        #expect(result.text == "sea holly, ice cream, and car park.")
    }

    @Test("RT-34.9 and RT-34.10: emphasis normalizes before speech substitutions")
    func substitutionsApplyAfterMarkupNormalization() {
        let result = ProsePreprocessor.preprocess(
            "Say *Cáit* and /taoiseach/.",
            substitutions: [
                "Cáit": "Kawch",
                "taoiseach": "/tiːʃəx/"
            ]
        )

        #expect(result.text == "Say \"Kawch\" and \"[taoiseach](/tiːʃəx/)\".")
    }

    @Test("RT-36.1: custom pronunciation substitutions are case-insensitive")
    func substitutionsAreCaseInsensitive() {
        let result = ProsePreprocessor.preprocess(
            "The jacket, Jacket, and JACKET. The Taoiseach and TAOISEACH.",
            substitutions: [
                "jacket": "coat",
                "taoiseach": "/tiːʃəx/"
            ]
        )

        #expect(result.text == "The coat, coat, and coat. The [Taoiseach](/tiːʃəx/) and [TAOISEACH](/tiːʃəx/).")
    }

    @Test("RT-47.44 and RT-47.45: substitutions match Unicode whole terms")
    func substitutionsMatchUnicodeWholeTerms() {
        let result = ProsePreprocessor.preprocess(
            "Cáit met CÁIT near Caitlin and the garda, not Gdansk.",
            substitutions: [
                "Cáit": "Kawch",
                "garda": "guard"
            ]
        )

        #expect(result.text == "Kawch met Kawch near Caitlin and the guard, not Gdansk.")
    }

    @Test("RT-47.45: multiword substitutions use outer term boundaries")
    func multiwordSubstitutionsUseOuterBoundaries() {
        let result = ProsePreprocessor.preprocess(
            "New York, new yorker, and anew york differ.",
            substitutions: ["new york": "NYC"]
        )

        #expect(result.text == "NYC, new yorker, and anew york differ.")
    }

    @Test("RT-46.52 through RT-46.55: IPA resolves by engine capability")
    func ipaResolvesByEngineCapability() {
        let supported = ProsePreprocessor.preprocess(
            "Taḋg met Cáit.",
            substitutions: [
                "Taḋg": "/taɪɡ/(Tigue)",
                "Cáit": "/kɔːt/"
            ],
            supportsIPA: true
        )
        let unsupported = ProsePreprocessor.preprocess(
            "Taḋg met Cáit.",
            substitutions: [
                "Taḋg": "/taɪɡ/(Tigue)",
                "Cáit": "/kɔːt/"
            ],
            supportsIPA: false
        )

        #expect(supported.text == "[Taḋg](/taɪɡ/) met [Cáit](/kɔːt/).")
        #expect(unsupported.text == "Tigue met Cáit.")
        #expect(unsupported.diagnostics.contains {
            $0.kind == .substitutionSkipped && $0.original == "Cáit"
        })
    }

    @Test("RT-34.12 through RT-34.14: section pause is distinct from paragraph break")
    func sectionPauseMetadataIsDistinctFromParagraphBreaks() {
        let result = ProsePreprocessor.preprocess("One.\n\nTwo.\n\n___\n\nThree.")

        #expect(result.text == "One.\n\nTwo.\n\nThree.")
        #expect(result.sectionBreaks == [
            ProseSectionBreak(lineIndex: 4, pause: .section)
        ])
        #expect(!result.sectionBreaks.contains { $0.pause == .paragraph })
    }

    @Test("RT-34.18 and RT-34.19: line-start dialogue dashes quote the whole line")
    func dialogueDashLinesBecomeQuotedLines() {
        let markdownDash = ProsePreprocessor.preprocess("--- I would like cheese, he said.")
        let emDash = ProsePreprocessor.preprocess("— Hello this is also speech, he said again.")

        #expect(markdownDash.text == "\"I would like cheese, he said.\"")
        #expect(emDash.text == "\"Hello this is also speech, he said again.\"")
        #expect(markdownDash.diagnostics.contains { $0.kind == .dialogueDash })
        #expect(emDash.diagnostics.contains { $0.kind == .dialogueDash })
    }
}
