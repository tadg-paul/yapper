// ABOUTME: Defines config-format-neutral, engine-extensible speech settings.
// ABOUTME: Supports deterministic layer merging without importing YAML into YapperKit.

import Foundation

public indirect enum EngineOptionValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case sequence([EngineOptionValue])
    case map([String: EngineOptionValue])

    public func merging(_ upper: EngineOptionValue) -> EngineOptionValue {
        guard case .map(let lowerMap) = self, case .map(let upperMap) = upper else {
            return upper
        }
        var result = lowerMap
        for (key, upperValue) in upperMap {
            if let lowerValue = result[key] {
                result[key] = lowerValue.merging(upperValue)
            } else {
                result[key] = upperValue
            }
        }
        return .map(result)
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values: [String: EngineOptionValue] = [:]
            for key in container.allKeys {
                values[key.stringValue] = try container.decode(EngineOptionValue.self, forKey: key)
            }
            self = .map(values)
            return
        }
        if var container = try? decoder.unkeyedContainer() {
            var values: [EngineOptionValue] = []
            while !container.isAtEnd {
                values.append(try container.decode(EngineOptionValue.self))
            }
            self = .sequence(values)
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .sequence(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .map(let values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values {
                try container.encode(value, forKey: DynamicCodingKey(key))
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

public enum SpeechConfigurationError: Error, Equatable, CustomStringConvertible {
    case missingOption(String)
    case invalidOption(path: String, expected: String)
    case decoderAlreadyRegistered(SpeechEngineID)
    case decoderNotRegistered(SpeechEngineID)
    case settingsTypeMismatch(engineID: SpeechEngineID, expected: String)

    public var description: String {
        switch self {
        case .missingOption(let path):
            return "Missing required engine setting '\(path)'."
        case .invalidOption(let path, let expected):
            return "Engine setting '\(path)' must be \(expected)."
        case .decoderAlreadyRegistered(let id):
            return "A settings decoder is already registered for engine '\(id)'."
        case .decoderNotRegistered(let id):
            return "No settings decoder is registered for engine '\(id)'."
        case .settingsTypeMismatch(let id, let expected):
            return "Settings for engine '\(id)' are not of expected type \(expected)."
        }
    }
}

public extension Dictionary where Key == String, Value == EngineOptionValue {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key] else {
            throw SpeechConfigurationError.missingOption(key)
        }
        guard case .string(let string) = value else {
            throw SpeechConfigurationError.invalidOption(path: key, expected: "a string")
        }
        return string
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let value = self[key] else {
            throw SpeechConfigurationError.missingOption(key)
        }
        guard case .integer(let integer) = value else {
            throw SpeechConfigurationError.invalidOption(path: key, expected: "an integer")
        }
        return integer
    }
}

public struct SpeechEngineConfiguration: Codable, Equatable, Sendable {
    public let voice: SpeechVoiceID?
    public let speed: Double?
    public let concurrency: Int?
    public let options: [String: EngineOptionValue]

    public init(
        voice: SpeechVoiceID? = nil,
        speed: Double? = nil,
        concurrency: Int? = nil,
        options: [String: EngineOptionValue] = [:]
    ) {
        self.voice = voice
        self.speed = speed
        self.concurrency = concurrency
        self.options = options
    }

    public func merging(_ upper: SpeechEngineConfiguration) -> SpeechEngineConfiguration {
        let lowerOptions = EngineOptionValue.map(options)
        let upperOptions = EngineOptionValue.map(upper.options)
        let mergedOptions: [String: EngineOptionValue]
        if case .map(let values) = lowerOptions.merging(upperOptions) {
            mergedOptions = values
        } else {
            mergedOptions = upper.options
        }
        return SpeechEngineConfiguration(
            voice: upper.voice ?? voice,
            speed: upper.speed ?? speed,
            concurrency: upper.concurrency ?? concurrency,
            options: mergedOptions
        )
    }
}

public struct SpeechConfiguration: Codable, Equatable, Sendable {
    public let selectedEngineID: SpeechEngineID?
    public let engines: [SpeechEngineID: SpeechEngineConfiguration]

    public init(
        selectedEngineID: SpeechEngineID? = nil,
        engines: [SpeechEngineID: SpeechEngineConfiguration] = [:]
    ) {
        self.selectedEngineID = selectedEngineID
        self.engines = engines
    }

    public func merging(_ upper: SpeechConfiguration) -> SpeechConfiguration {
        var mergedEngines = engines
        for (id, upperSettings) in upper.engines {
            if let lowerSettings = mergedEngines[id] {
                mergedEngines[id] = lowerSettings.merging(upperSettings)
            } else {
                mergedEngines[id] = upperSettings
            }
        }
        return SpeechConfiguration(
            selectedEngineID: upper.selectedEngineID ?? selectedEngineID,
            engines: mergedEngines
        )
    }
}

private protocol SpeechEngineSettingsBox: Sendable {
    func value<Settings>(as type: Settings.Type) -> Settings?
}

private struct ConcreteSpeechEngineSettingsBox<Settings: Sendable>: SpeechEngineSettingsBox {
    let settings: Settings

    func value<Value>(as type: Value.Type) -> Value? {
        settings as? Value
    }
}

private struct AnySpeechEngineSettings: Sendable {
    private let box: any SpeechEngineSettingsBox

    init<Settings: Sendable>(_ settings: Settings) {
        self.box = ConcreteSpeechEngineSettingsBox(settings: settings)
    }

    func value<Settings>(as type: Settings.Type) -> Settings? {
        box.value(as: type)
    }
}

public struct SpeechEngineSettingsRegistry: Sendable {
    private typealias Decoder = @Sendable ([String: EngineOptionValue]) throws -> AnySpeechEngineSettings
    private var decoders: [SpeechEngineID: Decoder] = [:]

    public init() {}

    public mutating func register<Settings: Sendable>(
        engineID: SpeechEngineID,
        decoder: @escaping @Sendable ([String: EngineOptionValue]) throws -> Settings
    ) {
        precondition(decoders[engineID] == nil, "Settings decoder already registered: \(engineID)")
        decoders[engineID] = { options in
            AnySpeechEngineSettings(try decoder(options))
        }
    }

    public func decode<Settings: Sendable>(
        _ type: Settings.Type,
        engineID: SpeechEngineID,
        options: [String: EngineOptionValue]
    ) throws -> Settings {
        guard let decoder = decoders[engineID] else {
            throw SpeechConfigurationError.decoderNotRegistered(engineID)
        }
        let decoded = try decoder(options)
        guard let settings = decoded.value(as: type) else {
            throw SpeechConfigurationError.settingsTypeMismatch(
                engineID: engineID,
                expected: String(describing: type)
            )
        }
        return settings
    }
}
