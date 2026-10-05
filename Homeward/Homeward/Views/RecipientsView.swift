import SwiftUI
import HomewardCore

struct RecipientsView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var addingRecipient = false

    private var recipients: [Recipient] {
        let all = store.ledger.recentRecipients
        guard !search.isEmpty else { return all }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(search) || ($0.nickname ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if recipients.isEmpty {
                    ContentUnavailableView("No recipients", systemImage: "person.2",
                                           description: Text("Add someone to send money to."))
                }
                ForEach(recipients) { recipient in
                    NavigationLink {
                        RecipientDetailView(recipientID: recipient.id)
                    } label: {
                        RecipientListRow(recipient: recipient)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteRecipient(recipient.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            store.sendRequest = SendRequest(recipient: recipient, target: recipient.currency)
                        } label: {
                            Label("Send", systemImage: "paperplane")
                        }
                        .tint(Theme.brand)
                    }
                }
            }
            .navigationTitle("Recipients")
            .searchable(text: $search)
            .toolbar {
                Button {
                    addingRecipient = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add recipient")
            }
            .sheet(isPresented: $addingRecipient) {
                NavigationStack {
                    AddRecipientView { recipient in
                        store.save(recipient)
                        addingRecipient = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingRecipient = false } }
                    }
                }
            }
        }
    }
}

struct RecipientDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    let recipientID: UUID
    @State private var confirmingDelete = false

    var body: some View {
        if let recipient = store.recipient(id: recipientID) {
            let transfers = store.ledger.transfers.filter { $0.recipient.id == recipientID }
            List {
                Section {
                    VStack(spacing: 8) {
                        PhotoPickerButton(key: recipient.id.uuidString) {
                            RecipientAvatar(recipient: recipient, size: 88)
                        }
                        Text(recipient.fullName).font(.title2.weight(.semibold))
                        if let nickname = recipient.nickname { Text(nickname).foregroundStyle(.secondary) }
                        if let total = store.ledger.totalDelivered(to: recipientID) {
                            Text("\(total.formattedCompact) delivered across \(transfers.filter { $0.status == .delivered }.count) transfers")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            store.sendRequest = SendRequest(recipient: recipient, target: recipient.currency)
                        } label: {
                            Label("Send money", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.primary)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Account") {
                    LabeledContent("Country", value: "\(recipient.country.flag) \(recipient.country.name)")
                    LabeledContent("Receives", value: recipient.currency.code)
                    LabeledContent("Account", value: recipient.payout.summary)
                    if let verified = recipient.verifiedName {
                        LabeledContent("Verified holder") {
                            Label(verified, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.brand)
                                .font(.footnote.weight(.medium))
                        }
                    }
                }

                if !transfers.isEmpty {
                    Section("History") {
                        ForEach(transfers) { transfer in
                            NavigationLink {
                                TransferDetailView(transferID: transfer.id)
                            } label: {
                                TransferRow(transfer: transfer)
                            }
                        }
                    }
                }

                Section {
                    Button("Delete recipient", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle(recipient.nickname ?? recipient.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete \(recipient.fullName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteRecipient(recipientID)
                    photos.removePhoto(for: recipientID.uuidString)
                    dismiss()
                }
            } message: {
                Text("Past transfers stay in your history. Scheduled transfers to them will stop.")
            }
        } else {
            ContentUnavailableView("Recipient removed", systemImage: "person.crop.circle.badge.xmark")
        }
    }
}
