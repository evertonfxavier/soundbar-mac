import Foundation

/// How the audio processes of the system become the list of apps in the menu. No hardware in here: the owner of
/// a process and the time are handed in, so the rules can be checked on their own.
enum AppListing {
    /// An app that went quiet stays in the list this long, so its slider does not vanish between two songs.
    static let lingerSeconds: TimeInterval = 15

    /// Groups the processes that do audio by the app that owns them (Chrome owns its "Helper" processes).
    static func group(_ processes: [AudioProcess], ownerOf: (pid_t) -> AppOwner) -> [String: AudioApp] {
        var groups: [String: AudioApp] = [:]
        for process in processes {
            let owner = ownerOf(process.pid)
            var group =
                groups[owner.id]
                ?? AudioApp(
                    id: owner.id, name: owner.name, icon: owner.icon,
                    objectIDs: [], isPlaying: false, isUsingMic: false, outputDeviceUID: nil)
            group.objectIDs.append(process.objectID)
            if process.isRunningOutput {
                group.isPlaying = true
                if group.outputDeviceUID == nil { group.outputDeviceUID = process.outputDeviceUID }
            }
            if process.isRunningInput { group.isUsingMic = true }
            groups[owner.id] = group
        }
        return groups
    }

    /// The apps to show: the ones doing audio, the ones the user changed, and the ones that did a moment ago,
    /// sorted with the ones playing first. `hideBrowsers` drops the browsers the user did not touch (their tabs
    /// are listed one by one instead).
    static func visible(
        _ apps: [AudioApp],
        settings: [String: AppSetting],
        lastActive: [String: Date],
        hideBrowsers: Bool,
        now: Date
    ) -> [AudioApp] {
        apps.filter { app in
            if hideBrowsers, Browsers.chromeIDs.contains(app.id), settings[app.id] == nil { return false }
            return app.isPlaying || app.isUsingMic || settings[app.id] != nil
                || (lastActive[app.id].map { now.timeIntervalSince($0) < lingerSeconds } ?? false)
        }.sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
