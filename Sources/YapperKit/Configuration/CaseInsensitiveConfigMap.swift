// ABOUTME: Provides Unicode case-insensitive identity for human-authored configuration maps.
// ABOUTME: Preserves accents and the spelling from the highest-precedence configuration layer.

import Foundation

public enum CaseInsensitiveConfigMap {
    public static func identity(_ key: String) -> String {
        key.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    public static func merging<Value>(
        _ lower: [String: Value],
        _ upper: [String: Value]
    ) -> [String: Value] {
        var result = lower
        var keysByIdentity: [String: String] = [:]
        for key in lower.keys {
            keysByIdentity[identity(key)] = key
        }

        for (key, value) in upper {
            let normalized = identity(key)
            if let previousKey = keysByIdentity[normalized] {
                result.removeValue(forKey: previousKey)
            }
            result[key] = value
            keysByIdentity[normalized] = key
        }
        return result
    }

    public static func value<Value>(for key: String, in values: [String: Value]) -> Value? {
        let normalized = identity(key)
        return values.first { identity($0.key) == normalized }?.value
    }
}
