import Foundation

struct WebRemoteHTTPHandler: Sendable {
    private let bundleRoot: URL?

    init(bundleRoot: URL? = nil) {
        if let bundleRoot {
            self.bundleRoot = bundleRoot
        } else {
            self.bundleRoot = Self.resolveWebResourceRoot()
        }
    }

    /// Resolve the web/ resource directory across both SPM (Bundle.module) and Xcode (Bundle.main) builds.
    private static func resolveWebResourceRoot() -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL?.appendingPathComponent("web", isDirectory: true)
        #else
        // Xcode build: resources are inside the app bundle's Resources directory
        if let resourceURL = Bundle.main.resourceURL {
            let webDir = resourceURL.appendingPathComponent("web", isDirectory: true)
            if FileManager.default.fileExists(atPath: webDir.path) {
                return webDir
            }
            // Fallback: resources may be processed flat
            return resourceURL
        }
        return nil
        #endif
    }

    func handle(request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/api/health"):
            return HTTPResponse.json(statusCode: 200, object: [
                "ok": true,
                "service": "web-remote"
            ])

        case ("GET", "/"):
            return serveFile(relativePath: "index.html")

        case ("GET", _):
            let cleanPath = request.path.hasPrefix("/")
                ? String(request.path.dropFirst())
                : request.path
            return serveFile(relativePath: cleanPath)

        default:
            return HTTPResponse.json(statusCode: 404, object: [
                "error": "Not found"
            ])
        }
    }

    private func serveFile(relativePath: String) -> HTTPResponse {
        guard let root = bundleRoot else {
            return HTTPResponse.text(statusCode: 404, text: "Web resources not found")
        }

        // URL-decode first, then sanitize to prevent %2e%2e bypass
        let decoded = relativePath.removingPercentEncoding ?? relativePath
        let sanitized = decoded
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !sanitized.isEmpty else {
            return HTTPResponse.text(statusCode: 404, text: "Not found")
        }

        // Reject paths containing traversal sequences even after decode
        if sanitized.contains("..") {
            return HTTPResponse.text(statusCode: 403, text: "Forbidden")
        }

        // Resolve and verify the final path stays within bundleRoot (resolve symlinks first)
        let fileURL = root.appendingPathComponent(sanitized).standardizedFileURL.resolvingSymlinksInPath()
        let rootResolved = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = fileURL.path
        guard filePath == rootResolved || filePath.hasPrefix(rootResolved + "/") else {
            return HTTPResponse.text(statusCode: 403, text: "Forbidden")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HTTPResponse.text(statusCode: 404, text: "Not found")
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return HTTPResponse.text(statusCode: 500, text: "Failed to read file")
        }

        let ext = (sanitized as NSString).pathExtension.lowercased()
        let contentType = Self.mimeType(for: ext)

        return HTTPResponse(
            statusCode: 200,
            headers: [
                "Content-Type": contentType,
                "Cache-Control": "no-cache"
            ],
            body: data
        )
    }

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "html": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        default: return "application/octet-stream"
        }
    }
}
