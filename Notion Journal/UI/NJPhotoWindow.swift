import SwiftUI
import Photos

struct NJPhotoWindow: View {
    let localIdentifier: String?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var status: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(12)

            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else if isLoading {
                    ProgressView("Loading photo…")
                        .padding()
                } else if status == .denied || status == .restricted {
                    Text("Photos access is required to view this photo.")
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    Text("Photo not available.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .task { await loadPhoto() }
    }

    private func loadPhoto() async {
        isLoading = true
        let nextStatus = await requestAuthorization()
        status = nextStatus
        guard nextStatus == .authorized || nextStatus == .limited else {
            isLoading = false
            return
        }

        let id = (localIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            isLoading = false
            return
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else {
            isLoading = false
            return
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            if let data, let img = UIImage(data: data) {
                image = img
            }
            isLoading = false
        }
    }

    private func requestAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != .notDetermined { return current }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                cont.resume(returning: status)
            }
        }
    }
}
