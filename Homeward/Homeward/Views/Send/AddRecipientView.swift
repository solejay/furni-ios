import SwiftUI
import HomewardCore

/// Adds a recipient with two safety nets: offline checks (checksums, number formats) as you type,
/// then a name check against the receiving bank before anything can be sent.
struct AddRecipientView: View {
    @Environment(AppStore.self) private var store
    let fixedCountry: Country?
    let onSave: (Recipient) -> Void

    @State private var country: Country = .nigeria
    @State private var method: PayoutMethod = .bankAccount
    @State private var fullName = ""
    @State private var nickname = ""
    @State private var bankCode = "058"
    @State private var bankName = ""
    @State private var accountNumber = ""
    @State private var network: GhanaNetwork = .mtn
    @State private var phone = ""
    @State private var ifsc = ""
    @State private var vpa = ""

    @State private var lookup: LookupState = .idle
    @State private var confirmedMismatch = false

    enum LookupState: Equatable {
        case idle, checking
        case found(name: String, verdict: NameMatcher.Verdict)
        case failed(String)
    }

    init(fixedCountry: Country? = nil, onSave: @escaping (Recipient) -> Void) {
        self.fixedCountry = fixedCountry
        self.onSave = onSave
        _country = State(initialValue: fixedCountry ?? .nigeria)
        _method = State(initialValue: (fixedCountry ?? .nigeria).payoutMethods[0])
    }

    private var details: PayoutDetails {
        switch (country, method) {
        case (.nigeria, _): return .nigeriaBank(bankCode: bankCode, accountNumber: accountNumber)
        case (.ghana, .bankAccount): return .ghanaBank(bankName: bankName, accountNumber: accountNumber)
        case (.ghana, _): return .ghanaMobileMoney(network: network, phone: phone)
        case (.kenya, _): return .kenyaMpesa(phone: phone)
        case (.india, .upi): return .indiaUPI(vpa: vpa)
        case (.india, _): return .indiaBank(ifsc: ifsc, accountNumber: accountNumber)
        }
    }

    private var issue: PayoutValidator.Issue? { PayoutValidator.validate(details) }

    /// Only nag once the field looks "finished", not on every keystroke.
    private var visibleIssue: PayoutValidator.Issue? {
        guard let issue else { return nil }
        switch issue {
        case .empty, .unknownBank: return nil
        case .wrongLength:
            return accountNumber.filter(\.isNumber).count > 10 ? issue : nil
        case .invalidFormat:
            return (phone.count >= 10 || ifsc.count >= 11 || vpa.contains("@")) ? issue : nil
        default:
            return issue
        }
    }

    private var nameIsValid: Bool { NameMatcher.tokens(fullName).count >= 2 }

    private var canSave: Bool {
        guard nameIsValid, issue == nil, case let .found(_, verdict) = lookup else { return false }
        return verdict != .mismatch || confirmedMismatch
    }

    var body: some View {
        Form {
            if fixedCountry == nil {
                Section {
                    Picker("Country", selection: $country) {
                        ForEach(Country.allCases) { Text("\($0.flag) \($0.name)").tag($0) }
                    }
                }
            }

            if country.payoutMethods.count > 1 {
                Section {
                    Picker("Receive by", selection: $method) {
                        ForEach(country.payoutMethods, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                TextField("Full name, as on their account", text: $fullName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                TextField("Nickname (optional), e.g. Mum", text: $nickname)
            } header: {
                Text("Recipient")
            } footer: {
                if !fullName.isEmpty && !nameIsValid { Text("Enter their first and last name.") }
            }

            Section {
                payoutFields
            } header: {
                Text(method == .mobileMoney ? "Mobile money" : method == .upi ? "UPI" : "Bank details")
            } footer: {
                if let visibleIssue {
                    Label(visibleIssue.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if issue == nil {
                    Label("Details look right", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                lookupView
            } footer: {
                Text("We ask the receiving bank or wallet who owns this account, so your money can't go to a stranger because of a typo.")
            }
        }
        .navigationTitle("New recipient")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Save and continue") {
                guard case let .found(name, _) = lookup else { return }
                onSave(Recipient(fullName: fullName.trimmingCharacters(in: .whitespaces), verifiedName: name,
                                 nickname: nickname.isEmpty ? nil : nickname, payout: details))
            }
            .buttonStyle(.primary)
            .disabled(!canSave)
            .padding()
            .background(.bar)
        }
        .onChange(of: country) { method = country.payoutMethods[0]; lookup = .idle }
        .onChange(of: details) { lookup = .idle; confirmedMismatch = false }
        .onChange(of: fullName) {
            if case let .found(name, _) = lookup {
                lookup = .found(name: name, verdict: NameMatcher.compare(entered: fullName, verified: name))
            }
        }
    }

    @ViewBuilder
    private var payoutFields: some View {
        switch (country, method) {
        case (.nigeria, _):
            Picker("Bank", selection: $bankCode) {
                ForEach(Bank.nigeria) { Text($0.name).tag($0.code) }
            }
            TextField("10-digit account number (NUBAN)", text: $accountNumber)
                .keyboardType(.numberPad)
                .monospacedDigit()
        case (.ghana, .bankAccount):
            TextField("Bank name", text: $bankName)
            TextField("Account number", text: $accountNumber).keyboardType(.numberPad)
        case (.ghana, _):
            Picker("Network", selection: $network) {
                ForEach(GhanaNetwork.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Phone number, e.g. 024 123 4567", text: $phone).keyboardType(.phonePad)
        case (.kenya, _):
            TextField("M-Pesa number, e.g. 0712 345 678", text: $phone).keyboardType(.phonePad)
        case (.india, .upi):
            TextField("UPI ID, e.g. name@okhdfc", text: $vpa)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case (.india, _):
            TextField("IFSC code", text: $ifsc)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Account number", text: $accountNumber).keyboardType(.numberPad)
        }
    }

    @ViewBuilder
    private var lookupView: some View {
        switch lookup {
        case .idle:
            Button {
                Task { await checkName() }
            } label: {
                Label("Check account name", systemImage: "person.text.rectangle")
            }
            .disabled(issue != nil || !nameIsValid)
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Asking the bank who owns this account…").foregroundStyle(.secondary)
            }
        case let .found(name, verdict):
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(name).font(.body.weight(.semibold))
                } icon: {
                    Image(systemName: verdict == .match ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(verdict == .match ? Color.green : verdict == .partial ? Color.orange : Color.red)
                }
                switch verdict {
                case .match:
                    Text("Name matches. You're sending to the right person.").font(.footnote).foregroundStyle(.secondary)
                case .partial:
                    Text("Close, but not an exact match with “\(fullName)”. Check it's the right person before continuing.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .mismatch:
                    Text("This account belongs to someone else, not “\(fullName)”. Money sent to the wrong account is very hard to recover.")
                        .font(.footnote).foregroundStyle(.red)
                    Toggle("I'm sure this is the right account", isOn: $confirmedMismatch)
                        .font(.footnote)
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.footnote).foregroundStyle(.orange)
                Button("Try again") { Task { await checkName() } }
            }
        }
    }

    private func checkName() async {
        lookup = .checking
        do {
            let name = try await store.lookUpAccountName(for: details, typedName: fullName)
            lookup = .found(name: name, verdict: NameMatcher.compare(entered: fullName, verified: name))
        } catch {
            lookup = .failed("We couldn't reach the bank just now. Your details haven't been saved.")
        }
    }
}
