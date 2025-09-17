//
//  CalendarService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  iOS 26: no MapKit deprecations, no Sendable warnings.
//  - Uses MKMapItem.location (not placemark)
//  - Uses MKMapItem(init:location:address:) (not MKPlacemark/init(placemark:))
//  - Reverse geocoding via MKReverseGeocodingRequest inside a detached task,
//    returning only String? (time zone id) to the main actor.
//

import Foundation
import EventKit
@preconcurrency import MapKit
import CoreLocation

enum CalendarServiceError: Error, LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:        return "Calendar access was not granted."
        case .noWritableCalendar:  return "No writable calendar is available."
        case .saveFailed(let m):   return "Failed to save event: \(m)"
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
        transport: MKDirectionsTransportType = .automobile,
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
        if let query = placeQuery,
           let place = await Self.searchFirstPlaceSummary(for: query)
        {
            event.location = place.displayName
            let coord = place.coordinate
            resolvedCoordinate = coord

            let sl = EKStructuredLocation(title: place.displayName)
            sl.geoLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            event.structuredLocation = sl

            if inferTimeZoneFromLocation, let tzID = place.timeZoneIdentifier, let tz = TimeZone(identifier: tzID) {
                event.timeZone = tz
                event.startDate = Self.rebase(date: event.startDate, from: Calendar.current.timeZone, to: tz)
                event.endDate   = Self.rebase(date: event.endDate,   from: Calendar.current.timeZone, to: tz)
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
            transport: .automobile,
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
               let r = Range(match.range, in: trimmed)
            {
                let candidate = String(trimmed[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }

        // Simple "at/@/in …" heuristic
        let patterns = [#"(?:^|\s)(?:at|@|in)\s+([^\n,.;:|]{3,80})"#]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let r = NSRange(trimmed.startIndex..., in: trimmed)
                if let m = re.firstMatch(in: trimmed, options: [], range: r),
                   m.numberOfRanges >= 2,
                   let range1 = Range(m.range(at: 1), in: trimmed)
                {
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
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String?
}

extension CalendarService {

    /// Searches a place and snapshots only Sendable bits (name/lat/lon/tz).
    @MainActor
    static func searchFirstPlaceSummary(for query: String) async -> PlaceSummary? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query

        struct Snapshot: Sendable { let name: String?; let lat: Double?; let lon: Double?; let tzID: String? }

        let snap: Snapshot? = await withCheckedContinuation { (cont: CheckedContinuation<Snapshot?, Never>) in
            MKLocalSearch(request: req).start { response, _ in
                guard let item = response?.mapItems.first else {
                    cont.resume(returning: nil)
                    return
                }
                // Use iOS 26 MapKit APIs (no placemark)
                let coord = item.location.coordinate
                cont.resume(returning: Snapshot(
                    name: item.name,
                    lat: coord.latitude,
                    lon: coord.longitude,
                    tzID: item.timeZone?.identifier
                ))
            }
        }

        guard let s = snap, let lat = s.lat, let lon = s.lon else { return nil }

        let display = (s.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(format: "%.5f, %.5f", lat, lon)

        var tzID: String? = s.tzID
        if tzID == nil {
            tzID = await reverseLookupTimeZoneIdentifier(lat: lat, lon: lon)
        }

        return PlaceSummary(
            displayName: display,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            timeZoneIdentifier: tzID
        )
    }

    /// Reverse-geocode using MapKit. All MK types live inside a detached task.
    private static func reverseLookupTimeZoneIdentifier(lat: Double, lon: Double) async -> String? {
        do {
            return try await Task.detached { () -> String? in
                let loc = CLLocation(latitude: lat, longitude: lon)
                guard let request = MKReverseGeocodingRequest(location: loc) else { return nil }
                let items = try await request.mapItems
                return items.first?.timeZone?.identifier
            }.value
        } catch {
            return nil
        }
    }

    static func etaSeconds(
        to dest: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType,
        fallback: TimeInterval?
    ) async -> TimeInterval? {
        // Destination MKMapItem using iOS 26 API (no MKPlacemark)
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
