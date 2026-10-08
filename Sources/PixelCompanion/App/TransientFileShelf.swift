import Combine
import Foundation

/// Explicitly selected file *references* only. No file content, uploads,
/// bookmarks or filesystem scans. Disabling the shelf clears all references.
struct FileShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let displayName: String
}

enum FileShelfLabel {
    static func sanitized(_ raw: String) -> String {
        // Filenames come from the filesystem and may contain linebreaks or
        // direction overrides. Display as plain, bounded local labels.
        let scalars = raw.unicodeScalars.filter { scalar in
            let value = scalar.value
            let bidi = (0x202A...0x202E).contains(value)
                || (0x2066...0x2069).contains(value)
                || value == 0x200E || value == 0x200F || value == 0x061C
            return !CharacterSet.controlCharacters.contains(scalar) && !bidi
        }
        let trimmed = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed file" : String(trimmed.prefix(80))
    }
}

@MainActor
final class TransientFileShelf: ObservableObject {
    @Published private(set) var items: [FileShelfItem] = []
    private(set) var enabled = false
    static let maximumItems = 8

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if !newValue { clear() }
    }

    /// Called only after a user explicitly selects file URLs from NSOpenPanel.
    /// Reject directories, nonfile URLs and repeats before retaining a URL.
    func add(_ urls: [URL]) {
        guard enabled else { return }
        for input in urls {
            guard items.count < Self.maximumItems else { break }
            guard input.isFileURL, !input.hasDirectoryPath else { continue }
            let url = input.standardizedFileURL
            guard url.lastPathComponent != "/", !url.lastPathComponent.isEmpty else { continue }
            guard !items.contains(where: { $0.url == url }) else { continue }
            items.append(
                FileShelfItem(
                    id: UUID(),
                    url: url,
                    displayName: FileShelfLabel.sanitized(url.lastPathComponent)
                )
            )
        }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }
}
