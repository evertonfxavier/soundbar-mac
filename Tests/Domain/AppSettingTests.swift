import Foundation
import Testing

@Suite("AppSetting")
struct AppSettingTests {
    @Test("an untouched app is the default: no tap needed")
    func untouchedIsDefault() {
        #expect(AppSetting().isDefault)
        #expect(AppSetting(volume: 1, muted: false).isDefault)
    }

    @Test("a volume within half a percent of 100% still counts as untouched")
    func almostFullIsDefault() {
        #expect(AppSetting(volume: 0.996).isDefault)
        #expect(AppSetting(volume: 1.004).isDefault)
        #expect(!AppSetting(volume: 0.99).isDefault)
        #expect(!AppSetting(volume: 1.01).isDefault)
    }

    @Test("muting is a change even at full volume")
    func mutedIsNotDefault() {
        #expect(!AppSetting(volume: 1, muted: true).isDefault)
    }

    @Test("the gain is the volume, or silence when muted")
    func gain() {
        #expect(AppSetting(volume: 0.4).gain == 0.4)
        #expect(AppSetting(volume: 0.4, muted: true).gain == 0)
        #expect(AppSetting(volume: 1.5).gain == 1.5)
    }

    @Test(
        "a volume is kept between silence and the maximum",
        arguments: [
            (-1 as Float, 0 as Float), (0, 0), (0.7, 0.7), (1.5, 1.5), (3, 1.5),
        ])
    func clamp(input: Float, expected: Float) {
        #expect(AppSetting.clamp(input) == expected)
    }

    @Test("it can boost an app to 150%")
    func maxVolume() {
        #expect(AppSetting.maxVolume == 1.5)
    }

    @Test("it is saved with the keys the earlier versions wrote")
    func savedShape() throws {
        let data = try JSONEncoder().encode(AppSetting(volume: 0.5, muted: true))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(json.keys) == ["volume", "muted"])
        #expect(json["volume"] as? Double == 0.5)
        #expect(json["muted"] as? Bool == true)
    }

    @Test("it reads what an earlier version saved")
    func readsOldFormat() throws {
        let old = Data(#"{"appSettings":{"com.spotify.client":{"volume":0.25,"muted":false}}}"#.utf8)
        let outer = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
        let inner = try JSONSerialization.data(withJSONObject: try #require(outer["appSettings"]))

        let settings = try JSONDecoder().decode([String: AppSetting].self, from: inner)

        #expect(settings == ["com.spotify.client": AppSetting(volume: 0.25, muted: false)])
    }
}
