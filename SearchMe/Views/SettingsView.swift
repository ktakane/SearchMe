import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLeaveConfirm = false
    @State private var showDisbandConfirm = false
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
                            showDisbandConfirm = true
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
            .alert("グループを解散しますか？", isPresented: $showDisbandConfirm) {
                Button("解散する", role: .destructive) { disband() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("全メンバーがグループから退出されます。この操作は取り消せません。")
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
