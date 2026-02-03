import UIKit
import Photos

enum NJPhotoPickerHelper {
    static func loadImage(itemIdentifier: String?, loadData: () async -> Data?) async -> UIImage? {
        if let id = itemIdentifier, let img = await imageFromAsset(localIdentifier: id) {
            return img
        }

        if let data = await loadData(),
           let img = UIImage(data: data) {
            return img
        }

        return nil
    }

    private static func imageFromAsset(localIdentifier: String) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }
}
