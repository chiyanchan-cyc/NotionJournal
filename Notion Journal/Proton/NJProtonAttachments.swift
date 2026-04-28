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

private final class NJWeakAttachmentOwnerBox: NSObject {
    weak var owner: NJCollapsibleAttachmentView?

    init(owner: NJCollapsibleAttachmentView?) {
        self.owner = owner
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
    case moveRow(row: Int, direction: Int)
    case moveColumn(column: Int, direction: Int)
    case setColumnType(column: Int, type: String)
    case setTotalsEnabled(Bool)
    case setTotalFormula(column: Int, formula: String?)
    case setHideChecked(Bool)
    case setColumnFilter(column: Int, filter: String)
    case setSort(column: Int?, direction: String?)
    case setColumnFormula(column: Int, formula: String?)
    case deleteRow
    case deleteColumn
    case deleteTable
    case copyTable
    case cutTable
    case setColumnAlignment(column: Int, alignment: String)
}

enum NJTableColumnAlignment: String {
    case left
    case right
    case decimal

    var textAlignment: NSTextAlignment {
        switch self {
        case .left:
            return .left
        case .right, .decimal:
            return .right
        }
    }
}

enum NJTableColumnType: String {
    case text
    case checkbox
    case formula
}

enum NJTableSortDirection: String {
    case ascending
    case descending
}

enum NJTableTotalFormula: String {
    case none
    case sum
    case average
}

let NJTableDefaultRowHeight: CGFloat = 30

final class NJCollapsibleAttachmentView: UIView, AttachmentViewIdentifying, UITextViewDelegate, UITextFieldDelegate, DynamicBoundsProviding, EditorViewDelegate {
    enum BodyFormatAction {
        case increaseFont
        case decreaseFont
        case toggleBold
        case toggleItalic
        case toggleUnderline
        case toggleStrike
        case applyTextColor(UIColor)
    }

    private static weak var activeBodyTextView: UITextView?
    private static var bodyOwnerKey: UInt8 = 0
    let attachmentID: String
    var name: EditorContent.Name { .njCollapsible }
    var type: AttachmentType { .block }

    private let headerButton = UIButton(type: .system)
    private let titleField = UITextField(frame: .zero)
    private let bodyEditor = NJKeyCommandEditorView()
    private let bodyListProvider = NJProtonListFormattingProvider()
    private let bodyHandle = NJProtonEditorHandle()
    private let stack = UIStackView(frame: .zero)
    private var isInternalUpdate: Bool = false
    private var hasUserEditedBody: Bool = false
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var collapsedBottomConstraint: NSLayoutConstraint?
    private var bodyMinHeightConstraint: NSLayoutConstraint?
    private var preferredHeightConstraint: NSLayoutConstraint?
    private var lastMeasuredWidth: CGFloat = 0
    private var deferredHeightRecalcWork: DispatchWorkItem?
    private var suppressNextBoundsNotification = false
    private weak var bodyTextView: UITextView?
    private var storedTitleText: NSAttributedString = NSAttributedString(string: "")
    private var storedBodyText: NSAttributedString = NSAttributedString(string: "")
    private var storedBodyProtonJSON: String = ""
    weak var boundsObserver: BoundsObserving?

    var isCollapsed: Bool {
        didSet { applyCollapsedState() }
    }

    var onContentChange: (() -> Void)?
    var onContentCommit: (() -> Void)?
    var onCollapseToggle: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    var titleAttributedText: NSAttributedString {
        get {
            storedTitleText
        }
        set {
            storedTitleText = NSAttributedString(attributedString: newValue)
            titleField.text = newValue.string
        }
    }

    var bodyAttributedText: NSAttributedString {
        get {
            storedBodyText
        }
        set {
            let normalized = NJEditorCanonicalizeRichText(newValue)
            storedBodyText = NSAttributedString(attributedString: normalized)
            storedBodyProtonJSON = bodyHandle.exportProtonJSONString(from: normalized)
            hasUserEditedBody = false
            applyBodyDisplayText(normalized)
            normalizeBodyTypingAttributesIfNeeded()
            recalculatePreferredHeight()
        }
    }

    var bodyProtonJSONString: String {
        syncStoredBodyFromEditorIfPossible()
        return storedBodyProtonJSON
    }

    init(
        attachmentID: String,
        title: NSAttributedString,
        body: NSAttributedString,
        bodyProtonJSON: String? = nil,
        isCollapsed: Bool
    ) {
        self.attachmentID = attachmentID
        self.isCollapsed = isCollapsed
        super.init(frame: .zero)
        buildUI()
        titleAttributedText = title
        let normalizedStoredBody = NJEditorCanonicalizeRichText(body)
        if let bodyProtonJSON, !bodyProtonJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let decodedBody = NJEditorCanonicalizeRichText(
                bodyHandle.attributedStringFromProtonJSONString(bodyProtonJSON)
            )
            storedBodyText = NSAttributedString(attributedString: normalizedStoredBody)
            storedBodyProtonJSON = bodyProtonJSON
            hasUserEditedBody = false
            if decodedBody.length > 0 || body.length == 0 {
                applyBodyDisplayText(decodedBody)
            } else {
                applyBodyDisplayText(normalizedStoredBody)
            }
            normalizeBodyTypingAttributesIfNeeded()
            recalculatePreferredHeight()
        } else {
            bodyAttributedText = normalizedStoredBody
        }
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
        attachBodyTextViewIfNeeded()
        let w = bounds.width
        if abs(w - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = w
            recalculatePreferredHeight()
        }
        notifyBoundsChangeIfNeeded(oldBounds: oldBounds)
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView === bodyTextView else { return }
        guard !isInternalUpdate else { return }
        hasUserEditedBody = true
        syncStoredBodyFromEditorIfPossible()
        recalculatePreferredHeight()
        onContentChange?()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard textView === bodyTextView else { return }
        Self.activeBodyTextView = textView
        bodyHandle.markAsActiveHandle()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard !isInternalUpdate else { return }
        onContentCommit?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard textView === bodyTextView else { return }
        guard !isInternalUpdate else { return }
        guard hasUserEditedBody else { return }
        syncStoredBodyFromEditorIfPossible()
        onContentCommit?()
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

    @objc private func titleChanged() {
        guard !isInternalUpdate else { return }
        storedTitleText = NSAttributedString(string: titleField.text ?? "")
        onContentChange?()
    }

    @objc private func toggleCollapsed() {
        isCollapsed.toggle()
        onCollapseToggle?()
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
        titleField.font = NJEditorCanonicalBodyFont(size: 15, bold: true, italic: false)
        titleField.textColor = .label
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(titleChanged), for: .editingChanged)
        addSubview(titleField)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        addSubview(stack)

        configureBodyEditor()
        stack.addArrangedSubview(bodyEditor)

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
        bodyMinHeightConstraint = bodyEditor.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)

        stackTopConstraint?.isActive = true
        stackBottomConstraint?.isActive = true
        bodyMinHeightConstraint?.isActive = true
        preferredHeightConstraint = heightAnchor.constraint(equalToConstant: 44)
        preferredHeightConstraint?.priority = .required
        preferredHeightConstraint?.isActive = true
        recalculatePreferredHeight()
    }

    private func configureBodyEditor() {
        bodyEditor.translatesAutoresizingMaskIntoConstraints = false
        bodyEditor.listFormattingProvider = bodyListProvider
        bodyEditor.registerProcessor(ListTextProcessor())
        bodyEditor.delegate = self
        bodyEditor.isScrollEnabled = false
        bodyEditor.backgroundColor = .clear
        bodyEditor.isEditable = true
        bodyEditor.isUserInteractionEnabled = true

        bodyHandle.withProgrammatic = { [weak self] f in
            guard let self else { return }
            self.isInternalUpdate = true
            f()
            self.isInternalUpdate = false
        }
        bodyHandle.editor = bodyEditor
        bodyEditor.njHandle = bodyHandle
        bodyEditor.njProtonHandle = bodyHandle
        bodyHandle.onOpenFullPhoto = { id in
            NJPhotoLibraryPresenter.presentFullPhoto(localIdentifier: id)
        }
        bodyHandle.onSnapshot = { [weak self] _, _ in
            guard let self, !self.isInternalUpdate else { return }
            guard self.hasUserEditedBody else {
                self.recalculatePreferredHeight()
                return
            }
            self.syncStoredBodyFromEditorIfPossible()
            self.recalculatePreferredHeight()
            self.onContentChange?()
        }
        bodyHandle.onEndEditing = { [weak self] _, _ in
            guard let self, !self.isInternalUpdate else { return }
            guard self.hasUserEditedBody else { return }
            self.syncStoredBodyFromEditorIfPossible()
            self.onContentCommit?()
        }
        bodyHandle.onRequestRemeasure = { [weak self] in
            self?.recalculatePreferredHeight()
        }

        attachBodyTextViewIfNeeded()
        normalizeBodyTypingAttributesIfNeeded()
    }

    private func attachBodyTextViewIfNeeded() {
        guard let tv = findTextView(in: bodyEditor) else { return }
        if bodyTextView === tv {
            return
        }

        bodyTextView = tv
        tv.delegate = self
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        tv.njProtonHandle = bodyHandle
        bodyHandle.textView = tv
        objc_setAssociatedObject(
            tv,
            &Self.bodyOwnerKey,
            NJWeakAttachmentOwnerBox(owner: self),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        NJInstallTextViewKeyCommandHook(tv)
        NJInstallTextViewPasteHook(tv)
        NJInstallTextViewCanPerformActionHook(tv)
        normalizeBodyTypingAttributesIfNeeded()
    }

    func currentBodyAttributedTextForExport() -> NSAttributedString {
        syncStoredBodyFromEditorIfPossible()
        return storedBodyText
    }

    private func captureLatestBodyStateIfNeeded() {
        guard hasUserEditedBody else { return }
        syncStoredBodyFromEditorIfPossible()
        recalculatePreferredHeight()
    }

    private func syncStoredBodyFromEditorIfPossible() {
        guard hasUserEditedBody else { return }
        let editorText = bodyEditor.attributedText
        let textViewText = bodyTextView?.attributedText

        let candidate: NSAttributedString
        if let textViewText, textViewText.length > 0 {
            candidate = textViewText
        } else if editorText.length > 0 {
            candidate = editorText
        } else if storedBodyText.length > 0 {
            candidate = storedBodyText
        } else {
            candidate = editorText
        }

        let normalized = NJEditorCanonicalizeRichText(candidate)
        storedBodyText = NSAttributedString(attributedString: normalized)
        storedBodyProtonJSON = bodyHandle.exportProtonJSONString(from: normalized)
    }

    private func markBodyEdited() {
        hasUserEditedBody = true
    }

    private func applyBodyDisplayText(_ text: NSAttributedString) {
        if let withProgrammatic = bodyHandle.withProgrammatic {
            withProgrammatic { [weak self] in
                self?.bodyEditor.attributedText = text
            }
        } else {
            bodyEditor.attributedText = text
        }
    }

    private func normalizeBodyTypingAttributesIfNeeded() {
        guard let tv = bodyTextView else { return }
        tv.typingAttributes = NJEditorCanonicalTypingAttributes(tv.typingAttributes, baseSize: 15)
    }

    private func findTextView(in root: UIView) -> UITextView? {
        if let tv = root as? UITextView { return tv }
        for sub in root.subviews {
            if let tv = findTextView(in: sub) { return tv }
        }
        return nil
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
        guard let next = measuredPreferredHeight() else {
            scheduleDeferredHeightRecalc()
            return
        }
        let changed = abs((preferredHeightConstraint?.constant ?? 0) - next) > 0.5
        if changed {
            preferredHeightConstraint?.constant = next
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            superview?.setNeedsLayout()
            suppressNextBoundsNotification = true
            notifyAttachmentOfHeightChange(from: oldHeight, to: next)
            onLayoutChange?()
        }
    }

    func sizeFor(attachment: Attachment, containerSize: CGSize, lineRect: CGRect) -> CGSize {
        let resolvedWidth: CGFloat
        if containerSize.width > 1 {
            resolvedWidth = containerSize.width
        } else if lineRect.width > 1 {
            resolvedWidth = lineRect.width
        } else {
            resolvedWidth = bounds.width
        }
        let containerWidth = max(1, resolvedWidth)
        let nextHeight = measuredPreferredHeight(containerWidth: containerWidth) ?? (preferredHeightConstraint?.constant ?? 44)
        let nextSize = CGSize(width: containerWidth, height: max(44, nextHeight))
        let current = preferredHeightConstraint?.constant ?? 0
        if abs(current - nextSize.height) > 0.5 {
            preferredHeightConstraint?.constant = nextSize.height
            invalidateIntrinsicContentSize()
        }
        return nextSize
    }

    private func measuredPreferredHeight(containerWidth: CGFloat? = nil) -> CGFloat? {
        if isCollapsed {
            return 44
        }
        let bodyWidth: CGFloat
        if let containerWidth, containerWidth > 1 {
            bodyWidth = max(1, containerWidth - 24)
        } else if let resolved = resolvedBodyMeasureWidth() {
            bodyWidth = resolved
        } else {
            return nil
        }

        guard let bodyTextView else { return nil }

        bodyTextView.bounds.size.width = bodyWidth
        bodyTextView.textContainer.size = CGSize(width: bodyWidth, height: .greatestFiniteMagnitude)
        bodyTextView.layoutIfNeeded()
        bodyTextView.layoutManager.ensureLayout(for: bodyTextView.textContainer)
        let fitted = bodyTextView.sizeThatFits(CGSize(width: bodyWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let laidOut = bodyTextView.layoutManager.usedRect(for: bodyTextView.textContainer).height
            + bodyTextView.textContainerInset.top
            + bodyTextView.textContainerInset.bottom
        // `contentSize` can lag behind after the attachment has already expanded,
        // which creates a self-reinforcing oversized section that never shrinks.
        let bodyFit = max(fitted, laidOut)
        return 56 + max(44, bodyFit)
    }

    private func resolvedBodyMeasureWidth() -> CGFloat? {
        let candidates: [CGFloat] = [
            bodyTextView?.bounds.width ?? 0,
            bodyTextView?.frame.width ?? 0,
            stack.bounds.width,
            stack.frame.width,
            bounds.width - 24
        ]

        let width = candidates.first(where: { $0 > 1 }) ?? 0
        return width > 1 ? width : nil
    }

    private func scheduleDeferredHeightRecalc() {
        deferredHeightRecalcWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.recalculatePreferredHeight()
        }
        deferredHeightRecalcWork = work
        DispatchQueue.main.async(execute: work)
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
        if suppressNextBoundsNotification {
            suppressNextBoundsNotification = false
            return
        }
        boundsObserver?.didChangeBounds(bounds, oldBounds: oldBounds)
    }

    static func insertImageIntoActiveBody(_ image: UIImage) -> Bool {
        guard let handle = resolvedActiveBodyHandle() else { return false }
        let activeTextView = resolvedActiveBodyTextView()
        let activeOwner = activeTextView != nil ? owner(for: activeTextView!) : nil
        activeOwner?.markBodyEdited()
        handle.isEditing = true
        handle.insertPhotoAttachment(image, fullPhotoRef: "")
        handle.snapshot(markUserEdit: true)
        activeOwner?.captureLatestBodyStateIfNeeded()
        activeOwner?.onContentChange?()
        return true
    }

    static func insertLinkIntoActiveBody(_ url: URL, title: String) -> Bool {
        guard let handle = resolvedActiveBodyHandle() else { return false }
        let activeTextView = resolvedActiveBodyTextView()
        let activeOwner = activeTextView != nil ? owner(for: activeTextView!) : nil
        activeOwner?.markBodyEdited()
        handle.isEditing = true
        handle.insertLink(url, title: title)
        handle.snapshot(markUserEdit: true)
        activeOwner?.captureLatestBodyStateIfNeeded()
        activeOwner?.onContentChange?()
        return true
    }

    static func insertTableIntoActiveBody(rows: Int = 2, cols: Int = 2) -> Bool {
        guard let handle = resolvedActiveBodyHandle() else { return false }
        let activeTextView = resolvedActiveBodyTextView()
        let activeOwner = activeTextView != nil ? owner(for: activeTextView!) : nil
        activeOwner?.markBodyEdited()
        handle.isEditing = true
        handle.insertTableAttachment(rows: rows, cols: cols)
        handle.snapshot(markUserEdit: true)
        activeOwner?.captureLatestBodyStateIfNeeded()
        activeOwner?.onContentChange?()
        return true
    }

    static func handleKeyCommandMutation(in textView: UITextView) {
        guard let owner = owner(for: textView) else { return }
        owner.markBodyEdited()
        owner.captureLatestBodyStateIfNeeded()
        owner.onContentChange?()
    }

    static func activeAttachmentID() -> String? {
        guard let tv = resolvedActiveBodyTextView() else { return nil }
        guard let owner = owner(for: tv) else { return nil }
        return owner.attachmentID
    }

    static func performActionOnActiveBody(_ action: BodyFormatAction) -> Bool {
        guard let textView = resolvedActiveBodyTextView(),
              let handle = textView.njProtonHandle else { return false }
        let owner = owner(for: textView)
        owner?.markBodyEdited()
        handle.isEditing = true

        switch action {
        case .increaseFont:
            handle.increaseFont()
        case .decreaseFont:
            handle.decreaseFont()
        case .toggleBold:
            handle.toggleBold()
        case .toggleItalic:
            handle.toggleItalic()
        case .toggleUnderline:
            handle.toggleUnderline()
        case .toggleStrike:
            handle.toggleStrike()
        case .applyTextColor(let color):
            handle.setTextColor(color)
        }

        handle.snapshot(markUserEdit: true)
        owner?.captureLatestBodyStateIfNeeded()
        owner?.onContentChange?()
        return true
    }

    static func flushActiveBodyEditing() {
        guard let tv = resolvedActiveBodyTextView() else { return }
        if tv.isFirstResponder {
            _ = tv.resignFirstResponder()
        }
        if let owner = owner(for: tv) {
            owner.captureLatestBodyStateIfNeeded()
            owner.onContentCommit?()
        }
    }

    private static func resolvedActiveBodyTextView() -> UITextView? {
        if let tv = findFirstResponderTextView(),
           owner(for: tv) != nil {
            activeBodyTextView = tv
            return tv
        }
        if let tv = activeBodyTextView,
           owner(for: tv) != nil {
            return tv
        }
        activeBodyTextView = nil
        return nil
    }

    private static func owner(for textView: UITextView) -> NJCollapsibleAttachmentView? {
        let box = objc_getAssociatedObject(textView, &Self.bodyOwnerKey) as? NJWeakAttachmentOwnerBox
        return box?.owner
    }

    private static func resolvedActiveBodyHandle() -> NJProtonEditorHandle? {
        resolvedActiveBodyTextView()?.njProtonHandle
    }

    private static func findFirstResponderTextView() -> UITextView? {
        guard let window = njKeyWindow() else { return nil }
        return findFirstResponder(in: window) as? UITextView
    }

    private static func njKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    }

    private static func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let hit = findFirstResponder(in: sub) { return hit }
        }
        return nil
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

    func editorViewDidChange(_ editorView: EditorView) {
        guard editorView === bodyEditor else { return }
        if !isInternalUpdate, hasUserEditedBody {
            syncStoredBodyFromEditorIfPossible()
            recalculatePreferredHeight()
        }
    }

    func editorViewDidEndEditing(_ editorView: EditorView) {
        guard editorView === bodyEditor else { return }
        guard !isInternalUpdate else { return }
        guard hasUserEditedBody else { return }
        syncStoredBodyFromEditorIfPossible()
        onContentCommit?()
    }

    func editorViewDidChangeSelection(_ editorView: EditorView) {
        guard editorView === bodyEditor else { return }
        bodyHandle.markAsActiveHandle()
        attachBodyTextViewIfNeeded()
    }
}

