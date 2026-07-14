// ABOUTME: YAML configuration for script reading mode.
// ABOUTME: Defines ScriptConfig parsed from script.yaml alongside the input file.

import Foundation
import YapperKit
import Yams

/// Configuration for script-reading mode, parsed from a YAML file.
/// Nested render configuration — shared schema with First Folio.
struct RenderConfig: Decodable {
    var stageDirections: Bool?
    var frontmatter: Bool?
    var footnotes: Bool?
    var characterTable: Bool?
    var transitions: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case stageDirections = "stage-directions"
        case frontmatter, footnotes, transitions
        case characterTable = "character-table"
    }
}

struct FALRemoteConfig: Decodable {
    var apiKey: String?
    var accountAPIKey: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api-key"
        case accountAPIKey = "account-api-key"
    }
}

struct OpenAIRemoteConfig: Decodable {
    var apiKey: String?
    var adminAPIKey: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "api-key"
        case adminAPIKey = "admin-api-key"
    }
}

struct YapperVoicesConfig: Decodable {
    var autoAssign: Bool?
    var narrator: String?
    var intro: String?
    var characters: [String: String]?

    enum CodingKeys: String, CodingKey {
        case autoAssign = "auto-assign"
        case narrator, intro, characters
    }
}

struct YapperPacingConfig: Decodable {
    var dialogueSpeed: Float?
    var stageDirectionSpeed: Float?
    var gapAfterDialogue: Double?
    var gapAfterStageDirection: Double?
    var gapAfterScene: Double?

    enum CodingKeys: String, CodingKey {
        case dialogueSpeed = "dialogue-speed"
        case stageDirectionSpeed = "stage-direction-speed"
        case gapAfterDialogue = "gap-after-dialogue"
        case gapAfterStageDirection = "gap-after-stage-direction"
        case gapAfterScene = "gap-after-scene"
    }
}

struct YapperPerformanceConfig: Decodable {
    var threads: Int?
}

struct RemoteSpeechConfig: Decodable {
    var fal: FALRemoteConfig?
    var openai: OpenAIRemoteConfig?

    enum CodingKeys: String, CodingKey {
        case fal, openai
    }
}

struct CredentialSourceYAML: Decodable {
    var literal: String?
    var helper: String?
    var baseDirectory: URL?

    enum CodingKeys: String, CodingKey {
        case literal, helper
    }

    var credentialConfig: SpeechCredentialConfig {
        let source: SpeechCredentialInput?
        if let literal {
            source = .literal(literal)
        } else if let helper {
            source = .helper(helper)
        } else {
            source = nil
        }
        return SpeechCredentialConfig(source: source, baseDirectory: baseDirectory)
    }

    func validate(path: String) throws {
        if literal != nil && helper != nil {
            throw ScriptError.invalidConfig(
                path: path,
                message: "Credential slot cannot contain both literal and helper"
            )
        }
    }
}

struct EngineCredentialsYAML: Decodable {
    var generation: CredentialSourceYAML?
    var account: CredentialSourceYAML?
    var admin: CredentialSourceYAML?
}

