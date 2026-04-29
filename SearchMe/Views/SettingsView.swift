import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLeaveConfirm = false
    @State private var showDisbandSheet = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("あなたの情報") {
                    LabeledContent("名前", value: appState.myName)
                    LabeledContent("グループ", value: appState.groupName)
                    LabeledContent("招待コード", value: appState.inviteCode)
                    if appState.isOwner {
                        Label("オーナー", systemImage: "crown.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                Section("招待コードを共有") {
                    HStack {
                        Text(appState.inviteCode)
                            .font(.title2.monospacedDigit().bold())
                            .foregroundColor(.orange)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = appState.inviteCode
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        ShareLink(item: "SearchMeの招待コード: \(appState.inviteCode)\nhttps://searchme.skyscanning.jp") {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }

                Section {
                    if appState.isOwner {
                        Button(role: .destructive) {
                            showDisbandSheet = true
                        } label: {
                            Label("グループを解散する", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label("グループから退出", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .alert("グループから退出しますか？", isPresented: $showLeaveConfirm) {
                Button("退出", role: .destructive) { leave() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("退出すると初期設定からやり直しになります。")
            }
            .sheet(isPresented: $showDisbandSheet) {
                DisbandConfirmSheet(
                    groupName: appState.groupName,
                    onDisband: {
                        showDisbandSheet = false
                        disband()
                    },
                    onCancel: { showDisbandSheet = false }
                )
            }
        }
    }

    private func leave() {
        let memberId = appState.myMemberId
        Task {
            do {
                try await APIService.shared.leaveGroup(memberId: memberId)
                await MainActor.run { appState.clearGroup() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func disband() {
        let groupId  = appState.groupId
        let memberId = appState.myMemberId
        Task {
            do {
                try await APIService.shared.deleteGroup(groupId: groupId, memberId: memberId)
                await MainActor.run { appState.clearGroup() }
            } catch {
                await MainActor.run { errorMessage = "解散に失敗しました: \(error.localizedDescription)" }
            }
        }
    }
}

// MARK: - 解散確認シート

struct DisbandConfirmSheet: View {
    let groupName: String
    let onDisband: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)

                Text("「\(groupName)」を解散しますか？")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    warningRow(icon: "person.badge.minus", text: "グループの全メンバーが強制的に退出されます")
                    warningRow(icon: "location.slash", text: "全員の位置情報・安否情報が削除されます")
                    warningRow(icon: "arrow.uturn.backward.slash", text: "この操作は取り消すことができません")
                    warningRow(icon: "iphone.slash", text: "家族の端末は次回起動時に初期設定画面に戻ります")
                }
                .padding()
                .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button(role: .destructive, action: onDisband) {
                    Text("グループを解散する")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: onCancel) {
                    Text("キャンセル")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .presentationDetents([.medium, .large])
    }

    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}