final class NJPhotoAttachmentView: UIView, AttachmentViewIdentifying, DynamicBoundsProviding {
    let name: EditorContent.Name = .njPhoto
    let type: AttachmentType = .block

    private let imageView = UIImageView()
    private let resizeButton = UIButton(type: .system)
    private(set) var attachmentID: String
    private(set) var displaySize: CGSize
    private var pinchStartSize: CGSize = .zero
    private var minDisplayWidth: CGFloat = 120
    private var maxDisplayWidth: CGFloat = 480
    var fullPhotoRef: String
    var onOpenFull: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onResize: (() -> Void)?
    var image: UIImage? { imageView.image }
    weak var boundsObserver: BoundsObserving?

    static let defaultDisplayWidth: CGFloat = 240

    init(attachmentID: String, size: CGSize, image: UIImage?, fullPhotoRef: String = "") {
        self.attachmentID = attachmentID
        let clamped = CGSize(width: max(1, size.width), height: max(1, size.height))
        self.displaySize = clamped
        self.fullPhotoRef = fullPhotoRef
        super.init(frame: CGRect(origin: .zero, size: clamped))
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.isMultipleTouchEnabled = true
        imageView.image = image
        imageView.frame = bounds
        addSubview(imageView)
        configureResizeButton()
        addSubview(resizeButton)
        addGestures()
        addContextMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        let buttonSize = CGSize(width: 34, height: 34)
        resizeButton.frame = CGRect(
            x: bounds.width - buttonSize.width - 8,
            y: 8,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    override var intrinsicContentSize: CGSize {
        displaySize
    }

    func sizeFor(attachment: Attachment, containerSize: CGSize, lineRect: CGRect) -> CGSize {
        displaySize
    }

    func updateImage(_ image: UIImage?) {
        imageView.image = image
    }

    func updateDisplaySize(_ size: CGSize) {
        let oldSize = displaySize
        displaySize = size
        frame = CGRect(origin: frame.origin, size: size)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
        let oldBounds = CGRect(origin: bounds.origin, size: oldSize)
        let newBounds = CGRect(origin: bounds.origin, size: size)
        if oldSize != size {
            boundsObserver?.didChangeBounds(newBounds, oldBounds: oldBounds)
        }
        onResize?()
    }

    func applyScaleMultiplier(_ multiplier: CGFloat) {
        let ratio = currentAspectRatio()
        let maxWidth = maximumDisplayWidth()
        let targetWidth = min(max(NJPhotoAttachmentView.defaultDisplayWidth * multiplier, minDisplayWidth), maxWidth)
        let targetHeight = max(1, targetWidth * ratio)
        updateDisplaySize(CGSize(width: targetWidth, height: targetHeight))
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

    private func configureResizeButton() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        resizeButton.configuration = config
        resizeButton.showsMenuAsPrimaryAction = true
        resizeButton.menu = resizeMenu()
        resizeButton.accessibilityLabel = "Resize photo"
    }

    private func resizeMenu() -> UIMenu {
        let resize1x = UIAction(title: "Resize 1x") { [weak self] _ in
            self?.applyScaleMultiplier(1)
        }
        let resize2x = UIAction(title: "Resize 2x") { [weak self] _ in
            self?.applyScaleMultiplier(2)
        }
        let resize4x = UIAction(title: "Resize 4x") { [weak self] _ in
            self?.applyScaleMultiplier(4)
        }
        let resizeFit = UIAction(title: "Fit width") { [weak self] _ in
            guard let self else { return }
            let ratio = self.currentAspectRatio()
            let width = self.maximumDisplayWidth()
            self.updateDisplaySize(CGSize(width: width, height: max(1, width * ratio)))
        }
        return UIMenu(title: "Resize", children: [resize1x, resize2x, resize4x, resizeFit])
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began {
            pinchStartSize = displaySize
            maxDisplayWidth = maximumDisplayWidth()
        }

        guard g.state == .began || g.state == .changed else { return }
        let scale = g.scale
        let ratio = currentAspectRatio(for: pinchStartSize)
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

    private func currentAspectRatio(for size: CGSize? = nil) -> CGFloat {
        if let image = imageView.image, image.size.width > 0 {
            return image.size.height / image.size.width
        }
        let base = size ?? displaySize
        return base.height / max(1, base.width)
    }

    private func maximumDisplayWidth() -> CGFloat {
        var candidates: [CGFloat] = [window?.bounds.width ?? 0]
        var current = superview
        while let view = current {
            candidates.append(view.bounds.width)
            candidates.append(view.frame.width)
            current = view.superview
        }
        let width = (candidates.max() ?? maxDisplayWidth) - 16
        return max(minDisplayWidth, width)
    }
}

extension NJPhotoAttachmentView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copy = UIAction(title: "Copy") { [weak self] _ in
                self?.onCopy?()
            }
            let cut = UIAction(title: "Cut") { [weak self] _ in
                self?.onCut?()
            }
            let delete = UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
                self?.onDelete?()
            }
            return UIMenu(title: "", children: [self.resizeMenu(), copy, cut, delete])
        }
    }
}

final class NJTableAttachmentView: UIView, AttachmentViewIdentifying, BackgroundColorObserving, DynamicBoundsProviding, BoundsObserving, UIGestureRecognizerDelegate, GridViewDelegate {
    private static let filterIndicatorAttribute = NSAttributedString.Key("NJTableFilterIndicator")
    private static let hiddenColumnWidth: CGFloat = 2
    private static let localColumnStateVersion = 1
    private static let minimumTableFontSize: CGFloat = 12
    private static let maximumTableFontSize: CGFloat = 30
    private static var checkboxTapRecognizerKey: UInt8 = 0
    private static var checkboxTapRowKey: UInt8 = 0
    private static var checkboxTapColumnKey: UInt8 = 0
    let attachmentID: String
    private var tableShortID: String
    private var tableName: String?
    private var needsIdentitySnapshot: Bool = false
    private(set) var gridView: GridView
    var name: EditorContent.Name { .njTable }
    var type: AttachmentType { .block }
    var onAddRow: (() -> Void)?
    var onAddColumn: (() -> Void)?
    var onDeleteRow: (() -> Void)?
    var onDeleteColumn: (() -> Void)?
    var onDeleteTable: (() -> Void)?
    var onCopyTable: (() -> Void)?
    var onCutTable: (() -> Void)?
    var onResizeTable: (() -> Void)?
    var onLocalLayoutChange: (() -> Void)?
    var onTableAction: ((NJTableAction) -> Void)?
    private var isColumnResizeModeEnabled: Bool = false
    private var activeRow: Int = 0
    private var activeColumn: Int = 0
    private var storedColumnWidths: [CGFloat]
    private var syncedColumnWidths: [CGFloat]
    private var storedColumnAlignments: [NJTableColumnAlignment]
    private var storedColumnTypes: [NJTableColumnType]
    private var storedColumnFormulas: [String]
    private var storedColumnFilters: [String]
    private var storedTotalFormulas: [NJTableTotalFormula]
    private var storedHiddenColumns: Set<Int> = []
    private var totalsEnabled: Bool
    private var hideCheckedRows: Bool
    private var sortColumn: Int?
    private var sortDirection: NJTableSortDirection?
    private var storedCellTexts: [String: NSAttributedString] = [:]
    private var visibleRowIndices: [Int] = []
    private var forcedVisibleActualRows: Set<Int> = []
    private var textBeginObservers: [NSObjectProtocol] = []
    private var globalTextBeginObserver: NSObjectProtocol?
    private var tableChangeObserver: NSObjectProtocol?
    private var hasRequestedCloudRefresh = false
    private var observedTextViewIDs: Set<ObjectIdentifier> = []
    private let resizeGrip = UIView(frame: .zero)
    private weak var resizePanGesture: UIPanGestureRecognizer?
    private var resizePanLastX: CGFloat?
    private var temporarilyDisabledAncestorPans: [UIPanGestureRecognizer] = []
    weak var boundsObserver: BoundsObserving?
    private var rowCount: Int
    private var columnCount: Int
    private var preferredHeight: CGFloat
    private var lastMeasuredWidth: CGFloat = 0

