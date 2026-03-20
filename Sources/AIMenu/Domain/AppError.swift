import Foundation

enum AppError: LocalizedError, Sendable {
    case fileNotFound(_ message: String, path: String? = nil)
    case invalidData(_ message: String, detail: String? = nil)
    case io(_ message: String, underlying: (any Error)? = nil)
    case network(_ message: String, statusCode: Int? = nil, underlying: (any Error)? = nil)
    case unauthorized(_ message: String, detail: String? = nil)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message, let path):
            if let path { return "\(message) [\(path)]" }
            return message
        case .invalidData(let message, let detail):
            if let detail { return "\(message) — \(detail)" }
            return message
        case .io(let message, let underlying):
            if let underlying { return "\(message) (\(underlying.localizedDescription))" }
            return message
        case .network(let message, let statusCode, let underlying):
            var result = message
            if let statusCode { result += " [HTTP \(statusCode)]" }
            if let underlying { result += " (\(underlying.localizedDescription))" }
            return result
        case .unauthorized(let message, let detail):
            if let detail { return "\(message) — \(detail)" }
            return message
        }
    }
}