struct EngineYAMLConfig: Decodable {
    var voice: String?
    var speed: Float?
    var concurrency: Int?
    var endpoint: String?
    var model: String?
    var outputFormat: String?
    var stability: Double?
    var similarityBoost: Double?
    var style: Double?
    var languageCode: String?
    var textNormalization: String?
    var instructions: String?
    var credentials: EngineCredentialsYAML?
    var speechSubstitution: [String: String]?
    var options: [String: EngineOptionValue]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case voice, speed, concurrency, endpoint, model, stability, style, instructions, credentials
        case speechSubstitution = "speech-substitution"
        case outputFormat = "output-format"
        case similarityBoost = "similarity-boost"
        case languageCode = "language-code"
        case textNormalization = "text-normalization"
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(
        voice: String? = nil,
        speed: Float? = nil,
        concurrency: Int? = nil,
        endpoint: String? = nil,
        model: String? = nil,
        outputFormat: String? = nil,
        stability: Double? = nil,
        similarityBoost: Double? = nil,
        style: Double? = nil,
        languageCode: String? = nil,
        textNormalization: String? = nil,
        instructions: String? = nil,
        credentials: EngineCredentialsYAML? = nil,
        speechSubstitution: [String: String]? = nil,
        options: [String: EngineOptionValue] = [:]
    ) {
        self.voice = voice
        self.speed = speed
        self.concurrency = concurrency
        self.endpoint = endpoint
        self.model = model
        self.outputFormat = outputFormat
        self.stability = stability
        self.similarityBoost = similarityBoost
        self.style = style
        self.languageCode = languageCode
        self.textNormalization = textNormalization
        self.instructions = instructions
        self.credentials = credentials
        self.speechSubstitution = speechSubstitution
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: CodingKeys.self)
        voice = try known.decodeIfPresent(String.self, forKey: .voice)
        speed = try known.decodeIfPresent(Float.self, forKey: .speed)
        concurrency = try known.decodeIfPresent(Int.self, forKey: .concurrency)
        endpoint = try known.decodeIfPresent(String.self, forKey: .endpoint)
        model = try known.decodeIfPresent(String.self, forKey: .model)
        outputFormat = try known.decodeIfPresent(String.self, forKey: .outputFormat)
        stability = try known.decodeIfPresent(Double.self, forKey: .stability)
        similarityBoost = try known.decodeIfPresent(Double.self, forKey: .similarityBoost)
        style = try known.decodeIfPresent(Double.self, forKey: .style)
        languageCode = try known.decodeIfPresent(String.self, forKey: .languageCode)
        textNormalization = try known.decodeIfPresent(String.self, forKey: .textNormalization)
        instructions = try known.decodeIfPresent(String.self, forKey: .instructions)
        credentials = try known.decodeIfPresent(EngineCredentialsYAML.self, forKey: .credentials)
        speechSubstitution = try known.decodeIfPresent(
            [String: String].self,
            forKey: .speechSubstitution
        )

        let knownNames = Set(CodingKeys.allCases.map(\.rawValue))
        let dynamic = try decoder.container(keyedBy: DynamicKey.self)
        options = [:]
        for key in dynamic.allKeys where !knownNames.contains(key.stringValue) {
            options[key.stringValue] = try dynamic.decode(EngineOptionValue.self, forKey: key)
        }
    }

    func merging(_ upper: EngineYAMLConfig) -> EngineYAMLConfig {
        EngineYAMLConfig(
            voice: upper.voice ?? voice,
            speed: upper.speed ?? speed,
            concurrency: upper.concurrency ?? concurrency,
            endpoint: upper.endpoint ?? endpoint,
            model: upper.model ?? model,
            outputFormat: upper.outputFormat ?? outputFormat,
            stability: upper.stability ?? stability,
            similarityBoost: upper.similarityBoost ?? similarityBoost,
            style: upper.style ?? style,
            languageCode: upper.languageCode ?? languageCode,
            textNormalization: upper.textNormalization ?? textNormalization,
            instructions: upper.instructions ?? instructions,
            credentials: mergeCredentials(credentials, upper.credentials),
            speechSubstitution: mergeOptionalConfigMaps(
                speechSubstitution,
                upper.speechSubstitution
            ),
            options: mergeOptions(options, upper.options)
        )
    }

    var normalized: SpeechEngineConfiguration {
        SpeechEngineConfiguration(
            voice: voice.map { SpeechVoiceID($0) },
            speed: speed.map(Double.init),
            concurrency: concurrency,
            options: knownOptions.mergingMap(options)
        )
    }

    private var knownOptions: [String: EngineOptionValue] {
        var result: [String: EngineOptionValue] = [:]
        if let endpoint { result["endpoint"] = .string(endpoint) }
        if let model { result["model"] = .string(model) }
        if let outputFormat { result["output-format"] = .string(outputFormat) }
        if let stability { result["stability"] = .double(stability) }
        if let similarityBoost { result["similarity-boost"] = .double(similarityBoost) }
        if let style { result["style"] = .double(style) }
        if let languageCode { result["language-code"] = .string(languageCode) }
        if let textNormalization { result["text-normalization"] = .string(textNormalization) }
        if let instructions { result["instructions"] = .string(instructions) }
        return result
    }

    private func mergeOptions(
        _ lower: [String: EngineOptionValue],
        _ upper: [String: EngineOptionValue]
    ) -> [String: EngineOptionValue] {
        lower.mergingMap(upper)
    }

    private func mergeCredentials(
        _ lower: EngineCredentialsYAML?,
        _ upper: EngineCredentialsYAML?
    ) -> EngineCredentialsYAML? {
        guard lower != nil || upper != nil else { return nil }
        return EngineCredentialsYAML(
            generation: upper?.generation ?? lower?.generation,
            account: upper?.account ?? lower?.account,
            admin: upper?.admin ?? lower?.admin
        )
    }
}

