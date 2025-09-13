//
//  ContactsService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import Contacts

enum ContactsService {
    static func save(contact dc: DetectedContact) async throws -> String {
        let store = CNContactStore()
        try await requestAccess(store: store)

        let c = CNMutableContact()
        if let given = dc.givenName { c.givenName = given }
        if let family = dc.familyName { c.familyName = family }

        c.emailAddresses = dc.emails.map {
            CNLabeledValue<NSString>(label: CNLabelWork, value: NSString(string: $0))
        }
        c.phoneNumbers = dc.phones.map {
            CNLabeledValue<CNPhoneNumber>(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: $0))
        }

        if let addr = dc.postalAddress {
            c.postalAddresses = [CNLabeledValue<CNPostalAddress>(label: CNLabelWork, value: addr)]
        }

        let save = CNSaveRequest()
        save.add(c, toContainerWithIdentifier: nil)
        try store.execute(save)
        return c.identifier
    }

    private static func requestAccess(store: CNContactStore) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAccess(for: .contacts) { granted, err in
                if let err { cont.resume(throwing: err); return }
                guard granted else {
                    cont.resume(throwing: NSError(domain: "ContactsService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Contacts access not granted."]))
                    return
                }
                cont.resume(returning: ())
            }
        }
    }
}
