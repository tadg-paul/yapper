// ABOUTME: Fetches optional account, pricing, usage, and cost diagnostics for remote speech engines.
// ABOUTME: Treats reporting failures as contextual diagnostics rather than synthesis blockers.

import Foundation

public struct RemoteSpeechDiagnostic: Codable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct FALAccountReporter: Sendable {
    private let baseURL: URL
    private let credential: ResolvedSpeechCredential
    private let httpClient: SpeechHTTPClient
    private let timeout: TimeInterval

    public init(
        baseURL: URL,
        credential: ResolvedSpeechCredential,
        httpClient: SpeechHTTPClient = URLSessionSpeechHTTPClient(),
        timeout: TimeInterval = 20
    ) {
        self.baseURL = baseURL
        self.credential = credential
        self.httpClient = httpClient
        self.timeout = timeout
    }

    public func dryRunDiagnostics(endpoint: String, characterCount: Int) async -> [RemoteSpeechDiagnostic] {
        var diagnostics: [RemoteSpeechDiagnostic] = []
        let pricing = await diagnosticResult("FAL pricing") {
            try await pricingDiagnostic(endpoint: endpoint, characterCount: characterCount)
        }
        diagnostics.append(pricing)
        let balance = await diagnosticResult("FAL account balance") {
            try await balanceDiagnostic(label: "FAL account balance")
        }
        diagnostics.append(balance)
        return diagnostics
    }

    public func normalStartDiagnostics() async -> [RemoteSpeechDiagnostic] {
        [await diagnosticResult("FAL starting balance") {
            try await balanceDiagnostic(label: "FAL starting balance")
        }]
    }

    public func normalEndDiagnostics(endpoint: String) async -> [RemoteSpeechDiagnostic] {
        [
            await diagnosticResult("FAL latest billing event") {
                try await latestBillingEventDiagnostic(endpoint: endpoint)
            },
            await diagnosticResult("FAL ending balance") {
                try await balanceDiagnostic(label: "FAL ending balance")
            }
        ]
    }

    private func pricingDiagnostic(endpoint: String, characterCount: Int) async throws -> RemoteSpeechDiagnostic {
        let data = try await get(path: "/v1/models/pricing", queryItems: [
            URLQueryItem(name: "endpoint_id", value: endpoint)
        ])
        let decoded = try JSONDecoder().decode(FALPricingResponse.self, from: data)
        guard let price = decoded.prices.first(where: { $0.endpointID == endpoint }) ?? decoded.prices.first else {
            return RemoteSpeechDiagnostic(label: "FAL pricing", value: "unavailable")
        }
        let unit = price.unit ?? "unit"
        let currency = price.currency ?? "usd"
        if unit.lowercased().contains("1000") && unit.lowercased().contains("character") {
            let estimate = Double(characterCount) / 1000.0 * price.unitPrice
            return RemoteSpeechDiagnostic(
                label: "FAL pricing",
                value: "\(price.unitPrice) \(currency)/\(unit), estimated \(String(format: "%.4f", estimate)) \(currency)"
            )
        }
        return RemoteSpeechDiagnostic(label: "FAL pricing", value: "\(price.unitPrice) \(currency)/\(unit), estimate unavailable")
    }

    private func balanceDiagnostic(label: String) async throws -> RemoteSpeechDiagnostic {
        let data = try await get(path: "/v1/account/billing", queryItems: [])
        let decoded = try JSONDecoder().decode(FALBillingResponse.self, from: data)
        guard let balance = decoded.credits?.currentBalance else {
            if decoded.username != nil {
                return RemoteSpeechDiagnostic(label: label, value: "authenticated, balance unavailable")
            }
            return RemoteSpeechDiagnostic(label: label, value: "unavailable")
        }
        return RemoteSpeechDiagnostic(label: label, value: "\(balance) \(decoded.credits?.currency ?? "usd")")
    }

    private func latestBillingEventDiagnostic(endpoint: String) async throws -> RemoteSpeechDiagnostic {
        let data = try await get(path: "/v1/models/billing-events", queryItems: [
            URLQueryItem(name: "endpoint_id", value: endpoint),
            URLQueryItem(name: "limit", value: "1")
        ])
        let decoded = try JSONDecoder().decode(FALBillingEventsResponse.self, from: data)
        guard let event = decoded.events.first else {
            return RemoteSpeechDiagnostic(label: "FAL latest billing event", value: "unavailable")
        }
        let endpointValue = event.endpointID ?? endpoint
        let units = event.outputUnits.map { String($0) } ?? "unknown"
        let timestamp = event.createdAt ?? event.timestamp ?? "unknown time"
        return RemoteSpeechDiagnostic(
            label: "FAL latest billing event",
            value: "\(endpointValue), units \(units), \(timestamp)"
        )
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.addValue("Key \(credential.value)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await httpClient.data(for: request, timeout: timeout)
        guard (200..<300).contains(response.statusCode) else {
            let body = safeReportingBody(data)
            let adminHint = response.statusCode == 403 ? " (check whether the key has Admin scope)" : ""
            throw SpeechProviderError.httpFailure(
                provider: "FAL",
                context: "\(path)\(adminHint)",
                status: response.statusCode,
                body: body
            )
        }
        return data
    }
}

public struct OpenAIAdminReporter: Sendable {
    private let baseURL: URL
    private let credential: ResolvedSpeechCredential
    private let httpClient: SpeechHTTPClient
    private let timeout: TimeInterval

    public init(
        baseURL: URL,
        credential: ResolvedSpeechCredential,
        httpClient: SpeechHTTPClient = URLSessionSpeechHTTPClient(),
        timeout: TimeInterval = 20
    ) {
        self.baseURL = baseURL
        self.credential = credential
        self.httpClient = httpClient
        self.timeout = timeout
    }

