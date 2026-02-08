import UIKit
import Photos

final class NJPhotoLibraryPresenter {
    static func presentFullPhoto(localIdentifier: String) {
        let id = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async {
                    self.presentFullPhoto(localIdentifier: id)
                }
            }
            return
        }

        guard status == .authorized || status == .limited else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                guard let vc = topViewController() else { return }
                let viewer = NJPhotoFullScreenViewController(image: image)
                viewer.modalPresentationStyle = .fullScreen
                vc.present(viewer, animated: true)
            }
        }
    }

    static func presentFullPhoto(image: UIImage) {
        guard let vc = topViewController() else { return }
        let viewer = NJPhotoFullScreenViewController(image: image)
        viewer.modalPresentationStyle = .fullScreen
        vc.present(viewer, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }),
               let root = window.rootViewController {
                var top = root
                while let presented = top.presentedViewController {
                    top = presented
                }
                return top
            }
        }
        return nil
    }
}

private final class NJPhotoFullScreenViewController: UIViewController {
    private let image: UIImage
    private let imageView = UIImageView()

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
