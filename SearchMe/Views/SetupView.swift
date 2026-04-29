import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subManager: SubscriptionManager
    @State private var name = ""
    @State private var inviteCode = ""
    @State private var groupName = ""
    @State private var isCreating = false
    @State private var isJoining = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showJoinSheet = false
    @State private var showCreateSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "figure.search")
                        .font(.system(size: 72))
                        .foregroundColor(.orange)
                    Text("SearchMe")
                        .font(.largeTitle.bold())
                    Text("災害時、家族があなたを見つけられるように")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("グループを作成する", systemImage: "person.3.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("招待コードで参加する", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateGroupSheet(isPresented: $showCreateSheet)
                .environmentObject(appState)
                .environmentObject(subManager)
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinGroupSheet(isPresented: $showJoinSheet)
                .environmentObject(appState)
        }
    }
}

struct CreateGroupSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var subManager: SubscriptionManager
    @State private var name = ""
    @State private var groupName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("あなたの名前") {
                    TextField("例: 田中太郎", text: $name)
                }
                Section("グループ名") {
                    TextField("例: 田中家", text: $groupName)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("グループを作成")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("作成") { create() }
                            .disabled(name.isEmpty || groupName.isEmpty)
                    }
                }
            }
        }
    }

    private func create() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let (group, member) = try await APIService.shared.createGroup(name: groupName, ownerName: name, maxMembers: subManager.planType.maxMembers)
                await MainActor.run {
                    appState.register(
                        memberId: member.id,
                        name: name,
                        groupId: group.id,
                        groupName: group.name,
                        inviteCode: group.inviteCode
                    )
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "作成に失敗しました: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct JoinGroupSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("あなたの名前") {
                    TextField("例: 田中花子", text: $name)
                }
                Section("招待コード") {
                    TextField("例: ABC123", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("グループに参加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("参加") { join() }
                            .disabled(name.isEmpty || inviteCode.isEmpty)
                    }
                }
            }
        }
    }

    private func join() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let (group, member) = try await APIService.shared.joinGroup(
                    inviteCode: inviteCode.uppercased(),
                    name: name
                )
                await MainActor.run {
                    appState.register(
                        memberId: member.id,
                        name: name,
                        groupId: group.id,
                        groupName: group.name,
                        inviteCode: group.inviteCode
                    )
                    isPresented = false
                }
            } catch APIError.groupFull(let max) {
                await MainActor.run {
                    errorMessage = "グループの人数上限（\(max)名）に達しています"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "参加に失敗しました: 招待コードを確認してください"
                    isLoading = false
                }
            }
        }
    }
}
