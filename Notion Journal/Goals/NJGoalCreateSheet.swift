//
//  NJGoalCreateSheet.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/10.
//


import SwiftUI

struct NJGoalCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repo: DBNoteRepository
    let originBlockID: String?

    @State private var name: String = ""
    @State private var desc: String = ""
    @State private var domainTagsText: String = ""
    @State private var goalTagText: String = ""
    @State private var allGoalTags: [String] = []
    @State private var goalTagSuggestions: [String] = []

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name")) {
                    TextField("Goal / Seedling name", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                Section(header: Text("Domain Tags")) {
                    TextField("e.g. dev.mj, me.mind", text: $domainTagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Goal Tag (optional)")) {
                    TextField("e.g. g.dev.llm.YTCrawler", text: $goalTagText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !goalTagSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(goalTagSuggestions, id: \.self) { t in
                                Button {
                                    goalTagText = t
                                    goalTagSuggestions = []
                                } label: {
                                    Text(t)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                    }
                }

                Section(header: Text("Description")) {
                    TextEditor(text: $desc)
                        .frame(minHeight: 220)
                }
                
                if let bid = originBlockID, !bid.isEmpty {
                    Section(header: Text("Origin Block")) {
                        Text(bid).font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("New Goal / Seedling")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if n.isEmpty { return }
                        let domains = domainTagsText
                        let gt = goalTagText
                        _ = repo.createGoalSeedling(
                            name: n,
                            descriptionPlainText: desc,
                            originBlockID: originBlockID,
                            domainTagsText: domains,
                            goalTagText: gt
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                allGoalTags = loadActiveGoalTags()
                refreshGoalTagSuggestions()
            }
            .onChange(of: goalTagText) { _, _ in
                refreshGoalTagSuggestions()
            }
        }
    }

    private func loadActiveGoalTags() -> [String] {
        let goals = repo.listGoalSummaries()
        var set = Set<String>()
        for g in goals {
            let t = g.goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let s = g.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["archive", "archived", "done", "closed"].contains(s) { continue }
            set.insert(t)
        }
        return Array(set).sorted()
    }

    private func refreshGoalTagSuggestions() {
        let q = goalTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            goalTagSuggestions = []
            return
        }
        let filtered = allGoalTags.filter { $0.lowercased().hasPrefix(q) }
        goalTagSuggestions = Array(filtered.prefix(6))
    }
}
