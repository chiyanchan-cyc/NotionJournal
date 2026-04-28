import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let njOpenLinkedNote = Notification.Name("nj_open_linked_note")
    static let njOpenLinkedView = Notification.Name("nj_open_linked_view")
}

enum NJExternalFileLinkKind: String, Identifiable {
    case file
    case folder

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .file: return "Choose File"
        case .folder: return "Choose Folder"
        }
    }
}

enum NJInternalLinkedViewKind: String, Codable, CaseIterable, Identifiable {
    case reconstructedManual = "reconstructed_manual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reconstructedManual: return "Filtered Blocks View"
        }
    }
}

enum NJInternalLinkedViewMatchMode: String, Codable, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .all: return "All"
        }
    }
}

struct NJInternalLinkedViewConfig: Codable, Hashable {
    var kind: NJInternalLinkedViewKind
    var title: String
    var filterText: String
    var matchMode: NJInternalLinkedViewMatchMode
    var startMs: Int64?
    var endMs: Int64?

    func windowValue() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return filterText
        }
        return string
    }

    static func fromWindowValue(_ value: String) -> NJInternalLinkedViewConfig? {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(NJInternalLinkedViewConfig.self, from: data) else {
            return nil
        }
        return decoded
    }
}

enum NJExternalFileLinkSupport {
    private static let defaultsKey = "nj_external_file_link_bookmarks_v1"
    private static let internalScheme = "nj-internal"
    private static let noteHost = "note"
    private static let viewHost = "view"
    private static let noteIDKey = "note_id"
    private static let viewKindKey = "kind"
    private static let viewPayloadKey = "payload"

    static func defaultDisplayName(for url: URL, kind: NJExternalFileLinkKind? = nil) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let noteID = internalNoteID(from: url) {
            return noteID.isEmpty ? "Open Note" : "Linked Note"
        }
        if let config = internalViewConfig(from: url) {
            let title = config.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Open View" : title
        }
        switch kind {
        case .folder: return "Folder Link"
        case .file: return "File Link"
        case .none: return "Open Link"
        }
    }

    static func noteURL(noteID: String) -> URL? {
        guard !noteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = internalScheme
        components.host = noteHost
        components.queryItems = [
            URLQueryItem(name: noteIDKey, value: noteID)
        ]
        return components.url
    }

    static func viewURL(config: NJInternalLinkedViewConfig) -> URL? {
        guard let data = try? JSONEncoder().encode(config),
              let payload = String(data: data, encoding: .utf8) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = internalScheme
        components.host = viewHost
        components.queryItems = [
            URLQueryItem(name: viewKindKey, value: config.kind.rawValue),
            URLQueryItem(name: viewPayloadKey, value: payload)
        ]
        return components.url
    }

    static func saveBookmark(for url: URL) {
        guard url.isFileURL else { return }
        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var map = bookmarkMap()
        map[url.absoluteString] = data.base64EncodedString()
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    static func open(url: URL) {
        if let noteID = internalNoteID(from: url) {
            NotificationCenter.default.post(
                name: .njOpenLinkedNote,
                object: nil,
                userInfo: [noteIDKey: noteID]
            )
            return
        }
        if let config = internalViewConfig(from: url) {
            NotificationCenter.default.post(
                name: .njOpenLinkedView,
                object: nil,
                userInfo: [viewPayloadKey: config.windowValue()]
            )
            return
        }
        let target = resolvedURL(for: url) ?? url
        let scoped = target.startAccessingSecurityScopedResource()
        UIApplication.shared.open(target) { _ in
            if scoped {
                target.stopAccessingSecurityScopedResource()
            }
        }
    }

    static func linkedNoteID(from notification: Notification) -> String? {
        (notification.userInfo?[noteIDKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func linkedViewPayload(from notification: Notification) -> String? {
        (notification.userInfo?[viewPayloadKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func internalNoteID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == internalScheme,
              components.host == noteHost else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == noteIDKey })?.value
    }

    static func internalViewConfig(from url: URL) -> NJInternalLinkedViewConfig? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == internalScheme,
              components.host == viewHost else {
            return nil
        }
        guard let payload = components.queryItems?.first(where: { $0.name == viewPayloadKey })?.value,
              let data = payload.data(using: .utf8),
              let config = try? JSONDecoder().decode(NJInternalLinkedViewConfig.self, from: data) else {
            return nil
        }
        return config
    }

    private static func resolvedURL(for url: URL) -> URL? {
        guard url.isFileURL else { return url }
        guard let encoded = bookmarkMap()[url.absoluteString],
              let data = Data(base64Encoded: encoded) else {
            return url
        }

        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return url
        }

        if isStale {
            saveBookmark(for: resolved)
        }
        return resolved
    }

    private static func bookmarkMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}

struct NJExternalLinkDocumentPicker: UIViewControllerRepresentable {
    let kind: NJExternalFileLinkKind
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let contentTypes: [UTType] = {
            switch kind {
            case .file:
                return [.item]
            case .folder:
                return [.folder]
            }
        }()

        let vc = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        vc.shouldShowFileExtensions = true
        vc.title = kind.pickerTitle
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
