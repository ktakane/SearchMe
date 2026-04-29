import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subManager: SubscriptionManager
    @State private var members: [FamilyMember] = []
    @State private var isLoading = false

    private var safeCount:    Int { members.filter { $0.safetyStatus == "safe" }.count }
    private var helpCount:    Int { members.filter { $0.safetyStatus == "need_help" }.count }
    private var unknownCount: Int { members.count - safeCount - helpCount }
    private var respondedCount: Int { safeCount + helpCount }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if appState.isDisasterMode {
                        safetyProgressCard
                    }
                    summaryRow
                    memberGrid
                }
                .padding()
            }
            .navigationTitle("\(subManager.planType.groupLabel)ダッシュボード")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button { Task { await fetch() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear { Task { await fetch() } }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    await fetch()
                }
            }
        }
    }

    // MARK: - 安否進捗

    private var safetyProgressCard: some View {
        let total = members.count
        let ratio = total > 0 ? Double(respondedCount) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.fill.checkmark")
                    .foregroundColor(.orange)
                Text("安否確認状況")
                    .font(.headline)
                Spacer()
                Text("\(respondedCount)/\(total) 名回答")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
            }
            ProgressView(value: ratio)
                .tint(.orange)
            HStack(spacing: 16) {
                Label("\(safeCount) 無事", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Label("\(helpCount) 要救助", systemImage: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Label("\(unknownCount) 未回答", systemImage: "questionmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .font(.caption.bold())
        }
        .padding()
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: - サマリータイル

    private var summaryRow: some View {
        let activeCount = members.filter { $0.hasLocation }.count
        let lowBatCount = members.filter { ($0.batteryLevel ?? 1) < 0.2 }.count
        return HStack(spacing: 12) {
            summaryTile(value: "\(members.count)", label: "メンバー",
                        icon: "person.3.fill", color: .blue)
            summaryTile(value: "\(activeCount)", label: "位置確認中",
                        icon: "location.fill", color: .green)
            summaryTile(value: "\(lowBatCount)", label: "低バッテリー",
                        icon: "battery.25", color: lowBatCount > 0 ? .red : .secondary)
        }
    }

    private func summaryTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.title3)
            Text(value).font(.title2.bold())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - メンバーグリッド

    private var memberGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(members) { member in
                NavigationLink(destination: HistoryView(member: member)) {
                    MemberDashboardCard(member: member, isMe: member.id == appState.myMemberId)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fetch() async {
        isLoading = true
        members = (try? await APIService.shared.fetchMembers(groupId: appState.groupId)) ?? []
        isLoading = false
    }
}

// MARK: - メンバーカード

struct MemberDashboardCard: View {
    let member: FamilyMember
    let isMe: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isMe ? Color.blue : Color.orange)
                    .frame(width: 52, height: 52)
                Text(String(member.name.prefix(1)))
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }

            Text(member.name)
                .font(.subheadline.bold())
                .lineLimit(1)

            if isMe {
                Text("（自分）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Label(member.safetyLabel, systemImage: member.safetyIcon)
                .font(.caption.bold())
                .foregroundColor(member.safetyColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(member.safetyColor.opacity(0.1), in: Capsule())

            if let battery = member.batteryLevel {
                HStack(spacing: 3) {
                    Image(systemName: batteryIcon(battery))
                    Text("\(Int(battery * 100))%")
                }
                .font(.caption2)
                .foregroundColor(battery < 0.2 ? .red : .secondary)
            }

            Text(member.hasLocation ? member.updatedAtDisplay : "位置情報なし")
                .font(.caption2)
                .foregroundColor(member.hasLocation ? .secondary : .red)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(member.safetyColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func batteryIcon(_ level: Float) -> String {
        if level > 0.75 { return "battery.100" }
        if level > 0.5  { return "battery.75" }
        if level > 0.25 { return "battery.25" }
        return "battery.0"
    }
}
