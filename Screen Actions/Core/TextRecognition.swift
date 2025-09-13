//
//  TextRecognition.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import Vision
import ImageIO
import AppIntents
import CoreGraphics

enum TextExtractor {
    /// Extract plain text from an optional IntentFile (image) or return empty.
    static func from(imageFile: IntentFile?) throws -> String {
        guard let imageFile else { return "" }
        let data = imageFile.data
        let cgImage = try makeCGImage(from: data)
        return try recognizeText(from: cgImage)
    }

    private static func makeCGImage(from data: Data) throws -> CGImage {
        let cfData = data as CFData
        guard
            let src = CGImageSourceCreateWithData(cfData, nil),
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            throw NSError(domain: "TextExtractor", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Could not decode image data."])
        }
        return img
    }

    static func recognizeText(from image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        let strings: [String] = request.results?.compactMap { obs in
            obs.topCandidates(1).first?.string
        } ?? []

        return strings.joined(separator: "\n")
    }
}
