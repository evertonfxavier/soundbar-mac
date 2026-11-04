import SwiftUI

struct PermissionBanner: View {
    @EnvironmentObject var mixer: Mixer

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissão necessária")
                    .font(.callout.weight(.semibold))
                Text("Para ajustar o volume de cada app, permita “Gravação de Áudio do Sistema”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(mixer.permission == .denied ? "Abrir Ajustes" : "Permitir") {
                    mixer.requestPermission()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
