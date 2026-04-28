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
private var NJTextViewTableOwnerKey: UInt8 = 0
private var NJKeyCommandsOriginalIMP: IMP?

private var NJEditorViewHandleKey: UInt8 = 0

private func NJCanonicalBodyFont(
    size: CGFloat = 17,
    bold: Bool = false,
    italic: Bool = false
) -> UIFont {
    NJEditorCanonicalBodyFont(size: size, bold: bold, italic: italic)
}

private func NJHasExplicitBoldTrait(_ font: UIFont) -> Bool {
    NJEditorHasExplicitBoldTrait(font)
}

extension EditorView {
    var njProtonHandle: NJProtonEditorHandle? {
        get { objc_getAssociatedObject(self, &NJEditorViewHandleKey) as? NJProtonEditorHandle }
        set { objc_setAssociatedObject(self, &NJEditorViewHandleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

private func NJStandardizeFontFamily(_ font: UIFont) -> UIFont {
    NJEditorStandardizeFontFamily(font)
}

private func NJStandardizeFontFamily(_ s: NSAttributedString) -> NSAttributedString {
    NJEditorStandardizeFontFamily(s)
}

private extension NSAttributedString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
}

private final class NJWeakTableAttachmentBox: NSObject {
    weak var owner: NJTableAttachmentView?

    init(owner: NJTableAttachmentView?) {
        self.owner = owner
    }
}

func NJSetTextViewTableOwner(_ tv: UITextView, owner: NJTableAttachmentView?) {
    objc_setAssociatedObject(
        tv,
        &NJTextViewTableOwnerKey,
        NJWeakTableAttachmentBox(owner: owner),
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
}

extension UITextView {
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
        h.isEditing = true
        f(h)
        h.snapshot(markUserEdit: true)
        NJCollapsibleAttachmentView.handleKeyCommandMutation(in: self)
        if !self.isFirstResponder { self.becomeFirstResponder() }
    }

    private var njTableOwner: NJTableAttachmentView? {
        (objc_getAssociatedObject(self, &NJTextViewTableOwnerKey) as? NJWeakTableAttachmentBox)?.owner
    }

    @objc func nj_tabIndent() {
        if let owner = njTableOwner {
            owner.focusNextCell()
            return
        }
        nj_fire("TAB INDENT") { $0.indent() }
    }

    @objc func nj_tabOutdent() {
        if let owner = njTableOwner {
            owner.focusPreviousCell()
            return
        }
        nj_fire("TAB OUTDENT") { $0.outdent() }
    }

    @objc func nj_tableReturn() {
        if let owner = njTableOwner {
            owner.handleReturnKey()
            return
        }
    }

    @objc func nj_cmdBold() { nj_fire("CMD+B") { $0.toggleBold() } }
    @objc func nj_cmdItalic() { nj_fire("CMD+I") { $0.toggleItalic() } }
    @objc func nj_cmdUnderline() { nj_fire("CMD+U") { $0.toggleUnderline() } }
    @objc func nj_cmdStrike() { nj_fire("SHIFT+CMD+X") { $0.toggleStrike() } }

    @objc func nj_cmdIndent() { nj_fire("CMD+]") { $0.indent() } }
    @objc func nj_cmdOutdent() { nj_fire("CMD+[") { $0.outdent() } }

    @objc func nj_cmdBullet() { }
    @objc func nj_cmdNumber() { }
    
}


import os

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "KeyCommands")
private var NJKeyCommandsOriginalIMPByClass: [ObjectIdentifier: IMP] = [:]
private var NJPasteOriginalIMPByClass: [ObjectIdentifier: IMP] = [:]
private var NJCanPerformActionOriginalIMPByClass: [ObjectIdentifier: IMP] = [:]

private func NJClipboardImage() -> UIImage? {
    let pb = UIPasteboard.general
    if let img = pb.image { return img }

    let candidateKeys = [
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.image",
        "com.apple.uikit.image"
    ]

    for item in pb.items {
        for key in candidateKeys {
            guard let value = item[key] else { continue }
            if let img = value as? UIImage { return img }
            if let data = value as? Data, let img = UIImage(data: data) { return img }
            if let data = value as? NSData, let img = UIImage(data: data as Data) { return img }
            if let url = value as? URL,
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                return img
            }
            if let s = value as? String,
               let url = URL(string: s),
               url.isFileURL,
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                return img
            }
        }
    }
    return nil
}

private func NJNormalizedURL(from value: Any?) -> URL? {
    if let url = value as? URL, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
        return url
    }
    if let s = value as? String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
    return nil
}

private func NJClipboardWebLink() -> (url: URL, title: String?)? {
    let pb = UIPasteboard.general

    if let url = NJNormalizedURL(from: pb.url) {
        let rawTitle = pb.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (rawTitle?.isEmpty == false && rawTitle != url.absoluteString) ? rawTitle : nil
        return (url, title)
    }

    for item in pb.items {
        if let url = NJNormalizedURL(from: item["public.url"]) {
            let rawTitle = (item["public.utf8-plain-text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty == false && rawTitle != url.absoluteString) ? rawTitle : nil
            return (url, title)
        }
    }

    if let s = pb.string, let url = NJNormalizedURL(from: s) {
        return (url, s)
    }

    return nil
}

private let NJTablePasteboardType = "com.notionjournal.table-json"
private let NJPhotoPasteboardType = "com.notionjournal.photo-json"

private func NJEncodeJSONObjectString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: []) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func NJDecodeJSONObject(_ string: String) -> [String: Any]? {
    guard let data = string.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data, options: []),
          let dict = value as? [String: Any] else { return nil }
    return dict
}

private func NJClipboardTablePayload() -> [String: Any]? {
    let pb = UIPasteboard.general

    for item in pb.items {
        if let data = item[NJTablePasteboardType] as? Data,
           let string = String(data: data, encoding: .utf8),
           let payload = NJDecodeJSONObject(string) {
            return payload
        }
        if let string = item[NJTablePasteboardType] as? String,
           let payload = NJDecodeJSONObject(string) {
            return payload
        }
    }

    return nil
}

private func NJSetClipboardTablePayload(_ payload: [String: Any], plainText: String) {
    guard let json = NJEncodeJSONObjectString(payload),
          let data = json.data(using: .utf8) else { return }
    UIPasteboard.general.setItems([[
        NJTablePasteboardType: data,
        "public.utf8-plain-text": plainText
    ]], options: [:])
}

private func NJClipboardPhotoPayload() -> [String: Any]? {
    let pb = UIPasteboard.general

    for item in pb.items {
        if let data = item[NJPhotoPasteboardType] as? Data,
           let string = String(data: data, encoding: .utf8),
           let payload = NJDecodeJSONObject(string) {
            return payload
        }
        if let string = item[NJPhotoPasteboardType] as? String,
           let payload = NJDecodeJSONObject(string) {
            return payload
        }
    }

    return nil
}

private func NJSetClipboardPhotoPayload(_ payload: [String: Any], image: UIImage) {
    guard let json = NJEncodeJSONObjectString(payload),
          let data = json.data(using: .utf8) else { return }

    if let png = image.pngData() {
        UIPasteboard.general.setItems([[
            NJPhotoPasteboardType: data,
            "public.png": png
        ]], options: [:])
        return
    }

    UIPasteboard.general.setItems([[
        NJPhotoPasteboardType: data,
        "com.apple.uikit.image": image
    ]], options: [:])
}

