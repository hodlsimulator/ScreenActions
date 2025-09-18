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
//  • Faster defaults for barcodes (quality = .fast)
//  • Region of Interest (ROI) to reduce work per frame
//  • Auto-capture barcodes (no tap required)
//  • Limit text languages to top locales
//  • Correct initializer parameter order
//  • @MainActor isolation for UI calls
//  • Removed NotificationCenter orientation observer (no Sendable/deinit issues)
//

@preconcurrency import ObjectiveC
import Foundation
import SwiftUI
import Vision
import VisionKit
import UIKit

// MARK: - Payload delivered to the host

enum VisualScanPayload: Equatable {
    case barcode(String)     // payload string from QR / barcode
    case text(String)

    var rawString: String {
        switch self {
        case .barcode(let s): return s
        case .text(let s):    return s
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
            // Visual ROI overlay to guide the user (matches regionOfInterest)
            .overlay(alignment: .center) {
                GeometryReader { geo in
                    let roi = ROIComputer.roi(in: geo.size, for: mode)
                    ScanOverlay(roi: roi)
                        .allowsHitTesting(false)
                }
            }
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

@MainActor
private struct ScannerContainer: UIViewControllerRepresentable {
    let mode: VisualScannerView.Mode
    let recognizesMultipleItems: Bool
    @Binding var isRunning: Bool
    let onRecognized: (VisualScanPayload) -> Void
    let onUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types = recognizedTypes(for: mode)
        let quality = qualityLevel(for: mode)

        // NOTE: argument order is strict on current SDKs.
        let vc = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: quality,
            recognizesMultipleItems: recognizesMultipleItems,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator

        // Availability checks
        guard DataScannerViewController.isSupported else {
            onUnavailable("This device doesn’t support live scanning.")
            return vc
        }
        guard DataScannerViewController.isAvailable else {
            onUnavailable("Camera is not available (in use or restricted).")
            return vc
        }

        // Set Region Of Interest (ROI)
        setROI(on: vc)

        // Keep a weak link for later ROI updates
        context.coordinator.attach(to: vc, mode: mode)

        do {
            try vc.startScanning()
        } catch {
            onUnavailable("Couldn’t start scanning: \(error.localizedDescription)")
        }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        // SwiftUI calls this on size/orientation changes — refresh ROI here.
        context.coordinator.updateROIIfNeeded()

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

    // MARK: - Config helpers

    private func recognizedTypes(for mode: VisualScannerView.Mode) -> Set<DataScannerViewController.RecognizedDataType> {
        switch mode {
        case .barcodes(let syms):
            let list = syms ?? VNBarcodeSymbology.defaultCommon
            return Set([.barcode(symbologies: list)])

        case .barcodesAndText(let syms):
            let list = syms ?? VNBarcodeSymbology.defaultCommon
            let langs = Array(Locale.preferredLanguages.prefix(2)) // keep small for perf
            return Set([ .barcode(symbologies: list),
                         .text(languages: langs) ])

        case .textOnly:
            let langs = Array(Locale.preferredLanguages.prefix(2))
            return Set([ .text(languages: langs) ])
        }
    }

    private func qualityLevel(for mode: VisualScannerView.Mode) -> DataScannerViewController.QualityLevel {
        switch mode {
        case .barcodes:
            return .fast        // prioritise speed for QR/barcodes
        case .barcodesAndText:
            return .balanced    // compromise
        case .textOnly:
            return .balanced
        }
    }

    private func setROI(on vc: DataScannerViewController) {
        let bounds = vc.view.bounds
        let roi = ROIComputer.roi(in: bounds.size, for: mode)
        vc.regionOfInterest = roi
    }

    // MARK: - Delegate / Coordinator

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onRecognized: (VisualScanPayload) -> Void
        private weak var vcRef: DataScannerViewController?
        private var mode: VisualScannerView.Mode = .barcodes(symbologies: nil)
        private var hasDelivered = false
        private var lastAppliedBounds: CGRect = .zero

        init(onRecognized: @escaping (VisualScanPayload) -> Void) {
            self.onRecognized = onRecognized
            super.init()
        }

        func attach(to vc: DataScannerViewController, mode: VisualScannerView.Mode) {
            self.vcRef = vc
            self.mode = mode
            self.lastAppliedBounds = vc.view.bounds
        }

        func updateROIIfNeeded(force: Bool = false) {
            guard let vc = vcRef else { return }
            let current = vc.view.bounds
            if force || current.size != lastAppliedBounds.size {
                let roi = ROIComputer.roi(in: current.size, for: mode)
                vc.regionOfInterest = roi
                lastAppliedBounds = current
            }
        }

        // Auto-capture: when VisionKit adds items, immediately act on a barcode.
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard hasDelivered == false else { return }

            for item in addedItems {
                if case .barcode(let b) = item, let s = b.payloadStringValue, !s.isEmpty {
                    hasDelivered = true
                    onRecognized(.barcode(s))
                    return
                }
            }

            // If text-only mode and not multiple selection, capture first decent line.
            if case .textOnly = mode, hasDelivered == false {
                for item in addedItems {
                    if case .text(let t) = item {
                        let s = t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty {
                            hasDelivered = true
                            onRecognized(.text(s))
                            return
                        }
                    }
                }
            }
        }

        // Fallback: still allow manual tap if auto-capture hasn't fired (e.g. user wants text).
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard hasDelivered == false else { return }

            switch item {
            case .barcode(let b):
                if let s = b.payloadStringValue, !s.isEmpty {
                    hasDelivered = true
                    onRecognized(.barcode(s))
                }
            case .text(let t):
                let s = t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return }
                hasDelivered = true
                onRecognized(.text(s))
            @unknown default:
                break
            }
        }
    }
}

