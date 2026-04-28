import SwiftUI
import UIKit
import Combine

struct UINoteListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    private func cleanDomainKey(_ s: String) -> String {
        var x = s.trimmingCharacters(in: .whitespacesAndNewlines)
        x = x.replacingOccurrences(of: "%", with: "")
        while x.hasSuffix(".") { x.removeLast() }
        if x.isEmpty { return "default" }
        return x
    }

    var body: some View {
        let nb = store.currentNotebookTitle ?? "default"
        let rawDomainKey = store.tabs.first(where: { $0.tabID == store.selectedTabID })?.domainKey ?? "default"
        let domainKey = cleanDomainKey(rawDomainKey)

        let notes: [NJNote] = (store.showFavoriteNotesOnly
            ? store.notes.listFavoriteNotes(notebook: store.currentNotebookTitle)
            : store.notes
                .listNotes(tabDomainKey: domainKey)
                .filter { $0.deleted == 0 })
            .sorted {
                if $0.pinned != $1.pinned { return $0.pinned > $1.pinned }
                if $0.updatedAtMs != $1.updatedAtMs { return $0.updatedAtMs > $1.updatedAtMs }
                return String(describing: $0.id) > String(describing: $1.id)
            }

        List {
            ForEach(notes) { n in
                Button {
                    open(n.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: n.noteType == .card ? "rectangle.stack.fill" : "doc.text")
                                .font(.caption)
                                .foregroundStyle(n.noteType == .card ? .blue : .secondary)
                            Text(n.title.isEmpty ? "Untitled" : n.title).font(.headline)
                            if n.favorited > 0 {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                            if n.pinned > 0 {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(n.tabDomain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        store.notes.setFavorited(noteID: n.id.raw, favorited: n.favorited == 0)
                        store.objectWillChange.send()
                    } label: {
                        Label(n.favorited == 0 ? "Star" : "Unstar", systemImage: n.favorited == 0 ? "star" : "star.slash")
                    }
                    .tint(n.favorited == 0 ? .yellow : .gray)

                    Button {
                        store.notes.setPinned(noteID: n.id.raw, pinned: n.pinned == 0)
                        store.objectWillChange.send()
                    } label: {
                        Label(n.pinned == 0 ? "Pin" : "Unpin", systemImage: n.pinned == 0 ? "pin" : "pin.slash")
                    }
                    .tint(n.pinned == 0 ? .orange : .gray)
                }
            }
        }
        .id("\(nb)|\(domainKey)|fav:\(store.showFavoriteNotesOnly)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Note", systemImage: "doc.text") {
                        let _ = store.notes.createNote(notebook: nb, tabDomain: domainKey, title: "New Note")
                    }
                    Button("New Card", systemImage: "rectangle.stack") {
                        let _ = store.notes.createNote(notebook: nb, tabDomain: domainKey, title: "", noteType: .card)
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func open(_ id: NJNoteID) {
        openWindow(value: id)
    }
}
