//
//  ExtractContactIntent.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import AppIntents
import Contacts

struct ExtractContactIntent: AppIntent {
    static var title: LocalizedStringResource { "Extract Contact" }
    static var description: IntentDescription { IntentDescription("Parses contact details (name, email, phone, address) from text or an image and saves a new contact.") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Image")
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sourceText: String
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = t
        } else {
            sourceText = try TextExtractor.from(imageFile: image)
        }

        guard !sourceText.isEmpty else {
            throw $text.needsValueError("Provide text or an image with text.")
        }

        let detected = ContactParser.detect(in: sourceText)
        let hasSomething = (detected.givenName?.isEmpty == false)
            || !detected.emails.isEmpty
            || !detected.phones.isEmpty
            || (detected.postalAddress != nil)

        guard hasSomething else {
            return .result(value: "No contact details found.", dialog: "No contact details found.")
        }

        let id = try await ContactsService.save(contact: detected)
        return .result(value: "Contact saved (\(id)).", dialog: "Contact saved.")
    }
}

extension ExtractContactIntent {
    @MainActor
    static func runStandalone(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Provide text first." }
        let detected = ContactParser.detect(in: trimmed)
        let hasSomething = (detected.givenName?.isEmpty == false) || !detected.emails.isEmpty || !detected.phones.isEmpty || (detected.postalAddress != nil)
        guard hasSomething else { return "No contact details found." }
        let id = try await ContactsService.save(contact: detected)
        return "Contact saved (\(id))."
    }
}
