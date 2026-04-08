import Foundation
import UIKit
import Proton
import ObjectiveC.runtime

private final class NJCollapsibleBodyTextView: UITextView {
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(nj_sectionCmdBold)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(nj_sectionCmdItalic)),
            UIKeyCommand(input: "u", modifierFlags: .command, action: #selector(nj_sectionCmdUnderline)),
            UIKeyCommand(input: "x", modifierFlags: [.command, .shift], action: #selector(nj_sectionCmdStrike))
        ].map {
            $0.wantsPriorityOverSystemBehavior = true
            return $0
        }
    }

    @objc private func nj_sectionCmdBold() {
        _ = NJCollapsibleAttachmentView.performActionOnActiveBody(.toggleBold)
    }

    @objc private func nj_sectionCmdItalic() {
        _ = NJCollapsibleAttachmentView.performActionOnActiveBody(.toggleItalic)
    }

    @objc private func nj_sectionCmdUnderline() {
        _ = NJCollapsibleAttachmentView.performActionOnActiveBody(.toggleUnderline)
    }

    @objc private func nj_sectionCmdStrike() {
        _ = NJCollapsibleAttachmentView.performActionOnActiveBody(.toggleStrike)
    }
}

extension EditorContent.Name {
    static let njPhoto = EditorContent.Name("nj_photo")
    static let njTable = EditorContent.Name("nj_table")
    static let njCollapsible = EditorContent.Name("nj_collapsible")
}

enum NJTableAction {
    case addRow
    case addColumn
}

final class NJCollapsibleAttachmentView: UIView, AttachmentViewIdentifying, UITextViewDelegate, UITextFieldDelegate {
    enum BodyFormatAction {
        case increaseFont
        case decreaseFont
        case toggleBold
        case toggleItalic
        case toggleUnderline
        case toggleStrike
    }

    private static weak var activeBodyTextView: UITextView?
    private static var bodyOwnerKey: UInt8 = 0
    let attachmentID: String
    var name: EditorContent.Name { .njCollapsible }
    var type: AttachmentType { .block }

    private let headerButton = UIButton(type: .system)
    private let titleField = UITextField(frame: .zero)
    private let bodyTextView = NJCollapsibleBodyTextView(frame: .zero)
    private let stack = UIStackView(frame: .zero)
    private var isInternalUpdate: Bool = false
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var collapsedBottomConstraint: NSLayoutConstraint?
    private var bodyMinHeightConstraint: NSLayoutConstraint?
    private var preferredHeightConstraint: NSLayoutConstraint?
    private var lastMeasuredWidth: CGFloat = 0
    weak var boundsObserver: BoundsObserving?

    var isCollapsed: Bool {
        didSet { applyCollapsedState() }
    }

    var onContentChange: (() -> Void)?
    var onContentCommit: (() -> Void)?
    var onCollapseToggle: (() -> Void)?

    var titleAttributedText: NSAttributedString {
        get {
            NSAttributedString(string: titleField.text ?? "")
        }
        set {
            titleField.text = newValue.string
        }
    }

    var bodyAttributedText: NSAttributedString {
        get {
            bodyTextView.attributedText ?? NSAttributedString(string: "")
        }
        set {
            bodyTextView.attributedText = newValue
        }
    }

