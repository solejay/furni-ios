import SwiftUI
import HomewardCore

@main
struct HomewardApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.brand)
                .task { store.start() }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    enum Tab: Hashable { case home, activity, recipients, profile }
    @State private var tab: Tab = .home

    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            HomeView(selectTab: { tab = $0 })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.portrait") }
                .tag(Tab.activity)
                .badge(store.inFlightTransfers.count)
            RecipientsView()
                .tabItem { Label("Recipients", systemImage: "person.2.fill") }
                .tag(Tab.recipients)
            ProfileView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .sheet(item: $store.sendRequest) { request in
            SendFlowView(request: request)
        }
        .overlay(alignment: .top) {
            if let alert = store.firedAlert {
                AlertBanner(alert: alert, rate: store.midRate(alert.source, alert.target)) {
                    store.firedAlert = nil
                    store.sendRequest = SendRequest(target: alert.target)
                } dismiss: {
                    store.firedAlert = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal)
            }
        }
        .animation(.spring(duration: 0.4), value: store.firedAlert)
    }
}

private struct AlertBanner: View {
    let alert: RateAlert
    let rate: Decimal
    let send: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(Theme.sun)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your rate is here").font(.subheadline.weight(.semibold))
                Text("1 \(alert.source.code) = \(MoneyFormatter.rate(rate)) \(alert.target.code)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Send", action: send).buttonStyle(.borderedProminent).controlSize(.small)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
