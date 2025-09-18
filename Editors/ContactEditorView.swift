//
//  ContactEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Can prefill from a photographed table on iOS 26.
//

import SwiftUI
import Contacts

@MainActor
public struct ContactEditorView: View {
    @EnvironmentObject private var pro: ProStore

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
    @State private var seededFromImage = false
    @State private var showPaywall = false

    public let onCancel: () -> Void
    public let onSaved: (String) -> Void

    private let sourceImageData: Data?

    public init(sourceText: String, sourceImageData: Data? = nil, onCancel: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
        let d = ContactParser.detect(in: sourceText)
        _givenName  = State(initialValue: d.givenName ?? "")
        _familyName = State(initialValue: d.familyName ?? "")
        _emails     = State(initialValue: d.emails)
        _phones     = State(initialValue: d.phones)
        if let a = d.postalAddress {
            _street = State(initialValue: a.street)
            _city = State(initialValue: a.city)
            _state = State(initialValue: a.state)
            _postalCode = State(initialValue: a.postalCode)
            _country = State(initialValue: a.country)
        } else {
            _street = State(initialValue: ""); _city = State(initialValue: "")
            _state = State(initialValue: ""); _postalCode = State(initialValue: ""); _country = State(initialValue: "")
        }
        self.sourceImageData = sourceImageData
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
                                get: { emails[i] }, set: { emails[i] = $0 }
                            ))
                            Button(role: .destructive) { emails.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button { emails.append("") } label: { Label("Add email", systemImage: "plus.circle") }
                }
                Section("Phones") {
                    ForEach(phones.indices, id: \.self) { i in
                        HStack {
                            TextField("+353 1 123 4567", text: Binding(
                                get: { phones[i] }, set: { phones[i] = $0 }
                            ))
                            Button(role: .destructive) { phones.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button { phones.append("") } label: { Label("Add phone", systemImage: "plus.circle") }
                }
                Section("Address") {
                    TextField("Street", text: $street)
                    TextField("City", text: $city)
                    TextField("County/State", text: $state)
                    TextField("Postcode", text: $postalCode)
                    TextField("Country", text: $country)
                }

                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                if seededFromImage {
                    Section {
                        Label("Seeded from document image", systemImage: "doc.viewfinder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            .overlay(alignment: .center) { if isSaving { ProgressView().scaleEffect(1.2) } }
            .sheet(isPresented: $showPaywall) { ProPaywallView().environmentObject(pro) }
            .task {
                if let data = sourceImageData, !seededFromImage {
                    if #available(iOS 26, *) {
                        do {
                            var _hint: VisionDocumentReader.SmudgeHint?
                            if let first = try await VisionDocumentReader.contacts(from: data, smudgeHint: &_hint).first {
                                if let g = first.givenName { givenName = g }
                                if let f = first.familyName { familyName = f }
                                if !first.emails.isEmpty { emails = first.emails }
                                if !first.phones.isEmpty { phones = first.phones }
                                if let a = first.postalAddress {
                                    street = a.street; city = a.city; state = a.state; postalCode = a.postalCode; country = a.country
                                }
                                seededFromImage = true
                            }
                        } catch { /* ignore */ }
                    }
                }
            }
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
        error = nil; isSaving = true; defer { isSaving = false }

        // Gate: only when seeded from an image (5/day free)
        if seededFromImage {
            let gate = QuotaManager.consume(feature: .createContactFromImage, isPro: pro.isPro)
            guard gate.allowed else {
                self.error = gate.message
                self.showPaywall = true
                return
            }
        }

        var dc = DetectedContact()
        if !givenName.trimmingCharacters(in: .whitespaces).isEmpty { dc.givenName = givenName }
        if !familyName.trimmingCharacters(in: .whitespaces).isEmpty { dc.familyName = familyName }
        dc.emails = emails.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        dc.phones = phones.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !(street.isEmpty && city.isEmpty && state.isEmpty && postalCode.isEmpty && country.isEmpty) {
            let a = CNMutablePostalAddress()
            a.street = street; a.city = city; a.state = state; a.postalCode = postalCode; a.country = country
            dc.postalAddress = a.copy() as? CNPostalAddress
        }

        let has = (dc.givenName?.isEmpty == false) || (dc.familyName?.isEmpty == false) || !dc.emails.isEmpty || !dc.phones.isEmpty || (dc.postalAddress != nil)
        guard has else { error = "Enter at least one contact field."; return }

        do {
            let id = try await ContactsService.save(contact: dc)
            onSaved("Contact saved (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
