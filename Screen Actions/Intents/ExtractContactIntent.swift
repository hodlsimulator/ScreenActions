//
//  ExtractContactIntent.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  iOS 26: supports batch contact capture from a photographed table.
//

import AppIntents
import Contacts

struct ExtractContactIntent: AppIntent {
    static var title: LocalizedStringResource { "Extract Contact" }
    static var description: IntentDescription {
        IntentDescription("Parses contact details (name, email, phone, address) from text or an image and saves new contact(s).")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Image")
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Text path
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let detected = ContactParser.detect(in: t)
            let ok = hasUsefulFields(detected)   // evaluate before returning (avoids autoclosure isolation)
            if !ok {
                return .result(value: "No contact details found.", dialog: "No contact details found.")
            }
            let id = try await ContactsService.save(contact: detected)
            return .result(value: "Contact saved (\(id)).", dialog: "Contact saved.")
        }

        // Image path — iOS 26 multi-row table support; fallback to OCR→ContactParser.
        if let data = image?.data {
            if #available(iOS 26, *) {
                var _hint: VisionDocumentReader.SmudgeHint?
                let list = try await VisionDocumentReader.contacts(from: data, smudgeHint: &_hint)
                if !list.isEmpty {
                    var saved = 0
                    for c in list {
                        let ok = hasUsefulFields(c)    // compute explicitly on main actor
                        if ok {
                            _ = try await ContactsService.save(contact: c)
                            saved += 1
                        }
                    }
                    let msg = saved == 1 ? "Saved 1 contact." : "Saved \(saved) contacts."
                    return .result(value: msg, dialog: "Contacts saved.")
                }
            }
            // Fallback: OCR then parse a single contact.
            let textOCR = try TextExtractor.from(imageFile: image)
            if textOCR.isEmpty {
                return .result(value: "No contact details found.", dialog: "No contact details found.")
            }
            let detected = ContactParser.detect(in: textOCR)
            let ok = hasUsefulFields(detected)
            if !ok {
                return .result(value: "No contact details found.", dialog: "No contact details found.")
            }
            let id = try await ContactsService.save(contact: detected)
            return .result(value: "Contact saved (\(id)).", dialog: "Contact saved.")
        }

        throw $text.needsValueError("Provide text or an image with text.")
    }

    // Marked @MainActor to match perform() and avoid cross-actor property access for CNPostalAddress.
    @MainActor
    private func hasUsefulFields(_ c: DetectedContact) -> Bool {
        (c.givenName?.isEmpty == false) ||
        (c.familyName?.isEmpty == false) ||
        !c.emails.isEmpty ||
        !c.phones.isEmpty ||
        (c.postalAddress != nil)
    }
}
