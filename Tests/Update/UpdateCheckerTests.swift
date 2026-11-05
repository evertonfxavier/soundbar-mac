import Foundation
import Testing

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    private let current = AppVersion("0.1.2")!

    private func release(
        tag: String = "v0.1.3", page: String? = nil, dmg: String? = nil, draft: Bool = false, prerelease: Bool = false,
        assets: Bool = true
    ) -> Data {
        let repo = UpdateChecker.repository
        let page = page ?? "https://github.com/\(repo)/releases/tag/\(tag)"
        let dmg = dmg ?? "https://github.com/\(repo)/releases/download/\(tag)/SoundBar-\(tag).dmg"
        let assetList =
            assets
            ? """
            [{"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/\(repo)/releases/download/\(tag)/SHA256SUMS.txt"},
             {"name": "SoundBar-\(tag).dmg", "browser_download_url": "\(dmg)"}]
            """ : "[]"
        return Data(
            """
            {"tag_name": "\(tag)", "html_url": "\(page)", "draft": \(draft), "prerelease": \(prerelease), "assets": \(assetList)}
            """.utf8)
    }

    @Test("a newer release gives its version, its page and its disk image")
    func newer() throws {
        let info = try UpdateChecker.parse(release(), newerThan: current)
        #expect(info?.version.description == "0.1.3")
        #expect(info?.pageURL.absoluteString == "https://github.com/\(UpdateChecker.repository)/releases/tag/v0.1.3")
        #expect(info?.downloadURL?.lastPathComponent == "SoundBar-v0.1.3.dmg")
    }

    @Test("the same version, or an older one, is nothing to update")
    func notNewer() throws {
        #expect(try UpdateChecker.parse(release(tag: "v0.1.2"), newerThan: current) == nil)
        #expect(try UpdateChecker.parse(release(tag: "v0.1.1"), newerThan: current) == nil)
    }

    @Test("a draft, a prerelease or a tag that is not a version is ignored")
    func ignored() throws {
        #expect(try UpdateChecker.parse(release(draft: true), newerThan: current) == nil)
        #expect(try UpdateChecker.parse(release(prerelease: true), newerThan: current) == nil)
        #expect(try UpdateChecker.parse(release(tag: "nightly"), newerThan: current) == nil)
        #expect(try UpdateChecker.parse(release(tag: "v0.2.0-rc1"), newerThan: current) == nil)
    }

    @Test("a release without a disk image still points to its page")
    func noDisk() throws {
        let info = try UpdateChecker.parse(release(assets: false), newerThan: current)
        #expect(info != nil)
        #expect(info?.downloadURL == nil)
    }

    @Test("links that are not this repository's GitHub pages are not trusted")
    func untrustedLinks() throws {
        let evil = [
            "https://evil.example/\(UpdateChecker.repository)/releases/tag/v9",
            "http://github.com/\(UpdateChecker.repository)/x",
            "https://github.com/someone-else/app/releases/tag/v9",
            "https://github.com.evil.example/\(UpdateChecker.repository)/x",
            "javascript:alert(1)", "file:///etc/passwd", "not a url",
        ]
        for link in evil {
            #expect(UpdateChecker.trusted(link) == nil, "\(link)")
            // a bad page means no update is offered at all
            #expect(try UpdateChecker.parse(release(page: link), newerThan: current) == nil, "\(link)")
        }
        // a bad disk link only costs the disk link
        let info = try UpdateChecker.parse(release(dmg: "https://evil.example/x.dmg"), newerThan: current)
        #expect(info != nil)
        #expect(info?.downloadURL == nil)
    }

    @Test("an answer that is not a release is an error, not a silent no")
    func malformed() {
        #expect(throws: UpdateError.malformed) { try UpdateChecker.parse(Data("{}".utf8), newerThan: current) }
        #expect(throws: UpdateError.malformed) { try UpdateChecker.parse(Data("<html>".utf8), newerThan: current) }
    }

    @Test("it asks for the latest release of this repository, through the fetch it was given")
    func asksTheRightPlace() async throws {
        let seen = Box<URLRequest>()
        let checker = UpdateChecker(current: current) { request in
            seen.value = request
            return self.release()
        }
        let info = try await checker.newerRelease()
        #expect(info?.version.description == "0.1.3")
        #expect(
            seen.value?.url?.absoluteString
                == "https://api.github.com/repos/\(UpdateChecker.repository)/releases/latest")
        #expect(seen.value?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test("a failing fetch is passed on")
    func failingFetch() async {
        let checker = UpdateChecker(current: current) { _ in throw UpdateError.http(403) }
        await #expect(throws: UpdateError.http(403)) { try await checker.newerRelease() }
    }
}

private final class Box<T>: @unchecked Sendable {
    var value: T?
}
