// ABOUTME: YAML configuration for script reading mode.
// ABOUTME: Defines ScriptConfig parsed from script.yaml alongside the input file.

import Foundation
import Yams

/// Configuration for script-reading mode, parsed from a YAML file.
/// Nested render configuration — shared schema with First Folio.
struct RenderConfig: Decodable {
    var stageDirections: Bool?
    var frontmatter: Bool?
    var footnotes: Bool?
    var characterTable: Bool?
    var transitions: Bool?

    enum CodingKeys: String, CodingKey {
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

struct YapperConfig: Decodable {
    var speechSubstitution: [String: String]?
    var voices: YapperVoicesConfig?
    var pacing: YapperPacingConfig?
    var performance: YapperPerformanceConfig?
    var remoteSpeech: RemoteSpeechConfig?

    enum CodingKeys: String, CodingKey {
        case speechSubstitution = "speech-substitution"
        case voices, pacing, performance
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
            let config = try YAMLDecoder().decode(ScriptConfig.self, from: yaml)
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
    ) -> ScriptConfig {
        var merged = ScriptConfig()

        // 1. Global: ~/.config/yapper/yapper.yaml
        let globalPath = NSHomeDirectory() + "/.config/yapper/yapper.yaml"
        if FileManager.default.fileExists(atPath: globalPath) {
            do {
                let global = try ScriptConfig.load(from: globalPath)
                merged = merge(base: merged, override: global)
            } catch {
                fputs("Warning: failed to parse global config \(globalPath): \(error)\n", stderr)
            }
        }

        // 2. Project: ./yapper.yaml or ./script.yaml in input dir
        if let dir = inputDir {
            for name in ["yapper.yaml", "script.yaml"] {
                let path = "\(dir)/\(name)"
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        let project = try ScriptConfig.load(from: path)
                        merged = merge(base: merged, override: project)
                    } catch {
                        fputs("Warning: failed to parse config \(path): \(error)\n", stderr)
                    }
                    break
                }
            }
        }

        // 3. Explicit CLI path
        if let path = explicitPath {
            do {
                let explicit = try ScriptConfig.load(from: path)
                merged = merge(base: merged, override: explicit)
            } catch {
                fputs("Warning: failed to parse config \(path): \(error)\n", stderr)
            }
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
            var merged = result.characterVoices ?? [:]
            for (k, v) in overrideVoices { merged[k] = v }
            result.characterVoices = merged
        }
        if let overrideSubs = override.speechSubstitution {
            var merged = result.speechSubstitution ?? [:]
            for (k, v) in overrideSubs { merged[k] = v }
            result.speechSubstitution = merged
        }
        applyNamespacedYapperConfig(from: override, to: &result)

        return result
    }

    private static func applyNamespacedYapperConfig(from override: ScriptConfig, to result: inout ScriptConfig) {
        guard let yapper = override.yapper else { return }

        if let namespacedSubs = yapper.speechSubstitution {
            var merged = result.speechSubstitution ?? [:]
            for (k, v) in namespacedSubs { merged[k] = v }
            result.speechSubstitution = merged
        }

        if let voices = yapper.voices {
            if let v = voices.autoAssign { result.autoAssignVoices = v }
            if let v = voices.narrator { result.narratorVoice = v }
            if let v = voices.intro { result.introVoice = v }
            if let characters = voices.characters {
                var merged = result.characterVoices ?? [:]
                for (k, v) in characters { merged[k] = v }
                result.characterVoices = merged
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
            warnings.append(("auto-assign-voices", "yapper.voices.auto-assign"))
        }
        if narratorVoice != nil {
            warnings.append(("narrator-voice", "yapper.voices.narrator"))
        }
        if introVoice != nil {
            warnings.append(("intro-voice", "yapper.voices.intro"))
        }
        if characterVoices != nil {
            warnings.append(("character-voices", "yapper.voices.characters"))
        }
        if dialogueSpeed != nil {
            warnings.append(("dialogue-speed", "yapper.pacing.dialogue-speed"))
        }
        if stageDirectionSpeed != nil {
            warnings.append(("stage-direction-speed", "yapper.pacing.stage-direction-speed"))
        }
        if gapAfterDialogue != nil {
            warnings.append(("gap-after-dialogue", "yapper.pacing.gap-after-dialogue"))
        }
        if gapAfterStageDirection != nil {
            warnings.append(("gap-after-stage-direction", "yapper.pacing.gap-after-stage-direction"))
        }
        if gapAfterScene != nil {
            warnings.append(("gap-after-scene", "yapper.pacing.gap-after-scene"))
        }
        if threads != nil {
            warnings.append(("threads", "yapper.performance.threads"))
        }
        return warnings
    }

    /// Apply speech substitutions to text.
    ///
    /// If a replacement value is IPA (wrapped in `/slashes/`), it is
    /// converted to MisakiSwift's inline IPA format: `[original](/phonemes/)`.
    /// Plain text replacements are applied directly.
    static func applySubstitutions(_ text: String, substitutions: [String: String]) -> String {
        guard !substitutions.isEmpty else { return text }
        var result = text
        for (find, replace) in substitutions {
            guard !find.isEmpty else { continue }
            let pattern = NSRegularExpression.escapedPattern(for: find)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let searchRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: searchRange)
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let matchedText = String(result[range])
                let replacement: String
                if replace.count > 2 && replace.hasPrefix("/") && replace.hasSuffix("/") {
                    // IPA value: wrap the matched source word for G2P processing.
                    replacement = "[\(matchedText)](\(replace))"
                } else {
                    replacement = replace
                }
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }
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
