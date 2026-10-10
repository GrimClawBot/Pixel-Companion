import AppKit
import SwiftUI

/// Files are selected by the human; Pixel Companion keeps only temporary URLs.
/// No connector or Paperclip request can access these references.
struct TransientFileShelfView: View {
    @ObservedObject var shelf: TransientFileShelf

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "File shelf")
                Spacer(minLength: 0)
                Text("This session only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if shelf.items.isEmpty {
                Text("Choose files to keep handy while Pixel Companion is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(shelf.items) { item in
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(item.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share \(item.displayName) with macOS")
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reveal \(item.displayName) in Finder")
                    Button {
                        shelf.remove(id: item.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(item.displayName)")
                }
            }
            HStack {
                Button("Add files…", action: chooseFiles)
                    .disabled(shelf.items.count >= TransientFileShelf.maximumItems)
                    .accessibilityIdentifier("companion.file-shelf.add")
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear", action: shelf.clear)
                        .accessibilityIdentifier("companion.file-shelf.clear")
                }
            }
            .controlSize(.small)
            Text("Up to 8 references · no files copied or uploaded")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .companionCard()
        .dropDestination(for: URL.self) { urls, _ in
            guard shelf.enabled else { return false }
            return shelf.add(urls)
        }
        .accessibilityIdentifier("companion.utility.file-shelf")
    }

    private func chooseFiles() {
        guard shelf.enabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose local files to reference temporarily in Pixel Companion."
        panel.prompt = "Add to shelf"
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in shelf.add(panel.urls) }
        }
    }
}
