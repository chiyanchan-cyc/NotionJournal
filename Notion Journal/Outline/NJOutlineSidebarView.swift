import SwiftUI

struct NJOutlineSidebarView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    @State private var showCreateOutline = false
    @State private var outlineTitleDraft = ""
    @State private var outlineCategoryDraft = ""

    private let mainTabs: [String] = ["ME", "ZZ", "MM"]
    private let railWidth: CGFloat = 72

    private func subTabs(for main: String) -> [String] {
        switch main.uppercased() {
        case "ME":
            return ["ALL", "Planner", "Lifelong"]
        case "ZZ":
            return ["ALL", "EDU", "ADHD"]
        case "MM":
            return ["ALL"]
        default:
            return ["ALL"]
        }
    }

    private var selectedMainTab: String {
        let current = (store.selectedOutlineMainTabID ?? "ME").uppercased()
        return mainTabs.contains(current) ? current : "ME"
    }

    private var selectedSubTab: String {
        let current = store.selectedOutlineCategoryID ?? "ALL"
        let options = subTabs(for: selectedMainTab)
        return options.contains(current) ? current : "ALL"
    }

    private var filteredOutlines: [NJOutlineSummary] {
        outline.outlines.filter { item in
            matchesMain(category: item.category, main: selectedMainTab) &&
            matchesSub(category: item.category, sub: selectedSubTab)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            topTabs()
            Divider()
            HStack(spacing: 0) {
                subTabRail()
                Divider()
                list()
            }
        }
        .onAppear {
            if store.selectedOutlineMainTabID == nil {
                store.selectedOutlineMainTabID = "ME"
            }
            if store.selectedOutlineCategoryID == nil {
                store.selectedOutlineCategoryID = "ALL"
            }
            ensureValidSubTab()
            reload()
        }
        .onChange(of: store.selectedOutlineMainTabID) { _, _ in
            ensureValidSubTab()
            reload()
        }
        .onChange(of: store.selectedOutlineCategoryID) { _, _ in reload() }
        .sheet(isPresented: $showCreateOutline) {
            NavigationStack {
                Form {
                    Section("Outline") {
                        TextField("Title", text: $outlineTitleDraft)
                        TextField("Category", text: $outlineCategoryDraft)
                    }
                }
                .navigationTitle("New Outline")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCreateOutline = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { createOutline() }
                    }
                }
            }
        }
    }

    private func header() -> some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                outlineTitleDraft = ""
                outlineCategoryDraft = selectedSubTab == "ALL" ? selectedMainTab : selectedSubTab
                showCreateOutline = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .padding(.trailing, 10)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(height: 36)
        .background(Color(UIColor.systemBackground))
    }

    private func topTabs() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(mainTabs, id: \.self) { tab in
                    let isOn = selectedMainTab == tab
                    Button {
                        store.selectedOutlineMainTabID = tab
                        store.selectedOutlineNodeID = nil
                    } label: {
                        Text(tab)
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isOn ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                            )
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemBackground))
    }

    private func subTabRail() -> some View {
        let tabs = subTabs(for: selectedMainTab)
        return GeometryReader { g in
            let H = g.size.height
            let tabCount = tabs.count
            let spacing: CGFloat = 12
            let tabMin: CGFloat = 72
            let tabMax: CGFloat = 176
            let topBottomPad: CGFloat = 24
            let usableForTabs = max(0, H - topBottomPad - (tabCount > 0 ? spacing * CGFloat(max(0, tabCount - 1)) : 0))
            let rawTab = tabCount > 0 ? usableForTabs / CGFloat(tabCount) : tabMax
            let tabHeight = min(tabMax, max(tabMin, rawTab))
            let small = tabHeight < 100
            let tabFontSize: CGFloat = small ? 10 : 12
            let colorHex = Color.accentColor.toHexString()

            VStack(spacing: spacing) {
                ForEach(tabs, id: \.self) { t in
                    Button {
                        store.selectedOutlineCategoryID = t
                        store.selectedOutlineNodeID = nil
                    } label: {
                        RotatedWrapLabel(
                            text: t,
                            railWidth: railWidth,
                            buttonHeight: tabHeight,
                            fontSize: tabFontSize,
                            lineLimit: 2,
                            isOn: selectedSubTab == t,
                            colorHex: colorHex
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: railWidth, height: tabHeight)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(width: railWidth)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .frame(width: railWidth)
    }

    private func list() -> some View {
        List(selection: $store.selectedOutlineID) {
            if filteredOutlines.isEmpty {
                ContentUnavailableView("Create an outline", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(filteredOutlines) { item in
                    Button {
                        store.selectedOutlineID = item.outlineID
                        store.selectedOutlineNodeID = nil
                        outline.loadNodes(outlineID: item.outlineID)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title.isEmpty ? "Untitled" : item.title)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            if !item.category.isEmpty {
                                Text(item.category)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .tag(item.outlineID)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func ensureValidSubTab() {
        let options = subTabs(for: selectedMainTab)
        let raw = store.selectedOutlineCategoryID ?? "ALL"
        if !options.contains(raw) {
            store.selectedOutlineCategoryID = "ALL"
        }
    }

    private func reload() {
        outline.reloadOutlines(category: nil)
        if let id = store.selectedOutlineID,
           !filteredOutlines.contains(where: { $0.outlineID == id }) {
            store.selectedOutlineID = nil
            store.selectedOutlineNodeID = nil
        }
    }

    private func createOutline() {
        var category = outlineCategoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if category.isEmpty {
            category = selectedSubTab == "ALL" ? selectedMainTab : selectedSubTab
        }
        guard let created = outline.createOutline(title: outlineTitleDraft, category: category) else { return }
        showCreateOutline = false

        store.selectedOutlineCategoryID = selectedSubTab

        outline.reloadOutlines(category: nil)
        store.selectedOutlineID = created.outlineID
        store.selectedOutlineNodeID = nil
        outline.loadNodes(outlineID: created.outlineID)
    }

    private func normalizedCategory(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func tokens(from category: String) -> [String] {
        normalizedCategory(category)
            .split(whereSeparator: { ".-_/ ".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func matchesMain(category: String, main: String) -> Bool {
        let t = tokens(from: category)
        if main == "MM", t.isEmpty { return true }
        if t.contains(main) { return true }
        if main == "ME", t.contains("PLANNER") || t.contains("LIFELONG") { return true }
        if main == "ZZ", t.contains("EDU") || t.contains("ADHD") { return true }
        return false
    }

    private func matchesSub(category: String, sub: String) -> Bool {
        if sub.uppercased() == "ALL" { return true }
        return tokens(from: category).contains(sub.uppercased())
    }
}
