//
//  Notebook.swift
//  Notion Journal
//
//  Created by Mac on 2025/12/30.
//


import Foundation

enum Notebook: String, CaseIterable, Identifiable {
    case selfBook = "Self"
    case zz = "ZZ"
    var id: String { rawValue }

    var tabs: [NotebookTab] {
        switch self {
        case .zz: return [.zzEdu, .zzAdhd]
        case .selfBook: return [.selfReflection, .selfFinance, .selfMarriage]
        }
    }

    var defaultTab: NotebookTab {
        tabs.first!
    }
}

enum NotebookTab: String, CaseIterable, Identifiable {
    case zzEdu = "EDU"
    case zzAdhd = "ADHD"
    case selfReflection = "Reflection"
    case selfFinance = "Finance"
    case selfMarriage = "Marriage"
    var id: String { rawValue }

    var notebook: Notebook {
        switch self {
        case .zzEdu, .zzAdhd: return .zz
        case .selfReflection, .selfFinance, .selfMarriage: return .selfBook
        }
    }

    var domainKey: String {
        switch self {
        case .zzEdu: return "zz.edu"
        case .zzAdhd: return "zz.adhd"
        case .selfReflection: return "self.reflection"
        case .selfFinance: return "self.finance"
        case .selfMarriage: return "self.marriage"
        }
    }
}
