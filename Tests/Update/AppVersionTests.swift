import Testing

@Suite("AppVersion")
struct AppVersionTests {
    @Test("reads the tag of a release, with or without the v")
    func readsTags() {
        #expect(AppVersion("v0.1.2")?.description == "0.1.2")
        #expect(AppVersion("0.1.2")?.description == "0.1.2")
        #expect(AppVersion(" V1.20.3 \n")?.description == "1.20.3")
    }

    @Test("a missing patch is zero")
    func missingPatch() {
        #expect(AppVersion("0.1") == AppVersion("0.1.0"))
    }

    @Test("what is not a version of ours is nil")
    func rejects() {
        for text in ["", "v", "latest", "1", "1.2.3.4", "0.1.2-beta", "1.a", "1..2", "-1.0.0", "１.２.３", "v0.1.2+build"]
        {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }

    @Test("versions are compared by their numbers, not by their text")
    func ordering() throws {
        let v = { try #require(AppVersion($0)) }
        #expect(try v("0.1.10") > v("0.1.9"))
        #expect(try v("0.2.0") > v("0.1.99"))
        #expect(try v("1.0.0") > v("0.99.99"))
        #expect(try v("0.1.2") == v("v0.1.2"))
        #expect(!(try v("0.1.2") > v("0.1.2")))
    }
}
