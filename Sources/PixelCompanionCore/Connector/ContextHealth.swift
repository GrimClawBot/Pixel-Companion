import Foundation

/// Evidence provenance must remain visible: a backend report is not a verified
/// exact tokenizer count, and cumulative run usage is not context occupancy.
public enum ContextConfidence: String, Hashable, Sendable {
    case exact
    case providerReported
    case estimated
    case unknown

    public var label: String {
        switch self {
        case .exact: return "Exact"
        case .providerReported: return "Provider reported"
        case .estimated: return "Estimated"
        case .unknown: return "Not reported"
        }
    }
}

public enum ContextRecommendation: Int, Comparable, Sendable {
    case unavailable = 0
    case healthy = 1
    case watch = 2
    case freshSessionRecommended = 3
    case stronglyFreshSessionRecommended = 4

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .unavailable: return "Context health unavailable"
        case .healthy: return "Context looks healthy"
        case .watch: return "Watch context usage"
        case .freshSessionRecommended: return "Consider a fresh session soon"
        case .stronglyFreshSessionRecommended: return "Fresh session strongly recommended"
        }
    }
}

public struct ContextHealth: Hashable, Sendable {
    public let usedTokens: Int?
    public let windowTokens: Int?
    public let confidence: ContextConfidence
    public let fraction: Double?
    public let recommendation: ContextRecommendation
    /// Independently reported signals contributing to the recommendation.
    public let reasons: [String]

    public init(
        reportedUsed: Int?,
        reportedWindow: Int?,
        confidence: ContextConfidence,
        compactions: Int? = nil,
        taskChanged: Bool? = nil,
        recentToolOutputTokens: Int? = nil
    ) {
        let valid = reportedUsed.flatMap { used in
            reportedWindow.flatMap { window in
                used >= 0 && window > 0 && used <= window
                    ? (used, window) : nil
            }
        }
        guard let (used, window) = valid, confidence != .unknown else {
            self.usedTokens = nil
            self.windowTokens = nil
            self.confidence = .unknown
            self.fraction = nil
            self.recommendation = .unavailable
            self.reasons = []
            return
        }

        self.usedTokens = used
        self.windowTokens = window
        self.confidence = confidence
        let fraction = Double(used) / Double(window)
        self.fraction = fraction

        var recommendation: ContextRecommendation
        if fraction >= 0.95 {
            recommendation = .stronglyFreshSessionRecommended
        } else if fraction >= 0.85 {
            recommendation = .freshSessionRecommended
        } else if fraction >= 0.7 {
            recommendation = .watch
        } else {
            recommendation = .healthy
        }
        var reasons: [String] = []
        if fraction >= 0.7 {
            reasons.append("Reported context usage is \(Int(fraction * 100))% of the window")
        }
        if let compactions, compactions >= 2, fraction >= 0.6 {
            recommendation = max(recommendation, .freshSessionRecommended)
            reasons.append("Multiple compactions reported")
        }
        if taskChanged == true && fraction >= 0.6 {
            recommendation = max(recommendation, .freshSessionRecommended)
            reasons.append("A change of task was reported")
        }
        if let tokens = recentToolOutputTokens, tokens >= 0,
           Double(tokens) / Double(window) >= 0.2, fraction >= 0.7 {
            recommendation = max(recommendation, .freshSessionRecommended)
            reasons.append("Large recent tool output reported")
        }
        self.recommendation = recommendation
        self.reasons = reasons
    }
}
