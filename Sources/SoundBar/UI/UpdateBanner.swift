import AppKit
import SwiftUI

/// "A newer version is out", with the links to download it and to read what changed.
struct UpdateBanner: View {
    let info: UpdateInfo

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nova versão: v\(info.version.description)")
                    .font(.callout.weight(.semibold))
                Text("Você está na v\(AppInfo.version). Baixe o instalador e abra-o como da primeira vez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Baixar") { NSWorkspace.shared.open(info.downloadURL ?? info.pageURL) }
                    Button("Novidades") { NSWorkspace.shared.open(info.pageURL) }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}
