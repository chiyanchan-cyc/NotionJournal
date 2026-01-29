//
//  NJShareSheet.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/29.
//


import SwiftUI
import UIKit

struct NJShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
