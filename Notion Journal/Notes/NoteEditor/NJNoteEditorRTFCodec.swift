//
//  NJNoteEditorRTFCodec.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/4.
//


import UIKit

let NJ_BLOCK_SENTINEL = "\n\n<<<NJ_BLOCK_BREAK_v1>>>\n\n"
let NJ_ZWSP: UInt16 = 8203

func baseAttrs() -> [NSAttributedString.Key: Any] {
    let p = NSMutableParagraphStyle()
    p.alignment = .left
    p.firstLineHeadIndent = 0
    p.headIndent = 0
    p.tailIndent = 0
    return [
        .font: UIFont.systemFont(ofSize: 17),
        .foregroundColor: UIColor.label,
        .paragraphStyle: p
    ]
}

func makeEmptyBlockAttr() -> NSAttributedString {
    NSAttributedString(string: String(UnicodeScalar(Int(NJ_ZWSP))!), attributes: baseAttrs())
}

func makeTaggedBlockAttr(tag: String) -> NSAttributedString {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return makeEmptyBlockAttr() }
    let line = "@tag: \(trimmed)\n"
    let zwsp = String(UnicodeScalar(Int(NJ_ZWSP))!)
    return NSAttributedString(string: line + zwsp, attributes: baseAttrs())
}

func ensureNonEmptyTyped(_ a: NSAttributedString) -> NSAttributedString {
    if a.length == 0 { return makeEmptyBlockAttr() }
    if a.length == 1 {
        let ch = (a.string as NSString).character(at: 0)
        if ch == NJ_ZWSP { return a }
    }
    return a
}

func stripZWSP(_ a: NSAttributedString) -> NSAttributedString {
    if a.length == 0 { return a }
    let s = a.string as NSString
    let out = NSMutableAttributedString()
    for i in 0..<s.length {
        let ch = s.character(at: i)
        if ch != NJ_ZWSP {
            out.append(a.attributedSubstring(from: NSRange(location: i, length: 1)))
        }
    }
    return out
}

func trimNewlines(_ a: NSAttributedString) -> NSAttributedString {
    let s = a.string as NSString
    var lo = 0
    var hi = s.length
    while lo < hi {
        let ch = s.character(at: lo)
        if ch == 10 || ch == 13 { lo += 1 } else { break }
    }
    while hi > lo {
        let ch = s.character(at: hi - 1)
        if ch == 10 || ch == 13 { hi -= 1 } else { break }
    }
    if hi <= lo { return NSAttributedString(string: "") }
    return a.attributedSubstring(from: NSRange(location: lo, length: hi - lo))
}

func splitAttributed(_ a: NSAttributedString, sentinel: String) -> [NSAttributedString] {
    if a.length == 0 { return [] }
    let s = a.string as NSString
    var out: [NSAttributedString] = []
    var start = 0
    while true {
        let r = s.range(of: sentinel, options: [], range: NSRange(location: start, length: s.length - start))
        if r.location == NSNotFound { break }
        out.append(trimNewlines(a.attributedSubstring(from: NSRange(location: start, length: r.location - start))))
        start = r.location + r.length
    }
    out.append(trimNewlines(a.attributedSubstring(from: NSRange(location: start, length: s.length - start))))
    return out.filter { $0.length > 0 }
}

func joinBlocks(_ blocks: [NSAttributedString], sentinel: String) -> NSAttributedString {
    let m = NSMutableAttributedString()
    for i in 0..<blocks.count {
        if i > 0 { m.append(NSAttributedString(string: sentinel)) }
        m.append(blocks[i])
    }
    return m
}
