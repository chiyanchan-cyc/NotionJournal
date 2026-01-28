import SwiftUI
import MapKit

struct NJGPSLogViewerPage: View {
    @State private var selectedDate = Date()
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var status: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Date") {
                    DatePicker("Track day", selection: $selectedDate, displayedComponents: [.date])
                    Button("Load Track") { loadSelectedDay() }
                }
                Section("Status") {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Divider()

            NJMapPolylineView(points: points)
        }
        .navigationTitle("GPS Tracks")
        .onAppear { loadSelectedDay() }
        .onChange(of: selectedDate) { _, _ in loadSelectedDay() }
    }

    private func loadSelectedDay() {
        let tz = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy/MM/yyyy-MM-dd"
        let rel = "GPS/\(f.string(from: selectedDate)).ndjson"

        guard let root = NJGPSLogger.shared.docsRootForViewer() else {
            status = "No documents root"
            points = []
            return
        }

        let url = root.appendingPathComponent(rel)
        let fm = FileManager.default

        var tried: [String] = []
        tried.append("rel=\(rel)")
        tried.append("url=\(url.path)")

        if fm.fileExists(atPath: url.path) == false {
            let isUbiq = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
            if isUbiq {
                _ = try? fm.startDownloadingUbiquitousItem(at: url)
                status = "Downloading iCloud file…\n" + tried.joined(separator: "\n")
                points = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    loadSelectedDay()
                }
                return
            } else {
                status = "No file\n" + tried.joined(separator: "\n")
                points = []
                return
            }
        }

        guard let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8) else {
            status = "Failed to read file\n" + tried.joined(separator: "\n")
            points = []
            return
        }

        var out: [CLLocationCoordinate2D] = []
        for line in s.split(separator: "\n") {
            if let p = parseLine(String(line)) {
                out.append(p)
            }
        }

        let dd = dedup(out)
        points = dd

        if dd.count >= 2 {
            status = "Loaded \(dd.count) points (polyline)\n" + tried.joined(separator: "\n")
        } else if dd.count == 1 {
            status = "Loaded 1 point (pin only)\n" + tried.joined(separator: "\n")
        } else {
            status = "Loaded 0 points\n" + tried.joined(separator: "\n")
        }
    }

    private func parseLine(_ line: String) -> CLLocationCoordinate2D? {
        guard let d = line.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        guard let lat = obj["lat"] as? Double, let lon = obj["lon"] as? Double else { return nil }
        if abs(lat) < 0.000001 && abs(lon) < 0.000001 { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func dedup(_ pts: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !pts.isEmpty else { return [] }
        var out: [CLLocationCoordinate2D] = [pts[0]]
        for p in pts.dropFirst() {
            let last = out[out.count - 1]
            if abs(p.latitude - last.latitude) > 0.000001 || abs(p.longitude - last.longitude) > 0.000001 {
                out.append(p)
            }
        }
        return out
    }
}

struct NJMapPolylineView: UIViewRepresentable {
    let points: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView(frame: .zero)
        v.delegate = context.coordinator
        v.showsUserLocation = false
        return v
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations)

        if points.isEmpty { return }

        if points.count == 1 {
            let p = points[0]
            let ann = MKPointAnnotation()
            ann.coordinate = p
            uiView.addAnnotation(ann)
            uiView.setRegion(
                MKCoordinateRegion(center: p, latitudinalMeters: 1500, longitudinalMeters: 1500),
                animated: true
            )
            return
        }

        let start = MKPointAnnotation()
        start.coordinate = points.first!
        uiView.addAnnotation(start)

        let end = MKPointAnnotation()
        end.coordinate = points.last!
        uiView.addAnnotation(end)

        let poly = MKPolyline(coordinates: points, count: points.count)
        uiView.addOverlay(poly)

        uiView.setVisibleMapRect(
            poly.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20),
            animated: true
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor.systemBlue
                r.lineWidth = 5
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
