//
//  NJReconstructedTagMatch.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/23.
//


import Foundation

enum NJReconstructedTagMatch: Equatable {
    case exact(String)
    case prefix(String)
}

enum NJReconstructedTimeField: Equatable {
    case blockCreatedAtMs
    case tagCreatedAtMs
}

struct NJReconstructedSpec: Equatable, Identifiable {
    let id: String

    var title: String
    var tab: String

    var match: NJReconstructedTagMatch
    var timeField: NJReconstructedTimeField

    var startMs: Int64?
    var endMs: Int64?

    var limit: Int
    var newestFirst: Bool

    static func weekly() -> NJReconstructedSpec {
        NJReconstructedSpec(
            id: "recon:#WEEKLY",
            title: "WEEKLY",
            tab: "RECONSTRUCTED",
            match: .exact("#WEEKLY"),
            timeField: .blockCreatedAtMs,
            startMs: nil,
            endMs: nil,
            limit: 500,
            newestFirst: true
        )
    }

    static func tagExact(_ tag: String, startMs: Int64? = nil, endMs: Int64? = nil, timeField: NJReconstructedTimeField = .blockCreatedAtMs, limit: Int = 500, newestFirst: Bool = true) -> NJReconstructedSpec {
        NJReconstructedSpec(
            id: "recon:exact:\(tag):\(startMs ?? 0):\(endMs ?? 0):\(timeField)",
            title: tag,
            tab: "RECONSTRUCTED",
            match: .exact(tag),
            timeField: timeField,
            startMs: startMs,
            endMs: endMs,
            limit: limit,
            newestFirst: newestFirst
        )
    }

    static func tagPrefix(_ prefix: String, startMs: Int64? = nil, endMs: Int64? = nil, timeField: NJReconstructedTimeField = .blockCreatedAtMs, limit: Int = 500, newestFirst: Bool = true) -> NJReconstructedSpec {
        NJReconstructedSpec(
            id: "recon:prefix:\(prefix):\(startMs ?? 0):\(endMs ?? 0):\(timeField)",
            title: prefix,
            tab: "RECONSTRUCTED",
            match: .prefix(prefix),
            timeField: timeField,
            startMs: startMs,
            endMs: endMs,
            limit: limit,
            newestFirst: newestFirst
        )
    }
}
