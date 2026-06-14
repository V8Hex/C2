import Foundation
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private(set) var currentLocation: CLLocation?
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
    }
    
    // MARK: - Authorization
    func requestAccess() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }
    
    // MARK: - Tracking
    func startTracking() {
        requestAccess()
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
    }
    
    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }
    
    func forceUpdate() {
        manager.requestLocation()
    }
    
    // MARK: - Get Location
    func getLocation() -> (Double, Double)? {
        guard let loc = currentLocation else { return nil }
        return (loc.coordinate.latitude, loc.coordinate.longitude)
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[PhotoVault] Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startTracking()
        default:
            break
        }
    }
}
