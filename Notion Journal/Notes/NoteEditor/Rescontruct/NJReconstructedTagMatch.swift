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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1 // Sunday

        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfDay) // 1 = Sunday
        let daysFromSunday = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -daysFromSunday, to: startOfDay) ?? startOfDay
        let endExclusive = calendar.date(byAdding: .day, value: 7, to: start) ?? now

        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000) - 1

        return NJReconstructedSpec(
            id: "recon:#WEEKLY",
            title: "WEEKLY",
            tab: "RECONSTRUCTED",
            match: .exact("#WEEKLY"),
            timeField: .blockCreatedAtMs,
            startMs: startMs,
            endMs: endMs,
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
