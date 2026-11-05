import Foundation

enum AppInfo {
    /// The version of the running app, as the build put it in Info.plist ("dev" when run outside an app bundle).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
