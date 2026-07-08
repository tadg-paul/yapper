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

struct RemoteSpeechConfig: Decodable {
    var fal: FALRemoteConfig?
    var openai: OpenAIRemoteConfig?

    enum CodingKeys: String, CodingKey {
        case fal, openai
    }
}

struct YapperConfig: Decodable {
    var remoteSpeech: RemoteSpeechConfig?

    enum CodingKeys: String, CodingKey {
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
            return try YAMLDecoder().decode(ScriptConfig.self, from: yaml)
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
    /// `speech-substitution` inherits all other keys from the global config.
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
    /// For dictionary fields (characterVoices, speechSubstitution), entries are
    /// merged key-by-key with override winning per-key.
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

        return result
    }

    /// Apply speech substitutions to text.
    /// Apply speech substitutions to text.
    ///
    /// If a replacement value is IPA (wrapped in `/slashes/`), it is
    /// converted to MisakiSwift's inline IPA format: `[original](/phonemes/)`.
    /// Plain text replacements are applied directly.
    static func applySubstitutions(_ text: String, substitutions: [String: String]) -> String {
        guard !substitutions.isEmpty else { return text }
        var result = text
        for (find, replace) in substitutions {
            if replace.count > 2 && replace.hasPrefix("/") && replace.hasSuffix("/") {
                // IPA value: wrap as [find](/phonemes/) for G2P processing
                result = result.replacingOccurrences(of: find, with: "[\(find)](\(replace))")
            } else {
                result = result.replacingOccurrences(of: find, with: replace)
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
