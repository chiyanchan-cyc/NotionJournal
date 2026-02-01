import SwiftUI
import UIKit
import Proton
import ProtonCore
import ObjectiveC.runtime


enum NJListKind: String {
    case bullet
    case number
}
private var NJTextViewHandleKey: UInt8 = 0
private var NJKeyCommandsOriginalIMP: IMP?

private var NJEditorViewHandleKey: UInt8 = 0

private extension EditorView {
    var njProtonHandle: NJProtonEditorHandle? {
        get { objc_getAssociatedObject(self, &NJEditorViewHandleKey) as? NJProtonEditorHandle }
        set { objc_setAssociatedObject(self, &NJEditorViewHandleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

private func NJStandardizeFontFamily(_ font: UIFont) -> UIFont {
    let fd = font.fontDescriptor
    if fd.symbolicTraits.contains(.traitMonoSpace) { return font }

    let size = font.pointSize

    let wRaw = (fd.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat
    let w0 = UIFont.Weight(wRaw ?? UIFont.Weight.regular.rawValue)

    let hadBoldTrait = fd.symbolicTraits.contains(.traitBold)
    let hadItalic = fd.symbolicTraits.contains(.traitItalic)

    let isBold = hadBoldTrait || (w0 >= .semibold)

    let w: UIFont.Weight = isBold ? (w0 < .semibold ? .semibold : w0) : .light
    let base = UIFont.systemFont(ofSize: size, weight: w)

    var keep: UIFontDescriptor.SymbolicTraits = []
    if hadItalic { keep.insert(.traitItalic) }

    if keep.isEmpty { return base }
    if let nfd = base.fontDescriptor.withSymbolicTraits(keep) {
        return UIFont(descriptor: nfd, size: size)
    }
    return base
}

private func NJStandardizeFontFamily(_ s: NSAttributedString) -> NSAttributedString {
    if s.length == 0 { return s }
    let m = NSMutableAttributedString(attributedString: s)
    let full = NSRange(location: 0, length: m.length)
    m.beginEditing()
    m.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
        guard let old = value as? UIFont else { return }
        let nf = NJStandardizeFontFamily(old)
        if nf.fontName != old.fontName || nf.pointSize != old.pointSize {
            m.addAttribute(.font, value: nf, range: range)
        }
    }
    m.endEditing()
    return m
}

private extension NSAttributedString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
}

private extension UITextView {
    var njProtonHandle: NJProtonEditorHandle? {
        get { objc_getAssociatedObject(self, &NJTextViewHandleKey) as? NJProtonEditorHandle }
        set { objc_setAssociatedObject(self, &NJTextViewHandleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func nj_log(_ name: StaticString) {
        let tvID = ObjectIdentifier(self)
        let hID = self.njProtonHandle.map { ObjectIdentifier($0) }
        NJShortcutLog.info("\(name) tv=\(String(describing: tvID)) handle=\(String(describing: hID))")
    }

    func nj_fire(_ name: StaticString, _ f: (NJProtonEditorHandle) -> Void) {
        nj_log(name)
        guard let h = self.njProtonHandle else { return }
        f(h)
        h.snapshot()
        if !self.isFirstResponder { self.becomeFirstResponder() }
    }

    @objc func nj_tabIndent() { nj_fire("TAB INDENT") { $0.indent() } }
    @objc func nj_tabOutdent() { nj_fire("TAB OUTDENT") { $0.outdent() } }

    @objc func nj_cmdBold() { nj_fire("CMD+B") { $0.toggleBold() } }
    @objc func nj_cmdItalic() { nj_fire("CMD+I") { $0.toggleItalic() } }
    @objc func nj_cmdUnderline() { nj_fire("CMD+U") { $0.toggleUnderline() } }
    @objc func nj_cmdStrike() { nj_fire("SHIFT+CMD+X") { $0.toggleStrike() } }

    @objc func nj_cmdIndent() { nj_fire("CMD+]") { $0.indent() } }
    @objc func nj_cmdOutdent() { nj_fire("CMD+[") { $0.outdent() } }

    @objc func nj_cmdBullet() { nj_fire("CMD+7") { $0.toggleBullet() } }
    @objc func nj_cmdNumber() { nj_fire("CMD+8") { $0.toggleNumber() } }
    
}


import os

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "KeyCommands")
private var NJKeyCommandsOriginalIMPByClass: [ObjectIdentifier: IMP] = [:]

private func NJInstallTextViewKeyCommandHook(_ tv: UITextView) {
    let cls: AnyClass = object_getClass(tv) ?? UITextView.self
    let key = ObjectIdentifier(cls)
    if NJKeyCommandsOriginalIMPByClass[key] != nil { return }

    let sel = #selector(getter: UIResponder.keyCommands)
    guard let method = class_getInstanceMethod(cls, sel) else { return }

    let origIMP = method_getImplementation(method)
    NJKeyCommandsOriginalIMPByClass[key] = origIMP

    typealias OrigFn = @convention(c) (AnyObject, Selector) -> [UIKeyCommand]?
    let newBlock: @convention(block) (UITextView) -> [UIKeyCommand]? = { t in
        var existing: [UIKeyCommand] = []
        if let imp = NJKeyCommandsOriginalIMPByClass[key] {
            let f = unsafeBitCast(imp, to: OrigFn.self)
            existing = f(t, sel) ?? []
        }

        guard t.njProtonHandle != nil else { return existing }

        let mk: (String, UIKeyModifierFlags, Selector) -> UIKeyCommand = { input, flags, action in
            let c = UIKeyCommand(input: input, modifierFlags: flags, action: action)
            c.wantsPriorityOverSystemBehavior = true
            return c
        }

        return existing + [
            mk("\t", [], #selector(UITextView.nj_tabIndent)),
            mk("\t", [.shift], #selector(UITextView.nj_tabOutdent)),
            mk("b", .command, #selector(UITextView.nj_cmdBold)),
            mk("i", .command, #selector(UITextView.nj_cmdItalic)),
            mk("u", .command, #selector(UITextView.nj_cmdUnderline)),
            mk("x", [.command, .shift], #selector(UITextView.nj_cmdStrike)),
            mk("]", .command, #selector(UITextView.nj_cmdIndent)),
            mk("[", .command, #selector(UITextView.nj_cmdOutdent)),
            mk("7", .command, #selector(UITextView.nj_cmdBullet)),
            mk("8", .command, #selector(UITextView.nj_cmdNumber))
        ]

    }

    let newIMP = imp_implementationWithBlock(newBlock)
    method_setImplementation(method, newIMP)
}


final class NJProtonListFormattingProvider: EditorListFormattingProvider {
    let listLineFormatting = LineFormatting(indentation: 24, spacingBefore: 2, spacingAfter: 2)
    private let font: UIFont = .systemFont(ofSize: 17, weight: .light)

    func listLineMarkerFor(editor: EditorView, index: Int, level: Int, previousLevel: Int, attributeValue: Any?) -> ListLineMarker {
        let kind: NJListKind = {
            if let tl = attributeValue as? NSTextList {
                return tl.markerFormat == .decimal ? .number : .bullet
            }
            if let tls = attributeValue as? [NSTextList], let tl = tls.first {
                return tl.markerFormat == .decimal ? .number : .bullet
            }
            if let s = attributeValue as? String, let k = NJListKind(rawValue: s) {
                return k
            }

            return .bullet
        }()

        let markerAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label
        ]

        switch kind {
        case .bullet:
            return .string(NSAttributedString(string: "•", attributes: markerAttrs))
        case .number:
            return .string(NSAttributedString(string: "\(index + 1).", attributes: markerAttrs))
        }
    }
}

final class NJProtonRoundTripDebugVC: UIViewController {
    private let jsonView = UITextView()
    private let previewHost: UIViewController

    init(json: String, previewAttr: NSAttributedString) {
        let handle = NJProtonEditorHandle()

        struct PreviewShell: View {
            let attr: NSAttributedString
            let handle: NJProtonEditorHandle

            @State private var snapshotAttr: NSAttributedString
            @State private var snapshotSel: NSRange = NSRange(location: 0, length: 0)
            @State private var h: CGFloat = 44

            init(attr: NSAttributedString, handle: NJProtonEditorHandle) {
                self.attr = attr
                self.handle = handle
                _snapshotAttr = State(initialValue: attr)
            }

            var body: some View {
                NJProtonEditorView(
                    initialAttributedText: attr,
                    initialSelectedRange: NSRange(location: 0, length: 0),
                    snapshotAttributedText: $snapshotAttr,
                    snapshotSelectedRange: $snapshotSel,
                    measuredHeight: $h,
                    handle: handle
                )
                .frame(minHeight: h)
            }
        }

        previewHost = UIHostingController(rootView: PreviewShell(attr: previewAttr, handle: handle))

        super.init(nibName: nil, bundle: nil)

        jsonView.text = json
        jsonView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        jsonView.isEditable = false
        jsonView.alwaysBounceVertical = true
    }


    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.addTarget(self, action: #selector(onClose), for: .touchUpInside)

        let top = UIView()
        top.translatesAutoresizingMaskIntoConstraints = false
        close.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(close)

        jsonView.translatesAutoresizingMaskIntoConstraints = false
        previewHost.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(previewHost)
        view.addSubview(top)
        view.addSubview(jsonView)
        view.addSubview(previewHost.view)
        previewHost.didMove(toParent: self)

        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            top.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 44),

            close.trailingAnchor.constraint(equalTo: top.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: top.centerYAnchor),

            jsonView.topAnchor.constraint(equalTo: top.bottomAnchor),
            jsonView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            jsonView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            jsonView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55),

            previewHost.view.topAnchor.constraint(equalTo: jsonView.bottomAnchor),
            previewHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewHost.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func onClose() {
        dismiss(animated: true)
    }
}

private func NJPresentRoundTripDebug(json: String, previewAttr: NSAttributedString) {
    DispatchQueue.main.async {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        let vc = NJProtonRoundTripDebugVC(json: json, previewAttr: previewAttr)
        vc.modalPresentationStyle = .pageSheet

        var top = root
        while let p = top.presentedViewController { top = p }
        top.present(vc, animated: true)
    }
}

func NJPresentDebugPopup(title: String, body: NSAttributedString) {
    struct ProtonPopupView: View {
        let title: String
        let bodyAttr: NSAttributedString
        let handle: NJProtonEditorHandle

        @Environment(\.dismiss) private var dismiss
        @State private var sel: NSRange = NSRange(location: 0, length: 0)
        @State private var h: CGFloat = 44

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Button("Close") { dismiss() }
                }
                .padding(12)

                Divider()

                ScrollView {
                    NJProtonEditorView(
                        initialAttributedText: bodyAttr,
                        initialSelectedRange: sel,
                        snapshotAttributedText: .constant(bodyAttr),
                        snapshotSelectedRange: $sel,
                        measuredHeight: $h,
                        handle: handle
                    )
                    .frame(minHeight: h)
                    .padding(12)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    let handle = NJProtonEditorHandle()
    let vc = UIHostingController(rootView: ProtonPopupView(title: title, bodyAttr: body, handle: handle))
    vc.modalPresentationStyle = UIModalPresentationStyle.pageSheet

    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
        return
    }

    var top = root
    while let p = top.presentedViewController { top = p }
    top.present(vc, animated: true)
}

typealias NJProtonAuditJSON = [String: Any]

struct NJProtonAuditJSONEncoder: EditorContentEncoder {
    let textEncoders: [EditorContent.Name: AnyEditorTextEncoding<NJProtonAuditJSON>] = [
        .paragraph: AnyEditorTextEncoding(NJAuditParagraphEncoder()),
        .text: AnyEditorTextEncoding(NJAuditTextEncoder())
    ]

    let attachmentEncoders: [EditorContent.Name: AnyEditorContentAttachmentEncoding<NJProtonAuditJSON>] = [:]
}

private struct NJAuditParagraphEncoder: EditorTextEncoding {
    func encode(name: EditorContent.Name, string: NSAttributedString) -> NJProtonAuditJSON {
        var json: NJProtonAuditJSON = [:]
        json["type"] = name.rawValue

        let full = NSRange(location: 0, length: string.length)

        var paragraphStyleJSON: NJProtonAuditJSON?
        string.enumerateAttribute(.paragraphStyle, in: full, options: []) { value, _, stop in
            if let ps = value as? NSParagraphStyle {
                paragraphStyleJSON = ps.nj_auditJSONValue
                stop.pointee = true
            }
        }
        if let paragraphStyleJSON {
            json["paragraphStyle"] = paragraphStyleJSON
        }

        var out: [NJProtonAuditJSON] = []
        string.enumerateAttributes(in: full, options: []) { _, range, _ in
            let sub = string.attributedSubstring(from: range)
            let enc = NJAuditTextEncoder()
            out.append(enc.encode(name: .text, string: sub))
        }
        json["contents"] = out

        return json
    }
}

private struct NJAuditTextEncoder: EditorTextEncoding {
    func encode(name: EditorContent.Name, string: NSAttributedString) -> NJProtonAuditJSON {
        var json: NJProtonAuditJSON = [:]
        json["type"] = name.rawValue
        json["text"] = string.string

        let full = NSRange(location: 0, length: string.length)
        var attributesJSON: NJProtonAuditJSON = [:]

        string.enumerateAttributes(in: full, options: []) { attrs, _, stop in
            for (k, v) in attrs {
                if k == .font, let font = v as? UIFont {
                    attributesJSON["font"] = font.nj_auditJSONValue
                } else if k == .paragraphStyle, let ps = v as? NSParagraphStyle {
                    attributesJSON["paragraphStyle"] = ps.nj_auditJSONValue
                } else if k == .foregroundColor, let c = v as? UIColor {
                    attributesJSON["foregroundColor"] = c.nj_auditRGBAJSONValue
                } else if k == .backgroundColor, let c = v as? UIColor {
                    attributesJSON["backgroundColor"] = c.nj_auditRGBAJSONValue
                } else if k == .underlineStyle {
                    attributesJSON["underline"] = true
                } else if k == .strikethroughStyle {
                    attributesJSON["strike"] = true
                }
            }
            stop.pointee = true
        }

        if !attributesJSON.isEmpty {
            json["attributes"] = attributesJSON
        }

        return json
    }
}

private extension UIFont {
    var nj_auditJSONValue: NJProtonAuditJSON {
        let d = fontDescriptor
        return [
            "name": fontName,
            "family": familyName,
            "size": d.pointSize,
            "isBold": d.symbolicTraits.contains(.traitBold),
            "isItalics": d.symbolicTraits.contains(.traitItalic),
            "isMonospace": d.symbolicTraits.contains(.traitMonoSpace),
            "textStyle": d.object(forKey: .textStyle) as? String ?? "UICTFontTextStyleBody"
        ]
    }
}

private extension NSParagraphStyle {
    var nj_auditJSONValue: NJProtonAuditJSON {
        var o: NJProtonAuditJSON = [
            "alignment": alignment.rawValue,
            "firstLineHeadIndent": firstLineHeadIndent,
            "headIndent": headIndent,
            "tailIndent": tailIndent,
            "lineSpacing": lineSpacing,
            "paragraphSpacing": paragraphSpacing,
            "paragraphSpacingBefore": paragraphSpacingBefore,
            "lineHeightMultiple": lineHeightMultiple,
            "minimumLineHeight": minimumLineHeight,
            "maximumLineHeight": maximumLineHeight
        ]

        if !textLists.isEmpty {
            o["textLists"] = textLists.map { tl in
                [
                    "markerFormat": (tl.markerFormat == .decimal) ? "decimal" : "disc",
                    "startingItemNumber": tl.startingItemNumber
                ]
            }
        }

        return o
    }
}

private extension UIColor {
    var nj_auditRGBAJSONValue: NJProtonAuditJSON {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return ["r": r, "g": g, "b": b, "a": a]
    }
}

private func NJApplyBaseFontWhereMissing(_ input: NSAttributedString, baseFont: UIFont) -> NSAttributedString {
    if input.length == 0 { return input }
    let m = NSMutableAttributedString(attributedString: input)
    let full = NSRange(location: 0, length: m.length)
    m.beginEditing()
    m.enumerateAttribute(.font, in: full, options: []) { v, r, _ in
        if v == nil {
            m.addAttribute(.font, value: baseFont, range: r)
        }
    }
    m.endEditing()
    return m
}

final class NJProtonEditorHandle {
    weak var editor: EditorView?
    var debugName: String = ""
    var ownerBlockUUID: UUID? = nil
    var isEditing: Bool = false
    var withProgrammatic: (((() -> Void)) -> Void)? = nil
    
    var onSnapshot: ((NSAttributedString, NSRange) -> Void)?
    var onUserTyped: ((NSAttributedString, NSRange) -> Void)?
    var onEndEditing: ((NSAttributedString, NSRange) -> Void)?
    
    private var pendingHydrateProtonJSON: String? = nil

    func indent() { adjustIndent(delta: 24) }
    func outdent() { adjustIndent(delta: -24) }
    
    func exportProtonJSONString() -> String {
        guard let editor else { return "" }
        return NJProtonDocCodecV1.encodeDocument(from: editor.attributedText)
    }
    
    func previewFirstLineFromProtonJSON(_ json: String) -> String {
        let decoded: NSAttributedString = {
            if let doc = NJProtonDocCodecV1.decodeIfPresent(json: json) {
                return NJProtonDocCodecV1.buildAttributedString(doc: doc)
            }
            if let nodes = NJProtonNodeCodecV1.decodeNodesIfPresent(json: json) {
                return NJProtonNodeCodecV1.buildAttributedString(nodes: nodes)
            }
            let mode = njDefaultContentMode()
            let maxSize = CGSize(width: 4096, height: 4096)
            let a = (try? NJProtonAuditCodec.decoder.decodeDocument(mode: mode, maxSize: maxSize, json: json)) ?? NSAttributedString(string: "")
            return NJProtonListFixups.apply(a)
        }()

        let s = decoded.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        return s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    private struct NJProtonDocCodecV1 {

        private static let schema = "nj_proton_doc_v1"
        private static let indentUnit: CGFloat = 24

        static func encodeDocument(from text: NSAttributedString) -> String {
            let doc = buildDoc(from: text)
            let root: [String: Any] = ["schema": schema, "doc": doc]
            guard JSONSerialization.isValidJSONObject(root) else { return "" }
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: []) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }

        static func decodeIfPresent(json: String) -> [[String: Any]]? {
            guard let data = json.data(using: .utf8) else { return nil }
            guard let rootAny = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
            guard let root = rootAny as? [String: Any] else { return nil }
            guard (root["schema"] as? String) == schema else { return nil }
            guard let docAny = root["doc"] as? [Any] else { return nil }
            let doc = docAny.compactMap { $0 as? [String: Any] }
            return doc.isEmpty ? nil : doc
        }

        static func buildAttributedString(doc: [[String: Any]]) -> NSAttributedString {
            let out = NSMutableAttributedString()

            for seg in doc {
                let t = (seg["type"] as? String) ?? ""

                if t == "rich" {
                    let b64 = (seg["rtf_base64"] as? String) ?? ""
                    if let a = decodeRTFBase64(b64) {
                        out.append(a)
                    }
                    continue
                }

                if t == "list" {
                    let itemsAny = (seg["items"] as? [Any]) ?? []
                    let items = itemsAny.compactMap { $0 as? [String: Any] }

                    var listItems: [ListItem] = []
                    listItems.reserveCapacity(items.count)

                    for it in items {
                        let lvl = max(0, (it["level"] as? Int) ?? 0)
                        let kind = (it["kind"] as? String) ?? "bullet"
                        let b64 = (it["rtf_base64"] as? String) ?? ""
                        let text = decodeRTFBase64(b64) ?? NSAttributedString(string: "")
                        listItems.append(ListItem(text: text, level: lvl, attributeValue: kind))
                    }

                    let parsed = ListParser.parse(list: listItems, indent: indentUnit)
                    let a = NSMutableAttributedString(attributedString: parsed)

                    func hasStrike(_ s: NSAttributedString) -> Bool {
                        if s.length == 0 { return false }
                        var hit = false
                        s.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: s.length), options: []) { v, _, stop in
                            if let i = v as? Int, i != 0 {
                                hit = true
                                stop.pointee = true
                            }
                        }
                        return hit
                    }

                    let ns = a.string as NSString
                    var loc = 0
                    var itemIdx = 0

                    while loc < ns.length && itemIdx < listItems.count {
                        let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                        if hasStrike(listItems[itemIdx].text) {
                            var rr = pr
                            if rr.length > 0 {
                                let last = ns.character(at: rr.location + rr.length - 1)
                                if last == 10 || last == 13 { rr.length -= 1 }
                            }
                            if rr.length > 0 {
                                a.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: rr)
                            }
                        }
                        loc = pr.location + pr.length
                        itemIdx += 1
                    }

                    let ns2 = a.string as NSString
                    if ns2.length == 0 || ns2.character(at: ns2.length - 1) != 10 {
                        a.append(NSAttributedString(string: "\n"))
                    }

                    out.append(a)
                    continue
                }
            }

            return out
        }


        private static func buildDoc(from text: NSAttributedString) -> [[String: Any]] {
            let fullLen = text.length
            if fullLen == 0 {
                return [["type": "rich", "rtf_base64": encodeRTFBase64(text) ?? ""]]
            }

            let parsed = ListParser.parse(attributedString: text, indent: indentUnit)
            if parsed.isEmpty {
                return [["type": "rich", "rtf_base64": encodeRTFBase64(text) ?? ""]]
            }

            struct CapturedItem {
                let paraRange: NSRange
                let listItem: ListItem
            }

            struct ListBlock {
                let start: Int
                let end: Int
                let items: [ListItem]
            }

            let s = text.string as NSString

            var captured: [CapturedItem] = []
            captured.reserveCapacity(parsed.count)

            for p in parsed {
                let paraRange = s.paragraphRange(for: NSRange(location: p.range.location, length: 0))
                captured.append(CapturedItem(paraRange: paraRange, listItem: normalizeListItem(p.listItem)))
            }

            captured.sort { $0.paraRange.location < $1.paraRange.location }

            var blocks: [ListBlock] = []
            blocks.reserveCapacity(captured.count)

            var curItems: [ListItem] = []
            var curStart = 0
            var curEnd = 0

            for it in captured {
                if curItems.isEmpty {
                    curItems = [it.listItem]
                    curStart = it.paraRange.location
                    curEnd = it.paraRange.location + it.paraRange.length
                    continue
                }

                if it.paraRange.location > curEnd {
                    blocks.append(ListBlock(start: curStart, end: curEnd, items: curItems))
                    curItems = [it.listItem]
                    curStart = it.paraRange.location
                    curEnd = it.paraRange.location + it.paraRange.length
                    continue
                }

                curItems.append(it.listItem)
                curEnd = max(curEnd, it.paraRange.location + it.paraRange.length)
            }

            if !curItems.isEmpty {
                blocks.append(ListBlock(start: curStart, end: curEnd, items: curItems))
            }

            blocks.sort { $0.start < $1.start }

            var doc: [[String: Any]] = []
            var pos = 0

            for b in blocks {
                if b.start > pos {
                    let sub = text.attributedSubstring(from: NSRange(location: pos, length: b.start - pos))
                    doc.append(["type": "rich", "rtf_base64": encodeRTFBase64(sub) ?? ""])
                }

                var itemsJSON: [[String: Any]] = []
                itemsJSON.reserveCapacity(b.items.count)

                for li in b.items {
                    let kind = normalizeKind(li.attributeValue)
                    itemsJSON.append([
                        "level": li.level,
                        "kind": kind,
                        "rtf_base64": encodeRTFBase64(li.text) ?? ""
                    ])
                }

                doc.append(["type": "list", "items": itemsJSON])
                pos = b.end
            }

            if pos < fullLen {
                let sub = text.attributedSubstring(from: NSRange(location: pos, length: fullLen - pos))
                doc.append(["type": "rich", "rtf_base64": encodeRTFBase64(sub) ?? ""])
            }

            if doc.isEmpty {
                doc.append(["type": "rich", "rtf_base64": encodeRTFBase64(text) ?? ""])
            }

            return doc
        }


        private static func trimTrailingNewlinesAttributed(_ a: NSAttributedString) -> NSAttributedString {
            if a.length == 0 { return a }
            var end = a.length
            while end > 0 {
                let ch = (a.string as NSString).character(at: end - 1)
                if ch == 10 || ch == 13 {
                    end -= 1
                    continue
                }
                break
            }
            if end == a.length { return a }
            return a.attributedSubstring(from: NSRange(location: 0, length: max(0, end)))
        }

        private static func normalizeListItem(_ li: ListItem) -> ListItem {
            let kind = normalizeKind(li.attributeValue)
            return ListItem(text: li.text, level: li.level, attributeValue: kind)
        }

        private static func normalizeKind(_ v: Any) -> String {
            if let tl = v as? NSTextList { return (tl.markerFormat == .decimal) ? "number" : "bullet" }
            if let tls = v as? [NSTextList], let tl = tls.first { return (tl.markerFormat == .decimal) ? "number" : "bullet" }
            if let s = v as? String { return (s == "number") ? "number" : "bullet" }
            return "bullet"
        }

        private static func encodeRTFBase64(_ s: NSAttributedString) -> String? {
            let r = NSRange(location: 0, length: s.length)
            guard let data = try? s.data(from: r, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return nil }
            return data.base64EncodedString()
        }

        private static func decodeRTFBase64(_ b64: String) -> NSAttributedString? {
            guard let data = Data(base64Encoded: b64) else { return nil }
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
    }


    private struct NJProtonNodesV1Codec {
        static let schema = "nj_proton_nodes_v1"
        static let indentUnit: CGFloat = 24

        static func decodeRoot(_ json: String) -> [[String: Any]]? {
            guard let data = json.data(using: .utf8) else { return nil }
            guard let rootAny = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
            guard let root = rootAny as? [String: Any] else { return nil }
            guard (root["schema"] as? String) == schema else { return nil }
            guard let nodesAny = root["nodes"] as? [Any] else { return nil }
            let nodes = nodesAny.compactMap { $0 as? [String: Any] }
            return nodes.isEmpty ? nil : nodes
        }

        static func buildAttributedString(nodes: [[String: Any]]) -> NSAttributedString {
            let out = NSMutableAttributedString()

            for (idx, n) in nodes.enumerated() {
                let t = (n["type"] as? String) ?? "text"
                var text = (n["text"] as? String) ?? ""
                text = stripZWSP(text)

                let line = NSMutableAttributedString(string: text)

                if t == "list_item" {
                    let kind = (n["kind"] as? String) ?? "bullet"
                    let level = max(0, (n["level"] as? Int) ?? 0)

                    let marker: NSTextList.MarkerFormat = (kind == "number") ? .decimal : .disc
                    let tl = NSTextList(markerFormat: marker, options: 0)

                    let ps = NSMutableParagraphStyle()
                    ps.textLists = [tl]

                    let indent = CGFloat(level) * indentUnit
                    ps.firstLineHeadIndent = indent
                    ps.headIndent = indent

                    line.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: line.length))
                }

                out.append(line)
                if idx != nodes.count - 1 {
                    out.append(NSAttributedString(string: "\n"))
                }
            }

            return out
        }

        private static func stripZWSP(_ s: String) -> String {
            s.replacingOccurrences(of: "\u{200B}", with: "").replacingOccurrences(of: "\u{FEFF}", with: "")
        }
    }

    private struct NJProtonNodeCodecV1 {

        private static let schema = "nj_proton_nodes_v1"
        private static let indentUnit: CGFloat = 24

        static func encodeJSONString(nodes: [[String: Any]]) -> String {
            let root: [String: Any] = ["schema": schema, "nodes": nodes]
            guard JSONSerialization.isValidJSONObject(root) else { return "" }
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: []) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }

        static func decodeNodesIfPresent(json: String) -> [[String: Any]]? {
            guard let data = json.data(using: .utf8) else { return nil }
            guard let rootAny = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
            guard let root = rootAny as? [String: Any] else { return nil }
            guard (root["schema"] as? String) == schema else { return nil }
            guard let nodesAny = root["nodes"] as? [Any] else { return nil }
            return nodesAny.compactMap { $0 as? [String: Any] }
        }

        static func encodeNodes(from text: NSAttributedString) -> [[String: Any]] {
            let s = text.string as NSString
            if s.length == 0 {
                return [["type": "text", "text": ""]]
            }

            var nodes: [[String: Any]] = []

            var i = 0
            while i < s.length {
                let paraRange = s.paragraphRange(for: NSRange(location: i, length: 0))
                let para = text.attributedSubstring(from: paraRange)

                let paraString = trimTrailingNewlines(para.string)
                let style = para.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

                let (kind, level) = listKindAndLevel(from: para, paragraphStyle: style)

                if let kind {
                    nodes.append([
                        "type": "list_item",
                        "kind": kind,
                        "level": level,
                        "text": paraString
                    ])
                } else {
                    nodes.append([
                        "type": "text",
                        "text": paraString
                    ])
                }

                i = paraRange.location + max(1, paraRange.length)
            }

            if nodes.isEmpty {
                nodes.append(["type": "text", "text": ""])
            }

            return nodes
        }

        static func buildAttributedString(nodes: [[String: Any]]) -> NSAttributedString {
            let out = NSMutableAttributedString()

            for (idx, n) in nodes.enumerated() {
                let t = (n["type"] as? String) ?? "text"
                let text = (n["text"] as? String) ?? ""

                let line = NSMutableAttributedString(string: text)

                if t == "list_item" {
                    let kind = (n["kind"] as? String) ?? "bullet"
                    let level = max(0, (n["level"] as? Int) ?? 0)

                    let tl: NSTextList = {
                        if kind == "number" { return NSTextList(markerFormat: .decimal, options: 0) }
                        return NSTextList(markerFormat: .disc, options: 0)
                    }()

                    let ps = NSMutableParagraphStyle()
                    ps.textLists = [tl]

                    let indent = CGFloat(level) * indentUnit
                    ps.headIndent = indent
                    ps.firstLineHeadIndent = indent

                    line.addAttribute(.paragraphStyle, value: ps, range: line.fullRange)
                    line.addAttribute(.listItem, value: tl, range: line.fullRange)
                }

                out.append(line)
                if idx != nodes.count - 1 {
                    out.append(NSAttributedString(string: "\n"))
                }
            }

            return out
        }

        private static func listKindAndLevel(from para: NSAttributedString, paragraphStyle: NSParagraphStyle?) -> (String?, Int) {
            let full = NSRange(location: 0, length: para.length)

            var listValue: Any? = nil
            para.enumerateAttribute(.listItem, in: full, options: []) { v, _, stop in
                if v != nil {
                    listValue = v
                    stop.pointee = true
                }
            }

            let tl: NSTextList? = {
                if let t = listValue as? NSTextList { return t }
                if let arr = listValue as? [NSTextList] { return arr.first }
                if let ps = paragraphStyle, let first = ps.textLists.first { return first }
                return nil
            }()

            guard let tl else {
                return (nil, 0)
            }

            let kind: String = (tl.markerFormat == .decimal) ? "number" : "bullet"

            let headIndent: CGFloat = {
                if let ps = paragraphStyle { return ps.headIndent }
                return 0
            }()

            let level = max(0, Int((headIndent / indentUnit).rounded()))
            return (kind, level)
        }

        private static func trimTrailingNewlines(_ s: String) -> String {
            var t = s
            while t.hasSuffix("\n") { t.removeLast() }
            return t
        }
    }

    func attributedStringFromProtonJSONString(_ json: String) -> NSAttributedString {
        let out = NSMutableAttributedString()

        guard
            let data = json.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return out
        }

        for node in arr {
            guard let type = node["type"] as? String else { continue }

            if type == "_paragraph" {
                if let contents = node["contents"] as? [[String: Any]] {
                    for c in contents {
                        if let t = c["text"] as? String {
                            let a = NSMutableAttributedString(string: t)
                            if let attrs = c["attributes"] as? [String: Any] {
                                applyAttributes(attrs, to: a)
                            }
                            out.append(a)
                        }
                    }
                }
                out.append(NSAttributedString(string: "\n"))
            }
        }

        return out
    }

    private func applyAttributes(_ attrs: [String: Any], to s: NSMutableAttributedString) {
        let r = NSRange(location: 0, length: s.length)

        if let font = attrs["font"] as? [String: Any],
           let size = font["size"] as? CGFloat {
            s.addAttribute(.font, value: UIFont.systemFont(ofSize: size), range: r)
        }

        if let color = attrs["foregroundColor"] as? [String: Any],
           let rC = color["r"] as? CGFloat,
           let gC = color["g"] as? CGFloat,
           let bC = color["b"] as? CGFloat,
           let aC = color["a"] as? CGFloat {
            s.addAttribute(.foregroundColor, value: UIColor(red: rC, green: gC, blue: bC, alpha: aC), range: r)
        }
    }

    private func adjustIndent(delta: CGFloat) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let sel = tv.selectedRange
        let ns = tv.text as NSString

        let startPara = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let endLoc = min(sel.location + max(sel.length, 0), ns.length)
        let endPara = ns.paragraphRange(for: NSRange(location: endLoc, length: 0))

        let range = NSRange(
            location: startPara.location,
            length: max(0, (endPara.location + endPara.length) - startPara.location)
        )

        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let base = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let ps = base.mutableCopy() as! NSMutableParagraphStyle

            let newHead = max(0, ps.headIndent + delta)
            let newFirst = max(0, ps.firstLineHeadIndent + delta)

            ps.headIndent = newHead
            ps.firstLineHeadIndent = newFirst

            tv.textStorage.addAttribute(.paragraphStyle, value: ps, range: subRange)
        }
        tv.textStorage.endEditing()

        if let cur = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
            let ps = cur.mutableCopy() as! NSMutableParagraphStyle
            ps.headIndent = max(0, ps.headIndent + delta)
            ps.firstLineHeadIndent = max(0, ps.firstLineHeadIndent + delta)
            tv.typingAttributes[.paragraphStyle] = ps
        }
    }

    func toggleBullet() {
        guard let editor else { return }
        let tl = NSTextList(markerFormat: .disc, options: 0)
        ListCommand().execute(on: editor, attributeValue: tl)
        snapshot()
    }

    func toggleNumber() {
        guard let editor else { return }
        let tl = NSTextList(markerFormat: .decimal, options: 0)
        ListCommand().execute(on: editor, attributeValue: tl)
        snapshot()
    }
    
    func toggleUnderline() { toggleUnderlineStyle() }

    func focus() {
        if let tv = textView {
            _ = tv.becomeFirstResponder()
            return
        }
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }
        textView = tv
        _ = tv.becomeFirstResponder()
    }

    private func toggleUnderlineStyle() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let r = tv.selectedRange
        if r.length == 0 {
            let v = (tv.typingAttributes[.underlineStyle] as? Int) ?? 0
            tv.typingAttributes[.underlineStyle] = (v == 0) ? NSUnderlineStyle.single.rawValue : 0
            return
        }

        let s = tv.textStorage
        let has = (s.attribute(.underlineStyle, at: r.location, effectiveRange: nil) as? Int ?? 0) != 0
        s.beginEditing()
        s.addAttribute(.underlineStyle, value: has ? 0 : NSUnderlineStyle.single.rawValue, range: r)
        s.endEditing()

        snapshot()
    }

    var onEndEditingSimple: (() -> Void)?

    func dumpProtonJSONPretty() -> String {
        guard let editor else { return "" }
        let obj = editor.transformContents(using: NJProtonAuditJSONEncoder())
        guard JSONSerialization.isValidJSONObject(obj) else { return "" }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    weak var textView: UITextView?

    func owns(textView tv: UITextView) -> Bool {
        if let t = textView { return t === tv }
        guard let editor else { return false }
        return findTextView(in: editor) === tv
    }

    func insertImageAttachment(_ image: UIImage, width: CGFloat = 400) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let w = max(1, width)
        let ratio = image.size.height / max(1, image.size.width)
        let h = max(1, w * ratio)

        let att = NSTextAttachment()
        att.image = image
        att.bounds = CGRect(x: 0, y: 0, width: w, height: h)

        let s = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange
        let attStr = NSAttributedString(attachment: att)
        s.replaceCharacters(in: r, with: attStr)

        tv.attributedText = s
        tv.selectedRange = NSRange(location: min(r.location + 1, s.length), length: 0)

        snapshot()
    }


    func insertPhoto(_ image: UIImage) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let w: CGFloat = 400
        let ratio = image.size.height / max(1, image.size.width)
        let h = max(1, w * ratio)

        let att = NSTextAttachment()
        att.image = image
        att.bounds = CGRect(x: 0, y: 0, width: w, height: h)

        let s = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange

        let attStr = NSAttributedString(attachment: att)
        s.replaceCharacters(in: r, with: attStr)

        tv.attributedText = s
        tv.selectedRange = NSRange(location: min(r.location + 1, s.length), length: 0)

        snapshot()
    }

    func insertLink(_ url: URL) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let r = tv.selectedRange
        if r.length == 0 { return }

        let s = NSMutableAttributedString(attributedString: tv.attributedText)
        s.addAttribute(.link, value: url, range: r)
        tv.attributedText = s
        tv.selectedRange = NSRange(location: r.location + r.length, length: 0)

        snapshot()
    }

