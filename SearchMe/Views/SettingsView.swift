import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showResetConfirm = false

    var body: some View {
        NavigationView {
            Form {
                Section("あなたの情報") {
                    LabeledContent("名前", value: appState.myName)
                    LabeledContent("グループ", value: appState.groupName)
                    LabeledContent("招待コード", value: appState.inviteCode)
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

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("グループから退出", systemImage: "person.badge.minus")
                    }
                }
            }
            .navigationTitle("設定")
            .alert("グループから退出しますか？", isPresented: $showResetConfirm) {
                Button("退出", role: .destructive) { reset() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("退出すると初期設定からやり直しになります。")
            }
        }
    }

    private func reset() {
        UserDefaults.standard.removeObject(forKey: "myMemberId")
        UserDefaults.standard.removeObject(forKey: "myName")
        UserDefaults.standard.removeObject(forKey: "groupId")
        UserDefaults.standard.removeObject(forKey: "groupName")
        UserDefaults.standard.removeObject(forKey: "inviteCode")
        appState.myMemberId = ""
        appState.myName     = ""
        appState.groupId    = ""
        appState.groupName  = ""
        appState.inviteCode = ""
    }
}
