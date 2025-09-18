//
//  CSVDocument.swift
//  Screen Actions
//
//  Created by Conor on 18/09/2025.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// Simple FileDocument so we can show the system "Save to Files…" UI.
public struct CSVDocument: FileDocument {
    public static var readableContentTypes: [UTType] = [
        .commaSeparatedText, .plainText, .utf8PlainText, .text
    ]

    public var text: String

    public init(text: String) {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            self.text = s
        } else {
            self.text = ""
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}
