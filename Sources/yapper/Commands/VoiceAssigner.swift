// ABOUTME: Assigns distinct Kokoro voices to script characters.
// ABOUTME: Supports explicit voice names, filter shorthands (e.g. "bf"), and auto-assignment.

import Foundation
import YapperKit

/// Assigns voices to characters based on config and the available voice registry.
struct VoiceAssigner {

    /// Assign a voice to each character. Returns a dictionary of character name → Voice.
    ///
    /// Precedence per character:
    ///   1. Explicit voice name from config (e.g. "bm_daniel")
    ///   2. Filter shorthand from config (e.g. "bf" → random British female)
    ///   3. Auto-assign from remaining pool
    static func assign(
        characters: [String],
        config: ScriptConfig?,
        registry: VoiceRegistry,
        narratorVoiceName: String? = nil
    ) -> (characterVoices: [String: Voice], narratorVoice: Voice) {
        let configVoices = config?.characterVoices ?? [:]
        var assigned: [String: Voice] = [:]
        var usedVoiceNames: Set<String> = []

        // Reserve narrator voice — supports explicit name or filter shorthand
        let narratorSpec = narratorVoiceName ?? config?.narratorVoice
        let narrator: Voice
        if let spec = narratorSpec {
            if spec.contains("_"), let v = registry.voices.first(where: { $0.name == spec }) {
                // Explicit voice name
                narrator = v
            } else if let filter = parseFilter(spec),
                      let v = registry.list(filter: filter).first {
                // Filter shorthand (e.g. "bf")
                narrator = v
            } else {
                // Fallback if spec matches nothing
                narrator = registry.voices.first(where: { $0.name == "af_heart" }) ?? registry.voices[0]
            }
        } else {
            narrator = registry.voices.first(where: { $0.name == "af_heart" }) ?? registry.voices[0]
        }
        usedVoiceNames.insert(narrator.name)

        // Phase 1: explicit voice names
        for char in characters {
            guard let voiceSpec = CaseInsensitiveConfigMap.value(
                for: char,
                in: configVoices
            ) else { continue }
            if voiceSpec.lowercased() == "auto" { continue }

            // Check if it's a full voice name (contains underscore)
            if voiceSpec.contains("_") {
                if let v = registry.voices.first(where: { $0.name == voiceSpec }) {
                    assigned[char] = v
                    usedVoiceNames.insert(v.name)
                }
            }
        }

        // Phase 2: filter shorthands (e.g. "bf", "am")
        for char in characters where assigned[char] == nil {
            guard let voiceSpec = CaseInsensitiveConfigMap.value(
                for: char,
                in: configVoices
            ) else { continue }
            if voiceSpec.lowercased() == "auto" { continue }
            if voiceSpec.contains("_") { continue } // Already handled in phase 1

            // Parse as filter: first char = accent, second char = gender (optional)
            let filter = parseFilter(voiceSpec)
            let candidates = registry.list(filter: filter)
                .filter { !usedVoiceNames.contains($0.name) }
            if let pick = candidates.first {
                assigned[char] = pick
                usedVoiceNames.insert(pick.name)
            } else if let fallback = registry.list(filter: filter).first {
                // All matching voices used — reuse one
                assigned[char] = fallback
                usedVoiceNames.insert(fallback.name)
            }
        }

        // Phase 3: auto-assign remaining
        let unassigned = characters.filter { assigned[$0] == nil }
        let pool = registry.voices.filter { !usedVoiceNames.contains($0.name) }
        for (i, char) in unassigned.enumerated() {
            if i < pool.count {
                assigned[char] = pool[i]
                usedVoiceNames.insert(pool[i].name)
            } else {
                // Pool exhausted — wrap around
                let wrapped = pool.isEmpty ? registry.voices[i % registry.voices.count] : pool[i % pool.count]
                assigned[char] = wrapped
            }
        }

        return (assigned, narrator)
    }

    /// Parse a filter shorthand like "bf" → VoiceFilter(accent: .british, gender: .female)
    static func parseFilterPublic(_ spec: String) -> VoiceFilter? {
        return parseFilter(spec)
    }

    /// Parse a filter shorthand like "bf" → VoiceFilter(accent: .british, gender: .female)
    private static func parseFilter(_ spec: String) -> VoiceFilter? {
        guard !spec.isEmpty else { return nil }
        let lower = spec.lowercased()
        let accent = Accent(rawValue: String(lower.prefix(1)))
        let gender: Gender?
        if lower.count > 1 {
            gender = Gender(rawValue: String(lower.dropFirst().prefix(1)))
        } else {
            gender = nil
        }
        return VoiceFilter(accent: accent, gender: gender)
    }
}
