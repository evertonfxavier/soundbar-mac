import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var mixer: Mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mixer.permission != .authorized {
                PermissionBanner()
            }

            DeviceRow(
                title: "Saída",
                device: mixer.output,
                onSymbol: "speaker.wave.2.fill",
                offSymbol: "speaker.slash.fill",
                setVolume: mixer.setOutputVolume,
                toggleMute: mixer.toggleOutputMute
            )

            DeviceRow(
                title: "Microfone",
                device: mixer.input,
                onSymbol: "mic.fill",
                offSymbol: "mic.slash.fill",
                setVolume: mixer.setInputVolume,
                toggleMute: mixer.toggleInputMute
            )

            if !mixer.micUserNames.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(mixer.input.muted ? Color.secondary : Color.red).frame(width: 7, height: 7)
                    Text(
                        (mixer.input.muted ? "Mutado para: " : "Em uso por: ")
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

                SectionTitle("ABAS DO CHROME")

                if mixer.browserTabs.count > 4 {
                    ScrollView { tabList }.frame(height: 260)
                } else {
                    tabList
                }
            }

            Divider()

            SectionTitle("APPS")

            if mixer.apps.isEmpty {
                Text("Nenhum app usando áudio agora.")
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
                    "Para controlar cada aba do Chrome, instale a extensão SoundBar Bridge (veja o README).",
                    systemImage: "puzzlepiece.extension"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Toggle(
                    "Abrir ao iniciar sessão",
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
                Button("Sair") { NSApp.terminate(nil) }
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

/// What the running build says about itself (set by scripts/build-app.sh in Info.plist).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}
