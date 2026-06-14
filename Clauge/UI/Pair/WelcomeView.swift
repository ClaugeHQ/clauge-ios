import SwiftUI

/// Pairing entry point ("Add device"): scan a QR or enter details manually.
struct WelcomeView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("On your desktop, open Settings → Mobile and turn the server on.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.pink)
                    Text("Add device")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                }

                Spacer()

                VStack(spacing: 14) {
                    NavigationLink {
                        ScanView()
                    } label: {
                        Label("Scan QR", systemImage: "qrcode")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(Theme.pink, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.background)

                    OrDivider()

                    NavigationLink {
                        ManualPairView()
                    } label: {
                        Text("Enter manually")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
                    .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }
}

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.outlineVariant).frame(height: 1)
            Text("or").font(.footnote).foregroundStyle(Theme.textSecondary)
            Rectangle().fill(Theme.outlineVariant).frame(height: 1)
        }
    }
}
