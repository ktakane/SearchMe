import Foundation
import CoreLocation
import UIKit
import UserNotifications

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var appState: AppState?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        authorizationStatus = manager.authorizationStatus
    }

    func setAppState(_ state: AppState) {
        self.appState = state
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startDisasterTracking() {
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        scheduleDisasterReminder()
    }

    func stopDisasterTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        cancelDisasterReminder()
    }

    private func scheduleDisasterReminder() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ 災害モード稼働中"
        content.body = "位置情報を送信中です。安全が確認できたら停止してください。"
        content.sound = .default

        // 3時間ごとに繰り返し通知
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 60 * 60, repeats: true)
        let request = UNNotificationRequest(identifier: "disaster_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 1
        }
    }

    private func cancelDisasterReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["disaster_reminder"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["disaster_reminder"])
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              let state = appState,
              state.isDisasterMode else { return }
        lastLocation = location
        sendLocation(location, state: state)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Private

    private func sendLocation(_ location: CLLocation, state: AppState) {
        let battery = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = true
        let payload = LocationPayload(
            memberId: state.myMemberId,
            groupId: state.groupId,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            batteryLevel: UIDevice.current.batteryLevel < 0 ? 1.0 : UIDevice.current.batteryLevel,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        Task {
            try? await APIService.shared.sendLocation(payload)
        }
        _ = battery
    }
}