    func insertDivider() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange

        let div = NSAttributedString(string: "\n──────────\n", attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .light),
            .foregroundColor: UIColor.secondaryLabel
        ])

        m.replaceCharacters(in: r, with: div)
        let loc = r.location + div.length
        tv.attributedText = m
        tv.selectedRange = NSRange(location: min(loc, m.length), length: 0)

        snapshot()
    }

    func insertTodoCheckbox() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange
        let box = NSAttributedString(string: "☐ ", attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .light),
            .foregroundColor: UIColor.label
        ])

        m.replaceCharacters(in: r, with: box)
        let loc = r.location + box.length
        tv.attributedText = m
        tv.selectedRange = NSRange(location: min(loc, m.length), length: 0)

        snapshot()
    }

    func insertTodayStamp() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let s = df.string(from: Date())
        let stamp = NSAttributedString(string: s, attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .light),
            .foregroundColor: UIColor.secondaryLabel
        ])

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange
        m.replaceCharacters(in: r, with: stamp)
        let loc = r.location + stamp.length
        tv.attributedText = m
        tv.selectedRange = NSRange(location: min(loc, m.length), length: 0)

        snapshot()
    }

    func insertCodeFence() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange
        let code = NSAttributedString(string: "\n```\n\n```\n", attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor.label
        ])

        m.replaceCharacters(in: r, with: code)
        let loc = r.location + 5
        tv.attributedText = m
        tv.selectedRange = NSRange(location: min(loc, m.length), length: 0)

        snapshot()
    }
    
    func insertTagLine() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange

        let attrs: [NSAttributedString.Key: Any] = [
            .font: (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light),
            .foregroundColor: (tv.typingAttributes[.foregroundColor] as? UIColor) ?? UIColor.label
        ]

        let tag = NSAttributedString(string: "@tag: ", attributes: attrs)

        m.replaceCharacters(in: r, with: tag)
        let loc = r.location + tag.length
        tv.attributedText = m
        tv.selectedRange = NSRange(location: min(loc, m.length), length: 0)

        snapshot()
    }

    func increaseFont() { adjustFontSize(delta: 1) }
    func decreaseFont() { adjustFontSize(delta: -1) }

    func toggleBold() { toggleBoldWeight() }

    private func toggleBoldWeight() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        func weightOf(_ font: UIFont) -> UIFont.Weight {
            let wRaw = (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat
            return UIFont.Weight(wRaw ?? UIFont.Weight.regular.rawValue)
        }

        func applyBold(_ on: Bool, _ font: UIFont) -> UIFont {
            let size = font.pointSize
            let fd = font.fontDescriptor
            let hadItalic = fd.symbolicTraits.contains(.traitItalic)

            let w0 = weightOf(font)
            let w1: UIFont.Weight = on ? (w0 < .semibold ? .semibold : w0) : .light

            let base = UIFont.systemFont(ofSize: size, weight: w1)

            if !hadItalic { return base }
            if let nfd = base.fontDescriptor.withSymbolicTraits([.traitItalic]) {
                return UIFont(descriptor: nfd, size: size)
            }
            return base
        }

        let r = tv.selectedRange
        if r.length == 0 {
            let old = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            let isBoldNow = old.fontDescriptor.symbolicTraits.contains(.traitBold) || (weightOf(old) >= .semibold)
            tv.typingAttributes[.font] = applyBold(!isBoldNow, old)
            return
        }

        let storage = tv.textStorage
        let isBoldNow: Bool = {
            let old = (storage.attribute(.font, at: r.location, effectiveRange: nil) as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            return old.fontDescriptor.symbolicTraits.contains(.traitBold) || (weightOf(old) >= .semibold)
        }()

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: r, options: []) { v, range, _ in
            let old = (v as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            let nf = applyBold(!isBoldNow, old)
            storage.addAttribute(.font, value: nf, range: range)
        }
        storage.endEditing()

        snapshot()
    }

    func toggleItalic() { toggleFontTrait(.traitItalic) }
    func toggleStrike() { toggleStrikeThrough() }

    func snapshot() {
        guard let editor else { return }
        onSnapshot?(editor.attributedText, editor.selectedRange)
    }

    private func adjustFontSize(delta: CGFloat) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let r = tv.selectedRange
        if r.length == 0 {
            let old = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            let newSize = max(8, min(48, old.pointSize + delta))
            let newFont = UIFont(descriptor: old.fontDescriptor, size: newSize)
            tv.typingAttributes[.font] = newFont
            return
        }

        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
            let old = (value as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            let newSize = max(8, min(48, old.pointSize + delta))
            let newFont = UIFont(descriptor: old.fontDescriptor, size: newSize)
            tv.textStorage.addAttribute(.font, value: newFont, range: range)
        }
        tv.textStorage.endEditing()

        snapshot()
    }

    private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let r = tv.selectedRange
        if r.length == 0 {
            let old = (tv.typingAttributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            let fd = old.fontDescriptor
            let has = fd.symbolicTraits.contains(trait)
            var traits = fd.symbolicTraits
            if has { traits.remove(trait) } else { traits.insert(trait) }
            if let nfd = fd.withSymbolicTraits(traits) {
                tv.typingAttributes[.font] = UIFont(descriptor: nfd, size: old.pointSize)
            }
            return
        }

        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
            let old = (value as? UIFont) ?? UIFont.systemFont(ofSize: 17, weight: .light)
            let fd = old.fontDescriptor
            let has = fd.symbolicTraits.contains(trait)
            var traits = fd.symbolicTraits
            if has { traits.remove(trait) } else { traits.insert(trait) }
            if let nfd = fd.withSymbolicTraits(traits) {
                let nf = UIFont(descriptor: nfd, size: old.pointSize)
                tv.textStorage.addAttribute(.font, value: nf, range: range)
            }
        }
        tv.textStorage.endEditing()

        snapshot()
    }

    private func toggleStrikeThrough() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let r = tv.selectedRange
        if r.length == 0 {
            let v = (tv.typingAttributes[.strikethroughStyle] as? Int) ?? 0
            if v == 0 {
                tv.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                tv.typingAttributes.removeValue(forKey: .strikethroughStyle)
            }
            return
        }

        let s = tv.textStorage
        let v = (s.attribute(.strikethroughStyle, at: r.location, effectiveRange: nil) as? Int) ?? 0
        let has = v != 0

        s.beginEditing()
        if has {
            s.removeAttribute(.strikethroughStyle, range: r)
        } else {
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        s.endEditing()

        snapshot()
    }

    func hydrateFromProtonJSONString(_ json: String) {
        pendingHydrateProtonJSON = json
        applyPendingHydrateIfNeeded()
    }

    private var didHydrate = false
    private var attachedEditorID: ObjectIdentifier? = nil

    func invalidateHydration() {
        didHydrate = false
        lastHydratedJSONSig = 0
        attachedEditorID = nil
        hydrationScheduled = false
        pendingJSON = nil
        pendingHydrateProtonJSON = nil
    }

    func editorDidAttach(_ ev: EditorView) {
        let id = ObjectIdentifier(ev)
        if attachedEditorID != id {
            attachedEditorID = id
            didHydrate = false
            hydrationScheduled = false
            pendingJSON = nil
        }
    }

    private var lastHydratedJSONSig: Int = 0

    func applyPendingHydrateIfNeeded() {
        guard let json = pendingHydrateProtonJSON else { return }
        guard editor != nil, textView != nil else { return }

        let sig = json.hashValue
        if didHydrate, sig == lastHydratedJSONSig {
            pendingHydrateProtonJSON = nil
            return
        }

        let run = { [weak self] in
            guard let self else { return }
            self.pendingHydrateProtonJSON = nil
            self.scheduleHydration(json)
        }

        if let withProgrammatic {
            withProgrammatic(run)
        } else {
            run()
        }
    }

    private var hydrationScheduled = false
    private var pendingJSON: String?

    private func buildParagraphStyle(from json: [String: Any]) -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()

        if let a = json["alignment"] as? Int { ps.alignment = NSTextAlignment(rawValue: a) ?? .natural }
        if let v = json["firstLineHeadIndent"] as? Double { ps.firstLineHeadIndent = CGFloat(v) }
        if let v = json["headIndent"] as? Double { ps.headIndent = CGFloat(v) }
        if let v = json["tailIndent"] as? Double { ps.tailIndent = CGFloat(v) }
        if let v = json["lineSpacing"] as? Double { ps.lineSpacing = CGFloat(v) }
        if let v = json["paragraphSpacing"] as? Double { ps.paragraphSpacing = CGFloat(v) }
        if let v = json["paragraphSpacingBefore"] as? Double { ps.paragraphSpacingBefore = CGFloat(v) }
        if let v = json["lineHeightMultiple"] as? Double { ps.lineHeightMultiple = CGFloat(v) }
        if let v = json["minimumLineHeight"] as? Double { ps.minimumLineHeight = CGFloat(v) }
        if let v = json["maximumLineHeight"] as? Double { ps.maximumLineHeight = CGFloat(v) }

        if let tls = json["textLists"] as? [[String: Any]], !tls.isEmpty {
            var lists: [NSTextList] = []
            for tl in tls {
                let mf = (tl["markerFormat"] as? String) ?? "disc"
                let marker: NSTextList.MarkerFormat = (mf == "decimal") ? .decimal : .disc
                let l = NSTextList(markerFormat: marker, options: 0)
                if let n = tl["startingItemNumber"] as? Int { l.startingItemNumber = n }
                lists.append(l)
            }
            ps.textLists = lists
        }

        return ps
    }

    func scheduleHydration(_ json: String) {
        pendingJSON = json
        guard !hydrationScheduled else { return }
        hydrationScheduled = true

        let run: () -> Void = { [weak self] in
            guard let self else { return }
            self.hydrationScheduled = false
            guard let json = self.pendingJSON else { return }
            self.pendingJSON = nil
            self.applyHydrateJSON(json)
        }

        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    private func applyHydrateJSON(_ json: String) {
        guard textView != nil else { return }
        guard let editor else { return }

        let baseFont = UIFont.systemFont(ofSize: 17, weight: .light)

        func apply(_ a: NSAttributedString) {
            let fixedFonts = NJApplyBaseFontWhereMissing(a, baseFont: baseFont)
            let r = editor.selectedRange
            editor.attributedText = fixedFonts
            editor.selectedRange = NSRange(location: min(r.location, fixedFonts.length), length: 0)

            if let tv = textView {
                var ta = tv.typingAttributes
                ta[.font] = baseFont
                if ta[.foregroundColor] == nil { ta[.foregroundColor] = UIColor.label }
                tv.typingAttributes = ta
            }

            didHydrate = true
            lastHydratedJSONSig = json.hashValue
            onSnapshot?(editor.attributedText, editor.selectedRange)
        }

        if let doc = NJProtonDocCodecV1.decodeIfPresent(json: json) {
            let decoded = NJStandardizeFontFamily(NJProtonDocCodecV1.buildAttributedString(doc: doc))
            apply(decoded)
            return
        }

        if let nodes = NJProtonNodeCodecV1.decodeNodesIfPresent(json: json) {
            let decoded = NJStandardizeFontFamily(NJProtonNodeCodecV1.buildAttributedString(nodes: nodes))
            apply(decoded)
            return
        }

        let mode = njDefaultContentMode()
        let maxSize = CGSize(width: 4096, height: 4096)
        let decoded = (try? NJProtonAuditCodec.decoder.decodeDocument(mode: mode, maxSize: maxSize, json: json)) ?? NSAttributedString(string: "")
        let fixed = NJStandardizeFontFamily(NJProtonListFixups.apply(decoded))
        apply(fixed)
    }

    private func njDefaultContentMode() -> EditorContentMode {
        var z = [UInt8](repeating: 0, count: MemoryLayout<EditorContentMode>.size)
        return z.withUnsafeBytes { $0.load(as: EditorContentMode.self) }
    }


    private func findTextView(in root: UIView) -> UITextView? {
        if let tv = root as? UITextView { return tv }
        for v in root.subviews {
            if let tv = findTextView(in: v) { return tv }
        }
        return nil
    }
}

