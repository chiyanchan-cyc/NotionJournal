import UIKit
import Photos

final class NJPhotoLibraryPresenter {
    private static let icloudPrefix = "icloud:"
    private static let iCloudContainerID = "iCloud.com.CYC.NotionJournal"
    private static let fullPhotoDir = "Documents/NJFullPhotos"

    static func saveFullPhotoToICloud(image: UIImage) -> String? {
        let fm = FileManager.default
        guard let base = fm.url(forUbiquityContainerIdentifier: iCloudContainerID) else { return nil }
        let dir = base.appendingPathComponent(fullPhotoDir, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let filename = UUID().uuidString.lowercased() + ".png"
        let dst = dir.appendingPathComponent(filename, isDirectory: false)
        guard let data = image.pngData() else { return nil }
        do {
            try data.write(to: dst, options: [.atomic])
            return icloudPrefix + "\(fullPhotoDir)/\(filename)"
        } catch {
            return nil
        }
    }

    static func presentFullPhoto(reference: String) {
        let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return }
        if ref.hasPrefix(icloudPrefix) {
            presentICloudPhoto(reference: ref)
            return
        }
        presentPhotoLibrary(localIdentifier: ref)
    }

    static func presentFullPhoto(localIdentifier: String) {
        presentFullPhoto(reference: localIdentifier)
    }

    private static func presentPhotoLibrary(localIdentifier: String) {
        let id = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async {
                    self.presentPhotoLibrary(localIdentifier: id)
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

    private static func presentICloudPhoto(reference: String) {
        guard let url = iCloudURL(fromReference: reference) else { return }
        Task {
            guard let localURL = await materializeICloudFile(url: url) else { return }
            guard let data = try? Data(contentsOf: localURL),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                presentFullPhoto(image: image)
            }
        }
    }

    private static func iCloudURL(fromReference ref: String) -> URL? {
        let raw = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix(icloudPrefix) else { return nil }
        let rel = String(raw.dropFirst(icloudPrefix.count))
        guard !rel.isEmpty else { return nil }
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID) else { return nil }
        return base.appendingPathComponent(rel, isDirectory: false)
    }

    private static func materializeICloudFile(url: URL) async -> URL? {
        let fm = FileManager.default
        let path = url.path
        if !fm.fileExists(atPath: path) {
            return nil
        }

        var isUbiq = false
        if let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           v.isUbiquitousItem == true {
            isUbiq = true
        }
        if isUbiq {
            try? fm.startDownloadingUbiquitousItem(at: url)
            for _ in 0..<60 {
                if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
                   status == .current {
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        return url
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