    public func usageAndCostDiagnostics() async -> [RemoteSpeechDiagnostic] {
        [
            await diagnosticResult("OpenAI audio speech usage") {
                try await usageDiagnostic()
            },
            await diagnosticResult("OpenAI organization costs") {
                try await costsDiagnostic()
            }
        ]
    }

    private func usageDiagnostic() async throws -> RemoteSpeechDiagnostic {
        let data = try await get(path: "/organization/usage/audio_speeches")
        let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
        let totals = decoded.data.flatMap(\.results).reduce((characters: 0, requests: 0)) { partial, result in
            (
                characters: partial.characters + (result.characters ?? 0),
                requests: partial.requests + (result.numModelRequests ?? 0)
            )
        }
        return RemoteSpeechDiagnostic(
            label: "OpenAI audio speech usage",
            value: "last 24h characters \(totals.characters), requests \(totals.requests)"
        )
    }

    private func costsDiagnostic() async throws -> RemoteSpeechDiagnostic {
        let data = try await get(path: "/organization/costs")
        let decoded = try JSONDecoder().decode(OpenAICostsResponse.self, from: data)
        let totals: [String: Double] = decoded.data.flatMap(\.results).reduce(into: [:]) { partial, result in
            guard let amount = result.amount else { return }
            partial[amount.currency ?? "usd", default: 0] += amount.value ?? 0
        }
        guard !totals.isEmpty else {
            return RemoteSpeechDiagnostic(label: "OpenAI organization costs", value: "unavailable")
        }
        let value = totals.sorted { $0.key < $1.key }
            .map { "\(String(format: "%.4f", $0.value)) \($0.key)" }
            .joined(separator: ", ")
        return RemoteSpeechDiagnostic(label: "OpenAI organization costs", value: "last 24h \(value)")
    }

    private func get(path: String) async throws -> Data {
        let end = Int(Date().timeIntervalSince1970)
        let start = end - 86_400
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(start)),
            URLQueryItem(name: "end_time", value: String(end)),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(credential.value)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await httpClient.data(for: request, timeout: timeout)
        guard (200..<300).contains(response.statusCode) else {
            throw SpeechProviderError.httpFailure(
                provider: "OpenAI",
                context: path,
                status: response.statusCode,
                body: safeReportingBody(data)
            )
        }
        return data
    }
}

private func diagnosticResult(_ label: String, operation: () async throws -> RemoteSpeechDiagnostic) async -> RemoteSpeechDiagnostic {
    do {
        return try await operation()
    } catch {
        return RemoteSpeechDiagnostic(label: label, value: "unavailable (\(error))")
    }
}

private struct FALPricingResponse: Decodable {
    let prices: [FALPrice]
}

private struct FALPrice: Decodable {
    let endpointID: String?
    let unitPrice: Double
    let unit: String?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case endpointID = "endpoint_id"
        case unitPrice = "unit_price"
        case unit, currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpointID = try container.decodeIfPresent(String.self, forKey: .endpointID)
        unitPrice = try container.decode(FlexibleDouble.self, forKey: .unitPrice).value
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
}

private struct FALBillingResponse: Decodable {
    struct Credits: Decodable {
        let currentBalance: Double?
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case currentBalance = "current_balance"
            case currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            currentBalance = try container.decodeIfPresent(FlexibleDouble.self, forKey: .currentBalance)?.value
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
        }
    }

    let credits: Credits?
    let username: String?
}

private struct FALBillingEventsResponse: Decodable {
    let events: [FALBillingEvent]

    enum CodingKeys: String, CodingKey {
        case events
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([FALBillingEvent].self, forKey: .events)
            ?? container.decodeIfPresent([FALBillingEvent].self, forKey: .data)
            ?? []
    }
}

private struct FALBillingEvent: Decodable {
    let endpointID: String?
    let outputUnits: Double?
    let createdAt: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case endpointID = "endpoint_id"
        case outputUnits = "output_units"
        case createdAt = "created_at"
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpointID = try container.decodeIfPresent(String.self, forKey: .endpointID)
        outputUnits = try container.decodeIfPresent(FlexibleDouble.self, forKey: .outputUnits)?.value
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

private struct OpenAIUsageResponse: Decodable {
    let data: [OpenAIUsageBucket]
}

private struct OpenAIUsageBucket: Decodable {
    let results: [OpenAIUsageResult]
}

private struct OpenAIUsageResult: Decodable {
    let characters: Int?
    let numModelRequests: Int?

    enum CodingKeys: String, CodingKey {
        case characters
        case numModelRequests = "num_model_requests"
    }
}

private struct OpenAICostsResponse: Decodable {
    let data: [OpenAICostBucket]
}

private struct OpenAICostBucket: Decodable {
    let results: [OpenAICostResult]
}

private struct OpenAICostResult: Decodable {
    struct Amount: Decodable {
        let currency: String?
        let value: Double?

        enum CodingKeys: String, CodingKey {
            case currency, value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            value = try container.decodeIfPresent(FlexibleDouble.self, forKey: .value)?.value
        }
    }

    let amount: Amount?
}

private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
            return
        }
        let stringValue = try container.decode(String.self)
        guard let doubleValue = Double(stringValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected numeric value or numeric string"
            )
        }
        value = doubleValue
    }
}

private func safeReportingBody(_ data: Data) -> String {
    guard let text = String(data: data, encoding: .utf8) else { return "" }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 500 else { return trimmed }
    return String(trimmed.prefix(500))
}
