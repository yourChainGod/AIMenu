import Foundation

enum ProxyRuntimeLimits {
    // Hard limits to prevent unbounded buffering from exhausting app memory.
    static let maxInboundRequestBytes = 8 * 1024 * 1024
    static let maxUpstreamResponseBytes = 12 * 1024 * 1024

    static func limitDescription(for bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Centralized Network Configuration

enum NetworkConfig {
    /// Upstream API request timeout (ChatGPT responses endpoint).
    static let upstreamTimeoutSeconds: TimeInterval = 180
    /// Port-check / lsof command timeout.
    static let portCheckTimeoutSeconds: TimeInterval = 1.5
    /// Grace period after SIGTERM before escalating to SIGKILL.
    static let processKillGraceSeconds: TimeInterval = 1.2
    /// Quick health-check request timeout (e.g. cursor2api /health).
    static let healthCheckTimeoutSeconds: TimeInterval = 1.2
    /// Max retry iterations when polling for a service to become ready.
    static let serviceReadyMaxRetries = 20
    /// Cloudflared quick-tunnel URL polling interval.
    static let cloudflaredRetryIntervalMs: UInt64 = 300
    /// Process termination polling interval.
    static let processTermPollIntervalMs: UInt64 = 100
    /// Initial receive buffer reservation for upstream responses.
    static let upstreamResponseBufferHint = 64 * 1024
    /// Per-connection receive chunk size for the built-in HTTP server.
    static let httpServerReceiveChunkSize = 64 * 1024
}
