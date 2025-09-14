//
//  ContactEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Inline editor to tweak detected contact fields before saving.
//  Saves via ContactsService.
//

import SwiftUI
import Contacts

@MainActor
public struct ContactEditorView: View {
    @State private var givenName: String
    @State private var familyName: String
    @State private var emails: [String]
    @State private var phones: [String]
    @State private var street: String
    @State private var city: String
    @State private var state: String
    @State private var postalCode: String
    @State private var country: String

    @State private var isSaving = false
    @State private var error: String?

    public let onCancel: () -> Void
    public let onSaved: (String) -> Void

    public init(sourceText: String, onCancel: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
        let detected = ContactParser.detect(in: sourceText)

        _givenName = State(initialValue: detected.givenName ?? "")
        _familyName = State(initialValue: detected.familyName ?? "")
        _emails     = State(initialValue: detected.emails)
        _phones     = State(initialValue: detected.phones)

        if let addr = detected.postalAddress {
            _street     = State(initialValue: addr.street)
            _city       = State(initialValue: addr.city)
            _state      = State(initialValue: addr.state)
            _postalCode = State(initialValue: addr.postalCode)
            _country    = State(initialValue: addr.country)
        } else {
            _street = State(initialValue: ""); _city = State(initialValue: "")
            _state  = State(initialValue: ""); _postalCode = State(initialValue: "")
            _country = State(initialValue: "")
        }

        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Given name", text: $givenName)
                    TextField("Family name", text: $familyName)
                }
                Section("Emails") {
                    ForEach(emails.indices, id: \.self) { i in
                        HStack {
                            TextField("email@example.com", text: Binding(
                                get: { emails[i] },
                                set: { emails[i] = $0 }
                            ))
                            Button(role: .destructive) { emails.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove email")
                        }
                    }
                    Button {
                        emails.append("")
                    } label: {
                        Label("Add email", systemImage: "plus.circle")
                    }
                }
                Section("Phones") {
                    ForEach(phones.indices, id: \.self) { i in
                        HStack {
                            TextField("+353 1 123 4567", text: Binding(
                                get: { phones[i] },
                                set: { phones[i] = $0 }
                            ))
                            Button(role: .destructive) { phones.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove phone")
                        }
                    }
                    Button {
                        phones.append("")
                    } label: {
                        Label("Add phone", systemImage: "plus.circle")
                    }
                }
                Section("Address") {
                    TextField("Street", text: $street)
                    TextField("City", text: $city)
                    TextField("County/State", text: $state)
                    TextField("Postcode", text: $postalCode)
                    TextField("Country", text: $country)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || allFieldsEmpty)
                }
            }
            .overlay { if isSaving { ProgressView().scaleEffect(1.2) } }
        }
    }

    private var allFieldsEmpty: Bool {
        givenName.trimmingCharacters(in: .whitespaces).isEmpty &&
        familyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        emails.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } &&
        phones.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } &&
        street.isEmpty && city.isEmpty && state.isEmpty && postalCode.isEmpty && country.isEmpty
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }

        var dc = DetectedContact()
        if !givenName.trimmingCharacters(in: .whitespaces).isEmpty { dc.givenName = givenName }
        if !familyName.trimmingCharacters(in: .whitespaces).isEmpty { dc.familyName = familyName }
        dc.emails = emails.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        dc.phones = phones.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if !(street.isEmpty && city.isEmpty && state.isEmpty && postalCode.isEmpty && country.isEmpty) {
            let addr = CNMutablePostalAddress()
            addr.street = street
            addr.city = city
            addr.state = state
            addr.postalCode = postalCode
            addr.country = country
            dc.postalAddress = addr.copy() as? CNPostalAddress
        }

        // Require at least one piece of info
        guard (dc.givenName?.isEmpty == false) ||
              (dc.familyName?.isEmpty == false) ||
              !dc.emails.isEmpty || !dc.phones.isEmpty || (dc.postalAddress != nil) else {
            error = "Enter at least one contact field."
            return
        }

        do {
            let id = try await ContactsService.save(contact: dc)
            onSaved("Contact saved (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
