import SwiftUI
import PhotosUI
import UIKit

/// Real photos of the people you send to (and of you), kept as small JPEGs in Application Support,
/// not in the ledger, so transfers stay light. Anyone without a photo is shown as a plain solid colour.
@Observable
@MainActor
final class PhotoStore {
    static let me = "me"

    private(set) var images: [String: UIImage] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directory = url
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" {
            if let image = UIImage(contentsOfFile: file.path) {
                images[file.deletingPathExtension().lastPathComponent] = image
            }
        }
    }

    func image(for key: String) -> UIImage? { images[key] }
    func image(for recipientID: UUID) -> UIImage? { images[recipientID.uuidString] }

    /// Crops to a square, shrinks to 320 pt and saves. Returns false if the data isn't an image.
    @discardableResult
    func setPhoto(_ data: Data, for key: String) -> Bool {
        guard let source = UIImage(data: data) else { return false }
        let side = min(source.size.width, source.size.height)
        let target = CGSize(width: 320, height: 320)
        let scale = target.width / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            source.draw(in: CGRect(x: (target.width - source.size.width * scale) / 2,
                                   y: (target.height - source.size.height * scale) / 2,
                                   width: source.size.width * scale,
                                   height: source.size.height * scale))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else { return false }
        try? jpeg.write(to: file(for: key), options: .atomic)
        images[key] = image
        return true
    }

    func removePhoto(for key: String) {
        try? FileManager.default.removeItem(at: file(for: key))
        images[key] = nil
    }

    func removeAll() {
        for key in images.keys { try? FileManager.default.removeItem(at: file(for: key)) }
        images = [:]
    }

    private func file(for key: String) -> URL { directory.appendingPathComponent(key).appendingPathExtension("jpg") }
}

/// A round picture: the photo when there is one, otherwise a blank solid colour.
struct PhotoCircle: View {
    let image: UIImage?
    let seed: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.solid(for: seed)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Wraps a picture in a Photos picker with a small camera badge, plus a way to remove the photo.
struct PhotoPickerButton<Picture: View>: View {
    let key: String
    @ViewBuilder var picture: () -> Picture
    @Environment(PhotoStore.self) private var photos
    @State private var item: PhotosPickerItem?

    var body: some View {
        let hasPhoto = photos.image(for: key) != nil
        VStack(spacing: 6) {
            PhotosPicker(selection: $item, matching: .images) {
                picture()
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 24, height: 24)
                            .background(Theme.sun, in: Circle())
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasPhoto ? "Change photo" : "Add a photo")

            if hasPhoto {
                Button("Remove photo", role: .destructive) { photos.removePhoto(for: key) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    photos.setPhoto(data, for: key)
                }
                item = nil
            }
        }
    }
}