    init(
        attachmentID: String,
        config: GridConfiguration,
        cells: [GridCell]? = nil,
        columnWidths: [CGFloat]? = nil,
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
        self.attachmentID = attachmentID
        let identity = NJTableStore.shared.ensureIdentity(
            tableID: attachmentID,
            preferredShortID: tableShortID,
            preferredName: tableName
        )
        self.tableShortID = identity.shortID
        self.tableName = identity.name
        self.needsIdentitySnapshot = identity.changed
        self.rowCount = max(1, config.rowsConfiguration.count)
        self.columnCount = max(1, config.columnsConfiguration.count)
        self.preferredHeight = max(44, CGFloat(max(1, config.rowsConfiguration.count)) * NJTableDefaultRowHeight)
        let safeColumnCount = max(1, config.columnsConfiguration.count)
        if let columnWidths, columnWidths.count == max(1, config.columnsConfiguration.count) {
            self.storedColumnWidths = columnWidths.map { max(60, $0) }
        } else {
            self.storedColumnWidths = Array(
                repeating: max(120, UIScreen.main.bounds.width / CGFloat(safeColumnCount)),
                count: safeColumnCount
            )
        }
        self.syncedColumnWidths = self.storedColumnWidths
        if let columnAlignments {
            let parsed = columnAlignments.compactMap(NJTableColumnAlignment.init(rawValue:))
            if parsed.count == safeColumnCount {
                self.storedColumnAlignments = parsed
            } else {
                self.storedColumnAlignments = Array(repeating: .left, count: safeColumnCount)
                for (index, value) in parsed.prefix(safeColumnCount).enumerated() {
                    self.storedColumnAlignments[index] = value
                }
            }
        } else {
            self.storedColumnAlignments = Array(repeating: .left, count: safeColumnCount)
        }
        if let columnTypes {
            let parsed = columnTypes.compactMap(NJTableColumnType.init(rawValue:))
            if parsed.count == safeColumnCount {
                self.storedColumnTypes = parsed
            } else {
                self.storedColumnTypes = Array(repeating: .text, count: safeColumnCount)
                for (index, value) in parsed.prefix(safeColumnCount).enumerated() {
                    self.storedColumnTypes[index] = value
                }
            }
        } else {
            self.storedColumnTypes = Array(repeating: .text, count: safeColumnCount)
        }
        if let columnFormulas {
            let parsed = columnFormulas.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parsed.count == safeColumnCount {
                self.storedColumnFormulas = parsed
            } else {
                self.storedColumnFormulas = Array(repeating: "", count: safeColumnCount)
                for (index, value) in parsed.prefix(safeColumnCount).enumerated() {
                    self.storedColumnFormulas[index] = value
                }
            }
        } else {
            self.storedColumnFormulas = Array(repeating: "", count: safeColumnCount)
        }
        if let totalFormulas {
            let parsed = totalFormulas.compactMap(NJTableTotalFormula.init(rawValue:))
            if parsed.count == safeColumnCount {
                self.storedTotalFormulas = parsed
            } else {
                self.storedTotalFormulas = Array(repeating: .none, count: safeColumnCount)
                for (index, value) in parsed.prefix(safeColumnCount).enumerated() {
                    self.storedTotalFormulas[index] = value
                }
            }
        } else {
            self.storedTotalFormulas = Array(repeating: .none, count: safeColumnCount)
        }
        self.totalsEnabled = totalsEnabled
        if let columnFilters {
            let parsed = columnFilters.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parsed.count == safeColumnCount {
                self.storedColumnFilters = parsed
            } else {
                self.storedColumnFilters = Array(repeating: "all", count: safeColumnCount)
                for (index, value) in parsed.prefix(safeColumnCount).enumerated() {
                    self.storedColumnFilters[index] = value
                }
            }
        } else {
            self.storedColumnFilters = Array(repeating: "all", count: safeColumnCount)
        }
        self.hideCheckedRows = hideCheckedRows
        self.sortColumn = sortColumn
        self.sortDirection = sortDirection.flatMap(NJTableSortDirection.init(rawValue:))
        if let cells {
            self.gridView = GridView(config: config, cells: cells)
        } else {
            self.gridView = GridView(config: config)
        }
        super.init(frame: .zero)
        loadLocalColumnViewState()
        clipsToBounds = false
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.clipsToBounds = false
        gridView.tintColor = .systemOrange
        gridView.selectionColor = .systemOrange
        addSubview(gridView)
        NSLayoutConstraint.activate([
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridView.topAnchor.constraint(equalTo: topAnchor),
            gridView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        gridView.delegate = self
        configureResizeGrip()
        configureGlobalTextViewObserver()
        configureTableChangeObserver()
        seedStoredCellTexts(from: gridView.cells)
        visibleRowIndices = computeVisibleRowIndices()
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        refreshCanonicalPayloadFromCloud()
        gridView.setColumnResizing(false)
        let menu = UIContextMenuInteraction(delegate: self)
        addInteraction(menu)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in textBeginObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let globalTextBeginObserver {
            NotificationCenter.default.removeObserver(globalTextBeginObserver)
        }
        if let tableChangeObserver {
            NotificationCenter.default.removeObserver(tableChangeObserver)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        if width > 1, abs(width - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = width
        }
        recalculatePreferredHeight()
        updateResizeGripFrame()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    func tableShortIDForExport() -> String {
        tableShortID
    }

    func tableNameForExport() -> String? {
        tableName
    }

    func flushPendingIdentitySnapshotIfNeeded() {
        guard needsIdentitySnapshot else { return }
        needsIdentitySnapshot = false
        onResizeTable?()
    }

    func sizeFor(attachment: Attachment, containerSize: CGSize, lineRect: CGRect) -> CGSize {
        let resolvedWidth: CGFloat
        if containerSize.width > 1 {
            resolvedWidth = containerSize.width
        } else if lineRect.width > 1 {
            resolvedWidth = lineRect.width
        } else {
            resolvedWidth = bounds.width
        }
        let width = max(1, resolvedWidth)
        let height = measuredPreferredHeight(containerWidth: width)
        if abs(preferredHeight - height) > 0.5 {
            preferredHeight = height
            invalidateIntrinsicContentSize()
        }
        return CGSize(width: width, height: height)
    }

    func containerEditor(_ editor: EditorView, backgroundColorUpdated color: UIColor?, oldColor: UIColor?) {
        gridView.backgroundColor = color
    }

    private func wireCellEditors() {
        for observer in textBeginObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        textBeginObservers.removeAll()
        observedTextViewIDs.removeAll()
        for cell in gridView.cells {
            bindCellEditorIfNeeded(cell)
        }
        applyAlignmentStylesToAllCells()
    }

    private func configureGlobalTextViewObserver() {
        globalTextBeginObserver = NotificationCenter.default.addObserver(
            forName: UITextView.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let tv = note.object as? UITextView else { return }
            guard tv.isDescendant(of: self) else { return }

            if let cell = self.findCell(containing: tv) {
                self.bindCellEditorIfNeeded(cell)
            } else {
                NJSetTextViewTableOwner(tv, owner: self)
                NJInstallTextViewKeyCommandHook(tv)
                DispatchQueue.main.async { [weak self, weak tv] in
                    guard let self, let tv, let cell = self.findCell(containing: tv) else { return }
                    self.bindCellEditorIfNeeded(cell)
                    self.cellEditingDidBegin(tv)
                    if tv.isFirstResponder {
                        _ = tv.resignFirstResponder()
                        _ = tv.becomeFirstResponder()
                    }
                }
            }

            self.cellEditingDidBegin(tv)
            self.recalculatePreferredHeight()
        }
    }

    private func configureTableChangeObserver() {
        tableChangeObserver = NotificationCenter.default.addObserver(
            forName: NJTableStore.tableDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let changedID = (note.userInfo?["table_id"] as? String) ?? ""
            guard changedID.caseInsensitiveCompare(self.attachmentID) == .orderedSame else { return }
            self.reloadCanonicalPayloadFromStoreIfIdle()
        }
    }

    private func reloadCanonicalPayloadFromStoreIfIdle() {
        if findTextViews(in: self).contains(where: { $0.isFirstResponder }) { return }
        guard let payload = NJTableStore.shared.loadCanonicalPayload(tableID: attachmentID) else { return }

        let rows = max(1, intValue(payload["rows"]) ?? rowCount)
        let cols = max(1, intValue(payload["cols"]) ?? columnCount)
        rowCount = rows
        columnCount = cols

        let widthValues = numberArray(payload["column_widths"]).map { CGFloat($0) }
        if widthValues.count == cols {
            storedColumnWidths = widthValues.map { max(60, $0) }
            syncedColumnWidths = storedColumnWidths
        } else {
            storedColumnWidths = normalizedWidthState(storedColumnWidths, columnCount: cols)
            syncedColumnWidths = normalizedWidthState(syncedColumnWidths, columnCount: cols)
        }

        storedColumnAlignments = normalizedEnumArray(
            stringArray(payload["column_alignments"]),
            count: cols,
            fallback: NJTableColumnAlignment.left
        )
        storedColumnTypes = normalizedEnumArray(
            stringArray(payload["column_types"]),
            count: cols,
            fallback: NJTableColumnType.text
        )
        storedColumnFormulas = normalizedStringArray(stringArray(payload["column_formulas"]), count: cols)
        storedTotalFormulas = normalizedEnumArray(
            stringArray(payload["total_formulas"]),
            count: cols,
            fallback: NJTableTotalFormula.none
        )
        storedColumnFilters = normalizedStringArray(
            stringArray(payload["column_filters"]),
            count: cols,
            fallback: "all"
        )
        totalsEnabled = boolValue(payload["totals_enabled"]) ?? false
        hideCheckedRows = boolValue(payload["hide_checked_rows"]) ?? false
        sortColumn = intValue(payload["sort_column"])
        sortDirection = (payload["sort_direction"] as? String).flatMap(NJTableSortDirection.init(rawValue:))
        tableName = payload["table_name"] as? String

        storedHiddenColumns = Set(storedHiddenColumns.filter { $0 >= 0 && $0 < cols })
        storedCellTexts.removeAll()
        let cellsAny = (payload["cells"] as? [Any]) ?? []
        for cellAny in cellsAny {
            guard let cell = cellAny as? [String: Any] else { continue }
            let row = intValue(cell["row"]) ?? 0
            let col = intValue(cell["col"]) ?? 0
            guard row >= 0, row < rows, col >= 0, col < cols else { continue }
            let text = Self.decodeRTFBase64((cell["rtf_base64"] as? String) ?? "") ?? NSAttributedString(string: "")
            setStoredCellText(text, atActualRow: row, column: col)
        }

        visibleRowIndices = computeVisibleRowIndices()
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        onResizeTable?()
    }

    private func refreshCanonicalPayloadFromCloud() {
        guard !hasRequestedCloudRefresh else { return }
        hasRequestedCloudRefresh = true

        Task { [weak self] in
            guard let self else { return }
            guard let fields = await NJTableCloudFetcher.fetchTable(tableID: self.attachmentID) else { return }
            await MainActor.run {
                NJTableStore.shared.applyCloudFields(fields)
            }
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes"].contains(lowered) { return true }
            if ["0", "false", "no"].contains(lowered) { return false }
        }
        return nil
    }

    private func numberArray(_ value: Any?) -> [Double] {
        ((value as? [Any]) ?? []).compactMap {
            if let number = $0 as? NSNumber { return number.doubleValue }
            if let double = $0 as? Double { return double }
            if let int = $0 as? Int { return Double(int) }
            if let string = $0 as? String { return Double(string) }
            return nil
        }
    }

    private func stringArray(_ value: Any?) -> [String] {
        ((value as? [Any]) ?? []).compactMap { $0 as? String }
    }

    private func normalizedStringArray(_ values: [String], count: Int, fallback: String = "") -> [String] {
        var result = Array(repeating: fallback, count: max(1, count))
        for (index, value) in values.prefix(result.count).enumerated() {
            result[index] = value
        }
        return result
    }

    private func normalizedEnumArray<T: RawRepresentable>(
        _ values: [String],
        count: Int,
        fallback: T
    ) -> [T] where T.RawValue == String {
        var result = Array(repeating: fallback, count: max(1, count))
        for (index, value) in values.prefix(result.count).enumerated() {
            if let parsed = T(rawValue: value) {
                result[index] = parsed
            }
        }
        return result
    }

    private func bindCellEditorIfNeeded(_ cell: GridCell) {
        applyAlignmentStyle(to: cell)
        let textViews = findTextViews(in: cell.editor)
        guard !textViews.isEmpty else { return }
        let visibleRow = cell.rowSpan.min() ?? 0
        let actualRow = actualRow(forVisibleRow: visibleRow)
        let column = cell.columnSpan.min() ?? 0
        let isCheckbox = isCheckboxColumn(column)
        let isFormula = isFormulaColumn(column)
        let isTotal = isTotalActualRow(actualRow)
        let tint = rowTintColor(forActualRow: actualRow)
        let shouldAllowTextEditing = !isTotal && !isCheckbox && !(isFormula && actualRow > 0)
        cell.editor.isEditable = shouldAllowTextEditing
        cell.editor.isUserInteractionEnabled = shouldAllowTextEditing || isCheckbox
        cell.editor.backgroundColor = tint
        cell.editor.contentInset = .zero
        cell.editor.textContainerInset = .zero
        cell.editor.maxHeight = .max(max(34, minimumRowHeight(forActualRow: actualRow)))
        configureCheckboxTapIfNeeded(for: cell.editor, actualRow: actualRow, column: column, enabled: isCheckbox && !isTotal)

        for tv in textViews {
            tv.isEditable = shouldAllowTextEditing
            tv.isSelectable = shouldAllowTextEditing
            tv.isUserInteractionEnabled = !isTotal && !isCheckbox
            tv.backgroundColor = tint
            tv.isScrollEnabled = false
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0
            if isTotal {
                tv.textColor = .secondaryLabel
                continue
            }
            let handle = tv.njProtonHandle ?? cell.editor.njProtonHandle ?? NJProtonEditorHandle()
            handle.editor = cell.editor
            handle.textView = tv
            handle.onSnapshot = { [weak self] _, _ in
                guard let self else { return }
                self.captureCurrentGridState()
                self.refreshComputedAndTotalVisibleCells()
                self.recalculatePreferredHeight()
                self.persistCanonicalPayloadToStore()
            }
            tv.njProtonHandle = handle
            cell.editor.njProtonHandle = handle
            if let keyEditor = cell.editor as? NJKeyCommandEditorView {
                keyEditor.njHandle = handle
            }
            if isCheckbox {
                let checkboxText = checkboxAttributedText(checked: checkboxState(atActualRow: actualRow, column: column))
                if cell.editor.attributedText.string != checkboxText.string {
                    cell.editor.attributedText = checkboxText
                }
                tv.textColor = displayTextColor(forActualRow: actualRow, isCheckbox: true)
            } else {
                tv.textColor = displayTextColor(forActualRow: actualRow, isCheckbox: false)
            }
            objc_setAssociatedObject(tv, Unmanaged.passUnretained(self).toOpaque(), cell, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            NJSetTextViewTableOwner(tv, owner: self)
            NJInstallTextViewKeyCommandHook(tv)

            let id = ObjectIdentifier(tv)
            if observedTextViewIDs.contains(id) { continue }
            observedTextViewIDs.insert(id)

            let observer = NotificationCenter.default.addObserver(
                forName: UITextView.textDidBeginEditingNotification,
                object: tv,
                queue: .main
            ) { [weak self, weak tv] _ in
                guard let self, let tv else { return }
                self.cellEditingDidBegin(tv)
            }
            textBeginObservers.append(observer)

            let changeObserver = NotificationCenter.default.addObserver(
                forName: UITextView.textDidChangeNotification,
                object: tv,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.captureCurrentGridState()
                self.refreshComputedAndTotalVisibleCells()
                self.recalculatePreferredHeight()
                self.persistCanonicalPayloadToStore()
            }
            textBeginObservers.append(changeObserver)
        }
    }

    private func configureCheckboxTapIfNeeded(for view: UIView, actualRow: Int, column: Int, enabled: Bool) {
        let existing = objc_getAssociatedObject(view, &Self.checkboxTapRecognizerKey) as? UITapGestureRecognizer
        if enabled {
            let recognizer = existing ?? {
                let tap = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTapGesture(_:)))
                tap.cancelsTouchesInView = false
                view.addGestureRecognizer(tap)
                objc_setAssociatedObject(view, &Self.checkboxTapRecognizerKey, tap, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return tap
            }()
            recognizer.isEnabled = true
            objc_setAssociatedObject(view, &Self.checkboxTapRowKey, NSNumber(value: actualRow), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            objc_setAssociatedObject(view, &Self.checkboxTapColumnKey, NSNumber(value: column), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } else {
            existing?.isEnabled = false
            objc_setAssociatedObject(view, &Self.checkboxTapRowKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            objc_setAssociatedObject(view, &Self.checkboxTapColumnKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    @objc
    private func handleCheckboxTapGesture(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view else { return }
        guard let rowValue = objc_getAssociatedObject(view, &Self.checkboxTapRowKey) as? NSNumber,
              let columnValue = objc_getAssociatedObject(view, &Self.checkboxTapColumnKey) as? NSNumber else { return }
        let actualRow = rowValue.intValue
        let column = columnValue.intValue
        guard !isTotalActualRow(actualRow), isCheckboxColumn(column) else { return }
        if let visibleRow = visibleRow(forActualRow: actualRow) {
            activeRow = visibleRow
        }
        activeColumn = column
        toggleCheckbox(atActualRow: actualRow, column: column)
    }

    private func cellEditingDidBegin(_ sender: UITextView) {
        sender.njProtonHandle?.markAsActiveHandle()
        updateActiveCell(from: sender)
        updateResizeGripFrame()
    }

    private func updateActiveCell(from textView: UITextView? = nil) {
        if let textView {
            if let cell = objc_getAssociatedObject(textView, Unmanaged.passUnretained(self).toOpaque()) as? GridCell {
                activeRow = cell.rowSpan.min() ?? activeRow
                activeColumn = cell.columnSpan.min() ?? activeColumn
                return
            }
            if let cell = findCell(containing: textView) {
                activeRow = cell.rowSpan.min() ?? activeRow
                activeColumn = cell.columnSpan.min() ?? activeColumn
                return
            }
        }

        for cell in gridView.cells {
            guard editorContainsFirstResponder(cell.editor) else { continue }
            activeRow = cell.rowSpan.min() ?? activeRow
            activeColumn = cell.columnSpan.min() ?? activeColumn
            return
        }
    }

    func selectedCellCoordinates() -> (row: Int, col: Int) {
        updateActiveCell()
        return (actualRow(forVisibleRow: activeRow), activeColumn)
    }

    private func updateActiveCell(from location: CGPoint) {
        for cell in gridView.cells {
            let cellFrame = convert(cell.frame, from: gridView)
            if cellFrame.contains(location) {
                activeRow = cell.rowSpan.min() ?? activeRow
                activeColumn = cell.columnSpan.min() ?? activeColumn
                return
            }
        }
    }

    private func configureResizeGrip() {
        resizeGrip.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        resizeGrip.layer.cornerRadius = 3
        resizeGrip.layer.borderWidth = 1
        resizeGrip.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        resizeGrip.isHidden = true
        resizeGrip.clipsToBounds = true
        addSubview(resizeGrip)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = true
        resizeGrip.addGestureRecognizer(pan)
        resizePanGesture = pan
    }

    private func updateResizeGripFrame() {
        guard isColumnResizeModeEnabled else {
            resizeGrip.isHidden = true
            return
        }
        guard let cell = gridView.cellAt(rowIndex: activeRow, columnIndex: activeColumn) else {
            resizeGrip.isHidden = true
            return
        }

        let cellFrame = convert(cell.frame, from: gridView)
        guard cellFrame.width > 0, cellFrame.height > 0 else {
            resizeGrip.isHidden = true
            return
        }

        let gripWidth: CGFloat = 18
        let gripHeight = max(36, min(cellFrame.height, bounds.height))
        let originX = cellFrame.maxX - (gripWidth / 2)
        let originY = cellFrame.midY - (gripHeight / 2)
        resizeGrip.frame = CGRect(x: originX, y: originY, width: gripWidth, height: gripHeight)
        resizeGrip.isHidden = false
        bringSubviewToFront(resizeGrip)
    }

    private func setColumnResizeMode(_ isEnabled: Bool) {
        isColumnResizeModeEnabled = isEnabled
        updateActiveCell()
        updateResizeGripFrame()
    }

    @objc
    private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            beginResizingGesture()
            resizePanLastX = location.x
        case .changed:
            guard let lastX = resizePanLastX else {
                resizePanLastX = location.x
                return
            }
            let deltaX = location.x - lastX
            resizePanLastX = location.x
            applyColumnWidthDelta(deltaX)
            onLocalLayoutChange?()
        case .ended, .cancelled, .failed:
            resizePanLastX = nil
            endResizingGesture()
            setColumnResizeMode(false)
            onLocalLayoutChange?()
        default:
            break
        }
    }

    private func applyColumnWidthDelta(_ deltaX: CGFloat) {
        guard activeColumn >= 0, activeColumn < storedColumnWidths.count else { return }
        guard !storedHiddenColumns.contains(activeColumn) else { return }
        let oldWidth = storedColumnWidths[activeColumn]
        let newWidth = clampColumnWidth(oldWidth + deltaX, totalColumns: max(1, columnCount))
        if abs(newWidth - oldWidth) < 0.5 { return }
        storedColumnWidths[activeColumn] = newWidth
        persistLocalColumnViewState()
        rebuildGrid(columnWidths: currentColumnWidths())
    }

    private func currentColumnWidths() -> [CGFloat] {
        let cols = max(1, columnCount)
        if storedColumnWidths.count == cols {
            return storedColumnWidths.enumerated().map { index, width in
                if storedHiddenColumns.contains(index) {
                    return Self.hiddenColumnWidth
                }
                return clampColumnWidth(width, totalColumns: cols)
            }
        }
        let fallback = clampColumnWidth(max(120, maximumTableWidth() / CGFloat(cols)), totalColumns: cols)
        return Array(repeating: fallback, count: cols)
    }

    private func currentSyncedColumnWidths() -> [CGFloat] {
        let cols = max(1, columnCount)
        if syncedColumnWidths.count == cols {
            return syncedColumnWidths.map { clampColumnWidth($0, totalColumns: cols) }
        }
        var next = Array(repeating: clampColumnWidth(max(120, maximumTableWidth() / CGFloat(cols)), totalColumns: cols), count: cols)
        for (index, width) in syncedColumnWidths.prefix(cols).enumerated() {
            next[index] = clampColumnWidth(width, totalColumns: cols)
        }
        return next
    }

    private func currentColumnAlignments() -> [NJTableColumnAlignment] {
        let cols = max(1, columnCount)
        if storedColumnAlignments.count == cols {
            return storedColumnAlignments
        }
        var next = Array(repeating: NJTableColumnAlignment.left, count: cols)
        for (index, alignment) in storedColumnAlignments.prefix(cols).enumerated() {
            next[index] = alignment
        }
        return next
    }

    private func currentColumnTypes() -> [NJTableColumnType] {
        let cols = max(1, columnCount)
        if storedColumnTypes.count == cols {
            return storedColumnTypes
        }
        var next = Array(repeating: NJTableColumnType.text, count: cols)
        for (index, type) in storedColumnTypes.prefix(cols).enumerated() {
            next[index] = type
        }
        return next
    }

    private func currentColumnFormulas() -> [String] {
        let cols = max(1, columnCount)
        if storedColumnFormulas.count == cols {
            return storedColumnFormulas
        }
        var next = Array(repeating: "", count: cols)
        for (index, formula) in storedColumnFormulas.prefix(cols).enumerated() {
            next[index] = formula
        }
        return next
    }

    private func currentColumnFilters() -> [String] {
        let cols = max(1, columnCount)
        if storedColumnFilters.count == cols {
            return storedColumnFilters
        }
        var next = Array(repeating: "all", count: cols)
        for (index, filter) in storedColumnFilters.prefix(cols).enumerated() {
            next[index] = filter
        }
        return next
    }

    private func decodedFilterTokens(from stored: String) -> [String] {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "all" else { return [] }
        if trimmed.hasPrefix("multi:") {
            let payload = String(trimmed.dropFirst("multi:".count))
            if let data = Data(base64Encoded: payload),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                return normalizedFilterTokens(decoded)
            }
        }
        return normalizedFilterTokens([trimmed])
    }

    private func normalizedFilterTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "all" else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        let tokenSet = Set(normalized)
        if tokenSet.contains("checked") && tokenSet.contains("unchecked") {
            return []
        }
        if tokenSet.contains("empty") && tokenSet.contains("nonEmpty") {
            return []
        }
        return normalized
    }

    private func encodedFilterTokens(_ tokens: [String]) -> String {
        let normalized = normalizedFilterTokens(tokens)
        guard !normalized.isEmpty else { return "all" }
        if normalized.count == 1, let first = normalized.first {
            return first
        }
        guard let data = try? JSONEncoder().encode(normalized) else {
            return normalized.first ?? "all"
        }
        return "multi:" + data.base64EncodedString()
    }

    private func columnFilterTokens(for column: Int) -> [String] {
        let filters = currentColumnFilters()
        guard column >= 0, column < filters.count else { return [] }
        return decodedFilterTokens(from: filters[column])
    }

    private func columnHasActiveFilter(_ column: Int) -> Bool {
        !columnFilterTokens(for: column).isEmpty
    }

    private func toggledFilterStorage(current: String, token: String) -> String {
        var tokens = decodedFilterTokens(from: current)
        if let existing = tokens.firstIndex(of: token) {
            tokens.remove(at: existing)
        } else {
            tokens.append(token)
        }
        return encodedFilterTokens(tokens)
    }

    private func filterIndicatorAttributedText() -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "line.3.horizontal.decrease.circle.fill")?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttribute(Self.filterIndicatorAttribute, value: true, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private func rowTintColor(forActualRow actualRow: Int) -> UIColor {
        if isTotalActualRow(actualRow) {
            return UIColor.tertiarySystemFill
        }
        if actualRow == 0 {
            return UIColor.secondarySystemFill
        }
        return .clear
    }

    private func displayTextColor(forActualRow actualRow: Int, isCheckbox: Bool) -> UIColor {
        if isTotalActualRow(actualRow) {
            return .secondaryLabel
        }
        if actualRow == 0 {
            return .label
        }
        if isCheckbox {
            return .secondaryLabel
        }
        return .label
    }

    private func formulaDisplayTextColor(forActualRow actualRow: Int) -> UIColor {
        if actualRow == 0 {
            return .label
        }
        return .secondaryLabel
    }

    private func styledDisplayText(_ text: NSAttributedString, actualRow: Int, isFormula: Bool = false) -> NSAttributedString {
        let styled = NSMutableAttributedString(attributedString: text)
        let fullRange = NSRange(location: 0, length: styled.length)
        guard fullRange.length > 0 else { return styled }
        if actualRow == 0 || isTotalActualRow(actualRow) {
            let foreground = displayTextColor(forActualRow: actualRow, isCheckbox: false)
            styled.addAttribute(.foregroundColor, value: foreground, range: fullRange)
            styled.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                let existing = (value as? UIFont) ?? NJEditorCanonicalBodyFont(size: baseTableFontSize(), bold: false, italic: false)
                let nextFont = NJEditorCanonicalBodyFont(size: existing.pointSize, bold: true, italic: false)
                styled.addAttribute(.font, value: nextFont, range: range)
            }
        } else if rowIsChecked(actualRow) {
            styled.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            styled.addAttribute(.strikethroughColor, value: UIColor.tertiaryLabel, range: fullRange)
            styled.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: fullRange)
        } else if isFormula {
            styled.addAttribute(.foregroundColor, value: formulaDisplayTextColor(forActualRow: actualRow), range: fullRange)
        }
        return styled
    }

    private func displayedCellAttributedText(atActualRow actualRow: Int, column col: Int, type: NJTableColumnType) -> NSAttributedString {
        let base: NSAttributedString
        if isTotalActualRow(actualRow) {
            base = totalCellAttributedText(forColumn: col)
        } else if type == .checkbox, actualRow != 0 {
            base = checkboxAttributedText(checked: checkboxState(atActualRow: actualRow, column: col))
        } else if type == .formula, actualRow != 0 {
            base = computedFormulaCellText(atActualRow: actualRow, column: col)
        } else {
            base = storedCellText(atActualRow: actualRow, column: col)
        }
        let normalized = normalizedTableCellText(base)
        let displayed = NSMutableAttributedString(
            attributedString: styledDisplayText(normalized, actualRow: actualRow, isFormula: type == .formula)
        )
        guard actualRow == 0, columnHasActiveFilter(col) else { return displayed }
        displayed.append(NSAttributedString(string: " "))
        displayed.append(filterIndicatorAttributedText())
        return displayed
    }

    private func stripFilterIndicator(from text: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: text)
        var ranges: [NSRange] = []
        mutable.enumerateAttribute(Self.filterIndicatorAttribute, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
            guard value != nil else { return }
            ranges.append(range)
            let preceding = NSRange(location: max(0, range.location - 1), length: min(1, range.location))
            if preceding.length == 1,
               mutable.attributedSubstring(from: preceding).string == " " {
                ranges.append(preceding)
            }
        }
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            mutable.deleteCharacters(in: range)
        }
        return mutable
    }

    private func rebuildGrid(columnWidths: [CGFloat], captureState: Bool = true) {
        if captureState {
            captureCurrentGridState()
        }
        let safeCols = max(1, columnWidths.count)
        storedColumnAlignments = currentColumnAlignments()
        storedColumnTypes = currentColumnTypes()
        storedColumnFormulas = currentColumnFormulas()
        storedTotalFormulas = currentTotalFormulas()
        storedColumnFilters = currentColumnFilters()
        applyFormulaColumns()
        visibleRowIndices = computeVisibleRowIndices()
        let displayRows = max(1, visibleRowIndices.count)
        let rowsCfg = (0..<displayRows).map { visibleRow in
            let actualRow = self.actualRow(forVisibleRow: visibleRow)
            return GridRowConfiguration(initialHeight: minimumRowHeight(forActualRow: actualRow))
        }
        let colsCfg = columnWidths.map { width in
            let resolvedWidth = width <= Self.hiddenColumnWidth ? Self.hiddenColumnWidth : max(60, width)
            return GridColumnConfiguration(width: .fixed(resolvedWidth))
        }

        let config = GridConfiguration(
            columnsConfiguration: colsCfg,
            rowsConfiguration: rowsCfg,
            style: .default,
            boundsLimitShadowColors: GradientColors(primary: .black, secondary: .white),
            collapsedColumnWidth: 2,
            collapsedRowHeight: 2,
            ignoresOptimizedInit: true
        )

        var cells: [GridCell] = []
        cells.reserveCapacity(displayRows * safeCols)

        for row in 0..<displayRows {
            let actualRow = self.actualRow(forVisibleRow: row)
            for col in 0..<safeCols {
                let cell = GridCell(
                    rowSpan: [row],
                    columnSpan: [col],
                    initialHeight: minimumRowHeight(forActualRow: actualRow),
                    ignoresOptimizedInit: true
                )
                cell.editor.forceApplyAttributedText = true
                let type = (col >= 0 && col < storedColumnTypes.count) ? storedColumnTypes[col] : .text
                cell.editor.attributedText = displayedCellAttributedText(atActualRow: actualRow, column: col, type: type)
                let alignment = (col >= 0 && col < storedColumnAlignments.count) ? storedColumnAlignments[col] : .left
                applyAlignmentStyle(to: cell, alignment: alignment)
                cells.append(cell)
            }
        }

        gridView.removeFromSuperview()
        let nextGrid = GridView(config: config, cells: cells)
        nextGrid.translatesAutoresizingMaskIntoConstraints = false
        nextGrid.clipsToBounds = false
        nextGrid.tintColor = .systemOrange
        nextGrid.selectionColor = .systemOrange
        nextGrid.delegate = self
        nextGrid.boundsObserver = self
        gridView = nextGrid
        addSubview(nextGrid)
        NSLayoutConstraint.activate([
            nextGrid.leadingAnchor.constraint(equalTo: leadingAnchor),
            nextGrid.trailingAnchor.constraint(equalTo: trailingAnchor),
            nextGrid.topAnchor.constraint(equalTo: topAnchor),
            nextGrid.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        columnCount = safeCols
        wireCellEditors()
        recalculatePreferredHeight()
        updateResizeGripFrame()
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func focusCell(row: Int, column: Int) {
        guard row >= 0, row < visibleRowCount(), column >= 0, column < columnCount else { return }
        guard !isTotalVisibleRow(row) else { return }
        guard let cell = gridView.cellAt(rowIndex: row, columnIndex: column) else { return }
        activeRow = row
        activeColumn = column
        gridView.scrollToCellAt(rowIndex: row, columnIndex: column, animated: false)
        cell.setFocus()
        DispatchQueue.main.async { [weak self, weak cell] in
            guard let self, let cell else { return }
            self.scrollCellIntoVisibleArea(cell)
        }
        updateResizeGripFrame()
    }

    private func scrollCellIntoVisibleArea(_ cell: GridCell) {
        var ancestor: UIView? = self
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                let rect = scrollView.convert(cell.frame, from: gridView).insetBy(dx: 0, dy: -24)
                scrollView.scrollRectToVisible(rect, animated: false)
                return
            }
            ancestor = view.superview
        }
    }

    private func focusActualCell(row actualRow: Int, column: Int) {
        guard let visibleRow = visibleRow(forActualRow: actualRow) else { return }
        focusCell(row: visibleRow, column: column)
    }

    func appendRow(focusColumn: Int? = nil) {
        let nextRow = rowCount
        captureCurrentGridState()
        rowCount += 1
        forcedVisibleActualRows.insert(nextRow)
        clearStoredRow(atActualRow: nextRow)
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        activeRow = visibleRow(forActualRow: nextRow) ?? max(0, visibleRowCount() - 1)
        activeColumn = min(activeColumn, max(0, columnCount - 1))
        persistCanonicalPayloadToStore()
        onResizeTable?()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recalculatePreferredHeight()
            self.boundsObserver?.didChangeBounds(self.bounds, oldBounds: self.bounds)
            let targetColumn = min(focusColumn ?? self.activeColumn, max(0, self.columnCount - 1))
            self.focusActualCell(row: nextRow, column: targetColumn)
        }
    }

    func handleReturnKey() {
        updateActiveCell()
        let targetColumn = activeColumn
        let currentActualRow = actualRow(forVisibleRow: activeRow)
        let nextActualRow = currentActualRow + 1
        if nextActualRow >= rowCount {
            appendRow(focusColumn: targetColumn)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.focusActualCell(row: nextActualRow, column: targetColumn)
        }
    }

    private func beginResizingGesture() {
        guard temporarilyDisabledAncestorPans.isEmpty else { return }
        var current = superview
        while let view = current {
            for recognizer in view.gestureRecognizers ?? [] {
                guard let pan = recognizer as? UIPanGestureRecognizer else { continue }
                guard pan !== resizePanGesture else { continue }
                guard pan.isEnabled else { continue }
                pan.isEnabled = false
                temporarilyDisabledAncestorPans.append(pan)
            }
            current = view.superview
        }
    }

    private func endResizingGesture() {
        let disabled = temporarilyDisabledAncestorPans
        temporarilyDisabledAncestorPans.removeAll()
        DispatchQueue.main.async {
            for pan in disabled {
                pan.isEnabled = true
            }
        }
    }

    private func moveFocus(forwardFromRow row: Int, column col: Int) {
        guard rowCount > 0, columnCount > 0 else { return }
        var nextRow = row
        var nextCol = col + 1
        while nextCol < columnCount && storedHiddenColumns.contains(nextCol) {
            nextCol += 1
        }
        if nextCol >= columnCount {
            nextCol = 0
            while nextCol < columnCount && storedHiddenColumns.contains(nextCol) {
                nextCol += 1
            }
            nextRow += 1
        }
        guard nextRow < visibleRowCount() else { return }
        guard nextCol >= 0, nextCol < columnCount else { return }
        guard !isTotalVisibleRow(nextRow) else { return }
        guard let cell = gridView.cellAt(rowIndex: nextRow, columnIndex: nextCol) else { return }
        activeRow = nextRow
        activeColumn = nextCol
        gridView.scrollToCellAt(rowIndex: nextRow, columnIndex: nextCol, animated: false)
        cell.setFocus()
        updateResizeGripFrame()
    }

    private func moveFocus(backwardFromRow row: Int, column col: Int) {
        guard rowCount > 0, columnCount > 0 else { return }
        var nextRow = row
        var nextCol = col - 1
        while nextCol >= 0 && storedHiddenColumns.contains(nextCol) {
            nextCol -= 1
        }
        if nextCol < 0 {
            nextRow -= 1
            nextCol = columnCount - 1
            while nextCol >= 0 && storedHiddenColumns.contains(nextCol) {
                nextCol -= 1
            }
        }
        guard nextRow >= 0 else { return }
        guard nextCol >= 0, nextCol < columnCount else { return }
        guard !isTotalVisibleRow(nextRow) else { return }
        guard let cell = gridView.cellAt(rowIndex: nextRow, columnIndex: nextCol) else { return }
        activeRow = nextRow
        activeColumn = nextCol
        gridView.scrollToCellAt(rowIndex: nextRow, columnIndex: nextCol, animated: false)
        cell.setFocus()
        updateResizeGripFrame()
    }

    func focusNextCell() {
        updateActiveCell()
        moveFocus(forwardFromRow: activeRow, column: activeColumn)
    }

    func focusPreviousCell() {
        updateActiveCell()
        moveFocus(backwardFromRow: activeRow, column: activeColumn)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === resizePanGesture
    }

    func gridView(_ gridView: GridView, didReceiveFocusAt range: NSRange, in cell: GridCell) {
        bindCellEditorIfNeeded(cell)
        activeRow = cell.rowSpan.min() ?? activeRow
        activeColumn = cell.columnSpan.min() ?? activeColumn
        updateResizeGripFrame()
    }

    func gridView(_ gridView: GridView, didLoseFocusFrom range: NSRange, in cell: GridCell) {
    }

    func gridView(_ gridView: GridView, didTapAtLocation location: CGPoint, characterRange: NSRange?, in cell: GridCell) {
        let visibleRow = cell.rowSpan.min() ?? 0
        let actualRow = actualRow(forVisibleRow: visibleRow)
        let column = cell.columnSpan.min() ?? 0
        activeRow = visibleRow
        activeColumn = column
        if isTotalActualRow(actualRow) {
            return
        }
        if isCheckboxColumn(column) {
            toggleCheckbox(atActualRow: actualRow, column: column)
        }
    }

    func gridView(_ gridView: GridView, didChangeSelectionAt range: NSRange, attributes: [NSAttributedString.Key : Any], contentType: EditorContent.Name, in cell: GridCell) {
    }

    func gridView(_ gridView: GridView, didChangeBounds bounds: CGRect, in cell: GridCell) {
    }

    func gridView(_ gridView: GridView, didSelectCells cells: [GridCell]) {
    }

    func gridView(_ gridView: GridView, didUnselectCells cells: [GridCell]) {
    }

    func gridView(_ gridView: GridView, didReceiveKey key: EditorKey, at range: NSRange, in cell: GridCell) {
        let row = cell.rowSpan.min() ?? activeRow
        let col = cell.columnSpan.min() ?? activeColumn
        if key == .tab {
            moveFocus(forwardFromRow: row, column: col)
        }
    }

    func gridView(_ gridView: GridView, shouldChangeColumnWidth proposedWidth: CGFloat, for columnIndex: Int) -> Bool {
        false
    }

    func gridView(_ gridView: GridView, didLayoutCell cell: GridCell) {
        bindCellEditorIfNeeded(cell)
    }

    func didChangeBounds(_ bounds: CGRect, oldBounds: CGRect) {
        recalculatePreferredHeight()
    }

    private func recalculatePreferredHeight() {
        let oldHeight = preferredHeight
        let nextHeight = measuredPreferredHeight(containerWidth: bounds.width)
        guard abs(nextHeight - oldHeight) > 0.5 else { return }
        preferredHeight = nextHeight
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
        let width = max(bounds.width, 1)
        let oldBoundsRect = CGRect(origin: self.bounds.origin, size: CGSize(width: width, height: max(oldHeight, 1)))
        let newBoundsRect = CGRect(origin: self.bounds.origin, size: CGSize(width: width, height: max(nextHeight, 1)))
        boundsObserver?.didChangeBounds(newBoundsRect, oldBounds: oldBoundsRect)
    }

    private func measuredPreferredHeight(containerWidth: CGFloat?) -> CGFloat {
        let widths = currentColumnWidths()
        let estimated = estimatedContentHeight(columnWidths: widths)
        layoutIfNeeded()
        gridView.layoutIfNeeded()
        let laidOutGridHeight = gridView.systemLayoutSizeFitting(
            CGSize(width: max(1, bounds.width), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return max(44, estimated, ceil(laidOutGridHeight))
    }

    private func minimumRowHeight(forActualRow actualRow: Int) -> CGFloat {
        let base = ceil(baseTableFontSize() + 10)
        if actualRow == 0 || isTotalActualRow(actualRow) {
            return max(32, base)
        }
        return max(28, base)
    }

    private func estimatedContentHeight(columnWidths: [CGFloat]) -> CGFloat {
        let safeCols = min(columnCount, columnWidths.count)
        guard safeCols > 0 else { return NJTableDefaultRowHeight }
        var totalHeight: CGFloat = 0

        for visibleRow in 0..<visibleRowCount() {
            let actualRow = actualRow(forVisibleRow: visibleRow)
            var rowHeight = minimumRowHeight(forActualRow: actualRow)

            for col in 0..<safeCols {
                let width = columnWidths[col]
                guard width > Self.hiddenColumnWidth + 1 else { continue }
                let type = (col < currentColumnTypes().count) ? currentColumnTypes()[col] : .text
                let text = displayedCellAttributedText(atActualRow: actualRow, column: col, type: type)
                let availableWidth = max(24, width - 16)
                let measured = text.boundingRect(
                    with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                rowHeight = max(rowHeight, ceil(measured.height) + 10)
            }

            totalHeight += rowHeight
        }

        return max(totalHeight, NJTableDefaultRowHeight)
    }

    private func maximumTableWidth() -> CGFloat {
        var candidates: [CGFloat] = []
        var current: UIView? = self
        while let view = current {
            if view.bounds.width > 1 { candidates.append(view.bounds.width) }
            if view.frame.width > 1 { candidates.append(view.frame.width) }
            current = view.superview
        }
        let width = candidates.max() ?? max(UIScreen.main.bounds.width - 32, 240)
        return max(240, width - 16)
    }

    private func clampColumnWidth(_ width: CGFloat, totalColumns: Int) -> CGFloat {
        let minWidth: CGFloat = 60
        let availableWidth = maximumTableWidth()
        let dynamicMax = max(180, min(availableWidth * 0.6, 420))
        if totalColumns <= 1 {
            return min(max(width, minWidth), availableWidth)
        }
        return min(max(width, minWidth), dynamicMax)
    }

    private func localColumnStateStorageKey() -> String {
        "NJTableLocalColumnState.v\(Self.localColumnStateVersion).\(deviceViewStateSuffix()).\(attachmentID)"
    }

    private func deviceViewStateSuffix() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "pad"
        case .phone:
            return "phone"
        case .mac:
            return "mac"
        default:
            return "other"
        }
    }

    private func loadLocalColumnViewState() {
        let cols = max(1, columnCount)
        let defaults = UserDefaults.standard
        guard let payload = defaults.dictionary(forKey: localColumnStateStorageKey()) else {
            storedColumnWidths = normalizedWidthState(storedColumnWidths, columnCount: cols)
            return
        }
        let persistedWidths = (payload["widths"] as? [NSNumber])?.map { CGFloat(truncating: $0) }
            ?? (payload["widths"] as? [Double])?.map { CGFloat($0) }
            ?? []
        let persistedHidden = Set(((payload["hidden"] as? [NSNumber])?.map { $0.intValue }
            ?? (payload["hidden"] as? [Int]) ?? []).filter { $0 >= 0 && $0 < cols })
        storedColumnWidths = normalizedWidthState(persistedWidths.isEmpty ? storedColumnWidths : persistedWidths, columnCount: cols)
        if persistedHidden.count < cols {
            storedHiddenColumns = persistedHidden
        }
    }

    private func persistLocalColumnViewState() {
        let defaults = UserDefaults.standard
        defaults.set(
            [
                "widths": normalizedWidthState(storedColumnWidths, columnCount: max(1, columnCount)).map(Double.init),
                "hidden": storedHiddenColumns.sorted()
            ],
            forKey: localColumnStateStorageKey()
        )
    }

    private func normalizedWidthState(_ widths: [CGFloat], columnCount: Int) -> [CGFloat] {
        let cols = max(1, columnCount)
        let fallback = clampColumnWidth(max(120, maximumTableWidth() / CGFloat(cols)), totalColumns: cols)
        var normalized = Array(repeating: fallback, count: cols)
        for (index, width) in widths.prefix(cols).enumerated() {
            normalized[index] = clampColumnWidth(width, totalColumns: cols)
        }
        return normalized
    }

    private func visibleColumnCount() -> Int {
        max(0, columnCount - storedHiddenColumns.count)
    }

    private func displayNameForColumn(_ column: Int) -> String {
        let header = storedCellText(atActualRow: 0, column: column).string.trimmingCharacters(in: .whitespacesAndNewlines)
        return header.isEmpty ? "Column \(column + 1)" : header
    }

    private func remapHiddenColumns(afterRemoving column: Int) {
        storedHiddenColumns = Set(storedHiddenColumns.compactMap { hidden in
            if hidden == column { return nil }
            return hidden > column ? hidden - 1 : hidden
        })
    }

    private func remapHiddenColumns(afterInserting column: Int) {
        storedHiddenColumns = Set(storedHiddenColumns.map { hidden in
            hidden >= column ? hidden + 1 : hidden
        })
    }

    private func swapLocalColumnState(from source: Int, to destination: Int) {
        guard source >= 0, source < columnCount, destination >= 0, destination < columnCount else { return }
        storedColumnWidths.swapAt(source, destination)
        syncedColumnWidths.swapAt(source, destination)
        let sourceHidden = storedHiddenColumns.contains(source)
        let destinationHidden = storedHiddenColumns.contains(destination)
        storedHiddenColumns.remove(source)
        storedHiddenColumns.remove(destination)
        if sourceHidden { storedHiddenColumns.insert(destination) }
        if destinationHidden { storedHiddenColumns.insert(source) }
        persistLocalColumnViewState()
    }

    private func insertLocalColumnState(at index: Int) {
        let clampedIndex = max(0, min(index, storedColumnWidths.count))
        let colsAfterInsert = max(1, columnCount + 1)
        let fallback = clampColumnWidth(max(120, maximumTableWidth() / CGFloat(colsAfterInsert)), totalColumns: colsAfterInsert)
        storedColumnWidths.insert(fallback, at: clampedIndex)
        syncedColumnWidths.insert(fallback, at: min(clampedIndex, syncedColumnWidths.count))
        remapHiddenColumns(afterInserting: clampedIndex)
        persistLocalColumnViewState()
    }

    private func removeLocalColumnState(at index: Int) {
        guard index >= 0, index < storedColumnWidths.count else { return }
        storedColumnWidths.remove(at: index)
        if index < syncedColumnWidths.count {
            syncedColumnWidths.remove(at: index)
        }
        remapHiddenColumns(afterRemoving: index)
        persistLocalColumnViewState()
    }

    private func hideColumn(_ column: Int) {
        guard column >= 0, column < columnCount else { return }
        guard !storedHiddenColumns.contains(column) else { return }
        guard visibleColumnCount() > 1 else { return }
        storedHiddenColumns.insert(column)
        if activeColumn == column {
            activeColumn = nextVisibleColumn(startingAt: column + 1, fallbackDirection: -1) ?? activeColumn
        }
        persistLocalColumnViewState()
        rebuildGrid(columnWidths: currentColumnWidths())
        onLocalLayoutChange?()
    }

    private func showColumn(_ column: Int) {
        guard storedHiddenColumns.contains(column) else { return }
        storedHiddenColumns.remove(column)
        persistLocalColumnViewState()
        rebuildGrid(columnWidths: currentColumnWidths())
        onLocalLayoutChange?()
    }

    private func showAllColumns() {
        guard !storedHiddenColumns.isEmpty else { return }
        storedHiddenColumns.removeAll()
        persistLocalColumnViewState()
        rebuildGrid(columnWidths: currentColumnWidths())
        onLocalLayoutChange?()
    }

    private func nextVisibleColumn(startingAt start: Int, fallbackDirection: Int) -> Int? {
        if columnCount <= 0 { return nil }
        if start >= 0 && start < columnCount {
            for candidate in start..<columnCount where !storedHiddenColumns.contains(candidate) {
                return candidate
            }
        }
        if fallbackDirection < 0 {
            for candidate in stride(from: min(max(start - 1, 0), columnCount - 1), through: 0, by: -1) where !storedHiddenColumns.contains(candidate) {
                return candidate
            }
        }
        return (0..<columnCount).first { !storedHiddenColumns.contains($0) }
    }

    private func findTextView(in root: UIView) -> UITextView? {
        if let tv = root as? UITextView { return tv }
        for sub in root.subviews {
            if let tv = findTextView(in: sub) { return tv }
        }
        return nil
    }

    private func findTextViews(in root: UIView) -> [UITextView] {
        var result: [UITextView] = []
        if let tv = root as? UITextView {
            result.append(tv)
        }
        for sub in root.subviews {
            result.append(contentsOf: findTextViews(in: sub))
        }
        return result
    }

    private func findCell(containing textView: UITextView) -> GridCell? {
        for cell in gridView.cells {
            if textView.isDescendant(of: cell.editor) || cell.editor === textView {
                return cell
            }
        }
        return nil
    }

    func shouldSuppressSystemEditMenu(for textView: UITextView) -> Bool {
        guard let cell = findCell(containing: textView) else { return false }
        let visibleRow = cell.rowSpan.min() ?? 0
        let actualRow = actualRow(forVisibleRow: visibleRow)
        let column = cell.columnSpan.min() ?? 0
        if actualRow == 0 { return true }
        if isTotalActualRow(actualRow) { return true }
        if isCheckboxColumn(column) { return true }
        if actualRow > 0 && isFormulaColumn(column) { return true }
        return false
    }

    private func editorContainsFirstResponder(_ root: UIView) -> Bool {
        if root.isFirstResponder { return true }
        for subview in root.subviews {
            if editorContainsFirstResponder(subview) {
                return true
            }
        }
        return false
    }

    private func applyAlignmentStylesToAllCells() {
        let alignments = currentColumnAlignments()
        for cell in gridView.cells {
            let col = cell.columnSpan.min() ?? 0
            let alignment = (col >= 0 && col < alignments.count) ? alignments[col] : .left
            applyAlignmentStyle(to: cell, alignment: alignment)
        }
    }

    private func applyAlignmentStyle(to cell: GridCell) {
        let col = cell.columnSpan.min() ?? 0
        let alignments = currentColumnAlignments()
        let alignment = (col >= 0 && col < alignments.count) ? alignments[col] : .left
        applyAlignmentStyle(to: cell, alignment: alignment)
    }

    private func applyAlignmentStyle(to cell: GridCell, alignment: NJTableColumnAlignment) {
        let text = NSMutableAttributedString(attributedString: normalizedTableCellText(cell.editor.attributedText))
        let fullRange = NSRange(location: 0, length: text.length)
        if fullRange.length > 0 {
            text.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
                let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.alignment = alignment.textAlignment
                style.lineSpacing = 0
                style.paragraphSpacing = 0
                style.paragraphSpacingBefore = 0
                style.lineHeightMultiple = 1
                style.minimumLineHeight = 0
                style.maximumLineHeight = 0
                text.addAttribute(.paragraphStyle, value: style, range: range)
            }
            cell.editor.attributedText = text
        }

        if let tv = findTextView(in: cell.editor) {
            tv.textAlignment = alignment.textAlignment
            var typing = tv.typingAttributes
            let style = ((typing[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.alignment = alignment.textAlignment
            style.lineSpacing = 0
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            style.lineHeightMultiple = 1
            style.minimumLineHeight = 0
            style.maximumLineHeight = 0
            typing[.paragraphStyle] = style
            tv.typingAttributes = typing
        }
    }

    func columnWidthsForExport() -> [Double] {
        currentSyncedColumnWidths().map(Double.init)
    }

    func columnAlignmentsForExport() -> [String] {
        currentColumnAlignments().map(\.rawValue)
    }

    func columnTypesForExport() -> [String] {
        currentColumnTypes().map(\.rawValue)
    }

    func columnFormulasForExport() -> [String] {
        currentColumnFormulas()
    }

    func totalsEnabledForExport() -> Bool {
        totalsEnabled
    }

    func totalFormulasForExport() -> [String] {
        currentTotalFormulas().map(\.rawValue)
    }

    func columnFiltersForExport() -> [String] {
        currentColumnFilters()
    }

    func hideCheckedRowsForExport() -> Bool {
        hideCheckedRows
    }

    func sortColumnForExport() -> Int? {
        sortColumn
    }

    func sortDirectionForExport() -> String? {
        sortDirection?.rawValue
    }

    func tableCellsForExport() -> [[String: Any]] {
        captureCurrentGridState()
        var cellsJSON: [[String: Any]] = []
        cellsJSON.reserveCapacity(max(1, rowCount) * max(1, columnCount))
        for row in 0..<max(1, rowCount) {
            for col in 0..<max(1, columnCount) {
                let rtf = NJTableAttachmentView.encodeRTFBase64(storedCellText(atActualRow: row, column: col)) ?? ""
                cellsJSON.append([
                    "row": row,
                    "col": col,
                    "row_span": [row],
                    "col_span": [col],
                    "rtf_base64": rtf
                ])
            }
        }
        return cellsJSON
    }

    private func canonicalPayloadForStore() -> [String: Any] {
        var payload: [String: Any] = [
            "table_id": attachmentID,
            "rows": max(1, rowCount),
            "cols": max(1, columnCount),
            "table_short_id": tableShortID,
            "column_widths": columnWidthsForExport(),
            "column_alignments": columnAlignmentsForExport(),
            "column_types": columnTypesForExport(),
            "column_formulas": columnFormulasForExport(),
            "totals_enabled": totalsEnabledForExport(),
            "total_formulas": totalFormulasForExport(),
            "column_filters": columnFiltersForExport(),
            "hide_checked_rows": hideCheckedRowsForExport(),
            "cells": tableCellsForExport()
        ]
        if let tableName, !tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["table_name"] = tableName
        }
        if let sortColumn {
            payload["sort_column"] = sortColumn
        }
        if let sortDirection {
            payload["sort_direction"] = sortDirection.rawValue
        }
        return payload
    }

    private func persistCanonicalPayloadToStore() {
        NJTableStore.shared.upsertCanonicalPayload(
            tableID: attachmentID,
            payload: canonicalPayloadForStore()
        )
    }

    private static func encodeRTFBase64(_ attributed: NSAttributedString) -> String? {
        let full = NSRange(location: 0, length: attributed.length)
        guard let data = try? attributed.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private static func decodeRTFBase64(_ b64: String) -> NSAttributedString? {
        guard !b64.isEmpty, let data = Data(base64Encoded: b64) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    private func visibleRowCount() -> Int {
        max(1, visibleRowIndices.count)
    }

    private func cellKey(row: Int, col: Int) -> String {
        "\(row):\(col)"
    }

    private func storedCellText(atActualRow row: Int, column col: Int) -> NSAttributedString {
        storedCellTexts[cellKey(row: row, col: col)] ?? NSAttributedString(string: "")
    }

    private func setStoredCellText(_ text: NSAttributedString, atActualRow row: Int, column col: Int) {
        storedCellTexts[cellKey(row: row, col: col)] = normalizedTableCellText(text)
    }

    private func normalizedTableCellText(_ text: NSAttributedString) -> NSAttributedString {
        guard text.length > 0 else { return text }
        let normalized = NSMutableAttributedString(attributedString: text)
        let fullRange = NSRange(location: 0, length: normalized.length)

        normalized.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineSpacing = 0
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            style.lineHeightMultiple = 1
            style.minimumLineHeight = 0
            style.maximumLineHeight = 0
            normalized.addAttribute(.paragraphStyle, value: style, range: range)
        }

        while normalized.length > 0 {
            let tailRange = NSRange(location: normalized.length - 1, length: 1)
            let tail = normalized.attributedSubstring(from: tailRange).string
            if tail == "\n" || tail == "\r" {
                normalized.deleteCharacters(in: tailRange)
                continue
            }
            break
        }

        return normalized
    }

    private func clearStoredRow(atActualRow row: Int) {
        guard row >= 0 else { return }
        for col in 0..<max(1, columnCount) {
            setStoredCellText(NSAttributedString(string: ""), atActualRow: row, column: col)
        }
    }

    private func seedStoredCellTexts(from cells: [GridCell]) {
        storedCellTexts.removeAll()
        for cell in cells {
            let row = cell.rowSpan.min() ?? 0
            let col = cell.columnSpan.min() ?? 0
            setStoredCellText(cell.editor.attributedText, atActualRow: row, column: col)
        }
    }

    private func captureCurrentGridState() {
        for cell in gridView.cells {
            let visibleRow = cell.rowSpan.min() ?? 0
            let actualRow = actualRow(forVisibleRow: visibleRow)
            guard !isTotalActualRow(actualRow) else { continue }
            let col = cell.columnSpan.min() ?? 0
            let cleanedText = stripFilterIndicator(from: cell.editor.attributedText)
            if actualRow == 0 {
                setStoredCellText(cleanedText, atActualRow: actualRow, column: col)
                continue
            }
            let type = (col >= 0 && col < currentColumnTypes().count) ? currentColumnTypes()[col] : .text
            if type == .checkbox {
                setStoredCellText(
                    checkboxAttributedText(checked: checkboxState(from: cleanedText)),
                    atActualRow: actualRow,
                    column: col
                )
            } else if type == .formula {
                continue
            } else {
                setStoredCellText(cleanedText, atActualRow: actualRow, column: col)
            }
        }
        applyFormulaColumns()
    }

    private func computeVisibleRowIndices() -> [Int] {
        let totalRows = max(1, rowCount)
        if totalRows <= 1 { return totalsEnabled ? [0, totalRows] : [0] }

        let headerRow = 0
        var dataRows = Array(1..<totalRows)
        dataRows = dataRows.filter { rowPassesFilters($0) || forcedVisibleActualRows.contains($0) }
        if let sortColumn, let sortDirection, sortColumn >= 0, sortColumn < columnCount {
            dataRows.sort { lhs, rhs in
                compareRows(lhs, rhs, byColumn: sortColumn, direction: sortDirection)
            }
        }

        var visible = [headerRow]
        visible.append(contentsOf: dataRows)
        if totalsEnabled {
            visible.append(totalRows)
        }
        if visible.isEmpty {
            visible.append(0)
        }
        return visible
    }

    private func actualRow(forVisibleRow row: Int) -> Int {
        guard row >= 0, row < visibleRowIndices.count else {
            return min(max(0, row), max(0, rowCount))
        }
        return visibleRowIndices[row]
    }

    private func visibleRow(forActualRow row: Int) -> Int? {
        visibleRowIndices.firstIndex(of: row)
    }

    private func isCheckboxColumn(_ column: Int) -> Bool {
        let types = currentColumnTypes()
        return column >= 0 && column < types.count && types[column] == .checkbox
    }

    private func isFormulaColumn(_ column: Int) -> Bool {
        let types = currentColumnTypes()
        return column >= 0 && column < types.count && types[column] == .formula
    }

    private func currentTotalFormulas() -> [NJTableTotalFormula] {
        let cols = max(1, columnCount)
        if storedTotalFormulas.count == cols {
            return storedTotalFormulas
        }
        var next = Array(repeating: NJTableTotalFormula.none, count: cols)
        for (index, formula) in storedTotalFormulas.prefix(cols).enumerated() {
            next[index] = formula
        }
        return next
    }

    private func normalizedFormulaStorage(_ formula: String?) -> String {
        let trimmed = formula?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("=") ? trimmed : "=\(trimmed)"
    }

    private func setColumnFormulaDefinition(_ formula: String?, for column: Int) {
        var formulas = currentColumnFormulas()
        guard column >= 0, column < formulas.count else { return }
        formulas[column] = normalizedFormulaStorage(formula)
        storedColumnFormulas = formulas
    }

    private func displayFormulaDefinition(for column: Int) -> String? {
        let formulas = currentColumnFormulas()
        guard column >= 0, column < formulas.count else { return nil }
        let formula = formulas[column].trimmingCharacters(in: .whitespacesAndNewlines)
        return formula.isEmpty ? nil : formula
    }

    private func headerNameByColumn() -> [Int: String] {
        var map: [Int: String] = [:]
        for col in 0..<max(1, columnCount) {
            let header = storedCellText(atActualRow: 0, column: col).string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !header.isEmpty else { continue }
            map[col] = header
        }
        return map
    }

    private func resolveFormulaReference(named name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for col in 0..<max(1, columnCount) {
            let header = storedCellText(atActualRow: 0, column: col).string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !header.isEmpty else { continue }
            if header.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                return col
            }
        }
        return nil
    }

    private func numericValueForFormulaCell(atActualRow row: Int, column col: Int) -> Double? {
        guard row > 0, row < rowCount else { return nil }
        let type = (col >= 0 && col < currentColumnTypes().count) ? currentColumnTypes()[col] : .text
        switch type {
        case .checkbox:
            return checkboxState(atActualRow: row, column: col) ? 1 : 0
        case .text, .formula:
            let raw = storedCellText(atActualRow: row, column: col).string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return normalizedNumericValue(from: raw)
        }
    }

    private enum FormulaToken: Equatable {
        case number(Double)
        case reference(String)
        case plus
        case minus
        case multiply
        case divide
        case leftParen
        case rightParen
    }

    private func tokenizeFormula(_ formula: String) -> [FormulaToken]? {
        var tokens: [FormulaToken] = []
        let source = formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
        let chars = Array(source)
        var index = 0

        func isIdentifierChar(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || c == "_" || c == "."
        }

        while index < chars.count {
            let c = chars[index]
            if c.isWhitespace {
                index += 1
                continue
            }
            switch c {
            case "+":
                tokens.append(.plus)
                index += 1
            case "-":
                tokens.append(.minus)
                index += 1
            case "*":
                tokens.append(.multiply)
                index += 1
            case "/":
                tokens.append(.divide)
                index += 1
            case "(":
                tokens.append(.leftParen)
                index += 1
            case ")":
                tokens.append(.rightParen)
                index += 1
            case "[":
                var end = index + 1
                while end < chars.count && chars[end] != "]" { end += 1 }
                guard end < chars.count else { return nil }
                let name = String(chars[(index + 1)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                tokens.append(.reference(name))
                index = end + 1
            default:
                if c.isNumber || c == "." {
                    var end = index + 1
                    while end < chars.count && (chars[end].isNumber || chars[end] == ".") { end += 1 }
                    guard let value = Double(String(chars[index..<end])) else { return nil }
                    tokens.append(.number(value))
                    index = end
                } else if isIdentifierChar(c) {
                    var end = index + 1
                    while end < chars.count && isIdentifierChar(chars[end]) { end += 1 }
                    let name = String(chars[index..<end])
                    tokens.append(.reference(name))
                    index = end
                } else {
                    return nil
                }
            }
        }
        return tokens
    }

    private func evaluateFormula(_ formula: String, atActualRow row: Int) -> String {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let tokens = tokenizeFormula(trimmed) else { return "ERR" }
        let nonEmptyReferencedValues = tokens.compactMap { token -> Double? in
            guard case .reference(let name) = token,
                  let col = resolveFormulaReference(named: name),
                  let value = numericValueForFormulaCell(atActualRow: row, column: col) else {
                return nil
            }
            return value
        }
        let referencedColumns: [Int] = tokens.compactMap { token in
            guard case .reference(let name) = token else { return nil }
            return resolveFormulaReference(named: name)
        }
        if !referencedColumns.isEmpty && nonEmptyReferencedValues.isEmpty {
            return ""
        }

        var position = 0

        func parseFactor() -> Double? {
            guard position < tokens.count else { return nil }
            let token = tokens[position]
            position += 1
            switch token {
            case .number(let value):
                return value
            case .reference(let name):
                guard let column = resolveFormulaReference(named: name),
                      let value = numericValueForFormulaCell(atActualRow: row, column: column) else {
                    return nil
                }
                return value
            case .minus:
                guard let value = parseFactor() else { return nil }
                return -value
            case .leftParen:
                guard let value = parseExpression(), position < tokens.count, tokens[position] == .rightParen else {
                    return nil
                }
                position += 1
                return value
            default:
                return nil
            }
        }

        func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while position < tokens.count {
                let token = tokens[position]
                if token == .multiply || token == .divide {
                    position += 1
                    guard let rhs = parseFactor() else { return nil }
                    if token == .divide {
                        guard abs(rhs) > .ulpOfOne else { return nil }
                        value /= rhs
                    } else {
                        value *= rhs
                    }
                } else {
                    break
                }
            }
            return value
        }

        func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while position < tokens.count {
                let token = tokens[position]
                if token == .plus || token == .minus {
                    position += 1
                    guard let rhs = parseTerm() else { return nil }
                    value = token == .plus ? (value + rhs) : (value - rhs)
                } else {
                    break
                }
            }
            return value
        }

        guard let value = parseExpression(), position == tokens.count else { return "ERR" }
        return formattedNumericValue(value)
    }

    private func applyFormulaColumns() {
        let types = currentColumnTypes()
        let formulas = currentColumnFormulas()
        guard !types.isEmpty else { return }
        for col in 0..<min(types.count, columnCount) where types[col] == .formula {
            let formula = (col < formulas.count) ? formulas[col] : ""
            for row in 1..<max(1, rowCount) {
                let text = evaluateFormula(formula, atActualRow: row)
                setStoredCellText(
                    NSAttributedString(
                        string: text,
                        attributes: [.font: NJEditorCanonicalBodyFont(size: baseTableFontSize(), bold: false, italic: false)]
                    ),
                    atActualRow: row,
                    column: col
                )
            }
        }
    }

    private func refreshComputedAndTotalVisibleCells() {
        applyFormulaColumns()
        let types = currentColumnTypes()

        for visibleRow in 0..<visibleRowCount() {
            let actualRow = actualRow(forVisibleRow: visibleRow)
            for col in 0..<columnCount {
                guard let cell = gridView.cellAt(rowIndex: visibleRow, columnIndex: col) else { continue }
                let type = (col < types.count) ? types[col] : .text
                if isTotalActualRow(actualRow) || (type == .formula && actualRow > 0) {
                    cell.editor.attributedText = displayedCellAttributedText(atActualRow: actualRow, column: col, type: type)
                    applyAlignmentStyle(to: cell)
                }
            }
        }
    }

    private func computedFormulaCellText(atActualRow row: Int, column col: Int) -> NSAttributedString {
        storedCellText(atActualRow: row, column: col)
    }

    private func totalRowActualIndex() -> Int {
        rowCount
    }

    private func isTotalActualRow(_ row: Int) -> Bool {
        totalsEnabled && row == totalRowActualIndex()
    }

    private func isTotalVisibleRow(_ row: Int) -> Bool {
        isTotalActualRow(actualRow(forVisibleRow: row))
    }

    private func checkboxAttributedText(checked: Bool, fontSize: CGFloat? = nil) -> NSAttributedString {
        NSAttributedString(
            string: checked ? "☑" : "☐",
            attributes: [
                .font: NJEditorCanonicalBodyFont(size: fontSize ?? baseTableFontSize(), bold: false, italic: false),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
    }

    private func checkboxState(from text: NSAttributedString) -> Bool {
        let value = text.string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["☑", "☒", "✅", "true", "1", "yes", "checked", "done", "x"].contains(value)
    }

    private func checkboxState(atActualRow row: Int, column col: Int) -> Bool {
        checkboxState(from: storedCellText(atActualRow: row, column: col))
    }

    private func rowIsChecked(_ row: Int) -> Bool {
        let types = currentColumnTypes()
        for col in 0..<min(types.count, columnCount) where types[col] == .checkbox {
            if checkboxState(atActualRow: row, column: col) {
                return true
            }
        }
        return false
    }

    private func hasAnyCheckboxColumn() -> Bool {
        currentColumnTypes().contains(.checkbox)
    }

    private func setRowChecked(_ checked: Bool, atActualRow row: Int) {
        guard row > 0, row < rowCount else { return }
        let types = currentColumnTypes()
        var changed = false
        for col in 0..<min(types.count, columnCount) where types[col] == .checkbox {
            let current = checkboxState(atActualRow: row, column: col)
            guard current != checked else { continue }
            setStoredCellText(checkboxAttributedText(checked: checked, fontSize: baseTableFontSize()), atActualRow: row, column: col)
            changed = true
        }
        guard changed else { return }
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        if let visibleRow = visibleRow(forActualRow: row) {
            activeRow = visibleRow
        }
        persistCanonicalPayloadToStore()
        onResizeTable?()
    }

    private func toggleCheckbox(atActualRow row: Int, column col: Int) {
        let checked = !checkboxState(atActualRow: row, column: col)
        setStoredCellText(checkboxAttributedText(checked: checked, fontSize: baseTableFontSize()), atActualRow: row, column: col)
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        if let visibleRow = visibleRow(forActualRow: row) {
            activeRow = visibleRow
        }
        activeColumn = col
        persistCanonicalPayloadToStore()
        onResizeTable?()
    }

    private func rowPassesFilters(_ row: Int) -> Bool {
        if hideCheckedRows && rowIsChecked(row) {
            return false
        }
        let filters = currentColumnFilters()
        let types = currentColumnTypes()
        for col in 0..<min(filters.count, columnCount) {
            let tokens = decodedFilterTokens(from: filters[col])
            guard !tokens.isEmpty else { continue }
            let text = storedCellText(atActualRow: row, column: col)
            switch types[col] {
            case .checkbox:
                let checked = checkboxState(from: text)
                let matches = tokens.contains { token in
                    if token == "checked" { return checked }
                    if token == "unchecked" { return !checked }
                    return false
                }
                if !matches { return false }
            case .text, .formula:
                let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
                let matches = tokens.contains { token in
                    if token == "empty" { return trimmed.isEmpty }
                    if token == "nonEmpty" { return !trimmed.isEmpty }
                    if token.hasPrefix("value:") {
                        return trimmed.localizedCaseInsensitiveCompare(String(token.dropFirst("value:".count))) == .orderedSame
                    }
                    return false
                }
                if !matches { return false }
            }
        }
        return true
    }

    private func compareRows(_ lhs: Int, _ rhs: Int, byColumn column: Int, direction: NJTableSortDirection) -> Bool {
        let type = currentColumnTypes()[column]
        switch type {
        case .checkbox:
            let left = checkboxState(atActualRow: lhs, column: column)
            let right = checkboxState(atActualRow: rhs, column: column)
            if left == right { return lhs < rhs }
            return direction == .ascending ? (!left && right) : (left && !right)
        case .text, .formula:
            let left = storedCellText(atActualRow: lhs, column: column).string.trimmingCharacters(in: .whitespacesAndNewlines)
            let right = storedCellText(atActualRow: rhs, column: column).string.trimmingCharacters(in: .whitespacesAndNewlines)
            let ordered = left.localizedCaseInsensitiveCompare(right)
            if ordered == .orderedSame { return lhs < rhs }
            return direction == .ascending ? ordered == .orderedAscending : ordered == .orderedDescending
        }
    }

    private func totalCellAttributedText(forColumn column: Int) -> NSAttributedString {
        let formula = (column >= 0 && column < currentTotalFormulas().count) ? currentTotalFormulas()[column] : .none
        let alignment = (column >= 0 && column < currentColumnAlignments().count) ? currentColumnAlignments()[column] : .left
        let style = NSMutableParagraphStyle()
        style.alignment = alignment.textAlignment
        let string: String
        switch formula {
        case .none:
            string = ""
        case .sum:
            string = computedTotalText(forColumn: column, averaging: false)
        case .average:
            string = computedTotalText(forColumn: column, averaging: true)
        }
        return NSAttributedString(
            string: string,
            attributes: [
                .font: NJEditorCanonicalBodyFont(size: baseTableFontSize(), bold: true, italic: false),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: style
            ]
        )
    }

    private func baseTableFontSize() -> CGFloat {
        for row in 0..<max(1, rowCount) {
            for col in 0..<max(1, columnCount) {
                let text = storedCellText(atActualRow: row, column: col)
                guard text.length > 0 else { continue }
                var foundSize: CGFloat?
                text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, stop in
                    if let font = value as? UIFont {
                        foundSize = font.pointSize
                        stop.pointee = true
                    }
                }
                if let foundSize {
                    return min(max(foundSize, Self.minimumTableFontSize), Self.maximumTableFontSize)
                }
            }
        }
        return 17
    }

    private func adjustedTableText(_ text: NSAttributedString, targetSize: CGFloat) -> NSAttributedString {
        guard text.length > 0 else { return text }
        let adjusted = NSMutableAttributedString(attributedString: text)
        let fullRange = NSRange(location: 0, length: adjusted.length)
        var sawFont = false
        adjusted.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let existing = value as? UIFont else { return }
            sawFont = true
            let traits = existing.fontDescriptor.symbolicTraits
            let nextFont = NJEditorCanonicalBodyFont(
                size: targetSize,
                bold: traits.contains(.traitBold),
                italic: traits.contains(.traitItalic)
            )
            adjusted.addAttribute(.font, value: nextFont, range: range)
        }
        if !sawFont {
            adjusted.addAttribute(.font, value: NJEditorCanonicalBodyFont(size: targetSize, bold: false, italic: false), range: fullRange)
        }
        return adjusted
    }

    private func adjustWholeTableFontSize(delta: CGFloat) {
        let currentSize = baseTableFontSize()
        let nextSize = min(max(currentSize + delta, Self.minimumTableFontSize), Self.maximumTableFontSize)
        guard abs(nextSize - currentSize) > 0.01 else { return }
        captureCurrentGridState()
        let types = currentColumnTypes()
        for row in 0..<max(1, rowCount) {
            for col in 0..<max(1, columnCount) {
                if row > 0, col < types.count, types[col] == .checkbox {
                    let checked = checkboxState(atActualRow: row, column: col)
                    setStoredCellText(checkboxAttributedText(checked: checked, fontSize: nextSize), atActualRow: row, column: col)
                } else {
                    let current = storedCellText(atActualRow: row, column: col)
                    setStoredCellText(adjustedTableText(current, targetSize: nextSize), atActualRow: row, column: col)
                }
            }
        }
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        persistCanonicalPayloadToStore()
        onResizeTable?()
    }

    private func computedTotalText(forColumn column: Int, averaging: Bool) -> String {
        var values: [Double] = []
        for row in 1..<max(1, rowCount) {
            guard rowPassesFilters(row) || forcedVisibleActualRows.contains(row) else { continue }
            let raw = storedCellText(atActualRow: row, column: column).string.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            guard let parsed = normalizedNumericValue(from: raw) else {
                return "ERR"
            }
            values.append(parsed)
        }
        guard !values.isEmpty else { return "" }
        let result = averaging ? (values.reduce(0, +) / Double(values.count)) : values.reduce(0, +)
        return formattedNumericValue(result)
    }

    private func normalizedNumericValue(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isNegativeByParens = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        let allowed = CharacterSet(charactersIn: "0123456789,.-")
        let filteredScalars = trimmed.unicodeScalars.filter { allowed.contains($0) }
        var filtered = String(String.UnicodeScalarView(filteredScalars))
        let dotCount = filtered.filter { $0 == "." }.count
        let commaCount = filtered.filter { $0 == "," }.count

        if dotCount > 0 && commaCount > 0 {
            let lastDot = filtered.lastIndex(of: ".") ?? filtered.startIndex
            let lastComma = filtered.lastIndex(of: ",") ?? filtered.startIndex
            if lastComma > lastDot {
                filtered = filtered.replacingOccurrences(of: ".", with: "")
                filtered = filtered.replacingOccurrences(of: ",", with: ".")
            } else {
                filtered = filtered.replacingOccurrences(of: ",", with: "")
            }
        } else if commaCount > 0 {
            let parts = filtered.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count >= 2, let last = parts.last, (1...2).contains(last.count) {
                let integerPart = parts.dropLast().joined()
                filtered = integerPart + "." + last
            } else {
                filtered = filtered.replacingOccurrences(of: ",", with: "")
            }
        }

        if isNegativeByParens && !filtered.hasPrefix("-") {
            filtered = "-" + filtered
        }
        return Double(filtered)
    }

    private func formattedNumericValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

extension NJTableAttachmentView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        updateActiveCell(from: location)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let isOnTotalRow = self.isTotalVisibleRow(self.activeRow)
            let actualActiveRow = self.actualRow(forVisibleRow: self.activeRow)
            let canToggleRowDone = !isOnTotalRow && actualActiveRow > 0 && self.hasAnyCheckboxColumn()
            let resizeColumn = UIAction(title: "Resize column", image: UIImage(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")) { [weak self] _ in
                self?.setColumnResizeMode(true)
            }
            let alignLeft = UIAction(title: "Align column left", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in
                self?.onSetColumnAlignment(.left)
            }
            let alignRight = UIAction(title: "Align column right", image: UIImage(systemName: "text.alignright")) { [weak self] _ in
                self?.onSetColumnAlignment(.right)
            }
            let alignDecimal = UIAction(title: "Align column decimal", image: UIImage(systemName: "number")) { [weak self] _ in
                self?.onSetColumnAlignment(.decimal)
            }
            let increaseTableFont = UIAction(title: "Increase table font", image: UIImage(systemName: "textformat.size.larger")) { [weak self] _ in
                self?.adjustWholeTableFontSize(delta: 1)
            }
            let decreaseTableFont = UIAction(title: "Decrease table font", image: UIImage(systemName: "textformat.size.smaller")) { [weak self] _ in
                self?.adjustWholeTableFontSize(delta: -1)
            }
            let moveColumnLeft = UIAction(title: "Move column left", image: UIImage(systemName: "arrow.left")) { [weak self] _ in
                self?.onMoveColumn(-1)
            }
            let moveColumnRight = UIAction(title: "Move column right", image: UIImage(systemName: "arrow.right")) { [weak self] _ in
                self?.onMoveColumn(1)
            }
            let moveRowUp = UIAction(title: "Move row up", image: UIImage(systemName: "arrow.up")) { [weak self] _ in
                self?.onMoveRow(-1)
            }
            let moveRowDown = UIAction(title: "Move row down", image: UIImage(systemName: "arrow.down")) { [weak self] _ in
                self?.onMoveRow(1)
            }
            let makeTextColumn = UIAction(title: "Make column text", image: UIImage(systemName: "text.cursor")) { [weak self] _ in
                self?.onSetColumnType(.text)
            }
            let makeCheckboxColumn = UIAction(title: "Make column checkbox", image: UIImage(systemName: "checkmark.square")) { [weak self] _ in
                self?.onSetColumnType(.checkbox)
            }
            let makeFormulaColumn = UIAction(title: "Make column formula", image: UIImage(systemName: "function")) { [weak self] _ in
                self?.presentColumnFormulaPrompt()
            }
            let addTotalRow = UIAction(
                title: self.totalsEnabled ? "Remove total row" : "Add total row",
                image: UIImage(systemName: self.totalsEnabled ? "minus.circle" : "sum")
            ) { [weak self] _ in
                self?.onToggleTotals()
            }
            let sortAscending = UIAction(title: "Sort ascending", image: UIImage(systemName: "arrow.up")) { [weak self] _ in
                self?.onSetSort(.ascending)
            }
            let sortDescending = UIAction(title: "Sort descending", image: UIImage(systemName: "arrow.down")) { [weak self] _ in
                self?.onSetSort(.descending)
            }
            let clearSort = UIAction(title: "Clear sort", image: UIImage(systemName: "xmark")) { [weak self] _ in
                self?.onClearSort()
            }
            let filterTokens = self.columnFilterTokens(for: max(0, min(self.activeColumn, max(0, self.columnCount - 1))))
            let filterAll = UIAction(
                title: "Show all",
                image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
                state: filterTokens.isEmpty ? .on : .off
            ) { [weak self] _ in
                self?.onClearFilters()
            }
            let filterChecked = UIAction(
                title: "Show checked",
                image: UIImage(systemName: "checkmark.circle"),
                state: filterTokens.contains("checked") ? .on : .off
            ) { [weak self] _ in
                self?.onSetFilter("checked")
            }
            let filterUnchecked = UIAction(
                title: "Show unchecked",
                image: UIImage(systemName: "circle"),
                state: filterTokens.contains("unchecked") ? .on : .off
            ) { [weak self] _ in
                self?.onSetFilter("unchecked")
            }
            let filterEmpty = UIAction(
                title: "Show empty",
                image: UIImage(systemName: "text.badge.xmark"),
                state: filterTokens.contains("empty") ? .on : .off
            ) { [weak self] _ in
                self?.onSetFilter("empty")
            }
            let toggleHideChecked = UIAction(
                title: self.hideCheckedRows ? "Show checked items" : "Hide checked items",
                image: UIImage(systemName: self.hideCheckedRows ? "eye" : "eye.slash")
            ) { [weak self] _ in
                self?.onToggleHideChecked()
            }
            let toggleRowDone = UIAction(
                title: self.rowIsChecked(actualActiveRow) ? "Mark not done" : "Mark done",
                image: UIImage(systemName: self.rowIsChecked(actualActiveRow) ? "arrow.uturn.backward.circle" : "checkmark.circle")
            ) { [weak self] _ in
                guard let self else { return }
                self.setRowChecked(!self.rowIsChecked(actualActiveRow), atActualRow: actualActiveRow)
            }
            let addRow = UIAction(title: "Add row") { [weak self] _ in
                self?.onAddRow?()
            }
            let addColumn = UIAction(title: "Add column") { [weak self] _ in
                self?.handleAddColumn()
            }
            let deleteRow = UIAction(title: "Delete row", attributes: .destructive) { [weak self] _ in
                self?.onDeleteRow?()
            }
            let deleteColumn = UIAction(title: "Delete column", attributes: .destructive) { [weak self] _ in
                self?.handleDeleteColumn()
            }
            let copyTable = UIAction(title: "Copy table") { [weak self] _ in
                self?.onCopyTable?()
            }
            let cutTable = UIAction(title: "Cut table") { [weak self] _ in
                self?.onCutTable?()
            }
            let renameTable = UIAction(title: "Rename table", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentRenameTablePrompt()
            }
            let copyTableID = UIAction(title: "Copy table ID", image: UIImage(systemName: "number")) { [weak self] _ in
                UIPasteboard.general.string = self?.tableShortID
            }
            let copyTableReference = UIAction(title: "Copy table reference", image: UIImage(systemName: "text.quote")) { [weak self] _ in
                UIPasteboard.general.string = self?.tableDisplayReference()
            }
            let deleteTable = UIAction(title: "Delete table", attributes: .destructive) { [weak self] _ in
                self?.onDeleteTable?()
            }
            let editFormula = UIAction(title: "Set column formula", image: UIImage(systemName: "text.badge.plus")) { [weak self] _ in
                self?.presentColumnFormulaPrompt()
            }
            let clearFormula = UIAction(title: "Clear column formula", image: UIImage(systemName: "xmark.circle")) { [weak self] _ in
                self?.onClearColumnFormula()
            }
            let columnTypeMenu = UIMenu(title: "Column Type", children: [makeTextColumn, makeCheckboxColumn, makeFormulaColumn])
            let formulaMenu = UIMenu(title: "Formula", children: [editFormula, clearFormula])
            let totalMenu: UIMenu? = {
                guard self.totalsEnabled, isOnTotalRow else { return nil }
                let none = UIAction(title: "None", image: UIImage(systemName: "xmark")) { [weak self] _ in
                    self?.onSetTotalFormula(.none)
                }
                let sum = UIAction(title: "Sum", image: UIImage(systemName: "sum")) { [weak self] _ in
                    self?.onSetTotalFormula(.sum)
                }
                let average = UIAction(title: "Average", image: UIImage(systemName: "function")) { [weak self] _ in
                    self?.onSetTotalFormula(.average)
                }
                return UIMenu(title: "Total", children: [none, sum, average])
            }()
            let sortMenu = UIMenu(title: "Sort", children: [sortAscending, sortDescending, clearSort])
            let filterMenu: UIMenu = {
                if self.isCheckboxColumn(max(0, min(self.activeColumn, max(0, self.columnCount - 1)))) {
                    return UIMenu(title: "Filter", children: [filterAll, filterChecked, filterUnchecked])
                }
                let col = max(0, min(self.activeColumn, max(0, self.columnCount - 1)))
                var children: [UIMenuElement] = [filterAll]
                let distinctValues = self.distinctTextFilterValues(for: col)
                children.append(contentsOf: distinctValues.map { value in
                    UIAction(title: value, state: filterTokens.contains("value:\(value)") ? .on : .off) { [weak self] _ in
                        self?.onSetFilter("value:\(value)")
                    }
                })
                if self.columnHasEmptyValues(col) {
                    children.append(filterEmpty)
                }
                return UIMenu(title: "Filter", children: children)
            }()
            let alignmentMenu = UIMenu(title: "Column Alignment", children: [alignLeft, alignRight, alignDecimal])
            let hiddenColumnItems = self.storedHiddenColumns.sorted().map { column in
                UIAction(title: self.displayNameForColumn(column), image: UIImage(systemName: "eye")) { [weak self] _ in
                    self?.showColumn(column)
                }
            }
            let columnVisibilityMenu = UIMenu(
                title: "Column Visibility",
                children: [
                    UIAction(title: "Hide this column", image: UIImage(systemName: "eye.slash")) { [weak self] _ in
                        self?.hideColumn(self?.activeColumn ?? 0)
                    },
                    UIMenu(title: "Show hidden columns", options: .displayInline, children: hiddenColumnItems.isEmpty ? [
                        UIAction(title: "No hidden columns", attributes: [.disabled]) { _ in }
                    ] : hiddenColumnItems),
                    UIAction(title: "Show all columns", image: UIImage(systemName: "rectangle.grid.1x2")) { [weak self] _ in
                        self?.showAllColumns()
                    }
                ]
            )
            let rearrangeMenu = UIMenu(title: "Rearrange Column", children: [moveColumnLeft, moveColumnRight])
            let rearrangeRowMenu: UIMenu? = {
                guard !isOnTotalRow else { return nil }
                return UIMenu(title: "Rearrange Row", children: [moveRowUp, moveRowDown])
            }()
            let identityMenu = UIMenu(title: "Table Identity", children: [
                UIAction(title: self.tableDisplayReference(), attributes: [.disabled]) { _ in },
                copyTableID,
                copyTableReference,
                renameTable
            ])
            var children: [UIMenuElement] = [resizeColumn, rearrangeMenu, columnVisibilityMenu, columnTypeMenu, formulaMenu, addTotalRow]
            if let rearrangeRowMenu {
                children.append(rearrangeRowMenu)
            }
            if let totalMenu {
                children.append(totalMenu)
            }
            if canToggleRowDone {
                children.append(toggleRowDone)
            }
            children.append(contentsOf: [identityMenu, sortMenu, filterMenu, alignmentMenu, increaseTableFont, decreaseTableFont, toggleHideChecked, addRow, addColumn])
            if !isOnTotalRow {
                children.append(deleteRow)
            }
            children.append(contentsOf: [deleteColumn, copyTable, cutTable, deleteTable])
            return UIMenu(title: "", children: children)
        }
    }

    private func onMoveColumn(_ direction: Int) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        let target = col + direction
        guard target >= 0, target < columnCount else { return }
        swapLocalColumnState(from: col, to: target)
        onTableAction?(.moveColumn(column: col, direction: direction))
    }

    private func onMoveRow(_ direction: Int) {
        let row = actualRow(forVisibleRow: activeRow)
        let target = row + direction
        guard row > 0 else { return }
        guard target > 0, target < rowCount else { return }
        onTableAction?(.moveRow(row: row, direction: direction))
    }

    private func onSetColumnAlignment(_ alignment: NJTableColumnAlignment) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        applyAlignmentStyleToColumn(col, alignment: alignment)
        onResizeTable?()
        onTableAction?(.setColumnAlignment(column: col, alignment: alignment.rawValue))
    }

    private func onSetColumnType(_ type: NJTableColumnType) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        onTableAction?(.setColumnType(column: col, type: type.rawValue))
    }

