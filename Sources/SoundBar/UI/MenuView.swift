import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var mixer: Mixer
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let update = updater.available {
                UpdateBanner(info: update)
            }

            if mixer.permission != .authorized {
                PermissionBanner()
            }

            DeviceRow(
                title: L.output.string,
                device: mixer.output,
                choices: mixer.outputDevices,
                select: { mixer.selectDevice(uid: $0, input: false) },
                onSymbol: "speaker.wave.2.fill",
                offSymbol: "speaker.slash.fill",
                setVolume: mixer.setOutputVolume,
                toggleMute: mixer.toggleOutputMute
            )

            DeviceRow(
                title: L.microphone.string,
                device: mixer.input,
                choices: mixer.inputDevices,
                select: { mixer.selectDevice(uid: $0, input: true) },
                onSymbol: "mic.fill",
                offSymbol: "mic.slash.fill",
                setVolume: mixer.setInputVolume,
                toggleMute: mixer.toggleInputMute
            )

            if !mixer.micUserNames.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(mixer.input.muted ? Color.secondary : Color.red).frame(width: 7, height: 7)
                    Text(
                        (mixer.input.muted ? L.micMutedFor.string : L.micInUseBy.string)
                            + mixer.micUserNames.joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }

            if !mixer.browserTabs.isEmpty {
                Divider()

                SectionTitle(L.sectionChromeTabs.string)

                if mixer.browserTabs.count > 4 {
                    ScrollView { tabList }.frame(height: 260)
                } else {
                    tabList
                }
            }

            Divider()

            SectionTitle(L.sectionApps.string)

            if mixer.apps.isEmpty {
                Text(L.noAppsPlaying.string)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if mixer.apps.count > 6 {
                ScrollView { appList }.frame(height: 340)
            } else {
                appList
            }

            if mixer.showExtensionHint {
                Label(
                    L.extensionHint.string,
                    systemImage: "puzzlepiece.extension"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            SoundboardSection()

            Divider()

            Toggle(L.checkForUpdates.string, isOn: $updater.checksForUpdates)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help(L.checkForUpdatesHelp.string)

            LanguageRow()

            HStack {
                Toggle(
                    L.launchAtLogin.string,
                    isOn: Binding(
                        get: { mixer.launchAtLogin },
                        set: { mixer.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                Text("v\(AppInfo.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button(L.quit.string) { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var tabList: some View {
        VStack(spacing: 10) {
            ForEach(mixer.browserTabs) { tab in
                TabRow(tab: tab)
            }
        }
    }

    private var appList: some View {
        VStack(spacing: 10) {
            ForEach(mixer.apps) { app in
                AppRow(app: app)
            }
        }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The language of the app: the three it speaks, and "automatic", which follows the system.
private struct LanguageRow: View {
    @EnvironmentObject var localizer: Localizer

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe").foregroundStyle(.secondary)
            Text(L.languageLabel.string).font(.caption)
            Menu {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    Button {
                        localizer.choice = option
                    } label: {
                        if option == localizer.choice {
                            Label(localizer.name(of: option), systemImage: "checkmark")
                        } else {
                            Text(localizer.name(of: option))
                        }
                    }
                }
            } label: {
                Text(localizer.name(of: localizer.choice)).font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }
}