// MARK: - ROI computer + overlay

private enum ROIComputer {
    /// Compute a centred Region-Of-Interest that suits the current mode.
    /// Result is in **view coordinates** (same space as `regionOfInterest`).
    static func roi(in size: CGSize, for mode: VisualScannerView.Mode) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)

        switch mode {
        case .barcodes:
            // A wide band for 1D codes & QR — ~86% width, ~24% height.
            let w = bounds.width * 0.86
            let h = max(120, bounds.height * 0.24)
            let x = (bounds.width  - w) / 2
            let y = (bounds.height - h) / 2
            return CGRect(x: x, y: y, width: w, height: h)

        case .barcodesAndText:
            // Slightly taller window to catch text near codes.
            let w = bounds.width * 0.86
            let h = max(160, bounds.height * 0.34)
            let x = (bounds.width  - w) / 2
            let y = (bounds.height - h) / 2
            return CGRect(x: x, y: y, width: w, height: h)

        case .textOnly:
            // Almost full screen; keep a small inset for comfort.
            return bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.06)
        }
    }
}

/// A semi-transparent mask with a punched-out ROI and a subtle border & corner marks.
private struct ScanOverlay: View {
    let roi: CGRect

    var body: some View {
        Canvas { ctx, size in
            let full = Path(CGRect(origin: .zero, size: size))
            let hole = Path(roi)
            var mask = full
            mask.addPath(hole)
            ctx.fill(mask, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))

            // Border
            ctx.stroke(hole, with: .color(.white.opacity(0.9)), lineWidth: 2)

            // Corners
            let corner: CGFloat = 18
            let line: CGFloat = 24

            func drawCorner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                var p = Path()
                p.move(to: CGPoint(x: x, y: y + dy*line))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + dx*line, y: y))
                ctx.stroke(p, with: .color(.white.opacity(0.9)), lineWidth: 4)
            }

            drawCorner(roi.minX, roi.minY + corner,  1,  0) // TL
            drawCorner(roi.maxX, roi.minY + corner, -1,  0) // TR
            drawCorner(roi.minX, roi.maxY - corner,  1,  0) // BL
            drawCorner(roi.maxX, roi.maxY - corner, -1,  0) // BR
        }
    }
}

// MARK: - Common symbologies (array to match API)

extension VNBarcodeSymbology {
    /// A sensible default set for general use.
    static var defaultCommon: [VNBarcodeSymbology] {
        [
            .qr,          // QR codes
            .aztec,       // Tickets/boarding
            .pdf417,      // Boarding passes, IDs
            .dataMatrix,  // Parcel labels
            .ean13, .ean8, // Retail
            .code128, .code39, .code93, // General purpose
            .itf14, .upce
        ]
    }
}
