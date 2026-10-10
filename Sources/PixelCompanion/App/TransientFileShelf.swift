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
    private var revision: UInt64 = 0
    private var pendingChecks = 0
    var isChecking: Bool { pendingChecks > 0 }
    private let isDirectory: @Sendable (URL) -> Bool
    static let maximumItems = 8
    private static let maximumPendingBatches = 2

    init(
        isDirectory: @escaping @Sendable (URL) -> Bool = {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    ) {
        self.isDirectory = isDirectory
    }

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if !newValue { clear() }
    }

    /// Accept candidate references immediately without touching file metadata on
    /// the UI actor. Finder shares and iCloud providers may stall on resourceValues.
    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        guard enabled, items.count < Self.maximumItems,
              pendingChecks < Self.maximumPendingBatches else { return false }
        let candidates = urls.compactMap { input -> URL? in
            guard input.isFileURL, !input.hasDirectoryPath else { return nil }
            let url = input.standardizedFileURL
            guard !url.lastPathComponent.isEmpty, url.lastPathComponent != "/",
                  !items.contains(where: { $0.url == url }) else { return nil }
            return url
        }
        guard !candidates.isEmpty else { return false }
        let currentRevision = revision
        pendingChecks += 1
        let directoryCheck = isDirectory
        Task.detached(priority: .utility) { [weak self] in
            let verified = candidates.filter { !directoryCheck($0) }
            await self?.acceptVerified(verified, revision: currentRevision)
        }
        return true
    }

    private func acceptVerified(_ urls: [URL], revision candidate: UInt64) {
        guard candidate == revision else { return }
        pendingChecks = max(0, pendingChecks - 1)
        guard enabled else { return }
        for url in urls {
            guard items.count < Self.maximumItems else { break }
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
        revision &+= 1
        pendingChecks = 0
        items.removeAll()
    }
}