final class NJKeyCommandEditorView: EditorView {
    weak var njHandle: NJProtonEditorHandle?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    override var keyCommands: [UIKeyCommand]? {
        [

            UIKeyCommand(input: "b", modifierFlags: [.command], action: #selector(cmdBold)),
            UIKeyCommand(input: "i", modifierFlags: [.command], action: #selector(cmdItalic)),
            UIKeyCommand(input: "u", modifierFlags: [.command], action: #selector(cmdUnderline)),
            UIKeyCommand(input: "x", modifierFlags: [.command, .shift], action: #selector(cmdStrike)),
            

            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabIndent)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(tabOutdent))
        ]
    }

    @objc private func cmdUnderline() {
        njHandle?.toggleUnderline()
        njHandle?.snapshot()
    }

    @objc private func cmdBold() {
        njHandle?.toggleBold()
        njHandle?.snapshot()
    }

    @objc private func cmdItalic() {
        njHandle?.toggleItalic()
        njHandle?.snapshot()
    }

    @objc private func cmdStrike() {
        njHandle?.toggleStrike()
        njHandle?.snapshot()
    }

    @objc private func tabIndent() {
        njHandle?.indent()
        njHandle?.snapshot()
    }

    @objc private func tabOutdent() {
        njHandle?.outdent()
        njHandle?.snapshot()
    }
}

struct NJProtonEditorView: UIViewRepresentable {
    let initialAttributedText: NSAttributedString
    let initialSelectedRange: NSRange

    @Binding var snapshotAttributedText: NSAttributedString
    @Binding var snapshotSelectedRange: NSRange
    @Binding var measuredHeight: CGFloat

    let handle: NJProtonEditorHandle

    private let listProvider = NJProtonListFormattingProvider()

    func makeUIView(context: Context) -> EditorView {
        let v = NJKeyCommandEditorView()
        v.listFormattingProvider = listProvider
        v.registerProcessor(ListTextProcessor())
        v.delegate = context.coordinator
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.isEditable = true
        v.isUserInteractionEnabled = true

        handle.withProgrammatic = { f in
            context.coordinator.beginProgrammatic()
            f()
            context.coordinator.endProgrammatic()
        }

        handle.withProgrammatic? {
            v.attributedText = NJStandardizeFontFamily(initialAttributedText)
            v.selectedRange = initialSelectedRange
        }

        if let tv = findTextView(in: v) {
            NJInstallTextViewKeyCommandHook(tv)
            if tv.njProtonHandle == nil || handle.owns(textView: tv) {
                tv.njProtonHandle = handle
                handle.textView = tv
            }

            tv.isScrollEnabled = false
            tv.backgroundColor = .clear
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0

            normalizeTypingAttributesIfNeeded(v)
            context.coordinator.attachTextView(tv)
        } else {
            normalizeTypingAttributesIfNeeded(v)
        }

        v.njProtonHandle = handle
        handle.editor = v
        handle.editorDidAttach(v)
        (v as? NJKeyCommandEditorView)?.njHandle = handle

        handle.onEndEditingSimple = nil

        handle.onSnapshot = { a, r in
            DispatchQueue.main.async {
                snapshotAttributedText = a
                snapshotSelectedRange = r
                context.coordinator.updateMeasuredHeight(from: v)
            }
        }

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinch(_:)))
        pinch.cancelsTouchesInView = false
        v.addGestureRecognizer(pinch)

        DispatchQueue.main.async {
            if let tv = findTextView(in: v) {
                NJInstallTextViewKeyCommandHook(tv)
                if tv.njProtonHandle == nil || handle.owns(textView: tv) {
                    tv.njProtonHandle = handle
                    handle.textView = tv
                }
                normalizeTypingAttributesIfNeeded(v)
            } else {
                normalizeTypingAttributesIfNeeded(v)
            }
            context.coordinator.updateMeasuredHeight(from: v)
            handle.applyPendingHydrateIfNeeded()
        }

        return v
    }

