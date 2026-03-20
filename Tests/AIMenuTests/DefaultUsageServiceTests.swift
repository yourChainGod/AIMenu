import XCTest
@testable import AIMenu

final class DefaultUsageServiceTests: XCTestCase {
    func testResolveUsageURLsForBackendBaseOriginKeepsUniqueCandidateOrder() {
        let urls = DefaultUsageService.resolveUsageURLs(baseOrigin: "https://example.com/backend-api")

        XCTAssertEqual(
            urls,
            [
                "https://example.com/backend-api/wham/usage",
                "https://example.com/api/codex/usage",
                "https://chatgpt.com/backend-api/wham/usage",
                "https://chatgpt.com/api/codex/usage"
            ]
        )
    }

    func testResolveUsageURLsForPlainBaseOriginAddsBackendWhamAndCodexFallbacks() {
        let urls = DefaultUsageService.resolveUsageURLs(baseOrigin: "https://example.com/proxy/")

        XCTAssertEqual(
            urls,
            [
                "https://example.com/proxy/backend-api/wham/usage",
                "https://example.com/proxy/wham/usage",
                "https://example.com/proxy/api/codex/usage",
                "https://chatgpt.com/backend-api/wham/usage",
                "https://chatgpt.com/api/codex/usage"
            ]
        )
    }
}
