// ABOUTME: Regression tests for canonical, engine-extensible speech configuration.
// ABOUTME: Verifies typed engine settings and deterministic layer merge behaviour.

import Foundation
import Testing
@testable import YapperKit

struct SpeechConfigurationTests {
    @Test("RT-47.43: custom engine settings decode without changing the root model")
    func customEngineSettingsDecodeThroughRegistry() throws {
        var registry = SpeechEngineSettingsRegistry()
        registry.register(engineID: "custom") { options in
            CustomSettings(
                model: try options.requiredString("model"),
                steps: try options.requiredInt("steps")
            )
        }
        let configuration = SpeechConfiguration(
            selectedEngineID: "custom",
            engines: [
                "custom": SpeechEngineConfiguration(
                    voice: "reference-one",
                    speed: 0.9,
                    concurrency: 1,
                    options: ["model": .string("weights-v1"), "steps": .integer(32)]
                )
            ]
        )

        let settings = try registry.decode(
            CustomSettings.self,
            engineID: try #require(configuration.selectedEngineID),
            options: try #require(configuration.engines["custom"]?.options)
        )

        #expect(settings == CustomSettings(model: "weights-v1", steps: 32))
    }

    @Test("RT-47.6 through RT-47.8: maps merge while sequences and explicit empties replace")
    func configurationLayersUseDocumentedMergeRules() {
        let lower = SpeechConfiguration(
            selectedEngineID: .yapper,
            engines: [
                .yapper: SpeechEngineConfiguration(
                    voice: "af_heart",
                    speed: 1,
                    concurrency: 3,
                    options: [
                        "characters": .map(["ALICE": .string("af_heart"), "BOB": .string("bm_daniel")]),
                        "pool": .sequence([.string("af_heart")])
                    ]
                )
            ]
        )
        let upper = SpeechConfiguration(
            engines: [
                .yapper: SpeechEngineConfiguration(
                    speed: 1.2,
                    options: [
                        "characters": .map(["ALICE": .string("bf_emma")]),
                        "pool": .sequence([])
                    ]
                )
            ]
        )

        let merged = lower.merging(upper)
        let yapper = merged.engines[.yapper]

        #expect(yapper?.voice == "af_heart")
        #expect(yapper?.speed == 1.2)
        #expect(yapper?.concurrency == 3)
        #expect(yapper?.options["characters"] == .map([
            "ALICE": .string("bf_emma"),
            "BOB": .string("bm_daniel")
        ]))
        #expect(yapper?.options["pool"] == .sequence([]))
    }

    @Test("RT-47.42: unselected future engine settings survive canonical merge")
    func unselectedFutureEngineSurvivesMerge() {
        let base = SpeechConfiguration(selectedEngineID: .yapper)
        let project = SpeechConfiguration(engines: [
            "future-local": SpeechEngineConfiguration(
                options: ["reference-profile": .string("narrator")]
            )
        ])

        let merged = base.merging(project)

        #expect(merged.selectedEngineID == .yapper)
        #expect(merged.engines["future-local"]?.options["reference-profile"] == .string("narrator"))
    }
}

private struct CustomSettings: Equatable, Sendable {
    let model: String
    let steps: Int
}
