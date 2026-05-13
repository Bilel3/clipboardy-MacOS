import AppKit
import Foundation

// MARK: - Model

struct ClipboardItem: Identifiable {
    let id: UUID
    let text: String?
    let image: NSImage?
    let date: Date

    var displayText: String {
        if let t = text {
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "[Image]"
    }

    var previewText: String {
        let raw = displayText
        let firstLine = raw.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? raw
        return firstLine.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Store

class ClipboardHistoryStore {

    private(set) var items: [ClipboardItem] = []
    let maxItems = 100
    var onChange: (() -> Void)?

    // MARK: Mutations

    func add(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }      // deduplicate
        let item = ClipboardItem(id: UUID(), text: text, image: nil, date: Date())
        items.insert(item, at: 0)
        trim()
        onChange?()
    }

    func add(image: NSImage) {
        let item = ClipboardItem(id: UUID(), text: nil, image: image, date: Date())
        items.insert(item, at: 0)
        trim()
        onChange?()
    }

    func clear() {
        items.removeAll()
        onChange?()
    }

    func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let text = item.text {
            pb.setString(text, forType: .string)
        } else if let image = item.image {
            pb.writeObjects([image])
        }
    }

    private func trim() {
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }
}

// MARK: - Date helper

extension Date {
    var relativeString: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }
}