    func updateUIView(_ uiView: EditorView, context: Context) {
        if let existing = uiView.njProtonHandle, existing !== handle {
            return
        }
        uiView.njProtonHandle = handle
        handle.editor = uiView
        handle.editorDidAttach(uiView)
        (uiView as? NJKeyCommandEditorView)?.njHandle = handle

        if let tv = findTextView(in: uiView) {
            NJInstallTextViewKeyCommandHook(tv)
            if tv.njProtonHandle == nil || handle.owns(textView: tv) {
                tv.njProtonHandle = handle
                handle.textView = tv
            }

            tv.isScrollEnabled = false
            tv.backgroundColor = .clear
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0

            normalizeTypingAttributesIfNeeded(uiView)
            context.coordinator.attachTextView(tv)

            handle.applyPendingHydrateIfNeeded()
        } else {
            normalizeTypingAttributesIfNeeded(uiView)
        }

        context.coordinator.updateMeasuredHeight(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(measuredHeight: $measuredHeight, handle: handle)
    }

    private func findTextView(in root: UIView) -> UITextView? {
        if let tv = root as? UITextView { return tv }
        for v in root.subviews {
            if let tv = findTextView(in: v) { return tv }
        }
        return nil
    }

    private func normalizeTypingAttributesIfNeeded(_ editor: EditorView) {
        guard let tv = findTextView(in: editor) else { return }

        var ta = tv.typingAttributes

        if let f = ta[.font] as? UIFont {
            ta[.font] = NJStandardizeFontFamily(f)
        } else {
            ta[.font] = UIFont.systemFont(ofSize: 17, weight: .light)
        }

        if ta[.foregroundColor] == nil {
            ta[.foregroundColor] = UIColor.label
        }

        tv.typingAttributes = ta
    }

    final class Coordinator: NSObject, EditorViewDelegate, UITextViewDelegate {
        @Binding private var measuredHeight: CGFloat
        private weak var editor: EditorView?
        private weak var textView: UITextView?
        private var textDidChangeObs: NSObjectProtocol?
        var textDidBeginObs: NSObjectProtocol? = nil
        private var textDidEndObs: NSObjectProtocol?
        private let handle: NJProtonEditorHandle
        private var isProgrammatic = false
        var typingIdleWork: DispatchWorkItem? = nil
        let typingIdleMs: Int = 1500


        private weak var activeAttachment: NSTextAttachment?
        private var activeInitialBounds: CGRect = .zero

        init(measuredHeight: Binding<CGFloat>, handle: NJProtonEditorHandle) {
            _measuredHeight = measuredHeight
            self.handle = handle
        }

        deinit {
            if let o = textDidChangeObs {
                NotificationCenter.default.removeObserver(o)
            }
        }
        
        private var isNormalizingFonts = false

        private func normalizeFontFamilyInTextStorage(_ tv: UITextView) {
            if isNormalizingFonts { return }
            let storage = tv.textStorage
            if storage.length == 0 { return }

            var didChange = false
            isNormalizingFonts = true
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length), options: []) { v, range, _ in
                guard let old = v as? UIFont else { return }
                let nf = NJStandardizeFontFamily(old)
                if nf.fontName != old.fontName {
                    storage.addAttribute(.font, value: nf, range: range)
                    didChange = true
                }
            }
            storage.endEditing()
            isNormalizingFonts = false

            if didChange {
                var ta = tv.typingAttributes
                if let f = ta[.font] as? UIFont {
                    ta[.font] = NJStandardizeFontFamily(f)
                    tv.typingAttributes = ta
                }
            }
        }


