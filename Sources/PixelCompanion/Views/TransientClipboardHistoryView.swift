import AppKit
import SwiftUI

/// Only accesses NSPasteboard on the explicit "Save copied text" button;
/// reads recognized concealment markers before requesting text bytes.
struct TransientClipboardHistoryView: View {
    @ObservedObject var history: TransientClipboardHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Clipboard")
                Spacer()
                Text("Manual · RAM only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Save copied text only when you choose. Don't save passwords or secrets.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if history.snippets.isEmpty {
                Text("No saved text in this session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(history.snippets) { snippet in
                HStack(spacing: 8) {
                    Text(snippet.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .font(.caption)
                    Spacer(minLength: 0)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(snippet.text, forType: .string)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy saved text")
                    Button {
                        history.remove(id: snippet.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove saved text")
                }
            }
            if let notice = history.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("companion.clipboard.notice")
            }
            HStack {
                Button("Save copied text", action: saveCopiedText)
                    .accessibilityIdentifier("companion.clipboard.save")
                Spacer()
                if !history.snippets.isEmpty {
                    Button("Clear", action: history.clear)
                        .accessibilityIdentifier("companion.clipboard.clear")
                }
            }
            .controlSize(.small)
        }
        .companionCard()
        .accessibilityIdentifier("companion.utility.clipboard")
    }

    private func saveCopiedText() {
        guard history.enabled else { return }
        let board = NSPasteboard.general
        let types = board.types?.map(\.rawValue) ?? []
        // Check confidentiality markers BEFORE reading clipboard text.
        guard ClipboardCapturePolicy.permits(types: types) else {
            history.rejectPrivate()
            return
        }
        history.capture(board.string(forType: .string), types: types)
    }
}
