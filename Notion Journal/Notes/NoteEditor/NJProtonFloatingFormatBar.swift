import SwiftUI
import PhotosUI

struct NJProtonFloatingFormatBar: View {
    let handle: NJProtonEditorHandle
    let currentHandle: (() -> NJProtonEditorHandle?)?
    @Binding var pickedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented: Bool = false
    @State private var photoTargetHandle: NJProtonEditorHandle? = nil

    init(
        handle: NJProtonEditorHandle,
        pickedPhotoItem: Binding<PhotosPickerItem?>,
        currentHandle: (() -> NJProtonEditorHandle?)? = nil
    ) {
        self.handle = handle
        self._pickedPhotoItem = pickedPhotoItem
        self.currentHandle = currentHandle
    }

    private func resolvedHandle() -> NJProtonEditorHandle? {
        NJProtonEditorHandle.firstResponderHandle() ?? currentHandle?() ?? NJProtonEditorHandle.activeHandle() ?? handle
    }

    private func withHandle(_ action: (NJProtonEditorHandle) -> Void) {
        guard let h = resolvedHandle() else { return }
        print("NJ_PHOTO_BAR_HANDLE owner=\(String(describing: h.ownerBlockUUID))")
        action(h)
    }

    private func withFormattingAction(
        sectionAction: NJCollapsibleAttachmentView.BodyFormatAction,
        handleAction: @escaping (NJProtonEditorHandle) -> Void
    ) {
        if NJCollapsibleAttachmentView.performActionOnActiveBody(sectionAction) {
            return
        }
        withHandle {
            handleAction($0)
            $0.snapshot()
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { withFormattingAction(sectionAction: .decreaseFont) { $0.decreaseFont() } } label: { Image(systemName: "textformat.size.smaller") }
                Button { withFormattingAction(sectionAction: .increaseFont) { $0.increaseFont() } } label: { Image(systemName: "textformat.size.larger") }

                Divider().frame(height: 18)

                Button { withFormattingAction(sectionAction: .toggleBold) { $0.toggleBold() } } label: { Image(systemName: "bold") }
                Button { withFormattingAction(sectionAction: .toggleItalic) { $0.toggleItalic() } } label: { Image(systemName: "italic") }
                Button { withFormattingAction(sectionAction: .toggleUnderline) { $0.toggleUnderline() } } label: { Image(systemName: "underline") }
                Button { withFormattingAction(sectionAction: .toggleStrike) { $0.toggleStrike() } } label: { Image(systemName: "strikethrough") }

                Divider().frame(height: 18)

                Button { withHandle { $0.toggleNumber(); $0.snapshot() } } label: { Image(systemName: "list.number") }
                Button { withHandle { $0.toggleBullet(); $0.snapshot() } } label: { Image(systemName: "list.bullet") }

                Divider().frame(height: 18)
                
                Button {
                    withHandle {
                        $0.insertTagLine()
                        $0.snapshot()
                    }
                } label: {
                    Image(systemName: "tag")
                }

                Button {
                    photoTargetHandle = resolvedHandle()
                    print("NJ_PHOTO_TARGET_CAPTURED owner=\(String(describing: photoTargetHandle?.ownerBlockUUID))")
                    isPhotoPickerPresented = true
                } label: {
                    Image(systemName: "photo")
                }
                .photosPicker(
                    isPresented: $isPhotoPickerPresented,
                    selection: $pickedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                )

                Button {
                    withHandle {
                        $0.insertTableAttachment()
                        $0.snapshot()
                    }
                } label: {
                    Image(systemName: "tablecells")
                }

                Button {
                    withHandle {
                        $0.convertSelectionToCollapsibleSection()
                    }
                } label: {
                    Image(systemName: "chevron.down.square")
                }

                Button {
                    withHandle {
                        $0.removeNearestCollapsibleSection()
                    }
                } label: {
                    Image(systemName: "minus.square")
                }

                Button { withHandle { $0.outdent(); $0.snapshot() } } label: { Image(systemName: "decrease.indent") }
                Button { withHandle { $0.indent(); $0.snapshot() } } label: { Image(systemName: "increase.indent") }
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.system(size: 16, weight: .semibold))
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let fullRef = newItem.itemIdentifier ?? ""
                if let img = await NJPhotoPickerHelper.loadImage(
                    itemIdentifier: newItem.itemIdentifier,
                    loadData: { try? await newItem.loadTransferable(type: Data.self) }
                ) {
                    await MainActor.run {
                        if NJCollapsibleAttachmentView.insertImageIntoActiveBody(img) {
                            pickedPhotoItem = nil
                            photoTargetHandle = nil
                            isPhotoPickerPresented = false
                            return
                        }
                        let h = photoTargetHandle ?? resolvedHandle()
                        guard let h else { return }
                        print("NJ_PHOTO_PICKER_HANDLE owner=\(String(describing: h.ownerBlockUUID))")
                        h.insertPhotoAttachment(img, fullPhotoRef: fullRef)
                        h.snapshot()
                    }
                }
                await MainActor.run {
                    pickedPhotoItem = nil
                    photoTargetHandle = nil
                    isPhotoPickerPresented = false
                }
            }
        }
    }
}
