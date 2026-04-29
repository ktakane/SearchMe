import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = MapViewModel()

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.members.filter { $0.hasLocation }) { member in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(
                        latitude: member.latitude!,
                        longitude: member.longitude!
                    )) {
                        MemberPin(member: member, isMe: member.id == appState.myMemberId)
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                Button {
                    Task { await viewModel.fetch(groupId: appState.groupId) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                        .background(.white, in: Circle())
                }
                .padding(24)
            }
            .navigationTitle("家族マップ")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading { ProgressView() }
                }
            }
            .onAppear {
                Task { await viewModel.fetch(groupId: appState.groupId) }
            }
        }
    }
}

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
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.9))
                .cornerRadius(4)
            Text(member.updatedAtDisplay)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

@MainActor
final class MapViewModel: ObservableObject {
    @Published var members: [FamilyMember] = []
    @Published var isLoading = false
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    func fetch(groupId: String) async {
        guard !groupId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if let fetched = try? await APIService.shared.fetchMembers(groupId: groupId) {
            members = fetched
            if let first = fetched.first(where: { $0.hasLocation }) {
                region.center = CLLocationCoordinate2D(latitude: first.latitude!, longitude: first.longitude!)
            }
        }
    }
}
