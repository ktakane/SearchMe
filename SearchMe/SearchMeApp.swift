import SwiftUI
import UserNotifications
import CoreLocation

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

    // バックグラウンド通知受信 → 都道府県を確認してから災害モード開始
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let type = userInfo["type"] as? String, type == "disaster_alert" else {
            completionHandler(.noData)
            return
        }

        let affectedAreas = userInfo["affected_areas"] as? [[String: String]] ?? []

        func activate() {
            DispatchQueue.main.async { [weak self] in
                guard let state = self?.appState, !state.isDisasterMode else {
                    completionHandler(.noData)
                    return
                }
                state.isDisasterMode = true
                LocationService.shared.startDisasterTracking()
                Task { try? await APIService.shared.activateDisaster(groupId: state.groupId) }
                completionHandler(.newData)
            }
        }

        // 地域データなし（速報等）→ 全員発動
        guard !affectedAreas.isEmpty else { activate(); return }

        // 現在地から都道府県を特定して照合
        guard let location = LocationService.shared.lastLocation else {
            activate(); return  // 現在地不明 → 安全のため発動
        }

        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let prefecture = placemarks?.first?.administrativeArea,
                  let userCode = Self.prefectureCode(from: prefecture) else {
                activate(); return  // 都道府県不明 → 安全のため発動
            }
            if affectedAreas.contains(where: { $0["code"] == userCode }) {
                activate()
            } else {
                completionHandler(.noData)
            }
        }
        _ = self
    }

    private static func prefectureCode(from name: String) -> String? {
        let map: [String: String] = [
            "北海道": "01", "青森県": "02", "岩手県": "03", "宮城県": "04",
            "秋田県": "05", "山形県": "06", "福島県": "07", "茨城県": "08",
            "栃木県": "09", "群馬県": "10", "埼玉県": "11", "千葉県": "12",
            "東京都": "13", "神奈川県": "14", "新潟県": "15", "富山県": "16",
            "石川県": "17", "福井県": "18", "山梨県": "19", "長野県": "20",
            "岐阜県": "21", "静岡県": "22", "愛知県": "23", "三重県": "24",
            "滋賀県": "25", "京都府": "26", "大阪府": "27", "兵庫県": "28",
            "奈良県": "29", "和歌山県": "30", "鳥取県": "31", "島根県": "32",
            "岡山県": "33", "広島県": "34", "山口県": "35", "徳島県": "36",
            "香川県": "37", "愛媛県": "38", "高知県": "39", "福岡県": "40",
            "佐賀県": "41", "長崎県": "42", "熊本県": "43", "大分県": "44",
            "宮崎県": "45", "鹿児島県": "46", "沖縄県": "47"
        ]
        return map[name]
    }
}
