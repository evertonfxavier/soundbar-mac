import Foundation

/// A release newer than the running app.
struct UpdateInfo: Equatable {
    let version: AppVersion
    /// The release page on GitHub, with the notes.
    let pageURL: URL
    /// The disk image, when the release has one.
    let downloadURL: URL?
}

enum UpdateError: Error, Equatable {
    case http(Int)
    case malformed
}

/// Asks GitHub whether the latest release is newer than the running version. It only reads the public API
/// (no login) and never downloads or runs anything: the result is a pair of links the user opens.
struct UpdateChecker {
    static let repository = "evertonfxavier/soundbar-mac"

    /// Sends a request and returns the body of a successful answer.
    typealias Fetch = @Sendable (URLRequest) async throws -> Data

    let current: AppVersion
    let fetch: Fetch

    static func live(userAgent: String) -> Fetch {
        { request in
            var request = request
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError.http(http.statusCode)
            }
            return data
        }
    }

    /// The newest release if it is newer than `current`; nil when the app is up to date.
    func newerRelease() async throws -> UpdateInfo? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return try Self.parse(try await fetch(request), newerThan: current)
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    static func parse(_ data: Data, newerThan current: AppVersion) throws -> UpdateInfo? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { throw UpdateError.malformed }
        guard release.draft != true, release.prerelease != true,
            let version = AppVersion(release.tag_name), version > current,
            let page = trusted(release.html_url)
        else { return nil }
        let dmg = release.assets?.first { $0.name.hasSuffix(".dmg") }.flatMap { trusted($0.browser_download_url) }
        return UpdateInfo(version: version, pageURL: page, downloadURL: dmg)
    }

    /// The links come from the network, and the app opens them in the browser: only links to this repository's own
    /// pages and downloads on GitHub are accepted.
    static func trusted(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host == "github.com",
            url.path.hasPrefix("/\(repository)/")
        else { return nil }
        return url
    }
}