    private func onSetColumnFormula(_ formula: String?) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        onTableAction?(.setColumnFormula(column: col, formula: formula))
    }

    private func onClearColumnFormula() {
        onSetColumnFormula(nil)
    }

    private func onToggleTotals() {
        onTableAction?(.setTotalsEnabled(!totalsEnabled))
    }

    private func onSetTotalFormula(_ formula: NJTableTotalFormula) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        onTableAction?(.setTotalFormula(column: col, formula: formula == .none ? nil : formula.rawValue))
    }

    private func onToggleHideChecked() {
        forcedVisibleActualRows.removeAll()
        onTableAction?(.setHideChecked(!hideCheckedRows))
    }

    private func onSetFilter(_ filter: String) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        let filters = currentColumnFilters()
        guard col >= 0, col < filters.count else { return }
        forcedVisibleActualRows.removeAll()
        let nextFilter = toggledFilterStorage(current: filters[col], token: filter)
        onTableAction?(.setColumnFilter(column: col, filter: nextFilter))
    }

    private func onClearFilters() {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        guard col >= 0, col < currentColumnFilters().count else { return }
        forcedVisibleActualRows.removeAll()
        onTableAction?(.setColumnFilter(column: col, filter: "all"))
    }

    private func onSetSort(_ direction: NJTableSortDirection) {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        forcedVisibleActualRows.removeAll()
        onTableAction?(.setSort(column: col, direction: direction.rawValue))
    }

    private func onClearSort() {
        forcedVisibleActualRows.removeAll()
        onTableAction?(.setSort(column: nil, direction: nil))
    }

    private func distinctTextFilterValues(for column: Int) -> [String] {
        var values = Set<String>()
        for row in 1..<max(1, rowCount) {
            let text = storedCellText(atActualRow: row, column: column).string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            values.insert(text)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func columnHasEmptyValues(_ column: Int) -> Bool {
        for row in 1..<max(1, rowCount) {
            let text = storedCellText(atActualRow: row, column: column).string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return true
            }
        }
        return false
    }

    private func applyAlignmentStyleToColumn(_ column: Int, alignment: NJTableColumnAlignment) {
        var alignments = currentColumnAlignments()
        guard column >= 0, column < alignments.count else { return }
        alignments[column] = alignment
        storedColumnAlignments = alignments
        applyAlignmentStylesToAllCells()
    }

    private func handleAddColumn() {
        insertLocalColumnState(at: columnCount)
        onAddColumn?()
    }

    private func handleDeleteColumn() {
        let column = max(0, min(activeColumn, max(0, columnCount - 1)))
        removeLocalColumnState(at: column)
        activeColumn = nextVisibleColumn(startingAt: min(column, max(0, columnCount - 2)), fallbackDirection: -1) ?? 0
        onDeleteColumn?()
    }

    private func tableDisplayReference() -> String {
        if let tableName, !tableName.isEmpty {
            return "Table \"\(tableName)\" [\(tableShortID)]"
        }
        return "Table [\(tableShortID)]"
    }

    private func presentRenameTablePrompt() {
        guard let presenter = topViewController() else { return }
        let alert = UIAlertController(
            title: "Rename Table",
            message: "Table ID: \(tableShortID)",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Unique table name"
            textField.text = self.tableName
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let proposedName = alert?.textFields?.first?.text
            switch NJTableStore.shared.renameTable(
                tableID: self.attachmentID,
                proposedName: proposedName
            ) {
            case .success(let appliedName):
                self.tableName = appliedName
                self.onResizeTable?()
            case .failure(let error):
                self.presentIdentityError(error.localizedDescription)
            }
        })
        presenter.present(alert, animated: true)
    }

    private func presentColumnFormulaPrompt() {
        let col = max(0, min(activeColumn, max(0, columnCount - 1)))
        guard let presenter = topViewController() else { return }
        let header = displayNameForColumn(col)
        let alert = UIAlertController(
            title: "Column Formula",
            message: "Formula for \(header)\nUse header names, for example: [Qty] * [Price]",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "=[Qty] * [Price]"
            textField.text = self.displayFormulaDefinition(for: col)
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.onClearColumnFormula()
        })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            let formula = alert?.textFields?.first?.text
            self?.onSetColumnFormula(formula)
        })
        presenter.present(alert, animated: true)
    }

    private func presentIdentityError(_ message: String) {
        guard let presenter = topViewController() else { return }
        let alert = UIAlertController(
            title: "Table Name Unavailable",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func moveStoredRow(from source: Int, to destination: Int) {
        guard source >= 0, source < rowCount, destination >= 0, destination < rowCount else { return }
        guard source != destination else { return }
        captureCurrentGridState()
        for col in 0..<columnCount {
            let sourceText = storedCellText(atActualRow: source, column: col)
            let destinationText = storedCellText(atActualRow: destination, column: col)
            setStoredCellText(destinationText, atActualRow: source, column: col)
            setStoredCellText(sourceText, atActualRow: destination, column: col)
        }
        rebuildGrid(columnWidths: currentColumnWidths(), captureState: false)
        if let visibleRow = visibleRow(forActualRow: destination) {
            activeRow = visibleRow
        }
    }
}

enum NJTableAttachmentFactory {
    static func make(
        attachmentID: String,
        config: GridConfiguration,
        cells: [GridCell]? = nil,
        columnWidths: [CGFloat]? = nil,
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
        tableName: String? = nil,
        onTableAction: ((String, NJTableAction) -> Void)? = nil,
        onResizeTable: ((String) -> Void)? = nil,
        onLocalLayoutChange: ((String) -> Void)? = nil
    ) -> Attachment {
        let view = NJTableAttachmentView(
            attachmentID: attachmentID,
            config: config,
            cells: cells,
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
        if let onTableAction {
            view.onAddRow = { onTableAction(attachmentID, .addRow) }
            view.onAddColumn = { onTableAction(attachmentID, .addColumn) }
            view.onDeleteRow = { onTableAction(attachmentID, .deleteRow) }
            view.onDeleteColumn = { onTableAction(attachmentID, .deleteColumn) }
            view.onDeleteTable = { onTableAction(attachmentID, .deleteTable) }
            view.onCopyTable = { onTableAction(attachmentID, .copyTable) }
            view.onCutTable = { onTableAction(attachmentID, .cutTable) }
            view.onTableAction = { action in onTableAction(attachmentID, action) }
        }
        if let onResizeTable {
            view.onResizeTable = { onResizeTable(attachmentID) }
        }
        if let onLocalLayoutChange {
            view.onLocalLayoutChange = { onLocalLayoutChange(attachmentID) }
        }
        let attachment = Attachment(view, size: .fullWidth)
        view.boundsObserver = attachment
        view.gridView.boundsObserver = view
        view.flushPendingIdentitySnapshotIfNeeded()
        return attachment
    }
}
