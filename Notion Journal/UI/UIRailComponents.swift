//
//  Rail.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/6.
//

import SwiftUI
import UIKit

struct Rail: View {
    @EnvironmentObject var store: AppStore
    let onChanged: () -> Void

    private let railWidth: CGFloat = 72
    private let spacing: CGFloat = 12
    private let tabMin: CGFloat = 72
    private let tabMax: CGFloat = 176

    @State private var didRunBLOnce = false

    var body: some View {
        GeometryReader { g in
            let H = g.size.height
            let tabCount = store.tabsForSelectedNotebook.count

            let topBottomPad: CGFloat = 24
            let usableForTabs = max(0, H - topBottomPad - (tabCount > 0 ? spacing * CGFloat(max(0, tabCount - 1)) : 0))

            let rawTab = tabCount > 0 ? usableForTabs / CGFloat(tabCount) : tabMax
            let tabHeight = min(tabMax, max(tabMin, rawTab))

            let small = tabHeight < 100
            let tabFontSize: CGFloat = small ? 10 : 12
            let tabLineLimit = 2

            VStack(spacing: spacing) {
                ForEach(store.tabsForSelectedNotebook) { t in
                    RailButton(
                        title: t.title,
                        isOn: store.selectedTabID == t.tabID,
                        railWidth: railWidth,
                        buttonHeight: tabHeight,
                        fontSize: tabFontSize,
                        lineLimit: tabLineLimit,
                        colorHex: t.colorHex
                    ) {
                        store.selectTab(t.tabID)
//                        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                        onChanged()
                    }
                }

                Spacer(minLength: 0)
            }
            .onAppear {
                if didRunBLOnce { return }
                didRunBLOnce = true
//                NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                onChanged()
            }
            .padding(.vertical, 12)
            .frame(width: railWidth)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .frame(width: railWidth)
    }
}

struct RailButton: View {
    let title: String
    let isOn: Bool
    let railWidth: CGFloat
    let buttonHeight: CGFloat
    let fontSize: CGFloat
    let lineLimit: Int
    let colorHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RotatedWrapLabel(
                text: title,
                railWidth: railWidth,
                buttonHeight: buttonHeight,
                fontSize: fontSize,
                lineLimit: lineLimit,
                isOn: isOn,
                colorHex: colorHex
            )
        }
        .buttonStyle(.plain)
        .frame(width: railWidth, height: buttonHeight)
    }
}

struct RotatedWrapLabel: View {
    let text: String
    let railWidth: CGFloat
    let buttonHeight: CGFloat
    let fontSize: CGFloat
    let lineLimit: Int
    let isOn: Bool
    let colorHex: String

    var body: some View {
        let padH: CGFloat = 10
        let padV: CGFloat = 10
        let wrapWidth = max(10, buttonHeight - padV * 2)
        let wrapHeight = max(10, railWidth - padH * 2)

        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isOn ? Color(hex: colorHex).opacity(0.22) : Color.clear)
                .frame(width: railWidth, height: buttonHeight)

            VStack(spacing: 6) {
                Text(text)
                    .font(.system(size: fontSize, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .frame(width: wrapWidth, height: wrapHeight, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: railWidth, height: buttonHeight)
        .contentShape(Rectangle())
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s = "FF" + s }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let a = Double((v & 0xFF000000) >> 24) / 255.0
        let r = Double((v & 0x00FF0000) >> 16) / 255.0
        let g = Double((v & 0x0000FF00) >> 8) / 255.0
        let b = Double(v & 0x000000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = Int(round(r * 255))
        let G = Int(round(g * 255))
        let B = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", R, G, B)
    }
}