private extension Dictionary where Key == String, Value == EngineOptionValue {
    func mergingMap(_ upper: [String: EngineOptionValue]) -> [String: EngineOptionValue] {
        guard case .map(let merged) = EngineOptionValue.map(self).merging(.map(upper)) else {
            return upper
        }
        return merged
    }
}

struct ScriptVoiceYAMLConfig: Decodable {
    var autoAssign: Bool?
    var pool: [String]?
    var narrator: String?
    var intro: String?
    var characters: [String: String]?

    enum CodingKeys: String, CodingKey {
        case autoAssign = "auto-assign"
        case pool, narrator, intro, characters
    }
}

struct CanonicalScriptYAMLConfig: Decodable {
    var voices: [String: ScriptVoiceYAMLConfig]?
    var pacing: YapperPacingConfig?
}

struct YapperConfig: Decodable {
    var engine: String?
    var engines: [String: EngineYAMLConfig]?
    var speechSubstitution: [String: String]?
    var script: CanonicalScriptYAMLConfig?
    var voices: YapperVoicesConfig?
    var pacing: YapperPacingConfig?
    var performance: YapperPerformanceConfig?
    var remoteSpeech: RemoteSpeechConfig?

    enum CodingKeys: String, CodingKey {
        case speechSubstitution = "speech-substitution"
        case engine, engines, script, voices, pacing, performance
        case remoteSpeech = "remote-speech"
    }
}

struct ScriptConfig: Decodable {
    var title: String?
    var subtitle: String?
    var author: String?
    var autoAssignVoices: Bool?
    var narratorVoice: String?
    var characterVoices: [String: String]?

    // Render settings (nested block, shared with First Folio)
    var render: RenderConfig?

    // Legacy flat keys (backwards compatibility)
    var renderStageDirections: Bool?
    var renderIntro: Bool?
    var renderFootnotes: Bool?

    // Issue #25: concurrent synthesis, gaps, speed
    var threads: Int?
    var gapAfterDialogue: Double?
    var gapAfterStageDirection: Double?
    var gapAfterScene: Double?
    var dialogueSpeed: Float?
    var stageDirectionSpeed: Float?

    // Issue #24: preamble
    var introVoice: String?

    // Pronunciation substitutions: applied to text before synthesis
    var speechSubstitution: [String: String]?
    var yapper: YapperConfig?

    var selectedEngine: String? { yapper?.engine }

    func engineConfig(_ id: String) -> EngineYAMLConfig? {
        yapper?.engines?[id]
    }

    func resolvedSpeechSubstitutions(engineID: SpeechEngineID) -> [String: String] {
        CaseInsensitiveConfigMap.merging(
            speechSubstitution ?? [:],
            engineConfig(engineID.rawValue)?.speechSubstitution ?? [:]
        )
    }

