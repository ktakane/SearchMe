import SwiftUI

struct SafetySheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    let isStopping: Bool
    var isReminder: Bool = false
    let onCompleted: (() -> Void)?

    @State private var isSending = false

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 56))
                        .foregroundColor(.orange)
                    Text(isStopping ? "停止前に安否を報告してください" : "現在の状況を家族に知らせてください")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 16) {
                    Button { send(status: "safe") } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("無事です")
                                .font(.title2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(.green)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(isSending)

                    Button { send(status: "need_help") } label: {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.title2)
                            Text("助けが必要")
                                .font(.title2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(isSending)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("安否確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isStopping && !isReminder {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { isPresented = false }
                    }
                }
            }
            .overlay {
                if isSending { ProgressView() }
            }
        }
    }

    private func send(status: String) {
        isSending = true
        Task {
            try? await APIService.shared.reportSafety(
                memberId: appState.myMemberId,
                groupId:  appState.groupId,
                status:   status
            )
            scheduleSafetyReminder()
            await MainActor.run {
                isSending = false
                isPresented = false
                onCompleted?()
            }
        }
    }

    private func scheduleSafetyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["safety_reminder"])
        let content = UNMutableNotificationContent()
        content.title = "安否確認をしてください"
        content.body = "災害モード稼働中です。家族に現在の状況を知らせてください。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(identifier: "safety_reminder", content: content, trigger: trigger)
        center.add(request)
    }
}
