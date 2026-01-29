//
//  NJBlockExportBundle.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/29.
//


import Foundation

struct NJBlockExportBundle: Codable {
    let schema: String
    let range: NJExportRange
    let tag_filter: String?
    let count: Int
    let blocks: [NJBlockExportItem]
}

struct NJExportRange: Codable {
    let from: String
    let to: String
    let tz: String
}

struct NJBlockExportItem: Codable {
    let ts_ms: Int64
    let note_id: String
    let block_id: String
    let note_domain: String
    let block_domain: String?
    let block_tags: [String]
    let body: String
}
