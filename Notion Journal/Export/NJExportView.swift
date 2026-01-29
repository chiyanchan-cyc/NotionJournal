//
//  NJExportView.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/29.
//


import SwiftUI

struct NJExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    @State private var fromDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var tagFilter: String = ""
    @State private var lastError: String = ""
    @State private var shareData: Data? = nil
    @State private var shareName: String = "nj_export.json"
    @State private var showingShare = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date Range")) {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, displayedComponents: .date)
                }

                Section(header: Text("Tag Filter (optional)")) {
                    TextField("#REMIND", text: $tagFilter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Export JSON") { exportNow() }
                }

                if !lastError.isEmpty {
                    Section {
                        Text(lastError).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShare) {
                if let shareData {
                    NJShareSheet(items: [NJShareItem(data: shareData, filename: shareName)])
                }
            }
        }
    }

    private func exportNow() {
        lastError = ""
        do {
            let tzID = "Asia/Hong_Kong"
            let tag = tagFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            let tagOpt: String? = tag.isEmpty ? nil : tag

            let data = try NJBlockExporter.exportJSON(
                tzID: tzID,
                fromDate: fromDate,
                toDate: toDate,
                tagFilter: tagOpt,
                fetchRows: {
                    try store.notes.exportBlockRows(fromDate: fromDate, toDate: toDate, tagFilter: tagOpt)
                }
            )

            shareData = data
            shareName = "nj_export_\(Int(Date().timeIntervalSince1970)).json"
            showingShare = true
        } catch {
            lastError = "\(error)"
        }
    }
}
