import SwiftUI
import HomewardCore

struct RecipientStepView: View {
    @Environment(AppStore.self) private var store
    @Bindable var draft: SendDraft
    @Binding var path: [SendStep]

    private var matching: [Recipient] {
        store.ledger.recentRecipients.filter { $0.currency == draft.target }
    }

    var body: some View {
        List {
            Section {
                Button {
                    path.append(.addRecipient)
                } label: {
                    Label("New recipient in \(Country(currency: draft.target)?.name ?? draft.target.name)", systemImage: "person.badge.plus")
                        .font(.body.weight(.medium))
                }
            }
            if !matching.isEmpty {
                Section("Your recipients") {
                    ForEach(matching) { recipient in
                        Button {
                            draft.recipient = recipient
                            draft.lockQuote(with: store.engine)
                            path.append(.review)
                        } label: {
                            RecipientListRow(recipient: recipient)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Who are you sending to?")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecipientListRow: View {
    let recipient: Recipient

    var body: some View {
        HStack(spacing: 12) {
            RecipientAvatar(recipient: recipient)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(recipient.displayName).font(.body.weight(.medium)).lineLimit(1)
                    if recipient.verifiedName != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.brand)
                            .accessibilityLabel("Name verified")
                    }
                }
                Text(recipient.payout.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
