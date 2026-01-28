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
        .onChange(of: selectedDate) { _ in loadSelectedDay() }
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

        guard let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8) else {
            status = "No file: \(rel)"
            points = []
            return
        }

        var out: [CLLocationCoordinate2D] = []
        for line in s.split(separator: "\n") {
            if let p = parseLine(String(line)) {
                out.append(p)
            }
        }

        points = dedup(out)
        status = "Loaded \(points.count) points"
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

        guard points.count >= 2 else {
            if let p = points.first {
                uiView.setRegion(
                    MKCoordinateRegion(center: p, latitudinalMeters: 1500, longitudinalMeters: 1500),
                    animated: true
                )
            }
            return
        }

        let poly = MKPolyline(coordinates: points, count: points.count)
        uiView.addOverlay(poly)

        let rect = poly.boundingMapRect
        uiView.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20),
            animated: true
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.lineWidth = 4
            return r
        }
    }
}
