//
//  NJBlockType.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/3.
//


import Foundation

enum NJBlockType: String, Codable, CaseIterable {
    case textRTF = "text_rtf"
    case clip = "clip"
}

struct NJBlockDescriptor: Hashable, Codable {
    let type: NJBlockType
    let displayName: String
}

enum NJBlockRegistry {
    static let descriptors: [NJBlockType: NJBlockDescriptor] = [
        .textRTF: NJBlockDescriptor(type: .textRTF, displayName: "Text (RTF)"),
        .clip: NJBlockDescriptor(type: .clip, displayName: "Clip")
    ]

    static func descriptor(for type: NJBlockType) -> NJBlockDescriptor? {
        descriptors[type]
    }

    static func descriptor(for rawType: String) -> NJBlockDescriptor? {
        guard let t = NJBlockType(rawValue: rawType) else { return nil }
        return descriptors[t]
    }

    static var all: [NJBlockDescriptor] {
        Array(descriptors.values)
    }
}
