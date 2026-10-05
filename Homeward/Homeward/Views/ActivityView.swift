import SwiftUI
import HomewardCore

struct ActivityView: View {
    @Environment(AppStore.self) private var store
    @State private var filter: Filter = .all
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", inProgress = "In progress", delivered = "Delivered", other = "Cancelled"
        var id: String { rawValue }

        func includes(_ status: TransferStatus) -> Bool {
            switch self {
            case .all: return true
            case .inProgress: return status.isInFlight || status == .failed
            case .delivered: return status == .delivered
            case .other: return status == .cancelled || status == .refunded
            }
        }
    }

    private var filtered: [Transfer] {
        store.ledger.transfers.filter { transfer in
            filter.includes(transfer.status) && (search.isEmpty
                || transfer.recipient.fullName.localizedCaseInsensitiveContains(search)
                || transfer.reference.localizedCaseInsensitiveContains(search))
        }
    }

    private var grouped: [(month: String, transfers: [Transfer])] {
        let groups = Dictionary(grouping: filtered) { $0.createdAt.formatted(.dateTime.month(.wide).year()) }
        return groups
            .map { (month: $0.key, transfers: $0.value) }
            .sorted { ($0.transfers.first?.createdAt ?? .distantPast) > ($1.transfers.first?.createdAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No transfers yet" : "No results",
                                           systemImage: "tray",
                                           description: Text(search.isEmpty ? "Transfers you send will show up here." : "Try a name or reference."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(grouped, id: \.month) { group in
                        Section {
                            ForEach(group.transfers) { transfer in
                                NavigationLink {
                                    TransferDetailView(transferID: transfer.id)
                                } label: {
                                    TransferRow(transfer: transfer)
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.month)
                                Spacer()
                                Text(Self.total(group.transfers)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity")
            .searchable(text: $search, prompt: "Name or reference")
        }
    }

    /// "£475 sent", counting delivered and in-flight transfers in the most common send currency.
    static func total(_ transfers: [Transfer]) -> String {
        let counted = transfers.filter { $0.status != .cancelled && $0.status != .refunded }
        guard let currency = counted.first?.quote.source else { return "" }
        let sum = counted.filter { $0.quote.source == currency }.map(\.quote.sendAmount).reduce(.zero(currency), +)
        return "\(sum.formattedCompact) sent"
    }
}
