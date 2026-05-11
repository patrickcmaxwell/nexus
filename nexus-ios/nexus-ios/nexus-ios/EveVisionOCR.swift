// EveVisionOCR.swift
// On-device OCR via the Vision framework. Used by the existing photo-attach
// flow to enrich the message body with any text the camera captured before
// it ships to /api/eve/local. The vision model still runs server-side
// (llava) — Vision OCR just gives Eve the parsed text alongside the image
// so she can answer "what's in this whiteboard / receipt / sign" without
// the model having to do letter recognition itself.
//
// All processing is local. No image leaves the device unless Eve calls
// askEveLocalWithImages.

import Foundation
import Vision
import UIKit

enum EveVisionOCR {
    /// Returns the recognized text, top-to-bottom. Best-effort; returns an
    /// empty string when the image has no text or recognition fails.
    static func recognizeText(in imageData: Data) async -> String {
        guard let image = UIImage(data: imageData)?.cgImage else { return "" }

        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: ""); return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            // Accuracy over speed — these are user-attached photos, latency
            // is dominated by the server round-trip anyway.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch {
                    NSLog("[nexus-ocr] Vision error: %@", error.localizedDescription)
                    cont.resume(returning: "")
                }
            }
        }
    }
}
