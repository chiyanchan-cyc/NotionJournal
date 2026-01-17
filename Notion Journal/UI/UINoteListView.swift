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

        let notes: [NJNote] = store.notes
            .listNotes(tabDomainKey: domainKey)
            .filter { $0.deleted == 0 }
            .sorted {
                if $0.updatedAtMs != $1.updatedAtMs { return $0.updatedAtMs > $1.updatedAtMs }
                return String(describing: $0.id) > String(describing: $1.id)
            }

        List {
            ForEach(notes) { n in
                Button {
                    open(n.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title.isEmpty ? "Untitled" : n.title).font(.headline)
                        Text(n.tabDomain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .id("\(nb)|\(domainKey)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let _ = store.notes.createNote(notebook: nb, tabDomain: domainKey, title: "New Note")
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
