import SwiftUI

struct NJOutlineSidebarView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    @State private var showCreateOutline = false
    @State private var outlineTitleDraft = ""
    @State private var outlineCategoryDraft = ""

    private var categoryOptions: [String] {
        ["All"] + outline.categories
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            categoryBar()
            Divider()
            list()
        }
        .onAppear {
            if store.selectedOutlineCategoryID == nil {
                store.selectedOutlineCategoryID = "All"
            }
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
                outlineCategoryDraft = store.selectedOutlineCategoryID == "All" ? "" : (store.selectedOutlineCategoryID ?? "")
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

    private func categoryBar() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categoryOptions, id: \.self) { c in
                    let isOn = (store.selectedOutlineCategoryID ?? "All") == c
                    Button {
                        store.selectedOutlineCategoryID = c
                    } label: {
                        Text(c)
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

    private func list() -> some View {
        List(selection: $store.selectedOutlineID) {
            if outline.outlines.isEmpty {
                ContentUnavailableView("Create an outline", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(outline.outlines) { item in
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

    private func selectedCategory() -> String? {
        let c = (store.selectedOutlineCategoryID ?? "All").trimmingCharacters(in: .whitespacesAndNewlines)
        return c == "All" ? nil : c
    }

    private func reload() {
        outline.reloadOutlines(category: selectedCategory())
        if let id = store.selectedOutlineID,
           !outline.outlines.contains(where: { $0.outlineID == id }) {
            store.selectedOutlineID = nil
            store.selectedOutlineNodeID = nil
        }
    }

    private func createOutline() {
        let category = outlineCategoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let created = outline.createOutline(title: outlineTitleDraft, category: category) else { return }
        showCreateOutline = false

        if !category.isEmpty {
            store.selectedOutlineCategoryID = category
        }

        outline.reloadOutlines(category: selectedCategory())
        store.selectedOutlineID = created.outlineID
        store.selectedOutlineNodeID = nil
        outline.loadNodes(outlineID: created.outlineID)
    }
}
