//
//  NJBlockEvent.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/3.
//


import Foundation

enum NJBlockEvent: Hashable {
    case focus(UUID)
    case ctrlReturn(UUID)
    case delete(UUID)
}

final class NJBlockEventBus {
    private var handler: ((NJBlockEvent) -> Void)?

    func setHandler(_ h: @escaping (NJBlockEvent) -> Void) {
        handler = h
    }

    func send(_ e: NJBlockEvent) {
        handler?(e)
    }

    func focus(_ id: UUID) { send(.focus(id)) }
    func ctrlReturn(_ id: UUID) { send(.ctrlReturn(id)) }
    func delete(_ id: UUID) { send(.delete(id)) }
}
