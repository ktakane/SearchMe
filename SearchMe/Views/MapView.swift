import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subManager: SubscriptionManager
    @StateObject private var viewModel = MapViewModel()
    @State private var showShelters = false
    @State private var selectedShelter: Shelter?
    @State private var showPaywall = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.allAnnotations(showShelters: showShelters)) { item in
                    MapAnnotation(coordinate: item.coordinate) {
                        switch item {
                        case .member(let m):
                            MemberPin(member: m, isMe: m.id == appState.myMemberId)
                        case .shelter(let s):
                            ShelterPin(shelter: s)
                                .onTapGesture { selectedShelter = s }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 12) {
                    Button {
                        if subManager.isSubscribed {
                            showShelters.toggle()
                            if showShelters { viewModel.loadShelters() }
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Image(systemName: showShelters ? "building.2.fill" : "building.2")
                            .font(.system(size: 24))
                            .foregroundColor(showShelters ? .green : .gray)
                            .frame(width: 44, height: 44)
                            .background(.white, in: Circle())
                            .shadow(radius: 2)
                    }

                    Button {
                        Task { await viewModel.fetch(groupId: appState.groupId) }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                            .background(.white, in: Circle())
                    }
                }
                .padding(24)
            }
            .navigationTitle("\(subManager.planType.groupLabel)マップ")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading { ProgressView() }
                }
            }
            .onAppear {
                Task { await viewModel.fetch(groupId: appState.groupId) }
            }
            .sheet(item: $selectedShelter) { shelter in
                ShelterDetailSheet(shelter: shelter)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(subManager)
            }
        }
    }
}

// MARK: - MapAnnotation ユニオン型

enum MapAnnotationItem: Identifiable {
    case member(FamilyMember)
    case shelter(Shelter)

    var id: String {
        switch self {
        case .member(let m):  return "m_\(m.id)"
        case .shelter(let s): return "s_\(s.id)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .member(let m):  return CLLocationCoordinate2D(latitude: m.latitude!, longitude: m.longitude!)
        case .shelter(let s): return s.coordinate
        }
    }
}

// MARK: - Pins

struct MemberPin: View {
    let member: FamilyMember
    let isMe: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isMe ? .blue : .orange)
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
            }
            Text(member.name)
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
            Text(member.updatedAtDisplay)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ShelterPin: View {
    let shelter: Shelter

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: 30, height: 30)
                Image(systemName: "house.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 14))
            }
            Text(shelter.name)
                .font(.caption2)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - 避難所詳細シート

struct ShelterDetailSheet: View {
    let shelter: Shelter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("施設情報") {
                    LabeledContent("施設名", value: shelter.name)
                    if let addr = shelter.address, !addr.isEmpty {
                        LabeledContent("住所", value: addr)
                    }
                }
                Section("対応災害") {
                    Text(shelter.disasterTypes)
                        .foregroundColor(.secondary)
                }
                Section {
                    Button {
                        let url = URL(string: "maps://?daddr=\(shelter.lat),\(shelter.lng)")!
                        UIApplication.shared.open(url)
                    } label: {
                        Label("マップで経路を見る", systemImage: "map.fill")
                    }
                }
            }
            .navigationTitle("避難所")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MapViewModel: ObservableObject {
    @Published var members: [FamilyMember] = []
    @Published var shelters: [Shelter] = []
    @Published var isLoading = false
    @Published var region: MKCoordinateRegion

    init() {
        let ls = LocationService.shared
        let center = (ls.lastLocation ?? ls.cachedLocation)?.coordinate
            ?? CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    func allAnnotations(showShelters: Bool) -> [MapAnnotationItem] {
        let memberItems = members.filter { $0.hasLocation }.map { MapAnnotationItem.member($0) }
        let shelterItems = showShelters ? shelters.map { MapAnnotationItem.shelter($0) } : []
        return memberItems + shelterItems
    }

    func fetch(groupId: String) async {
        guard !groupId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if let fetched = try? await APIService.shared.fetchMembers(groupId: groupId) {
            members = fetched
            if let first = fetched.first(where: { $0.hasLocation }) {
                region.center = CLLocationCoordinate2D(latitude: first.latitude!, longitude: first.longitude!)
            } else if let gps = LocationService.shared.lastLocation {
                region.center = gps.coordinate
            }
        }
    }

    func loadShelters() {
        let center: CLLocationCoordinate2D
        if let gps = LocationService.shared.lastLocation {
            center = gps.coordinate
        } else {
            center = region.center
        }
        region.center = center
        shelters = ShelterService.shared.nearbyShelters(lat: center.latitude, lng: center.longitude, radiusKm: 3.0)
    }
}
