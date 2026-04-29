import SwiftUI

struct FamilyListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subManager: SubscriptionManager
    @State private var members: [FamilyMember] = []
    @State private var isLoading = false
    @State private var showPaywall = false

    var body: some View {
        NavigationView {
            Group {
                if members.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("家族の情報を読み込んでいます")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        upgradeBanner
                        ForEach(members) { member in
                            MemberRow(member: member, isMe: member.id == appState.myMemberId)
                        }
                    }
                }
            }
            .navigationTitle("\(subManager.planType.groupLabel)一覧")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await fetch() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear { Task { await fetch() } }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(subManager)
            }
        }
    }

    private var upgradeBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(subManager.planType.groupLabel)ダッシュボード")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("安否状況・バッテリーを一覧で確認")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func fetch() async {
        isLoading = true
        members = (try? await APIService.shared.fetchMembers(groupId: appState.groupId)) ?? []
        isLoading = false
    }
}

struct MemberRow: View {
    let member: FamilyMember
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isMe ? .blue : .orange)
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.body.bold())
                    if isMe {
                        Text("（自分）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text(member.hasLocation ? "位置情報あり · \(member.updatedAtDisplay)" : "位置情報なし")
                    .font(.caption)
                    .foregroundColor(member.hasLocation ? .secondary : .red)
            }
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: member.safetyIcon)
                    .foregroundColor(member.safetyColor)
                    .font(.system(size: 20))
                Text(member.safetyLabel)
                    .font(.caption2)
                    .foregroundColor(member.safetyColor)
            }

            if let battery = member.batteryLevel {
                VStack(spacing: 2) {
                    Image(systemName: batteryIcon(battery))
                        .foregroundColor(battery < 0.2 ? .red : .secondary)
                    Text("\(Int(battery * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func batteryIcon(_ level: Float) -> String {
        if level > 0.75 { return "battery.100" }
        if level > 0.5  { return "battery.75" }
        if level > 0.25 { return "battery.25" }
        return "battery.0"
    }
}
