//
//  CalendarService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Updated: 15/09/2025 – iOS 26–clean. Embeds GeofencingManager to avoid missing-type issues.
//  Uses MKMapItem.location (no MKPlacemark), EKStructuredLocation, and optional geofencing.
//

import Foundation
import EventKit
import MapKit
import CoreLocation
import UserNotifications

// ============================================================================
// MARK: - GeofencingManager (embedded)
// ============================================================================

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

    // Permissions
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

    // Sync with OS-monitored regions
    private func syncMonitoredRegions() async {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }

        let now = Date()
        let sorted = geofencesByID.values.sorted { a, b in
            func priority(_ g: Geofence) -> (Int, Date) {
                if let s = g.startDate, s > now { return (0, s) }   // upcoming
                if let e = g.endDate, e > now { return (1, e) }     // ongoing
                return (2, g.lastUpdatedAt)                         // recent past
            }
            let pa = priority(a), pb = priority(b)
            if pa.0 != pb.0 { return pa.0 < pb.0 }
            return pa.1 < pb.1
        }
        let chosen = Array(sorted.prefix(maxRegions))
        let chosenIDs = Set(chosen.map { $0.id })

        for region in manager.monitoredRegions {
            if region.identifier.hasPrefix("event:") {
                let id = String(region.identifier.dropFirst("event:".count))
                if !chosenIDs.contains(id) {
                    manager.stopMonitoring(for: region)
                }
            }
        }

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

    // Notifications
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

    // Persistence
    private func save() {
        guard let data = try? JSONEncoder().encode(geofencesByID) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return }
        geofencesByID = (try? JSONDecoder().decode([String: Geofence].self, from: data)) ?? [:]
    }

    // CLLocationManagerDelegate
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

// ============================================================================
// MARK: - CalendarService
// ============================================================================

enum CalendarServiceError: Error, LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:       return "Calendar access was not granted."
        case .noWritableCalendar: return "No writable calendar is available."
        case .saveFailed(let m):  return "Failed to save event: \(m)"
        }
    }
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    @discardableResult
    func addEvent(
        title: String,
        start: Date,
        end: Date,
        notes: String?,
        locationHint: String? = nil,
        inferTimeZoneFromLocation: Bool = true,
        alertMinutesBefore: Int? = nil,
        travelTimeAlarm: Bool = false,
        transport: MKDirectionsTransportType = MKDirectionsTransportType.automobile,
        geofenceProximity: GeofencingManager.GeofenceProximity? = nil,
        geofenceRadius: CLLocationDistance = 150
    ) async throws -> String {

        try await requestAccess()
        let calendar = try defaultWritableCalendar()

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Event" : title
        event.startDate = start
        event.endDate = end
        event.notes = notes

        // Location hint (optional)
        let combinedText = [title, notes ?? ""].joined(separator: "\n")
        let placeQuery: String? = {
            if let hint = locationHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                return hint
            }
            return Self.firstLocationHint(in: combinedText)
        }()

        // Resolve place (MapKit search)
        var resolvedCoordinate: CLLocationCoordinate2D?
        if let query = placeQuery, let place = await Self.searchFirstPlaceSummary(for: query) {
            event.location = place.displayName

            let coord = place.coordinate
            resolvedCoordinate = coord

            let sl = EKStructuredLocation(title: place.displayName)
            sl.geoLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            event.structuredLocation = sl

            if inferTimeZoneFromLocation {
                if let tzID = place.timeZoneIdentifier, let tz = TimeZone(identifier: tzID) {
                    event.timeZone = tz
                    event.startDate = Self.rebase(date: event.startDate, from: Calendar.current.timeZone, to: tz)
                    event.endDate   = Self.rebase(date: event.endDate,   from: Calendar.current.timeZone, to: tz)
                }
            }
        } else if let query = placeQuery {
            event.location = query
        }

        // Fixed alert
        if let m = alertMinutesBefore, m > 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-m * 60)))
        }

        // Travel-time alarm — only if we actually resolved coordinates
        if travelTimeAlarm, let coord = resolvedCoordinate {
            if let eta = await Self.etaSeconds(to: coord, transport: transport, fallback: nil), eta > 0 {
                let leaveBy = event.startDate.addingTimeInterval(-eta)
                event.addAlarm(EKAlarm(absoluteDate: leaveBy))
            }
        }

        // Save
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarServiceError.saveFailed(error.localizedDescription)
        }

        // Normalise event identifier across SDKs (String? historically).
        let id = event.eventIdentifier ?? ""
        if id.isEmpty {
            throw CalendarServiceError.saveFailed("Event saved but identifier is unavailable.")
        }

        // Optional geofence — only if we actually resolved coordinates
        if let prox = geofenceProximity, let coord = resolvedCoordinate {
            await GeofencingManager.shared.upsertForEvent(
                id: id,
                title: event.title,
                coordinate: coord,
                radius: geofenceRadius,
                proximity: prox,
                startDate: event.startDate,
                endDate: event.endDate
            )
        }

        return id
    }

    func addEvent(title: String, start: Date, end: Date, notes: String?) async throws -> String {
        try await addEvent(
            title: title,
            start: start,
            end: end,
            notes: notes,
            locationHint: nil,
            inferTimeZoneFromLocation: true,
            alertMinutesBefore: nil,
            travelTimeAlarm: false,
            transport: MKDirectionsTransportType.automobile,
            geofenceProximity: nil,
            geofenceRadius: 150
        )
    }
}

