//
//  VisualScannerView.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//
//  Live camera scanner for barcodes/QR (primary, non-OCR) with optional text.
//  Wraps VisionKit.DataScannerViewController for SwiftUI.
//
//  Updated 18/09/2025:
//  • symbologies: [VNBarcodeSymbology]? (array) to match .barcode init
//  • recognizedDataTypes: Set<RecognizedDataType>
//  • RecognizedItem (top-level) in delegate
//  • CharacterSet.whitespacesAndNewlines (Foundation import)
//

import Foundation
import SwiftUI
import Vision
import VisionKit

// MARK: - Payload delivered to the host

enum VisualScanPayload: Equatable {
    case barcode(String)   // payload string from QR / barcode
    case text(String)

    var rawString: String {
        switch self {
        case .barcode(let s): return s
        case .text(let s): return s
        }
    }
}

// MARK: - SwiftUI screen

struct VisualScannerView: View {
    enum Mode: Equatable {
        /// Strictly barcodes/QR (non-OCR). Best performance.
        case barcodes(symbologies: [VNBarcodeSymbology]?)
        /// Barcodes + text (lets you capture addresses, phones, etc.).
        case barcodesAndText(symbologies: [VNBarcodeSymbology]?)
        /// Text only.
        case textOnly
    }

    var mode: Mode
    var recognizesMultipleItems: Bool
    var onRecognized: (VisualScanPayload) -> Void
    var onCancel: () -> Void

    @State private var scannerIsRunning = true
    @State private var warning: String?

    init(
        mode: Mode = .barcodesAndText(symbologies: nil),
        recognizesMultipleItems: Bool = false,
        onRecognized: @escaping (VisualScanPayload) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.recognizesMultipleItems = recognizesMultipleItems
        self.onRecognized = onRecognized
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScannerContainer(
                mode: mode,
                recognizesMultipleItems: recognizesMultipleItems,
                isRunning: $scannerIsRunning,
                onRecognized: { payload in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRecognized(payload)
                    if !recognizesMultipleItems { scannerIsRunning = false }
                },
                onUnavailable: { message in
                    warning = message
                }
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 12) {
                    Button {
                        scannerIsRunning = false
                        onCancel()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding()
            }

            if let warning {
                Text(warning)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable wrapper

private struct ScannerContainer: UIViewControllerRepresentable {
    let mode: VisualScannerView.Mode
    let recognizesMultipleItems: Bool
    @Binding var isRunning: Bool
    let onRecognized: (VisualScanPayload) -> Void
    let onUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types = recognizedTypes(for: mode) // Set<RecognizedDataType>

        let vc = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: .balanced,
            recognizesMultipleItems: recognizesMultipleItems,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true
        )
        vc.delegate = context.coordinator

        guard DataScannerViewController.isSupported else {
            onUnavailable("This device doesn’t support live scanning.")
            return vc
        }
        guard DataScannerViewController.isAvailable else {
            onUnavailable("Camera is not available (in use or restricted).")
            return vc
        }

        do {
            try vc.startScanning()
        } catch {
            onUnavailable("Couldn’t start scanning: \(error.localizedDescription)")
        }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if isRunning {
            if vc.isScanning == false {
                do { try vc.startScanning() } catch { /* transient */ }
            }
        } else {
            vc.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognized: onRecognized)
    }

    // Recognized types mapping (Set)
    private func recognizedTypes(for mode: VisualScannerView.Mode) -> Set<DataScannerViewController.RecognizedDataType> {
        switch mode {
        case .barcodes(let syms):
            let list = syms ?? VNBarcodeSymbology.defaultCommon
            return Set([.barcode(symbologies: list)])

        case .barcodesAndText(let syms):
            let list = syms ?? VNBarcodeSymbology.defaultCommon
            return Set([
                .barcode(symbologies: list),
                .text(languages: Locale.preferredLanguages) // non-optional [String]
            ])

        case .textOnly:
            return Set([.text(languages: Locale.preferredLanguages)])
        }
    }

    // Delegate
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: (VisualScanPayload) -> Void

        init(onRecognized: @escaping (VisualScanPayload) -> Void) {
            self.onRecognized = onRecognized
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .barcode(let b):
                if let s = b.payloadStringValue, !s.isEmpty {
                    onRecognized(.barcode(s))
                }
            case .text(let t):
                let s = t.transcript.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !s.isEmpty else { return }
                onRecognized(.text(s))
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Common symbologies (array to match API)

extension VNBarcodeSymbology {
    /// A sensible default set for general use.
    static var defaultCommon: [VNBarcodeSymbology] {
        [
            .qr,           // QR codes
            .aztec,        // Tickets/boarding
            .pdf417,       // Boarding passes, IDs
            .dataMatrix,   // Parcel labels
            .ean13, .ean8, // Retail
            .code128, .code39, .code93, // General purpose
            .itf14, .upce
        ]
    }
}