    init(
        attachmentID: String,
        title: NSAttributedString,
        body: NSAttributedString,
        isCollapsed: Bool
    ) {
        self.attachmentID = attachmentID
        self.isCollapsed = isCollapsed
        super.init(frame: .zero)
        buildUI()
        titleAttributedText = title
        bodyAttributedText = body
        applyCollapsedState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeightConstraint?.constant ?? 44)
    }

    override func layoutSubviews() {
        let oldBounds = bounds
        super.layoutSubviews()
        let w = bounds.width
        if abs(w - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = w
            recalculatePreferredHeight()
        }
        notifyBoundsChangeIfNeeded(oldBounds: oldBounds)
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isInternalUpdate else { return }
        recalculatePreferredHeight()
        onContentChange?()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        Self.activeBodyTextView = textView
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard !isInternalUpdate else { return }
        onContentCommit?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard !isInternalUpdate else { return }
        onContentCommit?()
    }

    @objc private func titleChanged() {
        guard !isInternalUpdate else { return }
        onContentChange?()
    }

    @objc private func toggleCollapsed() {
        isCollapsed.toggle()
        onCollapseToggle?()
        onContentChange?()
    }

    private func buildUI() {
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        backgroundColor = UIColor.secondarySystemBackground

        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        headerButton.tintColor = .secondaryLabel
        headerButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)
        addSubview(headerButton)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.borderStyle = .none
        titleField.placeholder = "Section"
        titleField.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = .label
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(titleChanged), for: .editingChanged)
        addSubview(titleField)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        addSubview(stack)

        bodyTextView.translatesAutoresizingMaskIntoConstraints = false
        bodyTextView.isScrollEnabled = false
        bodyTextView.backgroundColor = .clear
        bodyTextView.delegate = self
        bodyTextView.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        bodyTextView.textColor = .label
        objc_setAssociatedObject(bodyTextView, &Self.bodyOwnerKey, self, .OBJC_ASSOCIATION_ASSIGN)
        stack.addArrangedSubview(bodyTextView)

        let headerConstraints = [
            headerButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            headerButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerButton.widthAnchor.constraint(equalToConstant: 28),
            headerButton.heightAnchor.constraint(equalToConstant: 28),

            titleField.leadingAnchor.constraint(equalTo: headerButton.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
            titleField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ]
        NSLayoutConstraint.activate(headerConstraints)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])

        stackTopConstraint = stack.topAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: 8)
        stackBottomConstraint = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        collapsedBottomConstraint = headerButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        bodyMinHeightConstraint = bodyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)

        stackTopConstraint?.isActive = true
        stackBottomConstraint?.isActive = true
        bodyMinHeightConstraint?.isActive = true
        preferredHeightConstraint = heightAnchor.constraint(equalToConstant: 44)
        preferredHeightConstraint?.priority = .required
        preferredHeightConstraint?.isActive = true
        recalculatePreferredHeight()
    }

    private func applyCollapsedState() {
        isInternalUpdate = true
        stack.isHidden = isCollapsed
        stackTopConstraint?.isActive = !isCollapsed
        stackBottomConstraint?.isActive = !isCollapsed
        collapsedBottomConstraint?.isActive = isCollapsed
        bodyMinHeightConstraint?.constant = isCollapsed ? 0 : 44
        let symbol = isCollapsed ? "chevron.right" : "chevron.down"
        headerButton.setImage(UIImage(systemName: symbol), for: .normal)
        isInternalUpdate = false
        recalculatePreferredHeight()
        DispatchQueue.main.async { [weak self] in
            self?.recalculatePreferredHeight()
        }
    }

    private func recalculatePreferredHeight() {
        let oldHeight = preferredHeightConstraint?.constant ?? bounds.height
        let next: CGFloat
        if isCollapsed {
            next = 44
        } else {
            let width = max(220, bounds.width - 24)
            let bodyFit = bodyTextView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
            next = 56 + max(44, bodyFit)
        }
        let changed = abs((preferredHeightConstraint?.constant ?? 0) - next) > 0.5
        if changed {
            preferredHeightConstraint?.constant = next
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            superview?.setNeedsLayout()
            notifyAttachmentOfHeightChange(from: oldHeight, to: next)
        }
    }

    private func notifyAttachmentOfHeightChange(from oldHeight: CGFloat, to newHeight: CGFloat) {
        let width = max(bounds.width, 1)
        let oldBounds = CGRect(origin: bounds.origin, size: CGSize(width: width, height: max(oldHeight, 1)))
        let newBounds = CGRect(origin: bounds.origin, size: CGSize(width: width, height: max(newHeight, 1)))
        boundsObserver?.didChangeBounds(newBounds, oldBounds: oldBounds)
    }

    private func notifyBoundsChangeIfNeeded(oldBounds: CGRect) {
        guard oldBounds != bounds else { return }
        guard oldBounds != .zero, bounds != .zero else { return }
        boundsObserver?.didChangeBounds(bounds, oldBounds: oldBounds)
    }

    static func insertImageIntoActiveBody(_ image: UIImage) -> Bool {
        guard let tv = activeBodyTextView else { return false }
        let existing = tv.attributedText ?? NSAttributedString(string: "")
        let m = NSMutableAttributedString(attributedString: existing)
        let safeLoc = min(max(0, tv.selectedRange.location), m.length)
        let safeLen = min(max(0, tv.selectedRange.length), m.length - safeLoc)
        let range = NSRange(location: safeLoc, length: safeLen)

        let maxW = max(120, tv.bounds.width - 8)
        let prepared = downscaledImage(image, maxDisplayWidth: maxW, displayScale: max(1, tv.traitCollection.displayScale))
        let ratio = prepared.size.height / max(1, prepared.size.width)
        let w = max(1, maxW)
        let h = max(1, w * ratio)

        let att = NSTextAttachment()
        att.image = prepared
        att.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let attText = NSAttributedString(attachment: att)
        let replacement = NSMutableAttributedString()
        let ns = m.string as NSString
        let needsLeadingNewline = range.location > 0 && ns.character(at: range.location - 1) != 10 && ns.character(at: range.location - 1) != 13
        let endIndex = range.location + range.length
        let needsTrailingNewline = endIndex < ns.length && ns.character(at: endIndex) != 10 && ns.character(at: endIndex) != 13
        if needsLeadingNewline { replacement.append(NSAttributedString(string: "\n")) }
        replacement.append(attText)
        replacement.append(NSAttributedString(string: needsTrailingNewline ? "\n\n" : "\n"))

        m.replaceCharacters(in: range, with: replacement)
        tv.attributedText = m
        tv.selectedRange = NSRange(location: min(range.location + replacement.length, m.length), length: 0)

        if let owner = objc_getAssociatedObject(tv, &Self.bodyOwnerKey) as? NJCollapsibleAttachmentView {
            owner.recalculatePreferredHeight()
            owner.onContentChange?()
            owner.onContentCommit?()
        }
        return true
    }

    static func activeAttachmentID() -> String? {
        guard let tv = activeBodyTextView else { return nil }
        guard let owner = objc_getAssociatedObject(tv, &Self.bodyOwnerKey) as? NJCollapsibleAttachmentView else { return nil }
        return owner.attachmentID
    }

    static func performActionOnActiveBody(_ action: BodyFormatAction) -> Bool {
        guard let tv = activeBodyTextView else { return false }
        guard let owner = objc_getAssociatedObject(tv, &Self.bodyOwnerKey) as? NJCollapsibleAttachmentView else { return false }

        func baseFont(for value: Any?) -> UIFont {
            (value as? UIFont) ?? UIFont.systemFont(ofSize: 15, weight: .regular)
        }

        func canonicalBodyFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
            let weight: UIFont.Weight = bold ? .semibold : .regular
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard italic else { return base }
            if let nfd = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitItalic)) {
                return UIFont(descriptor: nfd, size: size)
            }
            return base
        }

        func bodySnapshot() {
            owner.recalculatePreferredHeight()
            owner.onContentChange?()
            owner.onContentCommit?()
        }

        func adjustFontSize(delta: CGFloat) {
            let r = tv.selectedRange
            if r.length == 0 {
                let old = baseFont(for: tv.typingAttributes[.font])
                let newSize = max(8, min(48, old.pointSize + delta))
                tv.typingAttributes[.font] = UIFont(descriptor: old.fontDescriptor, size: newSize)
                return
            }

            tv.textStorage.beginEditing()
            tv.textStorage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
                let old = baseFont(for: value)
                let newSize = max(8, min(48, old.pointSize + delta))
                let newFont = UIFont(descriptor: old.fontDescriptor, size: newSize)
                tv.textStorage.addAttribute(.font, value: newFont, range: range)
            }
            tv.textStorage.endEditing()
            bodySnapshot()
        }

        func toggleBold() {
            func applyBold(_ on: Bool, _ font: UIFont) -> UIFont {
                let size = font.pointSize
                let fd = font.fontDescriptor
                let hadItalic = fd.symbolicTraits.contains(.traitItalic)
                return canonicalBodyFont(size: size, bold: on, italic: hadItalic)
            }

            let r = tv.selectedRange
            if r.length == 0 {
                let old = baseFont(for: tv.typingAttributes[.font])
                let isBoldNow = old.fontDescriptor.symbolicTraits.contains(.traitBold)
                tv.typingAttributes[.font] = applyBold(!isBoldNow, old)
                return
            }

            let storage = tv.textStorage
            let isBoldNow: Bool = {
                let old = baseFont(for: storage.attribute(.font, at: r.location, effectiveRange: nil))
                return old.fontDescriptor.symbolicTraits.contains(.traitBold)
            }()

            storage.beginEditing()
            storage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
                let old = baseFont(for: value)
                storage.addAttribute(.font, value: applyBold(!isBoldNow, old), range: range)
            }
            storage.endEditing()
            bodySnapshot()
        }

        func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
            let r = tv.selectedRange
            if r.length == 0 {
                let old = baseFont(for: tv.typingAttributes[.font])
                let hasItalic = old.fontDescriptor.symbolicTraits.contains(.traitItalic)
                let hasBold = old.fontDescriptor.symbolicTraits.contains(.traitBold)
                let nextItalic = trait == .traitItalic ? !hasItalic : hasItalic
                tv.typingAttributes[.font] = canonicalBodyFont(size: old.pointSize, bold: hasBold, italic: nextItalic)
                return
            }

            tv.textStorage.beginEditing()
            tv.textStorage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
                let old = baseFont(for: value)
                let hasItalic = old.fontDescriptor.symbolicTraits.contains(.traitItalic)
                let hasBold = old.fontDescriptor.symbolicTraits.contains(.traitBold)
                let nextItalic = trait == .traitItalic ? !hasItalic : hasItalic
                tv.textStorage.addAttribute(
                    .font,
                    value: canonicalBodyFont(size: old.pointSize, bold: hasBold, italic: nextItalic),
                    range: range
                )
            }
            tv.textStorage.endEditing()
            bodySnapshot()
        }

        func toggleUnderline() {
            let r = tv.selectedRange
            if r.length == 0 {
                let v = (tv.typingAttributes[.underlineStyle] as? Int) ?? 0
                tv.typingAttributes[.underlineStyle] = (v == 0) ? NSUnderlineStyle.single.rawValue : 0
                return
            }

            let s = tv.textStorage
            let has = ((s.attribute(.underlineStyle, at: r.location, effectiveRange: nil) as? Int) ?? 0) != 0
            s.beginEditing()
            if has {
                s.removeAttribute(.underlineStyle, range: r)
            } else {
                s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
            s.endEditing()
            bodySnapshot()
        }

        func toggleStrike() {
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
            let has = ((s.attribute(.strikethroughStyle, at: r.location, effectiveRange: nil) as? Int) ?? 0) != 0
            s.beginEditing()
            if has {
                s.removeAttribute(.strikethroughStyle, range: r)
            } else {
                s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
            s.endEditing()
            bodySnapshot()
        }

        switch action {
        case .increaseFont:
            adjustFontSize(delta: 1)
        case .decreaseFont:
            adjustFontSize(delta: -1)
        case .toggleBold:
            toggleBold()
        case .toggleItalic:
            toggleFontTrait(.traitItalic)
        case .toggleUnderline:
            toggleUnderline()
        case .toggleStrike:
            toggleStrike()
        }

        return true
    }

    static func flushActiveBodyEditing() {
        guard let tv = activeBodyTextView else { return }
        if tv.isFirstResponder {
            _ = tv.resignFirstResponder()
        }
        if let owner = objc_getAssociatedObject(tv, &Self.bodyOwnerKey) as? NJCollapsibleAttachmentView {
            owner.onContentCommit?()
        }
    }

    private static func downscaledImage(_ image: UIImage, maxDisplayWidth: CGFloat, displayScale: CGFloat) -> UIImage {
        let maxPixelWidth = max(240, maxDisplayWidth * displayScale * 1.5)
        let srcW = max(1, image.size.width)
        if srcW <= maxPixelWidth { return image }

        let scale = maxPixelWidth / srcW
        let newSize = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: fmt)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

final class NJPhotoAttachmentView: UIView, AttachmentViewIdentifying {
    let name: EditorContent.Name = .njPhoto
    let type: AttachmentType = .block

    private let imageView = UIImageView()
    private(set) var attachmentID: String
    private(set) var displaySize: CGSize
    private var pinchStartSize: CGSize = .zero
    private var minDisplayWidth: CGFloat = 120
    private var maxDisplayWidth: CGFloat = 480
    var fullPhotoRef: String
    var onOpenFull: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var image: UIImage? { imageView.image }

    static let defaultDisplayWidth: CGFloat = 240

    init(attachmentID: String, size: CGSize, image: UIImage?, fullPhotoRef: String = "") {
        self.attachmentID = attachmentID
        let clamped = Self.clampInitialSize(size)
        self.displaySize = clamped
        self.fullPhotoRef = fullPhotoRef
        super.init(frame: CGRect(origin: .zero, size: clamped))
        isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.image = image
        imageView.frame = bounds
        addSubview(imageView)
        addGestures()
        addContextMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    override var intrinsicContentSize: CGSize {
        displaySize
    }

    func updateImage(_ image: UIImage?) {
        imageView.image = image
    }

    func updateDisplaySize(_ size: CGSize) {
        displaySize = size
        frame = CGRect(origin: frame.origin, size: size)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    private static func clampInitialSize(_ size: CGSize) -> CGSize {
        let maxW = max(1, defaultDisplayWidth)
        if size.width <= maxW { return size }
        let ratio = size.height / max(1, size.width)
        return CGSize(width: maxW, height: maxW * ratio)
    }

    private func addGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        addGestureRecognizer(doubleTap)
    }

    private func addContextMenu() {
        let menu = UIContextMenuInteraction(delegate: self)
        addInteraction(menu)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began {
            pinchStartSize = displaySize
            let maxFromSuperview = (superview?.bounds.width ?? maxDisplayWidth) - 16
            maxDisplayWidth = max(minDisplayWidth, maxFromSuperview)
        }

        guard g.state == .began || g.state == .changed else { return }
        let scale = g.scale
        let ratio = pinchStartSize.height / max(1, pinchStartSize.width)
        var newW = pinchStartSize.width * scale
        newW = min(max(newW, minDisplayWidth), maxDisplayWidth)
        let newH = max(1, newW * ratio)
        updateDisplaySize(CGSize(width: newW, height: newH))
    }

    @objc private func handleDoubleTap() {
        let id = fullPhotoRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        onOpenFull?(id)
    }
}

extension NJPhotoAttachmentView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let delete = UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
                self?.onDelete?()
            }
            return UIMenu(title: "", children: [delete])
        }
    }
}