    func scriptVoiceConfig(_ id: String) -> ScriptVoiceYAMLConfig? {
        yapper?.script?.voices?[id]
    }

    var hasScriptSettings: Bool {
        yapper?.script != nil
            || autoAssignVoices != nil
            || narratorVoice != nil
            || characterVoices != nil
            || render != nil
            || renderStageDirections != nil
            || renderIntro != nil
            || renderFootnotes != nil
            || introVoice != nil
            || threads != nil
            || gapAfterDialogue != nil
            || gapAfterStageDirection != nil
            || gapAfterScene != nil
            || dialogueSpeed != nil
            || stageDirectionSpeed != nil
    }

    var normalizedSpeechConfiguration: SpeechConfiguration {
        SpeechConfiguration(
            selectedEngineID: selectedEngine.map { SpeechEngineID($0) },
            engines: Dictionary(uniqueKeysWithValues: (yapper?.engines ?? [:]).map {
                (SpeechEngineID($0.key), $0.value.normalized)
            })
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, subtitle, author, threads, render
        case autoAssignVoices = "auto-assign-voices"
        case renderStageDirections = "render-stage-directions"
        case narratorVoice = "narrator-voice"
        case characterVoices = "character-voices"
        case gapAfterDialogue = "gap-after-dialogue"
        case gapAfterStageDirection = "gap-after-stage-direction"
        case gapAfterScene = "gap-after-scene"
        case dialogueSpeed = "dialogue-speed"
        case stageDirectionSpeed = "stage-direction-speed"
        case renderIntro = "render-intro"
        case introVoice = "intro-voice"
        case renderFootnotes = "render-footnotes"
        case speechSubstitution = "speech-substitution"
        case yapper
    }

    // Resolved accessors — prefer nested render block, fall back to legacy flat keys
    var resolvedRenderStageDirections: Bool { render?.stageDirections ?? renderStageDirections ?? true }
    var resolvedRenderFrontmatter: Bool { render?.frontmatter ?? renderIntro ?? true }
    var resolvedRenderFootnotes: Bool { render?.footnotes ?? renderFootnotes ?? true }
    var resolvedRenderCharacterTable: Bool { render?.characterTable ?? true }
    var resolvedRenderTransitions: Bool { render?.transitions ?? true }

    /// Load config from a YAML file path.
    static func load(from path: String) throws -> ScriptConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw ScriptError.invalidConfig(path: path, message: "File is not valid UTF-8")
        }
        do {
            var config = try YAMLDecoder().decode(ScriptConfig.self, from: yaml)
            config.setCredentialBaseDirectory(
                URL(fileURLWithPath: path).deletingLastPathComponent()
            )
            try config.validateCanonicalCredentials(path: path)
            emitDeprecationWarnings(config: config, path: path)
            return config
        } catch {
            throw ScriptError.invalidConfig(path: path, message: error.localizedDescription)
        }
    }

    /// Load and merge config from cascading sources.
    ///
    /// Precedence (later overrides earlier):
    /// 1. `~/.config/yapper/yapper.yaml` — global defaults
    /// 2. `./yapper.yaml` or `./script.yaml` in input file's directory
    /// 3. `explicitPath` (`--script-config` CLI flag)
    ///
    /// Keys are merged individually — a project config that sets only
    /// `yapper.speech-substitution` inherits all other keys from the global config.
    static func loadMerged(
        explicitPath: String? = nil,
        inputDir: String? = nil
    ) throws -> ScriptConfig {
        var merged = ScriptConfig()

        // 1. Global: ~/.config/yapper/yapper.yaml
        let globalPath = NSHomeDirectory() + "/.config/yapper/yapper.yaml"
        if FileManager.default.fileExists(atPath: globalPath) {
            let global = try ScriptConfig.load(from: globalPath)
            merged = merge(base: merged, override: global)
        }

        // 2. Project: ./yapper.yaml or ./script.yaml in input dir
        if let dir = inputDir {
            for name in ["yapper.yaml", "script.yaml"] {
                let path = "\(dir)/\(name)"
                if FileManager.default.fileExists(atPath: path) {
                    let project = try ScriptConfig.load(from: path)
                    merged = merge(base: merged, override: project)
                    break
                }
            }
        }

        // 3. Explicit CLI path
        if let path = explicitPath {
            let explicit = try ScriptConfig.load(from: path)
            merged = merge(base: merged, override: explicit)
        }

        return merged
    }

    /// Merge two configs: non-nil values in `override` replace values in `base`.
    /// Legacy top-level Yapper keys are applied first, then namespaced `yapper.*`
    /// keys, so the new schema wins when both forms are present.
    private static func merge(base: ScriptConfig, override: ScriptConfig) -> ScriptConfig {
        var result = base
        if let v = override.title { result.title = v }
        if let v = override.subtitle { result.subtitle = v }
        if let v = override.author { result.author = v }
        if let v = override.autoAssignVoices { result.autoAssignVoices = v }
        if let v = override.narratorVoice { result.narratorVoice = v }
        if let v = override.threads { result.threads = v }
        if let v = override.gapAfterDialogue { result.gapAfterDialogue = v }
        if let v = override.gapAfterStageDirection { result.gapAfterStageDirection = v }
        if let v = override.gapAfterScene { result.gapAfterScene = v }
        if let v = override.dialogueSpeed { result.dialogueSpeed = v }
        if let v = override.stageDirectionSpeed { result.stageDirectionSpeed = v }
        if let v = override.introVoice { result.introVoice = v }

        // Legacy flat render keys
        if let v = override.renderStageDirections { result.renderStageDirections = v }
        if let v = override.renderIntro { result.renderIntro = v }
        if let v = override.renderFootnotes { result.renderFootnotes = v }

        // Nested render block — merge field by field
        if let overrideRender = override.render {
            var merged = result.render ?? RenderConfig()
            if let v = overrideRender.stageDirections { merged.stageDirections = v }
            if let v = overrideRender.frontmatter { merged.frontmatter = v }
            if let v = overrideRender.footnotes { merged.footnotes = v }
            if let v = overrideRender.characterTable { merged.characterTable = v }
            if let v = overrideRender.transitions { merged.transitions = v }
            result.render = merged
        }

        // Merge dictionaries key-by-key
        if let overrideVoices = override.characterVoices {
            result.characterVoices = overrideVoices.isEmpty
                ? [:]
                : CaseInsensitiveConfigMap.merging(
                    result.characterVoices ?? [:],
                    overrideVoices
                )
        }
        if let overrideSubs = override.speechSubstitution {
            result.speechSubstitution = overrideSubs.isEmpty
                ? [:]
                : CaseInsensitiveConfigMap.merging(
                    result.speechSubstitution ?? [:],
                    overrideSubs
                )
        }
        applyNamespacedYapperConfig(from: override, to: &result)

        return result
    }

    private static func applyNamespacedYapperConfig(from override: ScriptConfig, to result: inout ScriptConfig) {
        guard let yapper = override.yapper else { return }

        var mergedYapper = result.yapper ?? YapperConfig()
        if let engine = yapper.engine {
            mergedYapper.engine = engine
        }
        if let overrideEngines = yapper.engines {
            if overrideEngines.isEmpty {
                mergedYapper.engines = [:]
            } else {
                var engines = mergedYapper.engines ?? [:]
                for (id, settings) in overrideEngines {
                    engines[id] = engines[id]?.merging(settings) ?? settings
                }
                mergedYapper.engines = engines
            }
        }
        if let script = yapper.script {
            mergedYapper.script = mergeCanonicalScript(mergedYapper.script, script)
        }
        result.yapper = mergedYapper

        if let namespacedSubs = yapper.speechSubstitution {
            result.speechSubstitution = namespacedSubs.isEmpty
                ? [:]
                : CaseInsensitiveConfigMap.merging(
                    result.speechSubstitution ?? [:],
                    namespacedSubs
                )
        }

        if let voices = yapper.voices {
            if let v = voices.autoAssign { result.autoAssignVoices = v }
            if let v = voices.narrator { result.narratorVoice = v }
            if let v = voices.intro { result.introVoice = v }
            if let characters = voices.characters {
                result.characterVoices = characters.isEmpty
                    ? [:]
                    : CaseInsensitiveConfigMap.merging(
                        result.characterVoices ?? [:],
                        characters
                    )
            }
        }

        if let pacing = yapper.pacing {
            if let v = pacing.dialogueSpeed { result.dialogueSpeed = v }
            if let v = pacing.stageDirectionSpeed { result.stageDirectionSpeed = v }
            if let v = pacing.gapAfterDialogue { result.gapAfterDialogue = v }
            if let v = pacing.gapAfterStageDirection { result.gapAfterStageDirection = v }
            if let v = pacing.gapAfterScene { result.gapAfterScene = v }
        }

        if let v = yapper.performance?.threads {
            result.threads = v
        }

        applyCanonicalScriptConfig(yapper, to: &result)

        if let overrideFAL = override.yapper?.remoteSpeech?.fal {
            var remote = result.yapper?.remoteSpeech ?? RemoteSpeechConfig()
            var merged = remote.fal ?? FALRemoteConfig()
            if let v = overrideFAL.apiKey { merged.apiKey = v }
            if let v = overrideFAL.accountAPIKey { merged.accountAPIKey = v }
            remote.fal = merged
            var yapperConfig = result.yapper ?? YapperConfig()
            yapperConfig.remoteSpeech = remote
            result.yapper = yapperConfig
        }
        if let overrideOpenAI = override.yapper?.remoteSpeech?.openai {
            var remote = result.yapper?.remoteSpeech ?? RemoteSpeechConfig()
            var merged = remote.openai ?? OpenAIRemoteConfig()
            if let v = overrideOpenAI.apiKey { merged.apiKey = v }
            if let v = overrideOpenAI.adminAPIKey { merged.adminAPIKey = v }
            remote.openai = merged
            var yapperConfig = result.yapper ?? YapperConfig()
            yapperConfig.remoteSpeech = remote
            result.yapper = yapperConfig
        }
    }

    private static func mergeCanonicalScript(
        _ lower: CanonicalScriptYAMLConfig?,
        _ upper: CanonicalScriptYAMLConfig
    ) -> CanonicalScriptYAMLConfig {
        var voices = lower?.voices ?? [:]
        if let upperVoices = upper.voices {
            if upperVoices.isEmpty {
                voices = [:]
            } else {
                for (id, voiceConfig) in upperVoices {
                    voices[id] = mergeScriptVoice(voices[id], voiceConfig)
                }
            }
        }
        var pacing = lower?.pacing ?? YapperPacingConfig()
        if let upperPacing = upper.pacing {
            if let value = upperPacing.dialogueSpeed { pacing.dialogueSpeed = value }
            if let value = upperPacing.stageDirectionSpeed { pacing.stageDirectionSpeed = value }
            if let value = upperPacing.gapAfterDialogue { pacing.gapAfterDialogue = value }
            if let value = upperPacing.gapAfterStageDirection { pacing.gapAfterStageDirection = value }
            if let value = upperPacing.gapAfterScene { pacing.gapAfterScene = value }
        }
        return CanonicalScriptYAMLConfig(voices: voices, pacing: pacing)
    }

    private static func mergeScriptVoice(
        _ lower: ScriptVoiceYAMLConfig?,
        _ upper: ScriptVoiceYAMLConfig
    ) -> ScriptVoiceYAMLConfig {
        var characters = lower?.characters ?? [:]
        if let upperCharacters = upper.characters {
            characters = upperCharacters.isEmpty
                ? [:]
                : CaseInsensitiveConfigMap.merging(characters, upperCharacters)
        }
        return ScriptVoiceYAMLConfig(
            autoAssign: upper.autoAssign ?? lower?.autoAssign,
            pool: upper.pool ?? lower?.pool,
            narrator: upper.narrator ?? lower?.narrator,
            intro: upper.intro ?? lower?.intro,
            characters: characters
        )
    }

    private static func applyCanonicalScriptConfig(_ yapper: YapperConfig, to result: inout ScriptConfig) {
        if let voices = yapper.script?.voices?[SpeechEngineID.yapper.rawValue] {
            if let value = voices.autoAssign { result.autoAssignVoices = value }
            if let value = voices.narrator { result.narratorVoice = value }
            if let value = voices.intro { result.introVoice = value }
            if let characters = voices.characters {
                result.characterVoices = characters.isEmpty
                    ? [:]
                    : CaseInsensitiveConfigMap.merging(
                        result.characterVoices ?? [:],
                        characters
                    )
            }
        }
        if let pacing = yapper.script?.pacing {
            if let value = pacing.dialogueSpeed { result.dialogueSpeed = value }
            if let value = pacing.stageDirectionSpeed { result.stageDirectionSpeed = value }
            if let value = pacing.gapAfterDialogue { result.gapAfterDialogue = value }
            if let value = pacing.gapAfterStageDirection { result.gapAfterStageDirection = value }
            if let value = pacing.gapAfterScene { result.gapAfterScene = value }
        }
        if let concurrency = yapper.engines?[SpeechEngineID.yapper.rawValue]?.concurrency {
            result.threads = concurrency
        }
    }

    private static func emitDeprecationWarnings(config: ScriptConfig, path: String) {
        for warning in config.legacyYapperKeyWarnings() {
            print("WARNING: deprecated Yapper config key '\(warning.legacy)' in \(path); use '\(warning.replacement)' instead.")
        }
    }

    private func legacyYapperKeyWarnings() -> [(legacy: String, replacement: String)] {
        var warnings: [(legacy: String, replacement: String)] = []
        if speechSubstitution != nil {
            warnings.append(("speech-substitution", "yapper.speech-substitution"))
        }
        if autoAssignVoices != nil {
            warnings.append(("auto-assign-voices", "yapper.script.voices.yapper.auto-assign"))
        }
        if narratorVoice != nil {
            warnings.append(("narrator-voice", "yapper.script.voices.yapper.narrator"))
        }
        if introVoice != nil {
            warnings.append(("intro-voice", "yapper.script.voices.yapper.intro"))
        }
        if characterVoices != nil {
            warnings.append(("character-voices", "yapper.script.voices.yapper.characters"))
        }
        if dialogueSpeed != nil {
            warnings.append(("dialogue-speed", "yapper.script.pacing.dialogue-speed"))
        }
        if stageDirectionSpeed != nil {
            warnings.append(("stage-direction-speed", "yapper.script.pacing.stage-direction-speed"))
        }
        if gapAfterDialogue != nil {
            warnings.append(("gap-after-dialogue", "yapper.script.pacing.gap-after-dialogue"))
        }
        if gapAfterStageDirection != nil {
            warnings.append(("gap-after-stage-direction", "yapper.script.pacing.gap-after-stage-direction"))
        }
        if gapAfterScene != nil {
            warnings.append(("gap-after-scene", "yapper.script.pacing.gap-after-scene"))
        }
        if threads != nil {
            warnings.append(("threads", "yapper.engines.yapper.concurrency"))
        }
        if renderStageDirections != nil {
            warnings.append(("render-stage-directions", "render.stage-directions"))
        }
        if renderIntro != nil {
            warnings.append(("render-intro", "render.frontmatter"))
        }
        if renderFootnotes != nil {
            warnings.append(("render-footnotes", "render.footnotes"))
        }
        if yapper?.voices != nil {
            warnings.append(("yapper.voices", "yapper.script.voices.yapper"))
        }
        if yapper?.pacing != nil {
            warnings.append(("yapper.pacing", "yapper.script.pacing"))
        }
        if yapper?.performance?.threads != nil {
            warnings.append(("yapper.performance.threads", "yapper.engines.yapper.concurrency"))
        }
        if yapper?.remoteSpeech?.fal?.apiKey != nil {
            warnings.append((
                "yapper.remote-speech.fal.api-key",
                "yapper.engines.fal.credentials.generation.literal or .helper"
            ))
        }
        if yapper?.remoteSpeech?.fal?.accountAPIKey != nil {
            warnings.append((
                "yapper.remote-speech.fal.account-api-key",
                "yapper.engines.fal.credentials.account.literal or .helper"
            ))
        }
        if yapper?.remoteSpeech?.openai?.apiKey != nil {
            warnings.append((
                "yapper.remote-speech.openai.api-key",
                "yapper.engines.openai.credentials.generation.literal or .helper"
            ))
        }
        if yapper?.remoteSpeech?.openai?.adminAPIKey != nil {
            warnings.append((
                "yapper.remote-speech.openai.admin-api-key",
                "yapper.engines.openai.credentials.admin.literal or .helper"
            ))
        }
        return warnings
    }

    private func validateCanonicalCredentials(path: String) throws {
        for (engineID, engine) in yapper?.engines ?? [:] {
            try engine.credentials?.generation?.validate(
                path: "\(path): yapper.engines.\(engineID).credentials.generation"
            )
            try engine.credentials?.account?.validate(
                path: "\(path): yapper.engines.\(engineID).credentials.account"
            )
            try engine.credentials?.admin?.validate(
                path: "\(path): yapper.engines.\(engineID).credentials.admin"
            )
        }
    }

    private mutating func setCredentialBaseDirectory(_ directory: URL) {
        guard var engines = yapper?.engines else { return }
        for engineID in engines.keys {
            guard var credentials = engines[engineID]?.credentials else { continue }
            if credentials.generation != nil {
                credentials.generation?.baseDirectory = directory
            }
            if credentials.account != nil {
                credentials.account?.baseDirectory = directory
            }
            if credentials.admin != nil {
                credentials.admin?.baseDirectory = directory
            }
            engines[engineID]?.credentials = credentials
        }
        yapper?.engines = engines
    }

    /// Apply speech substitutions to text.
    ///
    /// If a replacement value is IPA (wrapped in `/slashes/`), it is
    /// converted to MisakiSwift's inline IPA format: `[original](/phonemes/)`.
    /// Plain text replacements are applied directly.
    static func applySubstitutions(
        _ text: String,
        substitutions: [String: String],
        supportsIPA: Bool = true
    ) -> String {
        ProsePreprocessor.preprocess(
            text,
            substitutions: substitutions,
            supportsIPA: supportsIPA
        ).text
    }
}

private func mergeOptionalConfigMaps<Value>(
    _ lower: [String: Value]?,
    _ upper: [String: Value]?
) -> [String: Value]? {
    guard lower != nil || upper != nil else { return nil }
    if let upper, upper.isEmpty { return [:] }
    return CaseInsensitiveConfigMap.merging(lower ?? [:], upper ?? [:])
}

enum ScriptError: Error, CustomStringConvertible {
    case invalidConfig(path: String, message: String)
    case noScriptPatterns(path: String)

    var description: String {
        switch self {
        case .invalidConfig(let path, let message):
            return "Invalid script config at \(path): \(message)"
        case .noScriptPatterns(let path):
            return "No script patterns found in \(path) — treating as prose"
        }
    }
}
