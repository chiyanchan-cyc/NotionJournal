//
//  NJNoteCloudMapper.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/3.
//


import Foundation

enum NJNoteCloudMapper {
    static let entity = "note"
    
    static let recordType = "NJNote"


    static func isEntity(_ s: String) -> Bool { s == entity }

    static func validateFields(_ f: [String: Any]) -> Bool {
        f["note_id"] != nil || f["noteID"] != nil
    }
}
