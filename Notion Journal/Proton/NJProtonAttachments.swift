import Foundation
import UIKit
import Proton

extension EditorContent.Name {
    static let njPhoto = EditorContent.Name("nj_photo")
    static let njTable = EditorContent.Name("nj_table")
}

enum NJTableAction {
    case addRow
    case addColumn
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