        func textViewDidBeginEditing(_ tv: UITextView) {
            if isProgrammatic { return }
            handle.isEditing = true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if isProgrammatic { return }
            handle.isEditing = false
        }

        func beginProgrammatic() { isProgrammatic = true }
        func endProgrammatic() { isProgrammatic = false }

        func attachTextView(_ tv: UITextView) {
            if textView === tv { return }

            if let o = textDidChangeObs { NotificationCenter.default.removeObserver(o); textDidChangeObs = nil }
            if let o = textDidBeginObs { NotificationCenter.default.removeObserver(o); textDidBeginObs = nil }
            if let o = textDidEndObs { NotificationCenter.default.removeObserver(o); textDidEndObs = nil }

            textView = tv

            textDidChangeObs = NotificationCenter.default.addObserver(
                forName: UITextView.textDidChangeNotification,
                object: tv,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.isProgrammatic { return }
                guard let ev = self.handle.editor else { return }

                self.handle.isEditing = true
                self.typingIdleWork?.cancel()
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.handle.isEditing = false
                }
                self.typingIdleWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(self.typingIdleMs), execute: w)

                self.normalizeFontFamilyInTextStorage(tv)

                self.handle.onSnapshot?(ev.attributedText, ev.selectedRange)
                self.handle.onUserTyped?(ev.attributedText, ev.selectedRange)
                self.updateMeasuredHeight(from: ev)


            }

            textDidEndObs = NotificationCenter.default.addObserver(
                forName: UITextView.textDidEndEditingNotification,
                object: tv,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.isProgrammatic { return }
                self.typingIdleWork?.cancel()
                self.typingIdleWork = nil
                self.handle.isEditing = false

                guard let ev = self.handle.editor else { return }

                self.handle.onSnapshot?(ev.attributedText, ev.selectedRange)
                self.handle.onEndEditing?(ev.attributedText, ev.selectedRange)
                self.handle.onEndEditingSimple?()
            }
        }

        private var snapshotWorkItem: DispatchWorkItem?
        private let snapshotDebounceMs: Int = 200

        func textViewDidChange(_ tv: UITextView) {
            if isProgrammatic { return }

            let sel = tv.selectedRange
            handle.onUserTyped?(tv.attributedText ?? NSAttributedString(string: ""), sel)

            snapshotWorkItem?.cancel()
            let ev = editor ?? (tv.superview as? EditorView)

            let wi = DispatchWorkItem { [weak self, weak tv] in
                guard let self else { return }
                if self.isProgrammatic { return }
                guard let tv else { return }

                let attr = tv.attributedText ?? NSAttributedString(string: "")
                let sel2 = tv.selectedRange

                self.handle.onSnapshot?(attr, sel2)

                if let ev { self.updateMeasuredHeight(from: ev) }
            }

            snapshotWorkItem = wi
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(snapshotDebounceMs), execute: wi)
        }


        func editorViewDidEndEditing(_ editorView: EditorView) {
            editor = editorView
            if isProgrammatic { return }
            handle.onSnapshot?(editorView.attributedText, editorView.selectedRange)
            handle.onEndEditing?(editorView.attributedText, editorView.selectedRange)
            handle.onEndEditingSimple?()
        }

        func editorViewDidChange(_ editorView: EditorView) {
            editor = editorView
            updateMeasuredHeight(from: editorView)
        }

        func editorViewDidChangeSelection(_ editorView: EditorView) {
            editor = editorView
            updateMeasuredHeight(from: editorView)
        }

        func updateMeasuredHeight(from editorView: EditorView) {
            editor = editorView

            guard let tv = findTextView(in: editorView) else { return }

            tv.isScrollEnabled = false
            tv.layoutIfNeeded()

            let targetW: CGFloat
            if tv.bounds.width > 1 {
                targetW = tv.bounds.width
            } else {
                targetW = UIScreen.main.bounds.width - 32
            }

            tv.textContainer.size = CGSize(width: targetW, height: .greatestFiniteMagnitude)
            tv.layoutIfNeeded()

            let fit = tv.sizeThatFits(CGSize(width: targetW, height: .greatestFiniteMagnitude))
            let h = max(44, ceil(fit.height))

            if abs(measuredHeight - h) > 0.5 {
                DispatchQueue.main.async { self.measuredHeight = h }
            }
        }

        @objc func onPinch(_ gr: UIPinchGestureRecognizer) {
            guard let ev = editor ?? (gr.view as? EditorView) else { return }
            editor = ev
            guard let tv = findTextView(in: ev) else { return }

            let point = gr.location(in: tv)
            let idx = characterIndex(at: point, in: tv)

            switch gr.state {
            case .began:
                activeAttachment = attachment(at: idx, in: tv)
                activeInitialBounds = activeAttachment?.bounds ?? .zero
            case .changed:
                guard let att = activeAttachment else { return }
                let scale = clamp(gr.scale, 0.2, 4.0)
                let b = activeInitialBounds == .zero ? defaultBounds(for: att) : activeInitialBounds
                att.bounds = CGRect(x: b.origin.x, y: b.origin.y, width: max(20, b.size.width * scale), height: max(20, b.size.height * scale))
                handle.snapshot()
                updateMeasuredHeight(from: ev)
            default:
                activeAttachment = nil
                activeInitialBounds = .zero
            }
        }

        private func findTextView(in root: UIView) -> UITextView? {
            if let tv = root as? UITextView { return tv }
            for v in root.subviews {
                if let tv = findTextView(in: v) { return tv }
            }
            return nil
        }

        private func characterIndex(at point: CGPoint, in tv: UITextView) -> Int {
            let layout = tv.layoutManager
            let container = tv.textContainer
            let p = CGPoint(x: point.x - tv.textContainerInset.left, y: point.y - tv.textContainerInset.top)
            let idx = layout.characterIndex(for: p, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            return idx
        }

        private func attachment(at idx: Int, in tv: UITextView) -> NSTextAttachment? {
            if idx < 0 || idx >= tv.attributedText.length { return nil }
            return tv.attributedText.attribute(.attachment, at: idx, effectiveRange: nil) as? NSTextAttachment
        }

        private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            min(max(v, lo), hi)
        }

        private func defaultBounds(for att: NSTextAttachment) -> CGRect {
            if let img = att.image {
                let w: CGFloat = 400
                let ratio = img.size.height / max(1, img.size.width)
                return CGRect(x: 0, y: 0, width: w, height: max(1, w * ratio))
            }
            return CGRect(x: 0, y: 0, width: 400, height: 300)
        }
    }
}

private enum NJProtonListFixups {
    static func apply(_ input: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: input)
        let s = m.string as NSString
        let full = NSRange(location: 0, length: s.length)

        var i = 0
        while i < s.length {
            let paraRange = s.paragraphRange(for: NSRange(location: i, length: 0))
            let para = m.attributedSubstring(from: paraRange)

            let hasList: Bool = {
                var v: Any? = nil
                para.enumerateAttribute(.listItem, in: NSRange(location: 0, length: para.length), options: []) { x, _, stop in
                    if x != nil { v = x; stop.pointee = true }
                }
                return v != nil
            }()

            if hasList {
                let local = para.string as NSString
                if local.length > 0 {
                    var j = 0
                    while j < local.length {
                        if local.character(at: j) == 10 {
                            let global = paraRange.location + j
                            m.addAttribute(.skipNextListMarker, value: true, range: NSRange(location: global, length: 1))
                        }
                        j += 1
                    }
                }
            }

            i = paraRange.location + max(1, paraRange.length)
        }

        return m
    }
}
