//
//  NJDocumentExporter.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/29.
//


import SwiftUI
import UIKit

struct NJDocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        vc.shouldShowFileExtensions = true
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
