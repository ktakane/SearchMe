import SwiftUI
import MapKit

struct HistoryView: View {
    let member: FamilyMember
    @State private var history: [HistoryPoint] = []
    @State private var isLoading = false
    @State private var selectedHours = 24

    private let hourOptions = [6, 24, 72, 168]

    var body: some View {
        VStack(spacing: 0) {
            Picker("期間", selection: $selectedHours) {
                Text("6時間").tag(6)
                Text("24時間").tag(24)
                Text("3日").tag(72)
                Text("7日").tag(168)
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading {
                Spacer()
                ProgressView("読み込み中...")
                Spacer()
            } else if history.isEmpty {
                emptyState
            } else {
                HistoryMapView(points: history)
                    .frame(height: 280)
                Divider()
                List {
                    ForEach(history.reversed()) { point in
                        HistoryRowView(point: point)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("\(member.name)の移動履歴")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedHours) { _ in Task { await fetch() } }
        .onAppear { Task { await fetch() } }
    }

    private var emptyState: some View {
        Spacer()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("移動履歴がありません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("災害モード中に位置情報が記録されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            )
    }

    private func fetch() async {
        isLoading = true
        history = (try? await APIService.shared.fetchHistory(memberId: member.id, hours: selectedHours)) ?? []
        isLoading = false
    }
}

// MARK: - マップ（ポリライン）

struct HistoryMapView: UIViewRepresentable {
    let points: [HistoryPoint]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        guard !points.isEmpty else { return }

        let coords = points.map { $0.coordinate }

        // ポリライン
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(polyline)

        // 開始ピン
        let start = MKPointAnnotation()
        start.coordinate = coords.first!
        start.title = "開始"
        map.addAnnotation(start)

        // 終端ピン
        let end = MKPointAnnotation()
        end.coordinate = coords.last!
        end.title = "現在地"
        map.addAnnotation(end)

        // 全体が見えるよう調整
        let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        if coords.count == 1 {
            let region = MKCoordinateRegion(center: coords[0],
                                            latitudinalMeters: 1000,
                                            longitudinalMeters: 1000)
            map.setRegion(region, animated: false)
        } else {
            map.setVisibleMapRect(polyline.boundingMapRect,
                                  edgePadding: padding,
                                  animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemOrange
            renderer.lineWidth = 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? MKPointAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.markerTintColor = ann.title == "現在地" ? .systemOrange : .systemGreen
            view.glyphImage = UIImage(systemName: ann.title == "現在地" ? "person.fill" : "flag.fill")
            return view
        }
    }
}

// MARK: - タイムライン行

struct HistoryRowView: View {
    let point: HistoryPoint

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.timeDisplay)
                    .font(.subheadline.bold())
                Text(String(format: "%.4f, %.4f", point.latitude, point.longitude))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let battery = point.battery {
                Text("\(Int(battery * 100))%")
                    .font(.caption2)
                    .foregroundColor(battery < 0.2 ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
