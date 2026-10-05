import SwiftUI
import HomewardCore

/// A keepsake for the person receiving the money: shareable on WhatsApp straight after delivery.
struct PostcardView: View {
    let transfer: Transfer
    let senderName: String

    private var greeting: String {
        let first = transfer.recipient.nickname ?? transfer.recipient.fullName.components(separatedBy: " ").first ?? ""
        return "For \(first), with love"
    }

    var body: some View {
        VStack(spacing: 0) {
            TextilePattern(style: .init(country: transfer.recipient.country), seed: TextilePattern.seed(from: transfer.id))
                .frame(height: 250)
                .overlay(alignment: .bottomLeading) {
                    Text(transfer.purpose.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                        .padding(14)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Text(transfer.quote.receiveAmount.formatted)
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let message = transfer.message {
                    Text("“\(message)”").font(.system(.body, design: .serif).italic())
                }
                HStack {
                    Text("from \(senderName)")
                    Spacer()
                    Text((transfer.date(of: .delivered) ?? transfer.createdAt).formatted(date: .abbreviated, time: .omitted))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "house.fill").foregroundStyle(Theme.brand)
                    Text("Delivered by Homeward · \(transfer.payoutReference ?? transfer.reference)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .foregroundStyle(Color.black)
        }
        .frame(width: 340)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PostcardSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transfer: Transfer
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PostcardView(transfer: transfer, senderName: store.ledger.profile.firstName)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    Text("The pattern is generated just for this transfer, inspired by \(TextilePattern.Style(country: transfer.recipient.country).name) from \(transfer.recipient.country.name).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let image {
                        ShareLink(item: image, preview: SharePreview("Postcard for \(transfer.recipient.fullName)", image: image)) {
                            Label("Share postcard", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.primary)
                    } else {
                        ProgressView()
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Postcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { render() }
        }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: PostcardView(transfer: transfer, senderName: store.ledger.profile.firstName))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        }
    }
}
