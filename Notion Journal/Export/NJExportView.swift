import SwiftUI
import Foundation
import UIKit

struct NJExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    @State private var fromDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var toDate: Date = Date()
    @State private var tagFilter: String = ""
    @State private var lastError: String = ""

    @State private var exportURL: URL? = nil
    @State private var showingExporter = false
    @State private var showingShare = false
    @State private var showErrorAlert = false
    @State private var lastCount: Int = 0

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date Range")) {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    DatePicker("To", selection: $toDate, displayedComponents: .date)
                }

                Section(header: Text("Tag Filter (optional)")) {
                    TextField("e.g. zz.* or #REMIND", text: $tagFilter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Export JSON") { exportNow() }
                    Button("Copy JSON to Clipboard") { copyNow() }
                }

                Section(header: Text("Last Export")) {
                    Text("Blocks: \(lastCount)")
                }

                if !lastError.isEmpty {
                    Section { Text(lastError).foregroundColor(.red) }
                }
            }
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingExporter) {
                if let url = exportURL {
                    NJDocumentExporter(url: url)
                }
            }
            .sheet(isPresented: $showingShare) {
                if let url = exportURL {
                    NJShareSheet(items: [url])
                }
            }
            .alert("Export failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lastError)
            }
        }
    }

    private func exportNow() {
        lastError = ""
        do {
            let (url, count) = try buildExportFileAndCount()
            exportURL = url
            lastCount = count

            if ProcessInfo.processInfo.isMacCatalystApp {
                showingExporter = true
            } else {
                showingShare = true
            }
        } catch {
            lastError = "\(error)"
            showErrorAlert = true
        }
    }

    private func copyNow() {
        lastError = ""
        do {
            let (data, count) = try buildExportDataAndCount()
            lastCount = count
            UIPasteboard.general.string = String(data: data, encoding: .utf8) ?? ""
        } catch {
            lastError = "\(error)"
            showErrorAlert = true
        }
    }

    private func buildExportDataAndCount() throws -> (Data, Int) {
        let tzID = "Asia/Hong_Kong"
        let tag = tagFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagOpt: String? = tag.isEmpty ? nil : tag

        var rowsCount = 0

        let data = try NJBlockExporter.exportJSON(
            tzID: tzID,
            fromDate: fromDate,
            toDate: toDate,
            tagFilter: tagOpt,
            fetchRows: {
                let rows = try store.notes.exportBlockRows(fromDate: fromDate, toDate: toDate, tagFilter: tagOpt)
                rowsCount = rows.count
                return rows
            }
        )

        return (data, rowsCount)
    }

    private func buildExportFileAndCount() throws -> (URL, Int) {
        let (data, count) = try buildExportDataAndCount()
        let filename = "nj_export_\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic])
        return (url, count)
    }
}