func NJInstallTextViewKeyCommandHook(_ tv: UITextView) {
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

        let tableOwner = (objc_getAssociatedObject(t, &NJTextViewTableOwnerKey) as? NJWeakTableAttachmentBox)?.owner
        guard t.njProtonHandle != nil || tableOwner != nil else { return existing }

        let mk: (String, UIKeyModifierFlags, Selector) -> UIKeyCommand = { input, flags, action in
            let c = UIKeyCommand(input: input, modifierFlags: flags, action: action)
            c.wantsPriorityOverSystemBehavior = true
            return c
        }

        var commands: [UIKeyCommand] = [
            mk("\t", [], #selector(UITextView.nj_tabIndent)),
            mk("\t", [.shift], #selector(UITextView.nj_tabOutdent))
        ]
        if tableOwner != nil {
            commands.append(mk("\r", [], #selector(UITextView.nj_tableReturn)))
        }
        if t.njProtonHandle != nil {
            commands.append(contentsOf: [
                mk("b", .command, #selector(UITextView.nj_cmdBold)),
                mk("i", .command, #selector(UITextView.nj_cmdItalic)),
                mk("u", .command, #selector(UITextView.nj_cmdUnderline)),
                mk("x", [.command, .shift], #selector(UITextView.nj_cmdStrike)),
                mk("]", .command, #selector(UITextView.nj_cmdIndent)),
                mk("[", .command, #selector(UITextView.nj_cmdOutdent))
            ])
        }

        return existing + commands

    }

    let newIMP = imp_implementationWithBlock(newBlock)
    method_setImplementation(method, newIMP)
}

func NJInstallTextViewPasteHook(_ tv: UITextView) {
    let cls: AnyClass = object_getClass(tv) ?? UITextView.self
    let key = ObjectIdentifier(cls)
    if NJPasteOriginalIMPByClass[key] != nil { return }

    let sel = #selector(UIResponderStandardEditActions.paste(_:))
    guard let method = class_getInstanceMethod(cls, sel) else { return }

    let origIMP = method_getImplementation(method)
    NJPasteOriginalIMPByClass[key] = origIMP

    typealias OrigFn = @convention(c) (AnyObject, Selector, Any?) -> Void
    let newBlock: @convention(block) (UITextView, Any?) -> Void = { t, sender in
        if let h = t.njProtonHandle {
            if let table = NJClipboardTablePayload() {
                let rows = (table["rows"] as? Int) ?? 2
                let cols = (table["cols"] as? Int) ?? 2
                let cells = (table["cells"] as? [Any])?.compactMap { $0 as? [String: Any] }
                let tableShortID = table["table_short_id"] as? String
                let tableName = table["table_name"] as? String
                h.insertTableAttachment(
                    rows: rows,
                    cols: cols,
                    cellsJSON: cells,
                    tableShortID: tableShortID,
                    tableName: tableName
                )
                h.snapshot(markUserEdit: true)
                if !t.isFirstResponder { _ = t.becomeFirstResponder() }
                return
            }

            if let img = NJClipboardImage() {
                let photoPayload = NJClipboardPhotoPayload()
                let fullRef = NJPhotoLibraryPresenter.saveFullPhotoToICloud(image: img) ?? ""
                if !fullRef.isEmpty {
                    let displayWidth = CGFloat((photoPayload?["display_w"] as? Int) ?? 400)
                    h.insertPhotoAttachment(img, displayWidth: displayWidth, fullPhotoRef: fullRef)
                    h.snapshot(markUserEdit: true)
                    if !t.isFirstResponder { _ = t.becomeFirstResponder() }
                    return
                }
            }

            if let link = NJClipboardWebLink() {
                h.insertLink(link.url, title: link.title)
                h.snapshot(markUserEdit: true)
                if !t.isFirstResponder { _ = t.becomeFirstResponder() }
                return
            }
        }

        guard let imp = NJPasteOriginalIMPByClass[key] else { return }
        let f = unsafeBitCast(imp, to: OrigFn.self)
        f(t, sel, sender)
    }

    let newIMP = imp_implementationWithBlock(newBlock)
    method_setImplementation(method, newIMP)
}

func NJInstallTextViewCanPerformActionHook(_ tv: UITextView) {
    let cls: AnyClass = object_getClass(tv) ?? UITextView.self
    let key = ObjectIdentifier(cls)
    if NJCanPerformActionOriginalIMPByClass[key] != nil { return }

    let sel = #selector(UIResponder.canPerformAction(_:withSender:))
    guard let method = class_getInstanceMethod(cls, sel) else { return }

    let origIMP = method_getImplementation(method)
    NJCanPerformActionOriginalIMPByClass[key] = origIMP

    typealias OrigFn = @convention(c) (AnyObject, Selector, Selector, Any?) -> Bool
    let newBlock: @convention(block) (UITextView, Selector, Any?) -> Bool = { t, action, sender in
        var allowed = false
        if let imp = NJCanPerformActionOriginalIMPByClass[key] {
            let f = unsafeBitCast(imp, to: OrigFn.self)
            allowed = f(t, sel, action, sender)
        }

        if let owner = (objc_getAssociatedObject(t, &NJTextViewTableOwnerKey) as? NJWeakTableAttachmentBox)?.owner,
           owner.shouldSuppressSystemEditMenu(for: t) {
            return false
        }

        if action == #selector(UIResponderStandardEditActions.paste(_:)),
           !allowed,
           t.njProtonHandle != nil,
           (NJClipboardImage() != nil || NJClipboardTablePayload() != nil) {
            return true
        }

        return allowed
    }

    let newIMP = imp_implementationWithBlock(newBlock)
    method_setImplementation(method, newIMP)
}


final class NJProtonListFormattingProvider: EditorListFormattingProvider {
    let listLineFormatting = LineFormatting(indentation: 24, spacingBefore: 2, spacingAfter: 2)
    private let font: UIFont = NJCanonicalBodyFont()

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

private func NJSanitizeSuspiciousBodyBold(_ input: NSAttributedString, baseFont: UIFont) -> NSAttributedString {
    guard input.length > 0 else { return input }

    let full = NSRange(location: 0, length: input.length)
    let bodySize = baseFont.pointSize
    var bodyChars = 0
    var boldBodyChars = 0

    input.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
        let font = (value as? UIFont) ?? baseFont
        let sizeMatchesBody = abs(font.pointSize - bodySize) < 0.6
        guard sizeMatchesBody else { return }

        let sample = input.attributedSubstring(from: range).string
        let visibleCount = sample.filter { !$0.isWhitespace && !$0.isNewline }.count
        bodyChars += visibleCount
        if NJHasExplicitBoldTrait(font) {
            boldBodyChars += visibleCount
        }
    }

    guard bodyChars >= 20 else { return input }
    let boldRatio = Double(boldBodyChars) / Double(max(bodyChars, 1))
    guard boldRatio > 0.75 else { return input }

    let out = NSMutableAttributedString(attributedString: input)
    out.beginEditing()
    out.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
        let old = (value as? UIFont) ?? baseFont
        let sizeMatchesBody = abs(old.pointSize - bodySize) < 0.6
        guard sizeMatchesBody, NJHasExplicitBoldTrait(old) else { return }
        let italic = old.fontDescriptor.symbolicTraits.contains(.traitItalic)
        out.addAttribute(
            .font,
            value: NJCanonicalBodyFont(size: old.pointSize, bold: false, italic: italic),
            range: range
        )
    }
    out.endEditing()
    return out
}

private func NJShouldLogIPadEditorDebug() -> Bool {
    UIDevice.current.userInterfaceIdiom == .pad
}

private func NJDebugFontSummary(_ attr: NSAttributedString, selection: NSRange? = nil, limit: Int = 6) -> String {
    guard attr.length > 0 else { return "len=0" }

    var parts: [String] = ["len=\(attr.length)"]
    if let selection {
        parts.append("sel=\(selection.location),\(selection.length)")
    }

    let cappedLength = min(attr.length, 240)
    let probeRange = NSRange(location: 0, length: cappedLength)
    var runCount = 0
    attr.enumerateAttribute(.font, in: probeRange, options: []) { value, range, stop in
        guard runCount < limit else {
            stop.pointee = true
            return
        }
        let font = value as? UIFont
        let size = Int((font?.pointSize ?? NJCanonicalBodyFont().pointSize).rounded())
        let bold = font.map(NJHasExplicitBoldTrait) ?? false
        let italic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
        let sample = attr.attributedSubstring(from: range).string
            .replacingOccurrences(of: "\n", with: "\\n")
        let trimmed = String(sample.prefix(18))
        parts.append("[\(range.location),\(range.length):b=\(bold ? 1 : 0),i=\(italic ? 1 : 0),s=\(size),\"\(trimmed)\"]")
        runCount += 1
    }
    return parts.joined(separator: " ")
}

private func NJLogIPadEditorDebug(_ event: String, attr: NSAttributedString, selection: NSRange? = nil, typingAttributes: [NSAttributedString.Key: Any]? = nil) {
    guard NJShouldLogIPadEditorDebug() else { return }
    var message = "NJ_IPAD_EDITOR \(event) \(NJDebugFontSummary(attr, selection: selection))"
    if let typingAttributes,
       let font = typingAttributes[.font] as? UIFont {
        let bold = NJHasExplicitBoldTrait(font)
        let italic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        message += " typingFont(b=\(bold ? 1 : 0),i=\(italic ? 1 : 0),s=\(Int(font.pointSize.rounded())))"
    }
    print(message)
}

final class NJProtonEditorHandle {
    private static weak var _activeHandle: NJProtonEditorHandle?

    static func activeHandle() -> NJProtonEditorHandle? {
        _activeHandle
    }

    static func firstResponderHandle() -> NJProtonEditorHandle? {
        func findFirstResponder(in view: UIView) -> UIResponder? {
            if view.isFirstResponder { return view }
            for sub in view.subviews {
                if let hit = findFirstResponder(in: sub) { return hit }
            }
            return nil
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows where window.isKeyWindow {
                if let tv = findFirstResponder(in: window) as? UITextView,
                   let h = tv.njProtonHandle {
                    return h
                }
            }
        }

        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
           let tv = findFirstResponder(in: window) as? UITextView,
           let h = tv.njProtonHandle {
            return h
        }

        return nil
    }

    func markAsActiveHandle() {
        NJProtonEditorHandle._activeHandle = self
    }

    weak var editor: EditorView?
    var debugName: String = ""
    var ownerBlockUUID: UUID? = nil
    var isEditing: Bool = false
    var isRunningProgrammaticUpdate: Bool = false
    var userEditSourceHint: String = "unknown"
    var withProgrammatic: (((() -> Void)) -> Void)? = nil
    var attachmentResolver: ((String) -> NJAttachmentRecord?)? = nil
    var attachmentThumbPathCleaner: ((String) -> Void)? = nil
    var onOpenFullPhoto: ((String) -> Void)? = nil
    var onTableAction: ((String, NJTableAction) -> Void)? = nil
    var onDeletePhotoAttachment: ((String) -> Void)? = nil
    
    var onSnapshot: ((NSAttributedString, NSRange) -> Void)?
    var onUserTyped: ((NSAttributedString, NSRange) -> Void)?
    var onEndEditing: ((NSAttributedString, NSRange) -> Void)?
    var onHydratedSnapshot: ((NSAttributedString, NSRange) -> Void)?
    var onRequestRemeasure: (() -> Void)?
    
    private var pendingHydrateProtonJSON: String? = nil

    private var isActivelyEditingText: Bool {
        if isEditing || (textView?.isFirstResponder ?? false) {
            return true
        }
        if let ownerBlockUUID,
           let responder = NJProtonEditorHandle.firstResponderHandle(),
           responder !== self,
           responder.ownerBlockUUID == ownerBlockUUID,
           (responder.isEditing || (responder.textView?.isFirstResponder ?? false)) {
            return true
        }
        if let ownerBlockUUID,
           let active = NJProtonEditorHandle.activeHandle(),
           active !== self,
           active.ownerBlockUUID == ownerBlockUUID,
           (active.isEditing || (active.textView?.isFirstResponder ?? false)) {
            return true
        }
        return false
    }

    func discardPendingHydration() {
        pendingHydrateProtonJSON = nil
        pendingJSON = nil
        hydrationScheduled = false
    }

    func indent() { adjustIndent(delta: 24) }
    func outdent() { adjustIndent(delta: -24) }
    
    func exportProtonJSONString() -> String {
        guard let editor else { return "" }
        return exportProtonJSONString(from: editor.attributedText)
    }

    func exportProtonJSONString(from text: NSAttributedString) -> String {
        let exportText = NJEditorCanonicalizeRichText(
            NJProtonListNormalizer.apply(
                synchronizedAttachmentTextForExport(text)
            )
        )
        return NJProtonDocCodecV2.encodeDocument(from: exportText)
    }
    
    func previewFirstLineFromProtonJSON(_ json: String) -> String {
        let decoded = decodeAttributedStringFromProtonJSONString(json, interactive: false)

        let s = decoded.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        return s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    private struct NJLegacyProtonDocCodec {

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
            if let rtfd = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            ) {
                return rtfd
            }
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        }
    }

    private struct NJProtonDocCodecV2 {
        private static let schema = "nj_proton_doc_v2"

        static func containsBlockAttachments(_ text: NSAttributedString) -> Bool {
            if text.length == 0 { return false }
            var found = false
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
                guard let att = value as? Attachment else { return }
                if att.isBlockType {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

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

        static func buildAttributedString(
            doc: [[String: Any]],
            resolveAttachment: ((String) -> NJAttachmentRecord?)?,
            onMissingThumb: ((String) -> Void)?,
            onOpenFullPhoto: ((String) -> Void)?,
            onTableAction: ((String, NJTableAction) -> Void)?,
            onDeletePhoto: ((String) -> Void)?,
            onResizePhoto: ((String, CGSize) -> Void)?,
            onCollapsibleContentChange: (() -> Void)?,
            onCollapsibleContentCommit: (() -> Void)?,
            onCollapsibleToggle: ((String) -> Void)?,
            onAttachmentLayoutChange: (() -> Void)?
        ) -> NSAttributedString {
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
                    let listAttr = buildListAttributedString(items)
                    out.append(listAttr)
                    continue
                }

                if t == "attachment" {
                    if let att = decodeAttachment(
                        seg,
                        resolveAttachment: resolveAttachment,
                        onMissingThumb: onMissingThumb,
                        onOpenFullPhoto: onOpenFullPhoto,
                        onTableAction: onTableAction,
                        onDeletePhoto: onDeletePhoto,
                        onResizePhoto: onResizePhoto,
                        onCollapsibleContentChange: onCollapsibleContentChange,
                        onCollapsibleContentCommit: onCollapsibleContentCommit,
                        onCollapsibleToggle: onCollapsibleToggle,
                        onAttachmentLayoutChange: onAttachmentLayoutChange
                    ) {
                        out.append(att)
                    }
                }
            }

            return out
        }

        private enum Segment {
            case text(NSAttributedString)
            case attachment(Attachment, UIView)
        }

        private static func buildDoc(from text: NSAttributedString) -> [[String: Any]] {
            let segments = splitByBlockAttachments(text)
            var doc: [[String: Any]] = []

            for seg in segments {
                switch seg {
                case .text(let sub):
                    let textDoc = textDocSegments(from: sub)
                    doc.append(contentsOf: textDoc)
                case .attachment(_, let view):
                    if let node = encodeAttachment(view) {
                        doc.append(node)
                    }
                }
            }

            if doc.isEmpty {
                doc.append(["type": "rich", "rtf_base64": encodeRTFBase64(text) ?? ""])
            }

            return doc
        }

        private static func splitByBlockAttachments(_ text: NSAttributedString) -> [Segment] {
            let full = NSRange(location: 0, length: text.length)
            var attachments: [(NSRange, Attachment, UIView)] = []

            text.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
                guard let att = value as? Attachment else { return }
                guard att.isBlockType else { return }
                guard let view = att.contentView else { return }
                attachments.append((range, att, view))
            }

            if attachments.isEmpty { return [.text(text)] }

            attachments.sort { $0.0.location < $1.0.location }

            var segments: [Segment] = []
            var pos = 0

            for (range, att, view) in attachments {
                if range.location > pos {
                    let sub = text.attributedSubstring(from: NSRange(location: pos, length: range.location - pos))
                    if sub.length > 0 { segments.append(.text(sub)) }
                }
                segments.append(.attachment(att, view))
                pos = range.location + range.length
            }

            if pos < text.length {
                let sub = text.attributedSubstring(from: NSRange(location: pos, length: text.length - pos))
                if sub.length > 0 { segments.append(.text(sub)) }
            }

            return segments
        }

        private static func textDocSegments(from text: NSAttributedString) -> [[String: Any]] {
            let fullLen = text.length
            if fullLen == 0 {
                return [["type": "rich", "rtf_base64": encodeRTFBase64(text) ?? ""]]
            }

            let parsed = ListParser.parse(attributedString: text, indent: 24)
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

            func normalizeKind(_ v: Any) -> String {
                if let tl = v as? NSTextList { return (tl.markerFormat == .decimal) ? "number" : "bullet" }
                if let tls = v as? [NSTextList], let tl = tls.first { return (tl.markerFormat == .decimal) ? "number" : "bullet" }
                if let s = v as? String { return (s == "number") ? "number" : "bullet" }
                return "bullet"
            }

            func normalizeListItem(_ li: ListItem) -> ListItem {
                ListItem(text: li.text, level: li.level, attributeValue: normalizeKind(li.attributeValue))
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
                    itemsJSON.append([
                        "level": li.level,
                        "kind": normalizeKind(li.attributeValue),
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

        private static func encodeAttachment(_ view: UIView) -> [String: Any]? {
            if let v = view as? NJPhotoAttachmentView {
                return [
                    "type": "attachment",
                    "kind": "photo",
                    "attachment_id": v.attachmentID,
                    "display_w": Int(v.displaySize.width),
                    "display_h": Int(v.displaySize.height)
                ]
            }
            if let v = view as? NJTableAttachmentView {
                var node: [String: Any] = [
                    "type": "attachment",
                    "kind": "table",
                    "attachment_id": v.attachmentID
                ]
                node["table"] = encodeTable(v)
                return node
            }
            if let v = view as? NJCollapsibleAttachmentView {
                let bodyForExport = v.currentBodyAttributedTextForExport()
                return [
                    "type": "attachment",
                    "kind": "collapsible",
                    "attachment_id": v.attachmentID,
                    "collapsed": v.isCollapsed,
                    "title_rtf_base64": encodeRTFBase64(v.titleAttributedText) ?? "",
                    "body_rtf_base64": encodeRTFBase64(bodyForExport) ?? "",
                    "body_proton_json": v.bodyProtonJSONString
                ]
            }
            return nil
        }

        private static func encodeTable(_ view: NJTableAttachmentView) -> [String: Any] {
            let cellsJSON = view.tableCellsForExport()
            let rows = cellsJSON.compactMap { $0["row"] as? Int }.max().map { $0 + 1 } ?? 1
            let cols = cellsJSON.compactMap { $0["col"] as? Int }.max().map { $0 + 1 } ?? 1
            var renderPayload: [String: Any] = [
                "table_id": view.attachmentID,
                "rows": rows,
                "cols": cols,
                "table_short_id": view.tableShortIDForExport()
            ]
            if let tableName = view.tableNameForExport(),
               !tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                renderPayload["table_name"] = tableName
            }
            return renderPayload
        }

        private static func decodeAttachment(
            _ node: [String: Any],
            resolveAttachment: ((String) -> NJAttachmentRecord?)?,
            onMissingThumb: ((String) -> Void)?,
            onOpenFullPhoto: ((String) -> Void)?,
            onTableAction: ((String, NJTableAction) -> Void)?,
            onDeletePhoto: ((String) -> Void)?,
            onResizePhoto: ((String, CGSize) -> Void)?,
            onCollapsibleContentChange: (() -> Void)?,
            onCollapsibleContentCommit: (() -> Void)?,
            onCollapsibleToggle: ((String) -> Void)?,
            onAttachmentLayoutChange: (() -> Void)?
        ) -> NSAttributedString? {
            let kind = (node["kind"] as? String) ?? ""
            let attachmentID = (node["attachment_id"] as? String) ?? UUID().uuidString

            if kind == "photo" {
                let w = CGFloat((node["display_w"] as? Int) ?? 400)
                let h = CGFloat((node["display_h"] as? Int) ?? 400)
                let size = CGSize(width: max(1, w), height: max(1, h))
                let record = resolveAttachment?(attachmentID)
                var image: UIImage? = nil

                if let record, !record.thumbPath.isEmpty {
                    image = NJAttachmentCache.imageFromPath(record.thumbPath)
                    if image == nil { onMissingThumb?(attachmentID) }
                }

                if image == nil, let url = NJAttachmentCache.fileURL(for: attachmentID),
                   FileManager.default.fileExists(atPath: url.path) {
                    image = UIImage(contentsOfFile: url.path)
                }

                let view = NJPhotoAttachmentView(
                    attachmentID: attachmentID,
                    size: size,
                    image: image,
                    fullPhotoRef: record?.fullPhotoRef ?? ""
                )
                if let onOpenFullPhoto {
                    view.onOpenFull = onOpenFullPhoto
                }
                view.onDelete = { onDeletePhoto?(attachmentID) }
                view.onCopy = { [weak view] in
                    guard let view else { return }
                    let payload: [String: Any] = [
                        "attachment_id": attachmentID,
                        "display_w": Int(view.displaySize.width),
                        "display_h": Int(view.displaySize.height)
                    ]
                    if let image = view.image {
                        NJSetClipboardPhotoPayload(payload, image: image)
                    }
                }
                view.onCut = { [weak view] in
                    guard let view else { return }
                    let payload: [String: Any] = [
                        "attachment_id": attachmentID,
                        "display_w": Int(view.displaySize.width),
                        "display_h": Int(view.displaySize.height)
                    ]
                    if let image = view.image {
                        NJSetClipboardPhotoPayload(payload, image: image)
                    }
                    onDeletePhoto?(attachmentID)
                }
                view.onResize = { [weak view] in
                    guard let view else { return }
                    onResizePhoto?(attachmentID, view.displaySize)
                    onAttachmentLayoutChange?()
                    onCollapsibleContentChange?()
                }
                if image == nil {
                    view.backgroundColor = UIColor.secondarySystemFill
                    NJAttachmentCloudFetcher.fetchThumbIfNeeded(attachmentID: attachmentID) { img in
                        guard let img else { return }
                        view.backgroundColor = .clear
                        view.updateImage(img)
                    }
                }
                let att = Attachment(view, size: .matchContent)
                view.boundsObserver = att
                att.selectOnTap = false
                att.selectBeforeDelete = false
                return att.string
            }

            if kind == "table" {
                guard let embeddedTable = node["table"] as? [String: Any] else { return nil }
                let rawTableID = ((embeddedTable["table_id"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let tableID = rawTableID.isEmpty ? attachmentID : rawTableID
                let loadedCanonical = NJTableStore.shared.loadCanonicalPayload(tableID: tableID)
                let table = loadedCanonical ?? embeddedTable
                if loadedCanonical == nil {
                    var migrated = table
                    migrated["table_id"] = tableID
                    NJTableStore.shared.cacheCanonicalPayload(tableID: tableID, payload: migrated)
                }
                let rows = (table["rows"] as? Int) ?? 2
                let cols = (table["cols"] as? Int) ?? 2
                let cellsAny = (table["cells"] as? [Any]) ?? []
                let cellsJSON = cellsAny.compactMap { $0 as? [String: Any] }
                let widthValues = ((table["column_widths"] as? [Any]) ?? []).compactMap {
                    if let n = $0 as? NSNumber { return CGFloat(truncating: n) }
                    if let d = $0 as? Double { return CGFloat(d) }
                    if let i = $0 as? Int { return CGFloat(i) }
                    return nil
                }
                let alignmentValues = ((table["column_alignments"] as? [Any]) ?? []).compactMap {
                    ($0 as? String)
                }
                let columnTypeValues = ((table["column_types"] as? [Any]) ?? []).compactMap {
                    ($0 as? String)
                }
                let columnFormulaValues = ((table["column_formulas"] as? [Any]) ?? []).compactMap {
                    ($0 as? String)
                }
                let totalFormulaValues = ((table["total_formulas"] as? [Any]) ?? []).compactMap {
                    ($0 as? String)
                }
                let totalsEnabled = (table["totals_enabled"] as? Bool) ?? false
                let columnFilterValues = ((table["column_filters"] as? [Any]) ?? []).compactMap {
                    ($0 as? String)
                }
                let hideCheckedRows = (table["hide_checked_rows"] as? Bool) ?? false
                let sortColumn = table["sort_column"] as? Int
                let sortDirection = table["sort_direction"] as? String
                let tableShortID = table["table_short_id"] as? String
                let tableName = table["table_name"] as? String

                let columns: [GridColumnConfiguration] = {
                    let safeCols = max(1, cols)
                    if widthValues.count == safeCols {
                        return widthValues.map { GridColumnConfiguration(width: .fixed(max(1, $0))) }
                    }
                    let colWidth: CGFloat = safeCols > 0 ? 1.0 / CGFloat(safeCols) : 1.0
                    return (0..<safeCols).map { _ in GridColumnConfiguration(width: .fractional(colWidth)) }
                }()
                let rowsCfg = (0..<max(1, rows)).map { _ in GridRowConfiguration(initialHeight: NJTableDefaultRowHeight) }

                let config = GridConfiguration(
                    columnsConfiguration: columns,
                    rowsConfiguration: rowsCfg,
                    style: .default,
                    boundsLimitShadowColors: GradientColors(primary: .black, secondary: .white),
                    collapsedColumnWidth: 2,
                    collapsedRowHeight: 2,
                    ignoresOptimizedInit: true
                )

                var cells: [GridCell] = []
                cells.reserveCapacity(max(1, rows) * max(1, cols))

                for r in 0..<max(1, rows) {
                    for c in 0..<max(1, cols) {
                        let cell = GridCell(rowSpan: [r], columnSpan: [c], initialHeight: NJTableDefaultRowHeight, ignoresOptimizedInit: true)
                        cell.editor.forceApplyAttributedText = true
                        cells.append(cell)
                    }
                }

                for c in cellsJSON {
                    let row = (c["row"] as? Int) ?? 0
                    let col = (c["col"] as? Int) ?? 0
                    let rtf = (c["rtf_base64"] as? String) ?? ""
                    let idx = (row * max(1, cols)) + col
                    if idx >= 0 && idx < cells.count {
                        let cell = cells[idx]
                        if let a = decodeRTFBase64(rtf) {
                            cell.editor.attributedText = a
                        }
                    }
                }

                let tableAttachment = NJTableAttachmentFactory.make(
                    attachmentID: attachmentID,
                    config: config,
                    cells: cells,
                    columnWidths: widthValues.count == max(1, cols) ? widthValues : nil,
                    columnAlignments: alignmentValues.count == max(1, cols) ? alignmentValues : nil,
                    columnTypes: columnTypeValues.count == max(1, cols) ? columnTypeValues : nil,
                    columnFormulas: columnFormulaValues.count == max(1, cols) ? columnFormulaValues : nil,
                    totalsEnabled: totalsEnabled,
                    totalFormulas: totalFormulaValues.count == max(1, cols) ? totalFormulaValues : nil,
                    hideCheckedRows: hideCheckedRows,
                    columnFilters: columnFilterValues.count == max(1, cols) ? columnFilterValues : nil,
                    sortColumn: sortColumn,
                    sortDirection: sortDirection,
                    tableShortID: tableShortID,
                    tableName: tableName,
                    onTableAction: onTableAction,
                    onResizeTable: { _ in
                        onAttachmentLayoutChange?()
                    }
                )
                return tableAttachment.string
            }

            if kind == "collapsible" {
                let collapsed = (node["collapsed"] as? Bool) ?? false
                let titleB64 = (node["title_rtf_base64"] as? String) ?? ""
                let bodyB64 = (node["body_rtf_base64"] as? String) ?? ""
                let title = decodeRTFBase64(titleB64) ?? NSAttributedString(string: "Section")
                let bodyJSON = (node["body_proton_json"] as? String) ?? ""
                let body = decodeRTFBase64(bodyB64) ?? NSAttributedString(string: "")
                let view = NJCollapsibleAttachmentView(
                    attachmentID: attachmentID,
                    title: title,
                    body: body,
                    bodyProtonJSON: bodyJSON,
                    isCollapsed: collapsed
                )
                view.onContentChange = onCollapsibleContentChange
                view.onContentCommit = onCollapsibleContentCommit
                view.onCollapseToggle = { onCollapsibleToggle?(attachmentID) }
                view.onLayoutChange = onAttachmentLayoutChange
                let att = Attachment(view, size: .fullWidth)
                view.boundsObserver = att
                att.selectOnTap = false
                att.selectBeforeDelete = false
                return att.string
            }

            return nil
        }

        private static func buildListAttributedString(_ items: [[String: Any]]) -> NSAttributedString {
            var listItems: [ListItem] = []
            listItems.reserveCapacity(items.count)

            for it in items {
                let lvl = max(0, (it["level"] as? Int) ?? 0)
                let kind = (it["kind"] as? String) ?? "bullet"
                let b64 = (it["rtf_base64"] as? String) ?? ""
                let text = decodeRTFBase64(b64) ?? NSAttributedString(string: "")
                listItems.append(ListItem(text: text, level: lvl, attributeValue: kind))
            }

            let parsed = ListParser.parse(list: listItems, indent: 24)
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

            return a
        }

        private static func encodeRTFBase64(_ s: NSAttributedString) -> String? {
            let r = NSRange(location: 0, length: s.length)
            guard let data = try? s.data(from: r, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return nil }
            return data.base64EncodedString()
        }

        private static func decodeRTFBase64(_ b64: String) -> NSAttributedString? {
            guard let data = Data(base64Encoded: b64) else { return nil }
            if let rtfd = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            ) {
                return rtfd
            }
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
        decodeAttributedStringFromProtonJSONString(json, interactive: true)
    }

    private func decodeAttributedStringFromProtonJSONString(_ json: String, interactive: Bool) -> NSAttributedString {
        if let doc = NJProtonDocCodecV2.decodeIfPresent(json: json) {
            let decoded = NJProtonDocCodecV2.buildAttributedString(
                doc: doc,
                resolveAttachment: interactive ? { [weak self] id in self?.attachmentResolver?(id) } : nil,
                onMissingThumb: interactive ? { [weak self] id in self?.attachmentThumbPathCleaner?(id) } : nil,
                onOpenFullPhoto: interactive ? { [weak self] id in self?.onOpenFullPhoto?(id) } : nil,
                onTableAction: interactive ? { [weak self] id, action in
                    self?.handleTableAction(attachmentID: id, action: action)
                } : nil,
                onDeletePhoto: interactive ? { [weak self] id in
                    self?.deletePhotoAttachment(attachmentID: id)
                } : nil,
                onResizePhoto: interactive ? { [weak self] id, size in
                    self?.replacePhotoAttachment(attachmentID: id, size: size)
                } : nil,
                onCollapsibleContentChange: interactive ? { [weak self] in
                    self?.handleCollapsibleContentChanged()
                } : nil,
                onCollapsibleContentCommit: interactive ? { [weak self] in
                    self?.handleCollapsibleContentCommitted()
                } : nil,
                onCollapsibleToggle: interactive ? { [weak self] id in
                    self?.replaceCollapsibleAttachment(attachmentID: id, shouldSnapshot: false)
                } : nil,
                onAttachmentLayoutChange: interactive ? { [weak self] in
                    self?.onRequestRemeasure?()
                } : nil
            )
            return NJEditorCanonicalizeRichText(NJProtonListNormalizer.apply(decoded))
        }

        if let doc = NJLegacyProtonDocCodec.decodeIfPresent(json: json) {
            return NJEditorCanonicalizeRichText(
                NJProtonListNormalizer.apply(
                    NJLegacyProtonDocCodec.buildAttributedString(doc: doc)
                )
            )
        }

        if let nodes = NJProtonNodeCodecV1.decodeNodesIfPresent(json: json) {
            return NJEditorCanonicalizeRichText(
                NJProtonListNormalizer.apply(
                    NJProtonNodeCodecV1.buildAttributedString(nodes: nodes)
                )
            )
        }

        let out = NSMutableAttributedString()

        guard
            let data = json.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            let mode = njDefaultContentMode()
            let maxSize = CGSize(width: 4096, height: 4096)
            let decoded = (try? NJProtonAuditCodec.decoder.decodeDocument(mode: mode, maxSize: maxSize, json: json)) ?? NSAttributedString(string: "")
            return NJEditorCanonicalizeRichText(NJProtonListNormalizer.apply(decoded))
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

        return NJEditorCanonicalizeRichText(out)
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
        toggleList(.bullet)
    }

    func toggleNumber() {
        toggleList(.number)
    }
    
    func toggleUnderline() { toggleUnderlineStyle() }

    func focus() {
        markAsActiveHandle()
        if let tv = textView, owns(textView: tv) {
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
        isEditing = true

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

    private func toggleList(_ kind: NJListKind) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        isEditing = true
        normalizeListAttributesInTextStorage(tv)

        if selectionIsEntirelyList(kind: kind, in: tv) {
            clearListFormatting(in: tv)
        } else {
            let tl = NSTextList(
                markerFormat: kind == .number ? .decimal : .disc,
                options: 0
            )
            ListCommand().execute(on: editor, attributeValue: tl)
            normalizeListAttributesInTextStorage(tv)
        }

        snapshot()
    }

    private func selectionIsEntirelyList(kind: NJListKind, in tv: UITextView) -> Bool {
        let paragraphRanges = paragraphRangesCovered(by: tv.selectedRange, in: tv.attributedText)
        guard !paragraphRanges.isEmpty else { return false }

        return paragraphRanges.allSatisfy { range in
            NJProtonListNormalizer.paragraphListKind(in: tv.attributedText, paragraphRange: range) == kind
        }
    }

    private func clearListFormatting(in tv: UITextView) {
        let storage = tv.textStorage
        let paragraphRanges = paragraphRangesCovered(by: tv.selectedRange, in: storage)
        guard !paragraphRanges.isEmpty else { return }

        storage.beginEditing()
        for range in paragraphRanges.reversed() {
            storage.removeAttribute(.listItem, range: range)
            storage.removeAttribute(.skipNextListMarker, range: range)

            let currentStyle = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            currentStyle.textLists = []
            currentStyle.headIndent = 0
            currentStyle.firstLineHeadIndent = 0
            storage.addAttribute(.paragraphStyle, value: currentStyle, range: range)
        }
        storage.endEditing()

        if let style = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
            let mutable = style.mutableCopy() as! NSMutableParagraphStyle
            mutable.textLists = []
            mutable.headIndent = 0
            mutable.firstLineHeadIndent = 0
            tv.typingAttributes[.paragraphStyle] = mutable
        }
    }

    private func paragraphRangesCovered(by selectedRange: NSRange, in text: NSAttributedString) -> [NSRange] {
        let ns = text.string as NSString
        guard ns.length > 0 else { return [] }

        let start = min(max(0, selectedRange.location), ns.length - 1)
        let end = min(
            max(start, selectedRange.location + max(0, selectedRange.length) - 1),
            ns.length - 1
        )

        let covered = ns.paragraphRange(for: NSRange(location: start, length: max(0, end - start)))
        var out: [NSRange] = []
        var cursor = covered.location

        while cursor < NSMaxRange(covered) {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            out.append(para)
            cursor = NSMaxRange(para)
        }

        if out.isEmpty {
            out.append(ns.paragraphRange(for: NSRange(location: start, length: 0)))
        }
        return out
    }

    private func normalizeListAttributesInTextStorage(_ tv: UITextView) {
        let storage = tv.textStorage
        guard storage.length > 0 else { return }

        storage.beginEditing()
        _ = NJProtonListNormalizer.normalizeTextStorage(storage)
        storage.endEditing()
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

    func insertPhotoAttachment(
        _ image: UIImage,
        displayWidth: CGFloat = NJPhotoAttachmentView.defaultDisplayWidth,
        fullPhotoRef: String = ""
    ) {
        guard let editor else { return }
        let attachmentID = UUID().uuidString

        let saved = NJAttachmentCache.saveThumbnail(
            image: image,
            attachmentID: attachmentID,
            width: NJAttachmentCache.thumbWidth
        )
        let size = {
            let w = max(1, displayWidth)
            let ratio = image.size.height / max(1, image.size.width)
            let h = max(1, w * ratio)
            return CGSize(width: w, height: h)
        }()

        let thumbImage = saved.flatMap { UIImage(contentsOfFile: $0.url.path) } ?? image
        let att = buildPhotoAttachment(
            attachmentID: attachmentID,
            size: size,
            image: thumbImage,
            fullPhotoRef: fullPhotoRef
        )

        let tv = activeTextView()
        let sourceText = tv?.attributedText ?? editor.attributedText
        let s = NSMutableAttributedString(attributedString: sourceText ?? NSAttributedString(string: ""))
        let rawRange = tv?.selectedRange ?? editor.selectedRange
        let r = clampedSelection(rawRange, maxLength: s.length)
        print("NJ_PHOTO_INSERT owner=\(String(describing: ownerBlockUUID)) sel=\(r.location):\(r.length) textLen=\(s.length)")
        let breakout = shouldBreakOutOfListForAttachment(in: editor, selectedRange: r)
        let insertion = attachmentInsertionString(
            att.string,
            breakoutFromList: breakout,
            baseText: s.string as NSString,
            selectedRange: r
        )
        s.replaceCharacters(in: r, with: insertion)
        if breakout {
            let insertedRange = NSRange(location: r.location, length: insertion.length)
            sanitizeListAttributesForAttachment(in: s, insertedRange: insertedRange)
        }

        editor.attributedText = s
        let newRange = NSRange(location: min(r.location + insertion.length, s.length), length: 0)
        editor.selectedRange = newRange
        tv?.selectedRange = newRange

        snapshot()
    }

    func insertTableAttachment(
        rows: Int = 2,
        cols: Int = 2,
        cellsJSON: [[String: Any]]? = nil,
        tableShortID: String? = nil,
        tableName: String? = nil
    ) {
        guard let editor else { return }
        isEditing = true
        let rCount = max(1, rows)
        let cCount = max(1, cols)

        let attachmentID = UUID().uuidString
        let attachment = buildTableAttachment(
            attachmentID: attachmentID,
            rows: rCount,
            cols: cCount,
            cellsJSON: cellsJSON,
            tableShortID: tableShortID,
            tableName: tableName
        )
        if let tableView = attachment.contentView as? NJTableAttachmentView {
            saveTableCanonicalPayload(from: tableView)
        }
        let tv = activeTextView()
        let sourceText = tv?.attributedText ?? editor.attributedText
        let s = NSMutableAttributedString(attributedString: sourceText ?? NSAttributedString(string: ""))
        let rawRange = tv?.selectedRange ?? editor.selectedRange
        let r = clampedSelection(rawRange, maxLength: s.length)
        let breakout = shouldBreakOutOfListForAttachment(in: editor, selectedRange: r)
        let insertion = attachmentInsertionString(
            attachment.string,
            breakoutFromList: breakout,
            baseText: s.string as NSString,
            selectedRange: r
        )
        s.replaceCharacters(in: r, with: insertion)
        if breakout {
            let insertedRange = NSRange(location: r.location, length: insertion.length)
            sanitizeListAttributesForAttachment(in: s, insertedRange: insertedRange)
        }

        editor.attributedText = s
        let newRange = NSRange(location: min(r.location + insertion.length, s.length), length: 0)
        editor.selectedRange = newRange
        tv?.selectedRange = newRange

        snapshot()
    }

    func convertSelectionToCollapsibleSection() {
        guard let editor else { return }
        isEditing = true
        let tv = activeTextView()
        let sourceText = tv?.attributedText ?? editor.attributedText
        let s = NSMutableAttributedString(attributedString: sourceText ?? NSAttributedString(string: ""))
        let rawRange = tv?.selectedRange ?? editor.selectedRange
        let cleanedRange = removeOrphanObjectPlaceholders(in: s, preserving: rawRange)
        var r = clampedSelection(cleanedRange, maxLength: s.length)

        if r.length == 0 {
            if s.length == 0 { return }
            let ns = s.string as NSString
            let probe = min(max(0, r.location), max(0, ns.length - 1))
            r = ns.paragraphRange(for: NSRange(location: probe, length: 0))
        }

        guard r.length > 0 else { return }
        let selected = s.attributedSubstring(from: r)
        let title = makeCollapsibleTitle(from: selected)
        let body = makeCollapsibleBody(from: selected, title: title.string)
        let attachmentID = UUID().uuidString
        let att = buildCollapsibleAttachment(
            attachmentID: attachmentID,
            title: title,
            body: body,
            isCollapsed: false
        )

        let breakout = shouldBreakOutOfListForAttachment(in: editor, selectedRange: r)
        let insertion = attachmentInsertionString(
            att.string,
            breakoutFromList: breakout,
            baseText: s.string as NSString,
            selectedRange: r
        )
        s.replaceCharacters(in: r, with: insertion)
        if breakout {
            let insertedRange = NSRange(location: r.location, length: insertion.length)
            sanitizeListAttributesForAttachment(in: s, insertedRange: insertedRange)
        }

        editor.attributedText = s
        let newRange = NSRange(location: min(r.location + insertion.length, s.length), length: 0)
        editor.selectedRange = newRange
        tv?.selectedRange = newRange
        snapshot()
    }

    private func removeOrphanObjectPlaceholders(
        in text: NSMutableAttributedString,
        preserving selection: NSRange
    ) -> NSRange {
        guard text.length > 0 else { return selection }
        var adjustedLocation = selection.location
        var adjustedLength = selection.length

        for idx in stride(from: text.length - 1, through: 0, by: -1) {
            let ch = (text.string as NSString).character(at: idx)
            guard ch == 0xFFFC else { continue }
            let attachment = text.attribute(.attachment, at: idx, effectiveRange: nil) as? Attachment
            if attachment?.isBlockType == true { continue }

            text.deleteCharacters(in: NSRange(location: idx, length: 1))
            if idx < adjustedLocation {
                adjustedLocation -= 1
            } else if idx < adjustedLocation + adjustedLength {
                adjustedLength = max(0, adjustedLength - 1)
            }
        }

        return NSRange(location: max(0, adjustedLocation), length: adjustedLength)
    }

    private func refreshEditorAfterCollapsibleMutation() {
        guard let editor else { return }
        let sel = editor.selectedRange
        let current = NSAttributedString(attributedString: editor.attributedText)
        editor.attributedText = current
        editor.selectedRange = clampedSelection(sel, maxLength: current.length)
        if let tv = activeTextView() {
            tv.selectedRange = clampedSelection(sel, maxLength: current.length)
        }
        snapshot()
    }

    private func buildCollapsibleAttachment(
        attachmentID: String,
        title: NSAttributedString,
        body: NSAttributedString,
        bodyProtonJSON: String? = nil,
        isCollapsed: Bool
    ) -> Attachment {
        let view = NJCollapsibleAttachmentView(
            attachmentID: attachmentID,
            title: title,
            body: body,
            bodyProtonJSON: bodyProtonJSON,
            isCollapsed: isCollapsed
        )
        view.onContentChange = { [weak self] in self?.handleCollapsibleContentChanged() }
        view.onContentCommit = { [weak self] in self?.handleCollapsibleContentCommitted() }
        view.onCollapseToggle = { [weak self] in
            self?.replaceCollapsibleAttachment(attachmentID: attachmentID, shouldSnapshot: false)
        }
        view.onLayoutChange = { [weak self] in self?.onRequestRemeasure?() }
        let att = Attachment(view, size: .fullWidth)
        view.boundsObserver = att
        att.selectOnTap = false
        att.selectBeforeDelete = false
        return att
    }

    func removeNearestCollapsibleSection() {
        guard let editor else { return }
        isEditing = true
        if let activeID = NJCollapsibleAttachmentView.activeAttachmentID() {
            if unwrapCollapsibleAttachment(attachmentID: activeID) { return }
        }
        let full = NSRange(location: 0, length: editor.attributedText.length)
        if full.length == 0 { return }

        let tv = activeTextView()
        let rawSelection = tv?.selectedRange ?? editor.selectedRange
        let selection = clampedSelection(rawSelection, maxLength: full.length)

        var target: (NSRange, NJCollapsibleAttachmentView)? = nil
        editor.attributedText.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
            guard let att = value as? Attachment else { return }
            guard att.isBlockType else { return }
            guard let view = att.contentView as? NJCollapsibleAttachmentView else { return }
            let intersects = selection.length > 0
                ? NSIntersectionRange(selection, range).length > 0
                : (selection.location >= range.location && selection.location <= range.location + range.length)
            if intersects {
                target = (range, view)
                stop.pointee = true
            }
        }

        guard let (_, view) = target else { return }
        _ = unwrapCollapsibleAttachment(attachmentID: view.attachmentID)
    }

    @discardableResult
    private func unwrapCollapsibleAttachment(attachmentID: String) -> Bool {
        guard let editor else { return false }
        guard let (range, view) = findCollapsibleAttachment(attachmentID: attachmentID, in: editor.attributedText) else { return false }

        let title = view.titleAttributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = view.currentBodyAttributedTextForExport()
        let replacement = NSMutableAttributedString()
        if !title.isEmpty {
            replacement.append(NSAttributedString(string: title + "\n"))
        }
        replacement.append(body)
        if replacement.length > 0 {
            let ns = replacement.string as NSString
            let last = ns.character(at: ns.length - 1)
            if last != 10 && last != 13 {
                replacement.append(NSAttributedString(string: "\n"))
            }
        }

        let s = NSMutableAttributedString(attributedString: editor.attributedText)
        s.replaceCharacters(in: range, with: replacement)
        editor.attributedText = s
        let newLoc = min(range.location + replacement.length, s.length)
        let newRange = NSRange(location: newLoc, length: 0)
        editor.selectedRange = newRange
        if let tv = activeTextView() {
            tv.selectedRange = newRange
        }
        snapshot()
        return true
    }

    private func clampedSelection(_ range: NSRange, maxLength: Int) -> NSRange {
        let safeLength = max(0, maxLength)
        let loc = min(max(0, range.location), safeLength)
        let len = min(max(0, range.length), safeLength - loc)
        return NSRange(location: loc, length: len)
    }

    private func makeCollapsibleTitle(from selected: NSAttributedString) -> NSAttributedString {
        let raw = selected.string
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        let first = raw.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let title = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSAttributedString(string: title.isEmpty ? "Section" : title)
    }

    private func makeCollapsibleBody(from selected: NSAttributedString, title: String) -> NSAttributedString {
        let withNewlines = normalizeLineSeparatorsForCollapsibleBody(selected)
        let trimmed = trimLeadingAndTrailingNewlines(from: withNewlines)
        if trimmed.length == 0 { return trimmed }
        let ns = trimmed.string as NSString
        let p0 = ns.paragraphRange(for: NSRange(location: 0, length: 0))
        let firstLine = ns.substring(with: p0).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && firstLine.caseInsensitiveCompare(title) == .orderedSame {
            let start = min(p0.location + p0.length, trimmed.length)
            let tail = trimmed.attributedSubstring(from: NSRange(location: start, length: max(0, trimmed.length - start)))
            return trimLeadingAndTrailingNewlines(from: tail)
        }
        return trimmed
    }

    private func normalizeLineSeparatorsForCollapsibleBody(_ input: NSAttributedString) -> NSAttributedString {
        guard input.length > 0 else { return input }
        let out = NSMutableAttributedString(attributedString: input)
        let full = NSRange(location: 0, length: out.length)
        let text = out.string as NSString
        var replacementRanges: [NSRange] = []
        for i in 0..<text.length {
            let c = text.character(at: i)
            if c == 0x2028 || c == 0x2029 {
                replacementRanges.append(NSRange(location: i, length: 1))
            }
        }
        if replacementRanges.isEmpty { return out }
        for r in replacementRanges.reversed() {
            out.replaceCharacters(in: r, with: "\n")
        }
        return out
    }

    private func trimLeadingAndTrailingNewlines(from selected: NSAttributedString) -> NSAttributedString {
        if selected.length == 0 { return selected }
        let ns = selected.string as NSString
        var start = 0
        var end = ns.length
        while start < end {
            let c = ns.character(at: start)
            if c == 10 || c == 13 { start += 1 } else { break }
        }
        while end > start {
            let c = ns.character(at: end - 1)
            if c == 10 || c == 13 { end -= 1 } else { break }
        }
        let len = max(0, end - start)
        return selected.attributedSubstring(from: NSRange(location: start, length: len))
    }

    private func shouldBreakOutOfListForAttachment(in editor: EditorView, selectedRange: NSRange) -> Bool {
        let text = editor.attributedText
        if text.length == 0 { return false }
        let probe = min(max(0, selectedRange.location), text.length - 1)
        if text.attribute(.listItem, at: probe, effectiveRange: nil) != nil { return true }
        if let ps = text.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
           !ps.textLists.isEmpty {
            return true
        }
        let ns = text.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: probe, length: 0))
        var found = false
        text.enumerateAttribute(.listItem, in: para, options: []) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func attachmentInsertionString(
        _ attachment: NSAttributedString,
        breakoutFromList: Bool,
        baseText: NSString,
        selectedRange: NSRange
    ) -> NSAttributedString {
        if !breakoutFromList { return attachment }
        let safeLoc = min(max(0, selectedRange.location), baseText.length)
        let needLeadingNewline: Bool = {
            if safeLoc == 0 { return false }
            let c = baseText.character(at: safeLoc - 1)
            return c != 10 && c != 13
        }()
        let needTrailingNewline: Bool = {
            if safeLoc >= baseText.length { return true }
            let c = baseText.character(at: safeLoc)
            return c != 10 && c != 13
        }()
        let out = NSMutableAttributedString()
        if needLeadingNewline {
            out.append(NSAttributedString(string: "\n"))
        }
        out.append(attachment)
        if needTrailingNewline {
            out.append(NSAttributedString(string: "\n"))
        }
        return out
    }

    private func sanitizeListAttributesForAttachment(in text: NSMutableAttributedString, insertedRange: NSRange) {
        guard insertedRange.length > 0 else { return }
        text.removeAttribute(.listItem, range: insertedRange)
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = 0
        ps.headIndent = 0
        ps.textLists = []
        text.addAttribute(.paragraphStyle, value: ps, range: insertedRange)
    }

    private func handleTableAction(attachmentID: String, action: NJTableAction) {
        guard let editor else { return }
        guard let (range, view) = findTableAttachment(attachmentID: attachmentID, in: editor.attributedText) else { return }

        let grid = view.gridView
        let currentCells = view.tableCellsForExport()
        var rows = (currentCells.compactMap { $0["row"] as? Int }.max().map { $0 + 1 }) ?? 1
        var cols = (currentCells.compactMap { $0["col"] as? Int }.max().map { $0 + 1 }) ?? 1
        let selected = view.selectedCellCoordinates()
        let currentAlignments = view.columnAlignmentsForExport()
        let currentTypes = view.columnTypesForExport()
        let currentFormulas = view.columnFormulasForExport()
        let currentTotalFormulas = view.totalFormulasForExport()
        let totalsEnabled = view.totalsEnabledForExport()
        let currentFilters = view.columnFiltersForExport()
        let hideCheckedRows = view.hideCheckedRowsForExport()
        let currentSortColumn = view.sortColumnForExport()
        let currentSortDirection = view.sortDirectionForExport()

        switch action {
        case .copyTable:
            copyTableAttachment(view)
            return
        case .cutTable:
            copyTableAttachment(view)
            deleteTableAttachment(attachmentID: attachmentID)
            return
        case .deleteTable:
            deleteTableAttachment(attachmentID: attachmentID)
            return
        case .addRow:
            view.appendRow()
            saveTableCanonicalPayload(from: view)
            return
        case .addColumn:
            cols += 1
            var nextWidths = view.columnWidthsForExport()
            var nextAlignments = currentAlignments
            let insertedWidth = nextWidths.last ?? Double(max(1, grid.bounds.width / CGFloat(max(1, cols))))
            nextWidths.append(insertedWidth)
            nextAlignments.append(nextAlignments.last ?? NJTableColumnAlignment.left.rawValue)
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: nextWidths,
                columnAlignments: nextAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas + [""],
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas + [NJTableTotalFormula.none.rawValue],
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .moveRow(let row, let direction):
            let target = row + direction
            guard row > 0, row < rows, target > 0, target < rows else { return }
            let nextCells = moveTableRow(from: row, to: target, in: currentCells)
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: nextCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .moveColumn(let column, let direction):
            let target = column + direction
            guard column >= 0, column < cols, target >= 0, target < cols else { return }
            let nextCells = moveTableColumn(from: column, to: target, in: currentCells)
            var nextWidths = view.columnWidthsForExport()
            var nextAlignments = currentAlignments
            var nextTypes = currentTypes
            var nextFormulas = currentFormulas
            var nextFilters = currentFilters
            var nextTotalFormulas = currentTotalFormulas
            if column < nextWidths.count, target < nextWidths.count {
                nextWidths.swapAt(column, target)
            }
            if column < nextAlignments.count, target < nextAlignments.count {
                nextAlignments.swapAt(column, target)
            }
            if column < nextTypes.count, target < nextTypes.count {
                nextTypes.swapAt(column, target)
            }
            if column < nextFormulas.count, target < nextFormulas.count {
                nextFormulas.swapAt(column, target)
            }
            if column < nextFilters.count, target < nextFilters.count {
                nextFilters.swapAt(column, target)
            }
            if column < nextTotalFormulas.count, target < nextTotalFormulas.count {
                nextTotalFormulas.swapAt(column, target)
            }
            let nextSortColumn = remapMovedColumnIndex(currentSortColumn, from: column, to: target)
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: nextCells,
                columnWidths: nextWidths,
                columnAlignments: nextAlignments,
                columnTypes: nextTypes,
                columnFormulas: nextFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: nextTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: nextFilters,
                sortColumn: nextSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setColumnType(let column, let type):
            var nextTypes = currentTypes
            var nextFormulas = currentFormulas
            guard column >= 0, column < nextTypes.count else { return }
            nextTypes[column] = type
            if type != NJTableColumnType.formula.rawValue, column < nextFormulas.count {
                nextFormulas[column] = ""
            }
            let nextCells = convertTableColumnType(column: column, to: type, in: currentCells)
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: nextCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: nextTypes,
                columnFormulas: nextFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setColumnFormula(let column, let formula):
            var nextTypes = currentTypes
            var nextFormulas = currentFormulas
            guard column >= 0, column < cols else { return }
            while nextTypes.count < cols { nextTypes.append(NJTableColumnType.text.rawValue) }
            while nextFormulas.count < cols { nextFormulas.append("") }
            nextTypes[column] = NJTableColumnType.formula.rawValue
            nextFormulas[column] = formula?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: nextTypes,
                columnFormulas: nextFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setTotalsEnabled(let shouldEnable):
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: shouldEnable,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setTotalFormula(let column, let formula):
            var nextTotalFormulas = currentTotalFormulas
            guard column >= 0, column < nextTotalFormulas.count else { return }
            nextTotalFormulas[column] = formula ?? NJTableTotalFormula.none.rawValue
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: true,
                totalFormulas: nextTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setHideChecked(let shouldHide):
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: shouldHide,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setColumnFilter(let column, let filter):
            guard column >= 0, column < currentFilters.count else { return }
            var nextFilters = currentFilters
            nextFilters[column] = filter
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: nextFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setSort(let column, let direction):
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: column,
                sortDirection: direction
            )
            return
        case .deleteRow:
            guard selected.row >= 0, selected.row < rows else { return }
            if rows <= 1 {
                deleteTableAttachment(attachmentID: attachmentID)
                return
            }
            let nextCells = removeTableRow(selected.row, from: currentCells)
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows - 1,
                cols: cols,
                cellsJSON: nextCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: currentAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .deleteColumn:
            if cols <= 1 {
                deleteTableAttachment(attachmentID: attachmentID)
                return
            }
            let nextCells = removeTableColumn(selected.col, from: currentCells)
            var nextWidths = view.columnWidthsForExport()
            var nextAlignments = currentAlignments
            var nextTypes = currentTypes
            var nextFormulas = currentFormulas
            var nextFilters = currentFilters
            var nextTotalFormulas = currentTotalFormulas
            if selected.col >= 0 && selected.col < nextWidths.count {
                nextWidths.remove(at: selected.col)
            }
            if selected.col >= 0 && selected.col < nextAlignments.count {
                nextAlignments.remove(at: selected.col)
            }
            if selected.col >= 0 && selected.col < nextTypes.count {
                nextTypes.remove(at: selected.col)
            }
            if selected.col >= 0 && selected.col < nextFormulas.count {
                nextFormulas.remove(at: selected.col)
            }
            if selected.col >= 0 && selected.col < nextFilters.count {
                nextFilters.remove(at: selected.col)
            }
            if selected.col >= 0 && selected.col < nextTotalFormulas.count {
                nextTotalFormulas.remove(at: selected.col)
            }
            let nextSortColumn = selected.col == currentSortColumn ? nil : remapRemovedColumnIndex(currentSortColumn, removed: selected.col)
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols - 1,
                cellsJSON: nextCells,
                columnWidths: nextWidths,
                columnAlignments: nextAlignments,
                columnTypes: nextTypes,
                columnFormulas: nextFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: nextTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: nextFilters,
                sortColumn: nextSortColumn,
                sortDirection: currentSortDirection
            )
            return
        case .setColumnAlignment(let column, let alignment):
            var nextAlignments = currentAlignments
            guard column >= 0, column < nextAlignments.count else { return }
            nextAlignments[column] = alignment
            replaceTableAttachment(
                attachmentID: attachmentID,
                range: range,
                rows: rows,
                cols: cols,
                cellsJSON: currentCells,
                columnWidths: view.columnWidthsForExport(),
                columnAlignments: nextAlignments,
                columnTypes: currentTypes,
                columnFormulas: currentFormulas,
                totalsEnabled: totalsEnabled,
                totalFormulas: currentTotalFormulas,
                hideCheckedRows: hideCheckedRows,
                columnFilters: currentFilters,
                sortColumn: currentSortColumn,
                sortDirection: currentSortDirection
            )
            return
        }
    }

    private func handleCollapsibleContentChanged() {
        isEditing = true
        collapsibleTypingIdleWork?.cancel()
        let wi = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isEditing = false
            self.snapshot(markUserEdit: true)
        }
        collapsibleTypingIdleWork = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(collapsibleTypingIdleMs), execute: wi)
        if let editor {
            discardPendingHydration()
            onUserTyped?(editor.attributedText, editor.selectedRange)
        }
        snapshot()
    }

    private func handleCollapsibleContentCommitted() {
        collapsibleTypingIdleWork?.cancel()
        collapsibleTypingIdleWork = nil
        isEditing = false
        synchronizeLiveCollapsibleAttachmentsIntoEditor()
        if let editor {
            onSnapshot?(editor.attributedText, editor.selectedRange)
            onEndEditing?(editor.attributedText, editor.selectedRange)
            onEndEditingSimple?()
        }
    }

    private func synchronizedAttachmentTextForExport(_ text: NSAttributedString) -> NSAttributedString {
        guard text.length > 0 else { return text }

        let full = NSRange(location: 0, length: text.length)
        var collapsibles: [(range: NSRange, view: NJCollapsibleAttachmentView)] = []
        text.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            guard let att = value as? Attachment,
                  att.isBlockType,
                  let view = att.contentView as? NJCollapsibleAttachmentView else { return }
            collapsibles.append((range, view))
        }

        guard !collapsibles.isEmpty else { return text }

        let out = NSMutableAttributedString(attributedString: text)
        for item in collapsibles.sorted(by: { $0.range.location > $1.range.location }) {
            let replacement = buildCollapsibleAttachment(
                attachmentID: item.view.attachmentID,
                title: item.view.titleAttributedText,
                body: item.view.currentBodyAttributedTextForExport(),
                bodyProtonJSON: item.view.bodyProtonJSONString,
                isCollapsed: item.view.isCollapsed
            )
            out.replaceCharacters(in: item.range, with: replacement.string)
        }
        return out
    }

    private func synchronizeLiveCollapsibleAttachmentsIntoEditor() {
        guard let editor else { return }
        let current = editor.attributedText
        let synced = synchronizedAttachmentTextForExport(current)
        guard !synced.isEqual(to: current) else { return }

        let apply = { [weak self] in
            guard let self else { return }
            let selection = self.clampedSelection(editor.selectedRange, maxLength: synced.length)
            editor.attributedText = synced
            editor.selectedRange = selection
            if let tv = self.activeTextView() {
                tv.selectedRange = selection
            }
        }

        if let withProgrammatic {
            withProgrammatic(apply)
        } else {
            apply()
        }
        onRequestRemeasure?()
    }

    private func findTableAttachment(
        attachmentID: String,
        in text: NSAttributedString
    ) -> (NSRange, NJTableAttachmentView)? {
        let full = NSRange(location: 0, length: text.length)
        var found: (NSRange, NJTableAttachmentView)? = nil
        text.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
            guard let att = value as? Attachment else { return }
            guard att.isBlockType else { return }
            guard let view = att.contentView as? NJTableAttachmentView else { return }
            guard view.attachmentID == attachmentID else { return }
            found = (range, view)
            stop.pointee = true
        }
        return found
    }

    private func findCollapsibleAttachment(
        attachmentID: String,
        in text: NSAttributedString
    ) -> (NSRange, NJCollapsibleAttachmentView)? {
        let full = NSRange(location: 0, length: text.length)
        var found: (NSRange, NJCollapsibleAttachmentView)? = nil
        text.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
            guard let att = value as? Attachment else { return }
            guard att.isBlockType else { return }
            guard let view = att.contentView as? NJCollapsibleAttachmentView else { return }
            guard view.attachmentID == attachmentID else { return }
            found = (range, view)
            stop.pointee = true
        }
        return found
    }

    private func replaceCollapsibleAttachment(attachmentID: String, shouldSnapshot: Bool = true) {
        guard let editor else { return }
        guard let (range, view) = findCollapsibleAttachment(attachmentID: attachmentID, in: editor.attributedText) else { return }
        let replacement = buildCollapsibleAttachment(
            attachmentID: attachmentID,
            title: view.titleAttributedText,
            body: view.currentBodyAttributedTextForExport(),
            bodyProtonJSON: view.bodyProtonJSONString,
            isCollapsed: view.isCollapsed
        )
        let applyReplacement = { [weak self] in
            guard let self else { return }
            let s = NSMutableAttributedString(attributedString: editor.attributedText)
            let sel = editor.selectedRange
            s.replaceCharacters(in: range, with: replacement.string)
            editor.attributedText = s
            let fullRange = NSRange(location: 0, length: s.length)
            if range.length > 0 {
                editor.invalidateLayout(for: range)
            }
            if fullRange.length > 0 {
                editor.invalidateLayout(for: fullRange)
            }
            editor.setNeedsLayout()
            editor.layoutIfNeeded()
            let clamped = self.clampedSelection(sel, maxLength: s.length)
            editor.selectedRange = clamped
            if let tv = self.activeTextView() {
                tv.textContainer.size = CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)
                tv.layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                tv.layoutManager.ensureLayout(for: tv.textContainer)
                tv.setNeedsLayout()
                tv.layoutIfNeeded()
                tv.selectedRange = clamped
            }
        }
        if let withProgrammatic {
            withProgrammatic(applyReplacement)
        } else {
            applyReplacement()
        }
        onRequestRemeasure?()
        if shouldSnapshot {
            snapshot()
        }
    }

    private func replaceTableAttachment(attachmentID: String, shouldSnapshot: Bool = true) {
        guard let editor else { return }
        guard let (range, view) = findTableAttachment(attachmentID: attachmentID, in: editor.attributedText) else { return }
        let payload = tablePayload(from: view)
        let rows = max(1, (payload["rows"] as? Int) ?? 1)
        let cols = max(1, (payload["cols"] as? Int) ?? 1)
        let cells = (payload["cells"] as? [[String: Any]]) ?? []
        let columnWidths = payload["column_widths"] as? [Double]
        let columnAlignments = payload["column_alignments"] as? [String]
        let columnTypes = payload["column_types"] as? [String]
        let columnFormulas = payload["column_formulas"] as? [String]
        let totalsEnabled = (payload["totals_enabled"] as? Bool) ?? false
        let totalFormulas = payload["total_formulas"] as? [String]
        let hideCheckedRows = (payload["hide_checked_rows"] as? Bool) ?? false
        let columnFilters = payload["column_filters"] as? [String]
        let sortColumn = payload["sort_column"] as? Int
        let sortDirection = payload["sort_direction"] as? String
        let tableShortID = payload["table_short_id"] as? String
        let tableName = payload["table_name"] as? String

        let replacement = buildTableAttachment(
            attachmentID: attachmentID,
            rows: rows,
            cols: cols,
            cellsJSON: cells,
            columnWidths: columnWidths,
            columnAlignments: columnAlignments,
            columnTypes: columnTypes,
            columnFormulas: columnFormulas,
            totalsEnabled: totalsEnabled,
            totalFormulas: totalFormulas,
            hideCheckedRows: hideCheckedRows,
            columnFilters: columnFilters,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            tableShortID: tableShortID,
            tableName: tableName
        )

        let applyReplacement = { [weak self] in
            guard let self else { return }
            let s = NSMutableAttributedString(attributedString: editor.attributedText)
            let sel = editor.selectedRange
            s.replaceCharacters(in: range, with: replacement.string)
            editor.attributedText = s
            let fullRange = NSRange(location: 0, length: s.length)
            if range.length > 0 {
                editor.invalidateLayout(for: range)
            }
            if fullRange.length > 0 {
                editor.invalidateLayout(for: fullRange)
            }
            editor.setNeedsLayout()
            editor.layoutIfNeeded()
            let clamped = self.clampedSelection(sel, maxLength: s.length)
            editor.selectedRange = clamped
            if let tv = self.activeTextView() {
                tv.textContainer.size = CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)
                tv.layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                tv.layoutManager.ensureLayout(for: tv.textContainer)
                tv.setNeedsLayout()
                tv.layoutIfNeeded()
                tv.selectedRange = clamped
            }
        }

        if let withProgrammatic {
            withProgrammatic(applyReplacement)
        } else {
            applyReplacement()
        }
        onRequestRemeasure?()
        if shouldSnapshot {
            snapshot()
        }
    }

    private func tableCellsJSON(from view: NJTableAttachmentView) -> [[String: Any]] {
        view.tableCellsForExport()
    }

    private func tablePayload(from view: NJTableAttachmentView) -> [String: Any] {
        let cells = tableCellsJSON(from: view)
        let rows = cells.compactMap { $0["row"] as? Int }.max().map { $0 + 1 } ?? 1
        let cols = cells.compactMap { $0["col"] as? Int }.max().map { $0 + 1 } ?? 1
        var payload: [String: Any] = [
            "table_id": view.attachmentID,
            "rows": rows,
            "cols": cols,
            "table_short_id": view.tableShortIDForExport(),
            "column_widths": view.columnWidthsForExport(),
            "column_alignments": view.columnAlignmentsForExport(),
            "column_types": view.columnTypesForExport(),
            "column_formulas": view.columnFormulasForExport(),
            "totals_enabled": view.totalsEnabledForExport(),
            "total_formulas": view.totalFormulasForExport(),
            "column_filters": view.columnFiltersForExport(),
            "hide_checked_rows": view.hideCheckedRowsForExport(),
            "cells": cells
        ]
        if let tableName = view.tableNameForExport(),
           !tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["table_name"] = tableName
        }
        if let sortColumn = view.sortColumnForExport() {
            payload["sort_column"] = sortColumn
        }
        if let sortDirection = view.sortDirectionForExport() {
            payload["sort_direction"] = sortDirection
        }
        return payload
    }

    private func saveTableCanonicalPayload(from view: NJTableAttachmentView) {
        NJTableStore.shared.upsertCanonicalPayload(tableID: view.attachmentID, payload: tablePayload(from: view))
    }

    private func photoPayload(from view: NJPhotoAttachmentView) -> [String: Any] {
        [
            "attachment_id": view.attachmentID,
            "display_w": Int(view.displaySize.width),
            "display_h": Int(view.displaySize.height)
        ]
    }

    private func buildPhotoAttachment(
        attachmentID: String,
        size: CGSize,
        image: UIImage?,
        fullPhotoRef: String
    ) -> Attachment {
        let view = NJPhotoAttachmentView(
            attachmentID: attachmentID,
            size: CGSize(width: max(1, size.width), height: max(1, size.height)),
            image: image,
            fullPhotoRef: fullPhotoRef
        )
        if let onOpenFullPhoto {
            view.onOpenFull = onOpenFullPhoto
        }
        view.onDelete = { [weak self] in
            self?.deletePhotoAttachment(attachmentID: attachmentID)
        }
        view.onCopy = { [weak self, weak view] in
            guard let self, let view else { return }
            self.copyPhotoAttachment(view)
        }
        view.onCut = { [weak self, weak view] in
            guard let self, let view else { return }
            self.copyPhotoAttachment(view)
            self.deletePhotoAttachment(attachmentID: attachmentID)
        }
        view.onResize = { [weak self, weak view] in
            guard let self, let view else { return }
            self.replacePhotoAttachment(attachmentID: attachmentID, size: view.displaySize)
        }
        let att = Attachment(view, size: .matchContent)
        view.boundsObserver = att
        att.selectOnTap = false
        att.selectBeforeDelete = false
        return att
    }

    private func copyPhotoAttachment(_ view: NJPhotoAttachmentView) {
        guard let image = view.image else { return }
        NJSetClipboardPhotoPayload(photoPayload(from: view), image: image)
    }

    private func copyTableAttachment(_ view: NJTableAttachmentView) {
        let payload = tablePayload(from: view)
        NJSetClipboardTablePayload(payload, plainText: plainTextTable(from: payload))
    }

    private func plainTextTable(from payload: [String: Any]) -> String {
        let rows = max(1, (payload["rows"] as? Int) ?? 1)
        let cols = max(1, (payload["cols"] as? Int) ?? 1)
        let cells = ((payload["cells"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        var grid = Array(
            repeating: Array(repeating: "", count: cols),
            count: rows
        )

        for cell in cells {
            let row = (cell["row"] as? Int) ?? 0
            let col = (cell["col"] as? Int) ?? 0
            guard row >= 0, row < rows, col >= 0, col < cols else { continue }
            let rtf = (cell["rtf_base64"] as? String) ?? ""
            let text = decodeRTFBase64(rtf)?.string
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            grid[row][col] = text
        }

        return grid.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    private func replaceTableAttachment(
        attachmentID: String,
        range: NSRange,
        rows: Int,
        cols: Int,
        cellsJSON: [[String: Any]],
        columnWidths: [Double]? = nil,
        columnAlignments: [String]? = nil,
        columnTypes: [String]? = nil,
        columnFormulas: [String]? = nil,
        totalsEnabled: Bool = false,
        totalFormulas: [String]? = nil,
        hideCheckedRows: Bool = false,
        columnFilters: [String]? = nil,
        sortColumn: Int? = nil,
        sortDirection: String? = nil,
        tableShortID: String? = nil,
        tableName: String? = nil
    ) {
        guard let editor else { return }
        let newAttachment = buildTableAttachment(
            attachmentID: attachmentID,
            rows: rows,
            cols: cols,
            cellsJSON: cellsJSON,
            columnWidths: columnWidths,
            columnAlignments: columnAlignments,
            columnTypes: columnTypes,
            columnFormulas: columnFormulas,
            totalsEnabled: totalsEnabled,
            totalFormulas: totalFormulas,
            hideCheckedRows: hideCheckedRows,
            columnFilters: columnFilters,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            tableShortID: tableShortID,
            tableName: tableName
        )
        if let tableView = newAttachment.contentView as? NJTableAttachmentView {
            saveTableCanonicalPayload(from: tableView)
        }

        let s = NSMutableAttributedString(attributedString: editor.attributedText)
        s.replaceCharacters(in: range, with: newAttachment.string)
        let fullRange = NSRange(location: 0, length: s.length)
        editor.attributedText = s
        if range.length > 0 {
            editor.invalidateLayout(for: range)
        }
        if fullRange.length > 0 {
            editor.invalidateLayout(for: fullRange)
        }
        editor.setNeedsLayout()
        editor.layoutIfNeeded()
        editor.selectedRange = NSRange(location: min(range.location + 1, s.length), length: 0)
        onRequestRemeasure?()
        snapshot()
    }

    private func findPhotoAttachment(
        attachmentID: String,
        in text: NSAttributedString
    ) -> (NSRange, NJPhotoAttachmentView)? {
        let full = NSRange(location: 0, length: text.length)
        var found: (NSRange, NJPhotoAttachmentView)?
        text.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
            guard let att = value as? Attachment else { return }
            guard att.isBlockType else { return }
            guard let view = att.contentView as? NJPhotoAttachmentView else { return }
            guard view.attachmentID == attachmentID else { return }
            found = (range, view)
            stop.pointee = true
        }
        return found
    }

    private func replacePhotoAttachment(attachmentID: String, size: CGSize) {
        guard let editor else { return }
        guard let (range, view) = findPhotoAttachment(attachmentID: attachmentID, in: editor.attributedText) else { return }
        let replacement = buildPhotoAttachment(
            attachmentID: attachmentID,
            size: size,
            image: view.image,
            fullPhotoRef: view.fullPhotoRef
        )

        let s = NSMutableAttributedString(attributedString: editor.attributedText)
        let sel = editor.selectedRange
        s.replaceCharacters(in: range, with: replacement.string)
        editor.attributedText = s
        let fullRange = NSRange(location: 0, length: s.length)
        if range.length > 0 {
            editor.invalidateLayout(for: range)
        }
        if fullRange.length > 0 {
            editor.invalidateLayout(for: fullRange)
        }
        editor.setNeedsLayout()
        editor.layoutIfNeeded()
        let clamped = clampedSelection(sel, maxLength: s.length)
        editor.selectedRange = clamped
        onRequestRemeasure?()
        snapshot()
    }

    private func removeTableRow(_ rowToRemove: Int, from cellsJSON: [[String: Any]]) -> [[String: Any]] {
        cellsJSON.compactMap { cell in
            let row = (cell["row"] as? Int) ?? 0
            if row == rowToRemove {
                return nil
            }
            var updated = cell
            if row > rowToRemove {
                updated["row"] = row - 1
                updated["row_span"] = [(row - 1)]
            }
            return updated
        }
    }

    private func removeTableColumn(_ columnToRemove: Int, from cellsJSON: [[String: Any]]) -> [[String: Any]] {
        cellsJSON.compactMap { cell in
            let col = (cell["col"] as? Int) ?? 0
            if col == columnToRemove {
                return nil
            }
            var updated = cell
            if col > columnToRemove {
                updated["col"] = col - 1
                updated["col_span"] = [(col - 1)]
            }
            return updated
        }
    }

    private func moveTableColumn(from source: Int, to destination: Int, in cellsJSON: [[String: Any]]) -> [[String: Any]] {
        cellsJSON.map { cell in
            let col = (cell["col"] as? Int) ?? 0
            var updated = cell
            if col == source {
                updated["col"] = destination
                updated["col_span"] = [destination]
            } else if source < destination, col > source, col <= destination {
                updated["col"] = col - 1
                updated["col_span"] = [col - 1]
            } else if source > destination, col >= destination, col < source {
                updated["col"] = col + 1
                updated["col_span"] = [col + 1]
            }
            return updated
        }
    }

    private func remapMovedColumnIndex(_ index: Int?, from source: Int, to destination: Int) -> Int? {
        guard let index else { return nil }
        if index == source { return destination }
        if source < destination, index > source, index <= destination {
            return index - 1
        }
        if source > destination, index >= destination, index < source {
            return index + 1
        }
        return index
    }

    private func remapRemovedColumnIndex(_ index: Int?, removed column: Int) -> Int? {
        guard let index else { return nil }
        if index == column { return nil }
        if index > column { return index - 1 }
        return index
    }

    private func moveTableRow(from source: Int, to destination: Int, in cellsJSON: [[String: Any]]) -> [[String: Any]] {
        cellsJSON.map { cell in
            let row = (cell["row"] as? Int) ?? 0
            var updated = cell
            if row == source {
                updated["row"] = destination
                updated["row_span"] = [destination]
            } else if source < destination, row > source, row <= destination {
                updated["row"] = row - 1
                updated["row_span"] = [row - 1]
            } else if source > destination, row >= destination, row < source {
                updated["row"] = row + 1
                updated["row_span"] = [row + 1]
            }
            return updated
        }
    }

    private func convertTableColumnType(column: Int, to type: String, in cellsJSON: [[String: Any]]) -> [[String: Any]] {
        cellsJSON.map { cell in
            let col = (cell["col"] as? Int) ?? 0
            guard col == column else { return cell }
            let row = (cell["row"] as? Int) ?? 0
            guard row > 0 else { return cell }
            var updated = cell
            let existingText = decodeRTFBase64((cell["rtf_base64"] as? String) ?? "")?.string ?? ""
            let trimmed = existingText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let nextString: String
            if type == NJTableColumnType.checkbox.rawValue {
                let checked = ["☑", "☒", "✅", "true", "1", "yes", "checked", "done", "x"].contains(trimmed)
                nextString = checked ? "☑" : "☐"
            } else if type == NJTableColumnType.formula.rawValue {
                nextString = ""
            } else {
                nextString = ["☑", "☒", "✅", "true", "1", "yes", "checked", "done", "x"].contains(trimmed) ? "checked" : ""
            }
            updated["rtf_base64"] = encodeRTFBase64(NSAttributedString(string: nextString)) ?? ""
            return updated
        }
    }

    private func buildTableAttachment(
        attachmentID: String,
        rows: Int,
        cols: Int,
        cellsJSON: [[String: Any]]?,
        columnWidths: [Double]? = nil,
        columnAlignments: [String]? = nil,
        columnTypes: [String]? = nil,
        columnFormulas: [String]? = nil,
        totalsEnabled: Bool = false,
        totalFormulas: [String]? = nil,
        hideCheckedRows: Bool = false,
        columnFilters: [String]? = nil,
        sortColumn: Int? = nil,
        sortDirection: String? = nil,
        tableShortID: String? = nil,
        tableName: String? = nil
    ) -> Attachment {
        let rCount = max(1, rows)
        let cCount = max(1, cols)
        let columns: [GridColumnConfiguration] = {
            if let columnWidths, columnWidths.count == cCount {
                return columnWidths.map { GridColumnConfiguration(width: .fixed(max(1, CGFloat($0)))) }
            }
            let colWidth: CGFloat = 1.0 / CGFloat(cCount)
            return (0..<cCount).map { _ in GridColumnConfiguration(width: .fractional(colWidth)) }
        }()
        let rowsCfg = (0..<rCount).map { _ in GridRowConfiguration(initialHeight: NJTableDefaultRowHeight) }

        let config = GridConfiguration(
            columnsConfiguration: columns,
            rowsConfiguration: rowsCfg,
            style: .default,
            boundsLimitShadowColors: GradientColors(primary: .black, secondary: .white),
            collapsedColumnWidth: 2,
            collapsedRowHeight: 2,
            ignoresOptimizedInit: true
        )

        var cells: [GridCell] = []
        cells.reserveCapacity(rCount * cCount)

        for r in 0..<rCount {
            for c in 0..<cCount {
                let cell = GridCell(rowSpan: [r], columnSpan: [c], initialHeight: NJTableDefaultRowHeight, ignoresOptimizedInit: true)
                cell.editor.forceApplyAttributedText = true
                cell.editor.attributedText = NSAttributedString(string: "")
                cells.append(cell)
            }
        }

        if let cellsJSON {
            for c in cellsJSON {
                let row = (c["row"] as? Int) ?? 0
                let col = (c["col"] as? Int) ?? 0
                let rtf = (c["rtf_base64"] as? String) ?? ""
                let idx = (row * cCount) + col
                if idx >= 0 && idx < cells.count {
                    if let a = decodeRTFBase64(rtf) {
                        cells[idx].editor.attributedText = a
                    }
                }
            }
        }

        return NJTableAttachmentFactory.make(
            attachmentID: attachmentID,
            config: config,
            cells: cells,
            columnWidths: columnWidths?.map { CGFloat($0) },
            columnAlignments: columnAlignments,
            columnTypes: columnTypes,
            columnFormulas: columnFormulas,
            totalsEnabled: totalsEnabled,
            totalFormulas: totalFormulas,
            hideCheckedRows: hideCheckedRows,
            columnFilters: columnFilters,
            sortColumn: sortColumn,
            sortDirection: sortDirection,
            tableShortID: tableShortID,
            tableName: tableName,
            onTableAction: { [weak self] id, action in
                self?.handleTableAction(attachmentID: id, action: action)
            },
            onResizeTable: { [weak self] _ in
                // Table reflow can happen during hydration, remote reload, or layout.
                // The real table data is saved through NJTableStore; remeasure must not
                // manufacture a block edit on an idle device.
                self?.onRequestRemeasure?()
            },
            onLocalLayoutChange: { [weak self] _ in
                self?.onRequestRemeasure?()
            }
        )
    }

    private func deletePhotoAttachment(attachmentID: String) {
        guard let editor else { return }
        let full = NSRange(location: 0, length: editor.attributedText.length)
        var target: NSRange? = nil

        editor.attributedText.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
            guard let att = value as? Attachment else { return }
            guard att.isBlockType else { return }
            guard let view = att.contentView as? NJPhotoAttachmentView else { return }
            guard view.attachmentID == attachmentID else { return }
            target = range
            stop.pointee = true
        }

        guard let target else { return }
        let s = NSMutableAttributedString(attributedString: editor.attributedText)
        s.replaceCharacters(in: target, with: NSAttributedString(string: ""))
        editor.attributedText = s
        editor.selectedRange = NSRange(location: min(target.location, s.length), length: 0)
        snapshot(markUserEdit: true)
    }

    private func deleteTableAttachment(attachmentID: String) {
        guard let editor else { return }
        guard let (target, _) = findTableAttachment(attachmentID: attachmentID, in: editor.attributedText) else { return }
        let s = NSMutableAttributedString(attributedString: editor.attributedText)
        s.replaceCharacters(in: target, with: NSAttributedString(string: ""))
        editor.attributedText = s
        editor.selectedRange = NSRange(location: min(target.location, s.length), length: 0)
        snapshot(markUserEdit: true)
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

    func insertLink(_ url: URL, title: String? = nil) {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let r = clampedSelection(tv.selectedRange, maxLength: tv.attributedText.length)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let s = NSMutableAttributedString(attributedString: tv.attributedText)
        if trimmedTitle.isEmpty && r.length > 0 {
            s.addAttribute(.link, value: url, range: r)
            s.addAttribute(.foregroundColor, value: UIColor.link, range: r)
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            tv.attributedText = s
            tv.selectedRange = NSRange(location: r.location + r.length, length: 0)
            snapshot()
            return
        }

        let displayTitle = trimmedTitle.isEmpty
            ? NJExternalFileLinkSupport.defaultDisplayName(for: url)
            : trimmedTitle

        var attrs = tv.typingAttributes
        if attrs[.font] == nil {
            attrs[.font] = NJCanonicalBodyFont()
        }
        attrs[.foregroundColor] = UIColor.link
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attrs[.link] = url

        let linkedText = NSAttributedString(string: displayTitle, attributes: attrs)
        s.replaceCharacters(in: r, with: linkedText)
        tv.attributedText = s
        tv.selectedRange = NSRange(location: min(r.location + linkedText.length, s.length), length: 0)

        snapshot()
    }

    func insertDivider() {
        guard let editor else { return }
        guard let tv = findTextView(in: editor) else { return }

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange

        let div = NSAttributedString(string: "\n──────────\n", attributes: [
            .font: NJCanonicalBodyFont(),
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
            .font: NJCanonicalBodyFont(),
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
            .font: NJCanonicalBodyFont(),
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
        isEditing = true

        let m = NSMutableAttributedString(attributedString: tv.attributedText)
        let r = tv.selectedRange

        let attrs: [NSAttributedString.Key: Any] = [
            .font: (tv.typingAttributes[.font] as? UIFont) ?? NJCanonicalBodyFont(),
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
    func setTextColor(_ color: UIColor) { applyTextColor(color) }

    func toggleBold() { toggleBoldWeight() }

    private func toggleBoldWeight() {
        guard let tv = activeTextView() else { return }
        isEditing = true

        func applyBold(_ on: Bool, _ font: UIFont) -> UIFont {
            let size = font.pointSize
            let fd = font.fontDescriptor
            let hadItalic = fd.symbolicTraits.contains(.traitItalic)
            return NJCanonicalBodyFont(size: size, bold: on, italic: hadItalic)
        }

        let r = tv.selectedRange
        func fontForInsertionPoint() -> UIFont {
            if let typingFont = tv.typingAttributes[.font] as? UIFont {
                return typingFont
            }
            let storage = tv.textStorage
            if storage.length == 0 { return NJCanonicalBodyFont() }
            let probe = max(0, min(r.location == storage.length ? storage.length - 1 : r.location, storage.length - 1))
            return (storage.attribute(.font, at: probe, effectiveRange: nil) as? UIFont) ?? NJCanonicalBodyFont()
        }

        func selectionIsFullyBold(in storage: NSTextStorage, range: NSRange) -> Bool {
            guard storage.length > 0, range.length > 0 else { return false }
            var sawFont = false
            var allBold = true
            storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
                let font = (value as? UIFont) ?? NJCanonicalBodyFont()
                sawFont = true
                if !NJHasExplicitBoldTrait(font) {
                    allBold = false
                    stop.pointee = true
                }
            }
            return sawFont && allBold
        }

        if r.length == 0 {
            let old = fontForInsertionPoint()
            let isBoldNow = NJHasExplicitBoldTrait(old)
            tv.typingAttributes[.font] = applyBold(!isBoldNow, old)
            return
        }

        let storage = tv.textStorage
        let shouldTurnBoldOn = !selectionIsFullyBold(in: storage, range: r)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: r, options: []) { v, range, _ in
            let old = (v as? UIFont) ?? NJCanonicalBodyFont()
            let nf = applyBold(shouldTurnBoldOn, old)
            storage.addAttribute(.font, value: nf, range: range)
        }
        storage.endEditing()
        if let baseFont = (storage.attribute(.font, at: r.location, effectiveRange: nil) as? UIFont) ?? (tv.typingAttributes[.font] as? UIFont) {
            tv.typingAttributes[.font] = applyBold(shouldTurnBoldOn, baseFont)
        }

        snapshot()
    }

    func toggleItalic() { toggleFontTrait(.traitItalic) }
    func toggleStrike() { toggleStrikeThrough() }

    func snapshot(markUserEdit: Bool = false) {
        let attributedText: NSAttributedString
        let selectedRange: NSRange
        if let tv = activeTextView() {
            attributedText = tv.attributedText ?? NSAttributedString(string: "")
            selectedRange = tv.selectedRange
        } else if let tv = textView, owns(textView: tv) {
            attributedText = tv.attributedText ?? NSAttributedString(string: "")
            selectedRange = tv.selectedRange
        } else if let editor {
            attributedText = editor.attributedText
            selectedRange = editor.selectedRange
        } else {
            return
        }
        onSnapshot?(attributedText, selectedRange)
        if markUserEdit && !isRunningProgrammaticUpdate {
            userEditSourceHint = "handle.snapshot(markUserEdit)"
            onUserTyped?(attributedText, selectedRange)
        }
        // Toolbar/shortcut formatting often changes attributes without emitting
        // UITextView text-change notifications, so we cannot rely on the typing
        // idle timer to end the editing window for commit/sync.
        if isEditing {
            DispatchQueue.main.async { [weak self] in
                self?.isEditing = false
            }
        }
    }

    private func adjustFontSize(delta: CGFloat) {
        guard let tv = activeTextView() else { return }
        isEditing = true

        let r = tv.selectedRange
        if r.length == 0 {
            let old = (tv.typingAttributes[.font] as? UIFont) ?? NJCanonicalBodyFont()
            let newSize = max(8, min(48, old.pointSize + delta))
            let newFont = UIFont(descriptor: old.fontDescriptor, size: newSize)
            tv.typingAttributes[.font] = newFont
            return
        }

        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
            let old = (value as? UIFont) ?? NJCanonicalBodyFont()
            let newSize = max(8, min(48, old.pointSize + delta))
            let newFont = UIFont(descriptor: old.fontDescriptor, size: newSize)
            tv.textStorage.addAttribute(.font, value: newFont, range: range)
        }
        tv.textStorage.endEditing()

        snapshot()
    }

    private func applyTextColor(_ color: UIColor) {
        guard let tv = activeTextView() else { return }
        isEditing = true

        let r = tv.selectedRange
        if r.length == 0 {
            tv.typingAttributes[.foregroundColor] = color
            return
        }

        let storage = tv.textStorage
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: color, range: r)
        storage.endEditing()

        tv.typingAttributes[.foregroundColor] = color
        snapshot()
    }

    private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = activeTextView() else { return }
        isEditing = true

        let r = tv.selectedRange
        if r.length == 0 {
            let old = (tv.typingAttributes[.font] as? UIFont) ?? NJCanonicalBodyFont()
            let hasItalic = old.fontDescriptor.symbolicTraits.contains(.traitItalic)
            let hasBold = NJHasExplicitBoldTrait(old)
            let nextItalic = trait == .traitItalic ? !hasItalic : hasItalic
            tv.typingAttributes[.font] = NJCanonicalBodyFont(
                size: old.pointSize,
                bold: hasBold,
                italic: nextItalic
            )
            return
        }

        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
            let old = (value as? UIFont) ?? NJCanonicalBodyFont()
            let hasItalic = old.fontDescriptor.symbolicTraits.contains(.traitItalic)
            let hasBold = NJHasExplicitBoldTrait(old)
            let nextItalic = trait == .traitItalic ? !hasItalic : hasItalic
            let nf = NJCanonicalBodyFont(size: old.pointSize, bold: hasBold, italic: nextItalic)
            tv.textStorage.addAttribute(.font, value: nf, range: range)
        }
        tv.textStorage.endEditing()

        snapshot()
    }

    private func toggleStrikeThrough() {
        guard let tv = activeTextView() else { return }
        isEditing = true

        let r = tv.selectedRange
        if r.length == 0 {
            let ns = tv.textStorage.string as NSString
            guard ns.length > 0 else {
                let v = (tv.typingAttributes[.strikethroughStyle] as? Int) ?? 0
                if v == 0 {
                    tv.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                } else {
                    tv.typingAttributes.removeValue(forKey: .strikethroughStyle)
                }
                return
            }

            let caret = min(r.location, max(0, ns.length - 1))
            var paragraphRange = ns.paragraphRange(for: NSRange(location: caret, length: 0))
            while paragraphRange.length > 0 {
                let last = ns.character(at: paragraphRange.location + paragraphRange.length - 1)
                if last == 10 || last == 13 {
                    paragraphRange.length -= 1
                } else {
                    break
                }
            }

            guard paragraphRange.length > 0 else {
                let v = (tv.typingAttributes[.strikethroughStyle] as? Int) ?? 0
                if v == 0 {
                    tv.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                } else {
                    tv.typingAttributes.removeValue(forKey: .strikethroughStyle)
                }
                return
            }

            let s = tv.textStorage
            let v = (s.attribute(.strikethroughStyle, at: paragraphRange.location, effectiveRange: nil) as? Int) ?? 0
            let has = v != 0

            s.beginEditing()
            if has {
                s.removeAttribute(.strikethroughStyle, range: paragraphRange)
                tv.typingAttributes.removeValue(forKey: .strikethroughStyle)
            } else {
                s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: paragraphRange)
                tv.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            s.endEditing()

            snapshot()
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
        guard !isActivelyEditingText else {
            discardPendingHydration()
            return
        }
        pendingHydrateProtonJSON = json
        applyPendingHydrateIfNeeded()
    }

    private var didHydrate = false
    private var attachedEditorID: ObjectIdentifier? = nil
    private var collapsibleTypingIdleWork: DispatchWorkItem?
    private let collapsibleTypingIdleMs: Int = 350

    func invalidateHydration() {
        didHydrate = false
        lastHydratedJSONSig = 0
        attachedEditorID = nil
        hydrationScheduled = false
        pendingJSON = nil
        pendingHydrateProtonJSON = nil
        collapsibleTypingIdleWork?.cancel()
        collapsibleTypingIdleWork = nil
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
        guard !isActivelyEditingText else {
            discardPendingHydration()
            return
        }

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
        guard !isActivelyEditingText else {
            discardPendingHydration()
            return
        }
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
        guard !isActivelyEditingText else {
            discardPendingHydration()
            return
        }

        let baseFont = NJCanonicalBodyFont()

        func apply(_ a: NSAttributedString) {
            let run = { [self] in
                let fixedFonts = NJEditorCanonicalizeRichText(a, baseSize: baseFont.pointSize)
                let r = editor.selectedRange
                editor.attributedText = fixedFonts
                editor.selectedRange = NSRange(location: min(r.location, fixedFonts.length), length: 0)

                if let tv = self.textView {
                    tv.typingAttributes = NJEditorCanonicalTypingAttributes(
                        tv.typingAttributes,
                        baseSize: baseFont.pointSize
                    )
                }

                NJLogIPadEditorDebug("hydrate", attr: fixedFonts, selection: editor.selectedRange, typingAttributes: self.textView?.typingAttributes)

                self.onHydratedSnapshot?(fixedFonts, editor.selectedRange)

                self.didHydrate = true
                self.lastHydratedJSONSig = json.hashValue
            }

            if let withProgrammatic {
                withProgrammatic(run)
            } else {
                run()
            }
        }

        apply(decodeAttributedStringFromProtonJSONString(json, interactive: true))
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

    private func activeTextView() -> UITextView? {
        guard let editor else { return nil }

        if let tv = textView, owns(textView: tv), tv.isFirstResponder {
            return tv
        }

        if let tv = findTextView(in: editor), tv.isFirstResponder {
            textView = tv
            return tv
        }

        if let tv = findFirstResponderTextView(), owns(textView: tv) {
            textView = tv
            return tv
        }

        if let tv = textView, owns(textView: tv) {
            return tv
        }

        if let tv = findTextView(in: editor) {
            textView = tv
            return tv
        }

        return nil
    }

    private func findFirstResponderTextView() -> UITextView? {
        guard let window = njKeyWindow() else { return nil }
        return findFirstResponder(in: window) as? UITextView
    }

    private func njKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    }

    private func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let hit = findFirstResponder(in: sub) { return hit }
        }
        return nil
    }

    private func encodeRTFBase64(_ s: NSAttributedString) -> String? {
        let r = NSRange(location: 0, length: s.length)
        guard let data = try? s.data(from: r, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return nil }
        return data.base64EncodedString()
    }

    private func decodeRTFBase64(_ b64: String) -> NSAttributedString? {
        guard let data = Data(base64Encoded: b64) else { return nil }
        if let rtfd = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) {
            return rtfd
        }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
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
        njHandle?.snapshot(markUserEdit: true)
    }

    @objc private func cmdBold() {
        njHandle?.toggleBold()
        njHandle?.snapshot(markUserEdit: true)
    }

    @objc private func cmdItalic() {
        njHandle?.toggleItalic()
        njHandle?.snapshot(markUserEdit: true)
    }

    @objc private func cmdStrike() {
        njHandle?.toggleStrike()
        njHandle?.snapshot(markUserEdit: true)
    }

    @objc private func tabIndent() {
        njHandle?.indent()
        njHandle?.snapshot(markUserEdit: true)
    }

    @objc private func tabOutdent() {
        njHandle?.outdent()
        njHandle?.snapshot(markUserEdit: true)
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
            handle.isRunningProgrammaticUpdate = true
            context.coordinator.beginProgrammatic()
            f()
            DispatchQueue.main.async {
                context.coordinator.endProgrammatic()
                handle.isRunningProgrammaticUpdate = false
            }
        }

        handle.withProgrammatic? {
            v.attributedText = NJStandardizeFontFamily(initialAttributedText)
            v.selectedRange = initialSelectedRange
        }

        if let tv = findTextView(in: v) {
            NJInstallTextViewKeyCommandHook(tv)
            NJInstallTextViewPasteHook(tv)
            NJInstallTextViewCanPerformActionHook(tv)
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

        let priorOnSnapshot = handle.onSnapshot
        handle.onSnapshot = { a, r in
            priorOnSnapshot?(a, r)
            DispatchQueue.main.async {
                snapshotAttributedText = a
                snapshotSelectedRange = r
                context.coordinator.updateMeasuredHeight(from: v)
            }
        }

        handle.onHydratedSnapshot = { a, r in
            DispatchQueue.main.async {
                snapshotAttributedText = a
                snapshotSelectedRange = r
                context.coordinator.updateMeasuredHeight(from: v)
            }
        }
        handle.onRequestRemeasure = { [weak v, weak coordinator = context.coordinator] in
            DispatchQueue.main.async {
                guard let v, let coordinator else { return }
                coordinator.invalidateAndRemeasure(from: v)
            }
        }

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        v.addGestureRecognizer(pinch)

        DispatchQueue.main.async {
            if let tv = findTextView(in: v) {
                NJInstallTextViewKeyCommandHook(tv)
                NJInstallTextViewPasteHook(tv)
                NJInstallTextViewCanPerformActionHook(tv)
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
            NJInstallTextViewPasteHook(tv)
            NJInstallTextViewCanPerformActionHook(tv)
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
        handle.onRequestRemeasure = { [weak uiView, weak coordinator = context.coordinator] in
            DispatchQueue.main.async {
                guard let uiView, let coordinator else { return }
                coordinator.invalidateAndRemeasure(from: uiView)
            }
        }
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
            ta[.font] = NJCanonicalBodyFont()
        }

        if ta[.foregroundColor] == nil {
            ta[.foregroundColor] = UIColor.label
        }

        tv.typingAttributes = ta
    }

    final class Coordinator: NSObject, EditorViewDelegate, UITextViewDelegate, UIGestureRecognizerDelegate {
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
        private struct ExpectedTextMutation {
            let expectedLength: Int
            let issuedAtMs: Int64
        }
        private var pendingLocalTextMutations: [ExpectedTextMutation] = []
        private var lastPersistedTextChangeSignature: String?
        private var lastPersistedTextChangeAtMs: Int64 = 0


        private weak var activeAttachment: NSTextAttachment?
        private var activeInitialBounds: CGRect = .zero
        private weak var activePhotoView: NJPhotoAttachmentView?
        private var activeInitialPhotoSize: CGSize = .zero
        private var deferredHeightMeasureWork: DispatchWorkItem?
        private var lastDeferredMeasureSignature: String?

        init(measuredHeight: Binding<CGFloat>, handle: NJProtonEditorHandle) {
            _measuredHeight = measuredHeight
            self.handle = handle
        }

        deinit {
            if let o = textDidChangeObs {
                NotificationCenter.default.removeObserver(o)
            }
            deferredHeightMeasureWork?.cancel()
        }
        
        private var isNormalizingFonts = false
        private var isNormalizingLists = false

        private func syncTypingAttributesToSelection(_ tv: UITextView) {
            let storage = tv.textStorage
            var ta = tv.typingAttributes

            let selected = tv.selectedRange
            let probe: Int? = {
                guard storage.length > 0 else { return nil }
                if selected.length > 0 {
                    return min(max(0, selected.location), storage.length - 1)
                }
                if selected.location > 0 {
                    return min(selected.location - 1, storage.length - 1)
                }
                if selected.location < storage.length {
                    return selected.location
                }
                return nil
            }()

            if let probe {
                let attrs = storage.attributes(at: probe, effectiveRange: nil)
                if let font = attrs[.font] as? UIFont {
                    ta[.font] = NJStandardizeFontFamily(font)
                } else {
                    ta[.font] = NJCanonicalBodyFont()
                }
                if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
                    ta[.paragraphStyle] = paragraphStyle
                }
                if let foregroundColor = attrs[.foregroundColor] as? UIColor {
                    ta[.foregroundColor] = foregroundColor
                } else if ta[.foregroundColor] == nil {
                    ta[.foregroundColor] = UIColor.label
                }
                if let underline = attrs[.underlineStyle] {
                    ta[.underlineStyle] = underline
                } else {
                    ta.removeValue(forKey: .underlineStyle)
                }
                if let strike = attrs[.strikethroughStyle] {
                    ta[.strikethroughStyle] = strike
                } else {
                    ta.removeValue(forKey: .strikethroughStyle)
                }
            } else {
                ta[.font] = NJCanonicalBodyFont()
                if ta[.foregroundColor] == nil {
                    ta[.foregroundColor] = UIColor.label
                }
            }

            tv.typingAttributes = ta
        }

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
                syncTypingAttributesToSelection(tv)
            }
        }

        private func normalizeListAttributesInTextStorage(_ tv: UITextView) {
            if isNormalizingLists { return }
            let storage = tv.textStorage
            if storage.length == 0 { return }

            isNormalizingLists = true
            storage.beginEditing()
            let didChange = NJProtonListNormalizer.normalizeTextStorage(storage)
            storage.endEditing()
            isNormalizingLists = false

            if didChange {
                syncTypingAttributesToSelection(tv)
            }
        }


        func textViewDidBeginEditing(_ tv: UITextView) {
            if isProgrammatic { return }
            handle.markAsActiveHandle()
            handle.isEditing = true
            syncTypingAttributesToSelection(tv)
            NJLogIPadEditorDebug("begin_edit", attr: tv.attributedText ?? NSAttributedString(string: ""), selection: tv.selectedRange, typingAttributes: tv.typingAttributes)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if isProgrammatic { return }
            handle.isEditing = false
        }

        func beginProgrammatic() { isProgrammatic = true }
        func endProgrammatic() { isProgrammatic = false }

        private func editorGateNowMs() -> Int64 {
            Int64(Date().timeIntervalSince1970 * 1000)
        }

        private func markLocalTextMutation(textView: UITextView, range: NSRange, replacementText text: String) {
            let currentLength = textView.attributedText?.length ?? 0
            let replacementLength = (text as NSString).length
            let expectedLength = max(0, currentLength - range.length + replacementLength)
            let now = editorGateNowMs()
            pendingLocalTextMutations.append(ExpectedTextMutation(expectedLength: expectedLength, issuedAtMs: now))
            pendingLocalTextMutations = Array(pendingLocalTextMutations.suffix(8))
            if let id = handle.ownerBlockUUID {
                print("NJ_EDITOR_LOCAL_MUTATION_TOKEN block_id=\(id.uuidString) expected_len=\(expectedLength) range=\(range.location),\(range.length) repl_len=\(replacementLength)")
            }
        }

        private func textChangeSignature(for tv: UITextView) -> String {
            let attr = tv.attributedText ?? NSAttributedString(string: "")
            let sel = tv.selectedRange
            return "\(attr.length):\(sel.location):\(sel.length):\(attr.string.hashValue)"
        }

        private func consumeMatchingLocalTextMutation(currentLength: Int, now: Int64) -> Bool {
            pendingLocalTextMutations.removeAll { now - $0.issuedAtMs > 2_000 }
            guard let index = pendingLocalTextMutations.firstIndex(where: { $0.expectedLength == currentLength }) else {
                return false
            }
            pendingLocalTextMutations.remove(at: index)
            return true
        }

        private func shouldPersistTextDidChange(for tv: UITextView) -> Bool {
            if isProgrammatic { return false }
            let now = editorGateNowMs()
            let length = tv.attributedText?.length ?? 0
            let signature = textChangeSignature(for: tv)
            if signature == lastPersistedTextChangeSignature && now - lastPersistedTextChangeAtMs < 150 {
                if let id = handle.ownerBlockUUID {
                    print("NJ_EDITOR_IGNORE_DUP_TEXT_CHANGE block_id=\(id.uuidString) len=\(length) sel=\(tv.selectedRange.location),\(tv.selectedRange.length)")
                }
                return false
            }
            guard consumeMatchingLocalTextMutation(currentLength: length, now: now) else {
                if let id = handle.ownerBlockUUID {
                    print("NJ_EDITOR_IGNORE_NONUSER_TEXT_CHANGE block_id=\(id.uuidString) len=\(length) sel=\(tv.selectedRange.location),\(tv.selectedRange.length) pending_tokens=\(pendingLocalTextMutations.count)")
                }
                return false
            }
            lastPersistedTextChangeSignature = signature
            lastPersistedTextChangeAtMs = now
            return true
        }

        private func noteUserEditingActivity(in tv: UITextView) {
            handle.isEditing = true
            typingIdleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.handle.isEditing = false
            }
            typingIdleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(typingIdleMs), execute: work)

            normalizeFontFamilyInTextStorage(tv)
            normalizeListAttributesInTextStorage(tv)
            handle.discardPendingHydration()
        }

        func attachTextView(_ tv: UITextView) {
            if textView === tv { return }

            if let o = textDidChangeObs { NotificationCenter.default.removeObserver(o); textDidChangeObs = nil }
            if let o = textDidBeginObs { NotificationCenter.default.removeObserver(o); textDidBeginObs = nil }
            if let o = textDidEndObs { NotificationCenter.default.removeObserver(o); textDidEndObs = nil }

            textView = tv
            tv.delegate = self
            tv.isSelectable = true
            tv.linkTextAttributes = [
                .foregroundColor: UIColor.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]

            textDidChangeObs = NotificationCenter.default.addObserver(
                forName: UITextView.textDidChangeNotification,
                object: tv,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.isProgrammatic { return }
                guard let ev = self.handle.editor else { return }

                self.handle.onSnapshot?(ev.attributedText, ev.selectedRange)
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

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if !isProgrammatic, textView.isFirstResponder {
                markLocalTextMutation(textView: textView, range: range, replacementText: text)
            }
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            if isProgrammatic { return }

            let sel = tv.selectedRange
            NJLogIPadEditorDebug("did_change", attr: tv.attributedText ?? NSAttributedString(string: ""), selection: sel, typingAttributes: tv.typingAttributes)
            if shouldPersistTextDidChange(for: tv) {
                handle.markAsActiveHandle()
                noteUserEditingActivity(in: tv)
                handle.userEditSourceHint = "delegate.textViewDidChange"
                handle.onUserTyped?(tv.attributedText ?? NSAttributedString(string: ""), sel)
            }

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
            if let tv = textView {
                syncTypingAttributesToSelection(tv)
                NJLogIPadEditorDebug("selection_change", attr: tv.attributedText ?? NSAttributedString(string: ""), selection: tv.selectedRange, typingAttributes: tv.typingAttributes)
            }
            handle.markAsActiveHandle()
            updateMeasuredHeight(from: editorView)
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            NJExternalFileLinkSupport.open(url: url)
            return false
        }

        func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
            NJExternalFileLinkSupport.open(url: url)
            return false
        }

        func updateMeasuredHeight(from editorView: EditorView) {
            editor = editorView

            guard let tv = findTextView(in: editorView) else { return }

            tv.isScrollEnabled = false
            tv.layoutIfNeeded()

            guard let targetW = resolvedMeasurementWidth(for: tv, in: editorView) else {
                scheduleDeferredHeightMeasure(from: editorView)
                return
            }

            tv.textContainer.size = CGSize(width: targetW, height: .greatestFiniteMagnitude)
            tv.layoutIfNeeded()
            tv.layoutManager.ensureLayout(for: tv.textContainer)

            let fit = tv.sizeThatFits(CGSize(width: targetW, height: .greatestFiniteMagnitude)).height
            let laidOut = tv.layoutManager.usedRect(for: tv.textContainer).height
                + tv.textContainerInset.top
                + tv.textContainerInset.bottom
            let content = tv.contentSize.height
            let settledHeight = max(fit, laidOut)
            let h = max(44, ceil(settledHeight))
            let hadHeightChange = abs(measuredHeight - h) > 0.5

            if hadHeightChange {
                DispatchQueue.main.async { self.measuredHeight = h }
            }

            let unstableAttachmentLayout =
                DBNoteRepository.containsAttachments(tv.attributedText) &&
                (
                    hadHeightChange ||
                    abs(fit - laidOut) > 1 ||
                    abs(content - laidOut) > 1 ||
                    abs(content - fit) > 1
                )

            if unstableAttachmentLayout {
                let signature = "\(Int(round(targetW)))|\(Int(round(h)))|\(Int(round(content)))|\(Int(round(laidOut)))"
                if lastDeferredMeasureSignature != signature {
                    lastDeferredMeasureSignature = signature
                    scheduleDeferredHeightMeasure(from: editorView)
                }
            } else {
                lastDeferredMeasureSignature = nil
            }
        }

        func invalidateAndRemeasure(from editorView: EditorView) {
            let fullRange = NSRange(location: 0, length: editorView.attributedText.length)
            if fullRange.length > 0 {
                editorView.invalidateLayout(for: fullRange)
            }
            editorView.setNeedsLayout()
            editorView.layoutIfNeeded()
            updateMeasuredHeight(from: editorView)

            DispatchQueue.main.async { [weak self, weak editorView] in
                guard let self, let editorView else { return }
                let fullRange = NSRange(location: 0, length: editorView.attributedText.length)
                if fullRange.length > 0 {
                    editorView.invalidateLayout(for: fullRange)
                }
                editorView.setNeedsLayout()
                editorView.layoutIfNeeded()
                self.updateMeasuredHeight(from: editorView)
            }
        }

        private func resolvedMeasurementWidth(for textView: UITextView, in editorView: EditorView) -> CGFloat? {
            let candidates: [CGFloat] = [
                textView.bounds.width,
                textView.frame.width,
                editorView.bounds.width,
                editorView.frame.width,
                editorView.superview?.bounds.width ?? 0,
                textView.textContainer.size.width
            ]

            let width = candidates.first(where: { $0 > 1 }) ?? 0
            return width > 1 ? width : nil
        }

        private func scheduleDeferredHeightMeasure(from editorView: EditorView) {
            if deferredHeightMeasureWork != nil { return }
            deferredHeightMeasureWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak editorView] in
                guard let self, let editorView else { return }
                self.deferredHeightMeasureWork = nil
                editorView.setNeedsLayout()
                editorView.layoutIfNeeded()
                self.updateMeasuredHeight(from: editorView)
            }
            deferredHeightMeasureWork = work
            DispatchQueue.main.async(execute: work)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var current = touch.view
            while let view = current {
                if view is NJPhotoAttachmentView {
                    return false
                }
                current = view.superview
            }
            return true
        }

        @objc func onPinch(_ gr: UIPinchGestureRecognizer) {
            guard let ev = editor ?? (gr.view as? EditorView) else { return }
            editor = ev
            guard let tv = findTextView(in: ev) else { return }

            let editorPoint = gr.location(in: ev)
            let point = gr.location(in: tv)
            let idx = characterIndex(at: point, in: tv)

            switch gr.state {
            case .began:
                activePhotoView = photoAttachmentView(at: editorPoint, in: ev) ?? photoAttachmentView(at: idx, in: tv)
                activeInitialPhotoSize = activePhotoView?.displaySize ?? .zero
                if activePhotoView != nil {
                    activeAttachment = nil
                    activeInitialBounds = .zero
                    return
                }
                activeAttachment = attachment(at: idx, in: tv)
                activeInitialBounds = activeAttachment?.bounds ?? .zero
            case .changed:
                if let photoView = activePhotoView {
                    let scale = clamp(gr.scale, 0.2, 4.0)
                    let start = activeInitialPhotoSize == .zero ? photoView.displaySize : activeInitialPhotoSize
                    let ratio = start.height / max(1, start.width)
                    var candidates: [CGFloat] = [ev.bounds.width, tv.bounds.width, photoView.window?.bounds.width ?? 0]
                    var current = photoView.superview
                    while let view = current {
                        candidates.append(view.bounds.width)
                        candidates.append(view.frame.width)
                        current = view.superview
                    }
                    let maxWidth = max(120, (candidates.max() ?? photoView.displaySize.width) - 16)
                    let width = min(max(start.width * scale, 120), maxWidth)
                    photoView.updateDisplaySize(CGSize(width: width, height: max(1, width * ratio)))
                    handle.snapshot(markUserEdit: true)
                    updateMeasuredHeight(from: ev)
                    return
                }
                guard let att = activeAttachment else { return }
                let scale = clamp(gr.scale, 0.2, 4.0)
                let b = activeInitialBounds == .zero ? defaultBounds(for: att) : activeInitialBounds
                att.bounds = CGRect(x: b.origin.x, y: b.origin.y, width: max(20, b.size.width * scale), height: max(20, b.size.height * scale))
                handle.snapshot(markUserEdit: true)
                updateMeasuredHeight(from: ev)
            default:
                activeAttachment = nil
                activeInitialBounds = .zero
                activePhotoView = nil
                activeInitialPhotoSize = .zero
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

        private func photoAttachmentView(at idx: Int, in tv: UITextView) -> NJPhotoAttachmentView? {
            if idx < 0 || idx >= tv.attributedText.length { return nil }
            guard let attachment = tv.attributedText.attribute(.attachment, at: idx, effectiveRange: nil) as? Attachment else {
                return nil
            }
            return attachment.contentView as? NJPhotoAttachmentView
        }

        private func photoAttachmentView(at point: CGPoint, in root: UIView) -> NJPhotoAttachmentView? {
            var current = root.hitTest(point, with: nil)
            while let view = current {
                if let photo = view as? NJPhotoAttachmentView {
                    return photo
                }
                current = view.superview
            }
            return nil
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

private enum NJProtonListNormalizer {
    static func apply(_ input: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: input)
        _ = normalizeTextStorage(m)
        return m
    }

    @discardableResult
    static func normalizeTextStorage(_ text: NSMutableAttributedString) -> Bool {
        let s = text.string as NSString
        guard s.length > 0 else { return false }

        var didChange = false
        var cursor = 0

        while cursor < s.length {
            let paragraphRange = s.paragraphRange(for: NSRange(location: cursor, length: 0))
            let kind = paragraphListKind(in: text, paragraphRange: paragraphRange)
            let textList = textList(in: text, paragraphRange: paragraphRange)
            let contentRange = contentRange(in: paragraphRange, text: s)

            if let textList {
                let currentStyle = (text.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                if currentStyle.textLists.first?.markerFormat != textList.markerFormat || currentStyle.textLists.count != 1 {
                    currentStyle.textLists = [textList]
                    text.addAttribute(.paragraphStyle, value: currentStyle, range: paragraphRange)
                    didChange = true
                }

                if contentRange.length > 0 && !contentRangeHasUniformList(text, range: contentRange, kind: kind) {
                    text.addAttribute(.listItem, value: textList, range: contentRange)
                    didChange = true
                }

                applySkipMarkerFixups(text, paragraphRange: paragraphRange, contentRange: contentRange)
            } else {
                if paragraphContainsAttribute(text, key: .listItem, range: paragraphRange) {
                    text.removeAttribute(.listItem, range: paragraphRange)
                    didChange = true
                }

                let currentStyle = (text.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle
                if let currentStyle, !currentStyle.textLists.isEmpty {
                    currentStyle.textLists = []
                    text.addAttribute(.paragraphStyle, value: currentStyle, range: paragraphRange)
                    didChange = true
                }

                if paragraphContainsAttribute(text, key: .skipNextListMarker, range: paragraphRange) {
                    text.removeAttribute(.skipNextListMarker, range: paragraphRange)
                    didChange = true
                }
            }

            cursor = paragraphRange.location + max(1, paragraphRange.length)
        }

        return didChange
    }

    static func paragraphListKind(in text: NSAttributedString, paragraphRange: NSRange) -> NJListKind? {
        guard let list = textList(in: text, paragraphRange: paragraphRange) else { return nil }
        return list.markerFormat == .decimal ? .number : .bullet
    }

    private static func textList(in text: NSAttributedString, paragraphRange: NSRange) -> NSTextList? {
        var listValue: Any?
        text.enumerateAttribute(.listItem, in: paragraphRange, options: []) { value, _, stop in
            if value != nil {
                listValue = value
                stop.pointee = true
            }
        }

        if let list = listValue as? NSTextList { return list }
        if let lists = listValue as? [NSTextList], let first = lists.first { return first }
        if let style = text.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle {
            return style.textLists.first
        }
        return nil
    }

    private static func contentRange(in paragraphRange: NSRange, text: NSString) -> NSRange {
        var range = paragraphRange
        while range.length > 0 {
            let last = text.character(at: range.location + range.length - 1)
            if last == 10 || last == 13 {
                range.length -= 1
            } else {
                break
            }
        }
        return range
    }

    private static func contentRangeHasUniformList(
        _ text: NSAttributedString,
        range: NSRange,
        kind: NJListKind?
    ) -> Bool {
        guard range.length > 0 else { return true }

        var cursor = range.location
        while cursor < NSMaxRange(range) {
            var effective = NSRange(location: 0, length: 0)
            let value = text.attribute(.listItem, at: cursor, effectiveRange: &effective)
            let currentKind = listKind(from: value)
            if currentKind != kind {
                return false
            }
            cursor = max(cursor + 1, NSMaxRange(effective))
        }

        return true
    }

    private static func paragraphContainsAttribute(
        _ text: NSAttributedString,
        key: NSAttributedString.Key,
        range: NSRange
    ) -> Bool {
        var found = false
        text.enumerateAttribute(key, in: range, options: []) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func applySkipMarkerFixups(
        _ text: NSMutableAttributedString,
        paragraphRange: NSRange,
        contentRange: NSRange
    ) {
        if paragraphContainsAttribute(text, key: .skipNextListMarker, range: paragraphRange) {
            text.removeAttribute(.skipNextListMarker, range: paragraphRange)
        }

        guard contentRange.length > 0 else { return }
        let local = text.attributedSubstring(from: contentRange).string as NSString
        guard local.length > 0 else { return }

        var didApply = false
        for idx in 0..<local.length where local.character(at: idx) == 10 {
            let global = contentRange.location + idx
            text.addAttribute(.skipNextListMarker, value: true, range: NSRange(location: global, length: 1))
            didApply = true
        }

        if !didApply && paragraphContainsAttribute(text, key: .skipNextListMarker, range: paragraphRange) {
            text.removeAttribute(.skipNextListMarker, range: paragraphRange)
        }
    }

    private static func listKind(from value: Any?) -> NJListKind? {
        if let list = value as? NSTextList {
            return list.markerFormat == .decimal ? .number : .bullet
        }
        if let lists = value as? [NSTextList], let first = lists.first {
            return first.markerFormat == .decimal ? .number : .bullet
        }
        return nil
    }
}
