import SwiftUI
import PDFKit

struct NJClipPDFWindowPage: View {
    let url: URL?

    var body: some View {
        Group {
            if let u = url {
                NJPDFKitViewer(url: u)
            } else {
                Text("PDF not found")
                    .padding()
            }
        }
        .navigationTitle("Clip PDF")
    }
}

struct NJPDFKitViewer: UIViewRepresentable {
    let url: URL

    final class FitWidthPDFView: PDFView {
        var fitWidthEnabled = true
        var lastFittedWidth: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            guard fitWidthEnabled else { return }
            let w = bounds.width
            if abs(w - lastFittedWidth) < 1 { return }
            lastFittedWidth = w
            fitToWidth()
        }

        func fitToWidth() {
            guard let page = document?.page(at: 0) else { return }
            let pageRect = page.bounds(for: .cropBox)
            let w = max(bounds.width, 1)
            let pw = max(pageRect.width, 1)
            let s = w / pw
            minScaleFactor = s
            scaleFactor = s
        }
    }

    func makeUIView(context: Context) -> FitWidthPDFView {
        let v = FitWidthPDFView()
        v.displayDirection = .vertical
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.autoScales = false
        v.usePageViewController(false, withViewOptions: nil)
        v.backgroundColor = .systemBackground
        return v
    }

    func updateUIView(_ v: FitWidthPDFView, context: Context) {
        if v.document == nil || v.document?.documentURL != url {
            v.document = PDFDocument(url: url)
            DispatchQueue.main.async {
                v.fitToWidth()
            }
        }
    }
}
