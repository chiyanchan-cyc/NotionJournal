//
//  NJReconstructedWorkspaceView.swift
//  Notion Journal
//

import SwiftUI

private struct NJReconstructedTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var tag: String

    init(title: String = "#REMIND", tag: String = "#REMIND", id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.tag = tag
    }
}

struct NJReconstructedWorkspaceView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var tabs: [NJReconstructedTab] = [NJReconstructedTab()]
    @State private var selectedID: UUID = UUID()

    init() {
        let first = NJReconstructedTab()
        _tabs = State(initialValue: [first])
        _selectedID = State(initialValue: first.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar()
            Divider()
            TabView(selection: $selectedID) {
                ForEach(tabs) { tab in
                    NJReconstructedManualView(
                        initialTag: tab.tag,
                        showsDismiss: false,
                        onTitleChange: { title in
                            updateTab(tab.id) { $0.title = title }
                        },
                        onTagChange: { tag in
                            updateTab(tab.id) { $0.tag = tag }
                        }
                    )
                    .tag(tab.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func tabBar() -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.vertical, 6)
            }
            Button {
                addTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)

            Button {
                detachSelectedTab()
            } label: {
                Label("Detach", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(tabs.count == 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func tabButton(_ tab: NJReconstructedTab) -> some View {
        let isSelected = tab.id == selectedID
        return HStack(spacing: 6) {
            Button {
                selectedID = tab.id
            } label: {
                Text(tab.title.isEmpty ? "(untitled)" : tab.title)
                    .lineLimit(1)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button {
                closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color(UIColor.secondarySystemBackground) : Color.clear)
        .cornerRadius(8)
    }

    private func addTab() {
        let tab = NJReconstructedTab()
        tabs.append(tab)
        selectedID = tab.id
    }

    private func closeTab(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: i)
        if tabs.isEmpty {
            let tab = NJReconstructedTab()
            tabs = [tab]
            selectedID = tab.id
        } else if selectedID == id {
            let newIndex = min(i, tabs.count - 1)
            selectedID = tabs[newIndex].id
        }
    }

    private func detachSelectedTab() {
        guard let tab = tabs.first(where: { $0.id == selectedID }) else { return }
        openWindow(id: "reconstructed-manual", value: tab.tag)
        closeTab(tab.id)
    }

    private func updateTab(_ id: UUID, mutate: (inout NJReconstructedTab) -> Void) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        var t = tabs[i]
        mutate(&t)
        tabs[i] = t
    }
}