// MARK: - Heuristics (location hint)

extension CalendarService {
    static func firstLocationHint(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range),
               let r = Range(match.range, in: trimmed) {
                let candidate = String(trimmed[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }

        let patterns = [ #"(?:^|\s)(?:at|@|in)\s+([^\n,.;:|]{3,80})"# ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let r = NSRange(trimmed.startIndex..., in: trimmed)
                if let m = re.firstMatch(in: trimmed, options: [], range: r),
                   m.numberOfRanges >= 2,
                   let range1 = Range(m.range(at: 1), in: trimmed) {
                    let candidate = String(trimmed[range1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty { return candidate }
                }
            }
        }
        return nil
    }
}

// MARK: - MapKit helpers

internal struct PlaceSummary: Sendable {
    let displayName: String
    let coordinate: CLLocationCoordinate2D               // non-optional
    let timeZoneIdentifier: String?                      // may be nil
}

extension CalendarService {
    @MainActor
    static func searchFirstPlaceSummary(for query: String) async -> PlaceSummary? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query

        return await withCheckedContinuation { (cont: CheckedContinuation<PlaceSummary?, Never>) in
            MKLocalSearch(request: req).start { response, _ in
                guard let item = response?.mapItems.first else {
                    cont.resume(returning: nil)
                    return
                }

                // In current SDKs, `location` is non-optional; do NOT optional-chain.
                let coord = item.location.coordinate

                let display: String
                if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    display = name
                } else {
                    display = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
                }

                let tzID = item.timeZone?.identifier
                cont.resume(returning: PlaceSummary(displayName: display, coordinate: coord, timeZoneIdentifier: tzID))
            }
        }
    }

    static func etaSeconds(
        to dest: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType,
        fallback: TimeInterval?
    ) async -> TimeInterval? {
        let destination = MKMapItem(location: CLLocation(latitude: dest.latitude, longitude: dest.longitude), address: nil)
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = transport
        request.requestsAlternateRoutes = false

        return await withCheckedContinuation { (cont: CheckedContinuation<TimeInterval?, Never>) in
            MKDirections(request: request).calculate { resp, _ in
                if let secs = resp?.routes.first?.expectedTravelTime, secs > 0 {
                    cont.resume(returning: secs)
                } else {
                    cont.resume(returning: fallback)
                }
            }
        }
    }

    static func rebase(date: Date, from: TimeZone, to: TimeZone) -> Date {
        var fromCal = Calendar(identifier: .gregorian)
        fromCal.timeZone = from
        let comps = fromCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        var toCal = Calendar(identifier: .gregorian)
        toCal.timeZone = to
        return toCal.date(from: comps) ?? date
    }
}

// MARK: - Permissions

extension CalendarService {
    func requestAccess() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToEvents { granted, error in
                if let error { cont.resume(throwing: error); return }
                guard granted else { cont.resume(throwing: CalendarServiceError.accessDenied); return }
                cont.resume(returning: ())
            }
        }
    }

    private func defaultWritableCalendar() throws -> EKCalendar {
        if let cal = store.defaultCalendarForNewEvents, cal.allowsContentModifications {
            return cal
        }
        if let writable = store.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            return writable
        }
        throw CalendarServiceError.noWritableCalendar
    }
}