final class NJTableAttachmentView: UIView, AttachmentViewIdentifying, BackgroundColorObserving {
    let attachmentID: String
    let gridView: GridView
    var name: EditorContent.Name { .njTable }
    var type: AttachmentType { .block }
    var onAddRow: (() -> Void)?
    var onAddColumn: (() -> Void)?

    init(attachmentID: String, config: GridConfiguration, cells: [GridCell]? = nil) {
        self.attachmentID = attachmentID
        if let cells {
            self.gridView = GridView(config: config, cells: cells)
        } else {
            self.gridView = GridView(config: config)
        }
        super.init(frame: .zero)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridView)
        NSLayoutConstraint.activate([
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridView.topAnchor.constraint(equalTo: topAnchor),
            gridView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let menu = UIContextMenuInteraction(delegate: self)
        addInteraction(menu)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func containerEditor(_ editor: EditorView, backgroundColorUpdated color: UIColor?, oldColor: UIColor?) {
        gridView.backgroundColor = color
    }
}

extension NJTableAttachmentView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let addRow = UIAction(title: "Add row") { [weak self] _ in
                self?.onAddRow?()
            }
            let addColumn = UIAction(title: "Add column") { [weak self] _ in
                self?.onAddColumn?()
            }
            return UIMenu(title: "", children: [addRow, addColumn])
        }
    }
}

enum NJTableAttachmentFactory {
    static func make(
        attachmentID: String,
        config: GridConfiguration,
        cells: [GridCell]? = nil,
        onTableAction: ((String, NJTableAction) -> Void)? = nil
    ) -> Attachment {
        let view = NJTableAttachmentView(attachmentID: attachmentID, config: config, cells: cells)
        if let onTableAction {
            view.onAddRow = { onTableAction(attachmentID, .addRow) }
            view.onAddColumn = { onTableAction(attachmentID, .addColumn) }
        }
        let attachment = Attachment(view, size: .fullWidth)
        view.gridView.boundsObserver = attachment
        return attachment
    }
}
