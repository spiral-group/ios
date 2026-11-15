//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: App Review F1 (decision 252). Spiral ships without location
// sharing and declares no location purpose string, so the binary must not
// reference CoreLocation's request or update APIs. The session's
// `LiveLocationManager` runs over this instead of a `CLLocationManager`: it
// reports location as restricted, so a share restored from storage stops and
// nothing ever asks for access.
//

import CoreLocation

final class SpiralNoLocationManager: CLLocationManagerProtocol {
    weak var delegate: CLLocationManagerDelegate?
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var desiredAccuracy = kCLLocationAccuracyReduced
    var distanceFilter = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    let authorizationStatus = CLAuthorizationStatus.restricted
    let accuracyAuthorization = CLAccuracyAuthorization.reducedAccuracy
    
    func requestAlwaysAuthorization() { }
    func startUpdatingLocation() { }
    func stopUpdatingLocation() { }
}
