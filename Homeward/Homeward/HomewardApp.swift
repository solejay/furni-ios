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

enum AppTab: Hashable { case home, activity, recipients, profile }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: AppTab = .home

    var body: some View {
        @Bindable var store = store
        tabs
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

    /// iOS 26: the system Liquid Glass tab bar shrinks while you scroll, with the transfer that's on its way
    /// (or a quick "Send money") pinned above it as a bottom accessory, like Music's mini player.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $tab) {
                Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                    HomeView(selectTab: { tab = $0 })
                }
                Tab("Activity", systemImage: "list.bullet.rectangle.portrait", value: AppTab.activity) {
                    ActivityView()
                }
                .badge(store.inFlightTransfers.count)
                Tab("Recipients", systemImage: "person.2.fill", value: AppTab.recipients) {
                    RecipientsView()
                }
                Tab("Account", systemImage: "person.crop.circle", value: AppTab.profile) {
                    ProfileView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                TransferAccessory()
            }
        } else {
            TabView(selection: $tab) {
                HomeView(selectTab: { tab = $0 })
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(AppTab.home)
                ActivityView()
                    .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.portrait") }
                    .tag(AppTab.activity)
                    .badge(store.inFlightTransfers.count)
                RecipientsView()
                    .tabItem { Label("Recipients", systemImage: "person.2.fill") }
                    .tag(AppTab.recipients)
                ProfileView()
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
                    .tag(AppTab.profile)
            }
        }
    }
}

/// The bottom accessory: the newest transfer that's on its way, with live progress, or a quick way to send.
/// The system gives it a Liquid Glass capsule; it compacts inline when the tab bar minimizes.
@available(iOS 26.0, *)
private struct TransferAccessory: View {
    @Environment(AppStore.self) private var store
    @State private var opened: Transfer?

    var body: some View {
        if let transfer = store.inFlightTransfers.first {
            let model = ReceiptModel(transfer: transfer)
            Button {
                opened = transfer
            } label: {
                HStack(spacing: 10) {
                    RecipientAvatar(recipient: transfer.recipient, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(transfer.quote.receiveAmount.formattedCompact) to \(transfer.recipient.nickname ?? transfer.recipient.fullName)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(model.status) · \(model.rightNote)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    ProgressView(value: transfer.status.progress)
                        .progressViewStyle(.circular)
                        .tint(Theme.sun)
                        .frame(width: 22, height: 22)
                }
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(transfer.quote.receiveAmount.formatted) to \(transfer.recipient.fullName), \(model.status)")
            .sheet(item: $opened) { transfer in
                NavigationStack { TransferDetailView(transferID: transfer.id) }
                    .presentationDetents([.large])
            }
        } else {
            Button {
                store.sendRequest = SendRequest()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill").foregroundStyle(Theme.brand)
                    Text("Send money home").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
        }
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
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your rate is here").font(.subheadline.weight(.semibold))
                Text("1 \(alert.source.code) = \(MoneyFormatter.rate(rate)) \(alert.target.code)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // The banner itself is glass, so its buttons stay standard (no glass on glass).
            Button("Send", action: send)
                .buttonStyle(.borderedProminent)
                .tint(Theme.sun)
                .foregroundStyle(Theme.ink)
                .controlSize(.small)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .liquidGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
