import SwiftUI
import UserNotifications

@main
struct SearchMeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    delegate.appState = appState
                    LocationService.shared.setAppState(appState)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    // デバイストークン取得成功
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
        if let state = appState, state.isSetupComplete {
            Task {
                try? await APIService.shared.registerToken(token: token, memberId: state.myMemberId, groupId: state.groupId)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    // バックグラウンド通知受信 → 自動で災害モード開始
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let type = userInfo["type"] as? String, type == "disaster_alert" else {
            completionHandler(.noData)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let state = self?.appState, !state.isDisasterMode else {
                completionHandler(.noData)
                return
            }
            state.isDisasterMode = true
            LocationService.shared.startDisasterTracking()
            Task {
                try? await APIService.shared.activateDisaster(groupId: state.groupId)
            }
        }
        completionHandler(.newData)
    }
}
