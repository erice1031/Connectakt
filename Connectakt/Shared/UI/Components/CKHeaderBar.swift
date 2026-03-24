import SwiftUI

/// Top section header bar — mimics the Digitakt screen header row.
struct CKHeaderBar: View {
    let title: String
    let status: ConnectionStatus

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(ConnektaktTheme.titleFont)
                    .foregroundStyle(ConnektaktTheme.textPrimary)
                    .tracking(2)

                Spacer()

                CKStatusBadge(status: status)
            }
            .padding(.horizontal, ConnektaktTheme.paddingMD)
            .padding(.vertical, ConnektaktTheme.paddingSM)

            Rectangle()
                .fill(ConnektaktTheme.primary.opacity(0.4))
                .frame(height: ConnektaktTheme.accentBarHeight)
        }
        .background(ConnektaktTheme.surface)
    }
}

#Preview {
    VStack(spacing: 0) {
        CKHeaderBar(title: "CONNECTAKT", status: .disconnected)
        CKHeaderBar(title: "CONNECTAKT", status: .connected(deviceName: "DIGITAKT"))
        CKHeaderBar(title: "RECORD", status: .scanning)
    }
    .background(ConnektaktTheme.background)
}
