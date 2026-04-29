import Foundation
import CoreLocation
import UIKit

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
    }

    func stopDisasterTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
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
