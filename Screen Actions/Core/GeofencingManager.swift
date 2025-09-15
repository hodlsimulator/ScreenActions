//
//  GeofencingManager.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Lightweight geofencing (enter/exit) via region monitoring + local notifications.
//  iOS 26–clean. No background mode required. Always-location permission recommended.
//

import Foundation
import CoreLocation
import UserNotifications

@MainActor
final class GeofencingManager: NSObject, CLLocationManagerDelegate {
    static let shared = GeofencingManager()

    struct GeofenceProximity: OptionSet, Sendable {
        let rawValue: Int
        static let enter = GeofenceProximity(rawValue: 1 << 0)
        static let exit  = GeofenceProximity(rawValue: 1 << 1)
    }

    private struct Geofence: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var latitude: Double
        var longitude: Double
        var radius: Double
        var notifyOnEnter: Bool
        var notifyOnExit: Bool
        var startDate: Date?
        var endDate: Date?
        var createdAt: Date
        var lastUpdatedAt: Date

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private let storeKey = "GeofencingManager.store.v1"
    private var geofencesByID: [String: Geofence] = [:]
    private let manager: CLLocationManager = CLLocationManager()
    private let maxRegions = 20

    private override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        load()
        Task { await syncMonitoredRegions() }
    }

    // MARK: Public API

    func upsertForEvent(
        id: String,
        title: String,
        coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 150,
        proximity: GeofenceProximity = [.enter],
        startDate: Date?,
        endDate: Date?
    ) async {
        await ensureNotificationPermission()
        await ensureLocationPermission()

        var gf = geofencesByID[id] ?? Geofence(
            id: id, title: title,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            radius: radius,
            notifyOnEnter: proximity.contains(.enter),
            notifyOnExit:  proximity.contains(.exit),
            startDate: startDate, endDate: endDate,
            createdAt: Date(), lastUpdatedAt: Date()
        )
        gf.title = title
        gf.latitude = coordinate.latitude
        gf.longitude = coordinate.longitude
        gf.radius = max(50, min(radius, 2000))
        gf.notifyOnEnter = proximity.contains(.enter)
        gf.notifyOnExit  = proximity.contains(.exit)
        gf.startDate = startDate
        gf.endDate = endDate
        gf.lastUpdatedAt = Date()

        geofencesByID[id] = gf
        save()
        await syncMonitoredRegions()
    }

    func removeForEvent(id: String) async {
        geofencesByID.removeValue(forKey: id)
        save()
        await syncMonitoredRegions()
    }

    // MARK: Permissions

    private func ensureLocationPermission() async {
        switch manager.authorizationStatus {
        case .authorizedAlways: return
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .denied, .restricted: return
        @unknown default: return
        }
    }

    private func ensureNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let status: UNAuthorizationStatus = await withCheckedContinuation { cont in
            center.getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus)
            }
        }
        if status == .notDetermined {
            _ = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, err in
                    if let err { cont.resume(throwing: err) } else { cont.resume(returning: ()) }
                }
            }
        }
    }

    // MARK: Sync

    private func syncMonitoredRegions() async {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }

        let now = Date()
        let sorted = geofencesByID.values.sorted { a, b in
            func priority(_ g: Geofence) -> (Int, Date) {
                if let s = g.startDate, s > now { return (0, s) }
                if let e = g.endDate, e > now { return (1, e) }
                return (2, g.lastUpdatedAt)
            }
            let pa = priority(a), pb = priority(b)
            if pa.0 != pb.0 { return pa.0 < pb.0 }
            return pa.1 < pb.1
        }
        let chosen = Array(sorted.prefix(maxRegions))
        let chosenIDs = Set(chosen.map { $0.id })

        // Stop monitoring regions we no longer want
        for region in manager.monitoredRegions {
            if region.identifier.hasPrefix("event:") {
                let id = String(region.identifier.dropFirst("event:".count))
                if !chosenIDs.contains(id) {
                    manager.stopMonitoring(for: region)
                }
            }
        }

        // Start/refresh chosen regions
        for gf in chosen {
            let identifier = "event:\(gf.id)"
            let existing = manager.monitoredRegions.first { $0.identifier == identifier } as? CLCircularRegion
            let region = CLCircularRegion(center: gf.coordinate, radius: gf.radius, identifier: identifier)
            region.notifyOnEntry = gf.notifyOnEnter
            region.notifyOnExit  = gf.notifyOnExit

            if let a = existing,
               a.center.latitude == region.center.latitude,
               a.center.longitude == region.center.longitude,
               a.radius == region.radius,
               a.notifyOnEntry == region.notifyOnEntry,
               a.notifyOnExit == region.notifyOnExit {
                continue
            }

            if let a = existing { manager.stopMonitoring(for: a) }
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Notifications

    private func postRegionNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "geofence:\(id):\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(geofencesByID) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return }
        geofencesByID = (try? JSONDecoder().decode([String: Geofence].self, from: data)) ?? [:]
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { await syncMonitoredRegions() }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("event:") else { return }
        let id = String(region.identifier.dropFirst("event:".count))
        guard let gf = geofencesByID[id], gf.notifyOnEnter else { return }
        postRegionNotification(title: "Arrived", body: "You’ve arrived at \(gf.title).", id: id)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("event:") else { return }
        let id = String(region.identifier.dropFirst("event:".count))
        guard let gf = geofencesByID[id], gf.notifyOnExit else { return }
        postRegionNotification(title: "Leaving", body: "You’re leaving \(gf.title).", id: id)
    }
}
