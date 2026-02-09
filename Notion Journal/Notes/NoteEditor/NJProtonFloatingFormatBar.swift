import SwiftUI
import PhotosUI

struct NJProtonFloatingFormatBar: View {
    let handle: NJProtonEditorHandle
    @Binding var pickedPhotoItem: PhotosPickerItem?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { handle.decreaseFont(); handle.snapshot() } label: { Image(systemName: "textformat.size.smaller") }
                Button { handle.increaseFont(); handle.snapshot() } label: { Image(systemName: "textformat.size.larger") }

                Divider().frame(height: 18)

                Button { handle.toggleBold(); handle.snapshot() } label: { Image(systemName: "bold") }
                Button { handle.toggleItalic(); handle.snapshot() } label: { Image(systemName: "italic") }
                Button { handle.toggleUnderline(); handle.snapshot() } label: { Image(systemName: "underline") }
                Button { handle.toggleStrike(); handle.snapshot() } label: { Image(systemName: "strikethrough") }

                Divider().frame(height: 18)

                Button { handle.toggleNumber(); handle.snapshot() } label: { Image(systemName: "list.number") }
                Button { handle.toggleBullet(); handle.snapshot() } label: { Image(systemName: "list.bullet") }

                Divider().frame(height: 18)
                
                Button {
                    handle.insertTagLine()
                    handle.snapshot()
                } label: {
                    Image(systemName: "tag")
                }

                PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo")
                }

                Button {
                    handle.insertTableAttachment()
                    handle.snapshot()
                } label: {
                    Image(systemName: "tablecells")
                }


                Button { handle.outdent(); handle.snapshot() } label: { Image(systemName: "decrease.indent") }
                Button { handle.indent(); handle.snapshot() } label: { Image(systemName: "increase.indent") }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 8)
        }
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let fullRef = newItem.itemIdentifier ?? ""
                if let img = await NJPhotoPickerHelper.loadImage(
                    itemIdentifier: newItem.itemIdentifier,
                    loadData: { try? await newItem.loadTransferable(type: Data.self) }
                ) {
                    handle.insertPhotoAttachment(img, fullPhotoRef: fullRef)
                    handle.snapshot()
                }
                await MainActor.run { pickedPhotoItem = nil }
            }
        }
    }
}
