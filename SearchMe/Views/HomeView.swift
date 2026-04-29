import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var locationService = LocationService.shared
    @State private var showDisasterConfirm = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard
                    disasterButton
                    infoCard
                }
                .padding()
            }
            .navigationTitle("SearchMe")
        }
        .onAppear {
            locationService.setAppState(appState)
            if locationService.authorizationStatus == .notDetermined {
                locationService.requestAlwaysAuthorization()
            }
        }
        .alert("災害モードを開始しますか？", isPresented: $showDisasterConfirm) {
            Button("開始", role: .destructive) { startDisasterMode() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("家族があなたの位置を確認できるようになります。")
        }
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(appState.isDisasterMode ? .red : .green)
                    .frame(width: 12, height: 12)
                Text(appState.isDisasterMode ? "災害モード稼働中" : "通常モード")
                    .font(.headline)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("グループ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.groupName)
                        .font(.body.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("招待コード")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.inviteCode)
                        .font(.body.monospacedDigit().bold())
                        .foregroundColor(.orange)
                }
            }

            if locationService.authorizationStatus != .authorizedAlways {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("位置情報を「常に許可」にしてください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("設定") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                }
                .padding(8)
                .background(.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var disasterButton: some View {
        Group {
            if appState.isDisasterMode {
                Button {
                    stopDisasterMode()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 48))
                        Text("災害モードを停止")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(16)
                }
            } else {
                Button {
                    showDisasterConfirm = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "sos.circle.fill")
                            .font(.system(size: 48))
                        Text("災害モードを開始")
                            .font(.headline)
                        Text("家族があなたの位置を確認できます")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(.orange)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("使い方", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundColor(.orange)
            Text("1. 家族全員がアプリをインストールし、同じグループに参加します。")
            Text("2. 災害発生時に「災害モードを開始」をタップします。")
            Text("3. 家族のマップ画面にあなたの位置が表示されます。")
            Text("4. 意識がない場合でも、iPhoneが位置情報を自動送信します。")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func startDisasterMode() {
        appState.isDisasterMode = true
        locationService.startDisasterTracking()
        Task {
            try? await APIService.shared.activateDisaster(groupId: appState.groupId)
        }
    }

    private func stopDisasterMode() {
        appState.isDisasterMode = false
        locationService.stopDisasterTracking()
        Task {
            try? await APIService.shared.deactivateDisaster(groupId: appState.groupId)
        }
    }
}
