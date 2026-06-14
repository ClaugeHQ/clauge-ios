import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: ServerStore
    @State private var page = 0

    private let remoteGuideURL = URL(string: "https://clauge.in/docs.html#mobile")!

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageOne.tag(0)
                    pageTwo.tag(1)
                    pageThree.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(action: advance) {
                    Text(page < 2 ? "Continue" : "Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(Theme.pink, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var pageOne: some View {
        OnboardingPage(
            title: "Clauge",
            subtitle: "Control your Clauge desktop coding sessions from your phone — watch your agents, send prompts, and stay in sync."
        )
    }

    private var pageTwo: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Same network or remote")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Your phone talks to your desktop over Wi-Fi — or anywhere via Tailscale.")
                .foregroundStyle(Theme.textSecondary)
            Link("Remote access guide →", destination: remoteGuideURL)
                .font(.subheadline)
                .foregroundStyle(Theme.pink)

            OnboardingStep(title: "Turn on the Mobile server",
                           detail: "On your desktop: Settings → Mobile, switch it on to show a pairing QR.")
            OnboardingStep(title: "Attach to your sessions",
                           detail: "Open any Agent or SSH session and drive it live from your phone.")
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private var pageThree: some View {
        OnboardingPage(
            title: "Pair your desktop",
            subtitle: "Scan the QR from desktop Settings → Mobile, or enter the host, port, and code."
        )
    }

    private func advance() {
        if page < 2 { withAnimation { page += 1 } } else { finish() }
    }

    private func finish() { store.onboarded = true }
}

private struct OnboardingPage: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(title).font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.title3).foregroundStyle(Theme.textSecondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }
}

private struct OnboardingStep: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }
}
