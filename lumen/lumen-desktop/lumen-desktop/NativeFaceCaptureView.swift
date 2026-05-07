import SwiftUI
import Combine
import AVFoundation
import Vision
import AppKit

// Native face capture for the Lumen entry screen. Replaces the embedded
// /auth/face WebView with a SwiftUI + AVFoundation pipeline:
//
//   1. Live camera preview via AVCaptureVideoPreviewLayer
//   2. Vision framework runs a lightweight face-rectangle detector on
//      each frame purely as a "user is in position" signal — no descriptor
//      compute, no model porting (face-api descriptors are still computed
//      server-side for compatibility with stored references).
//   3. After the face is held steadily for ~600ms we capture a still and
//      POST it to /api/security/face/match (server runs face-api via
//      tfjs-node and returns a session cookie on match).
//
// Why this design: keeps stored descriptors in face-api format (no
// re-enrollment needed), but the user-facing UI is 100% native — no
// WebView, no scrolling, no duplicate chrome.

struct NativeFaceCaptureView: View {
    let baseURL: String
    let onAuthenticated: (String) -> Void

    @StateObject private var session = FaceCaptureSession()
    @State private var stage: Stage = .starting
    @State private var statusMsg: String = "Starting camera…"
    @State private var failMsg: String = ""

    enum Stage { case starting, ready, capturing, uploading, success, fail, no_camera }

    var body: some View {
        ZStack {
            // Camera preview as the base layer
            CameraPreview(session: session.captureSession)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(stage == .success ? Color.greenAccent : (stage == .fail ? Color.redAccent : Color.cyanAccent.opacity(0.35)), lineWidth: 1.5)
                )
                .overlay(faceLockBadge, alignment: .topTrailing)
                .overlay(scanOverlay)
                .overlay(resultOverlay)

            if stage == .no_camera {
                noCameraView
            }
        }
        .frame(height: 360)
        .onAppear {
            session.onFrameCaptured = handleFrameCaptured
            session.onLockHeld = handleLockHeld
            session.onError = { msg in
                stage = .no_camera
                failMsg = msg
            }
            Task {
                let started = await session.start()
                stage = started ? .ready : .no_camera
                statusMsg = started ? "Look at the camera" : "Camera unavailable"
            }
        }
        .onDisappear {
            session.stop()
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var faceLockBadge: some View {
        if stage == .ready && session.faceDetected {
            HStack(spacing: 5) {
                Circle().fill(Color.greenAccent).frame(width: 5, height: 5)
                Text("FACE LOCK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color.greenAccent.opacity(0.9))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.45))
            .padding(10)
        }
    }

    @ViewBuilder
    private var scanOverlay: some View {
        if stage == .capturing || stage == .uploading {
            ZStack {
                Color.black.opacity(0.35)
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(.cyanAccent)
                    Text(stage == .capturing ? "CAPTURING…" : "VERIFYING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if stage == .success {
            ZStack {
                Color.greenAccent.opacity(0.18)
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(.greenAccent)
                    Text("ACCESS GRANTED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.greenAccent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if stage == .fail {
            ZStack {
                Color.redAccent.opacity(0.18)
                VStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(.redAccent)
                    Text(failMsg.isEmpty ? "FACE NOT RECOGNIZED" : failMsg.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.redAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("TRY AGAIN") {
                        stage = .ready
                        failMsg = ""
                        session.resetLockTimer()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.cyanAccent)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.cyanAccent.opacity(0.5), lineWidth: 1)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var noCameraView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.redAccent.opacity(0.4), lineWidth: 1)
                )
            VStack(spacing: 8) {
                Image(systemName: "video.slash")
                    .font(.system(size: 28))
                    .foregroundColor(Color.redAccent.opacity(0.7))
                Text(failMsg.isEmpty ? "CAMERA UNAVAILABLE" : failMsg.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Capture pipeline

    private func handleLockHeld() {
        guard stage == .ready else { return }
        stage = .capturing
        session.captureStill { jpegData in
            Task {
                if let jpegData {
                    await uploadAndMatch(jpegData: jpegData)
                } else {
                    await MainActor.run {
                        failMsg = "CAPTURE FAILED"
                        stage = .fail
                    }
                }
            }
        }
    }

    private func handleFrameCaptured() {
        // Hook for future per-frame UI (confidence meter etc); intentionally
        // empty for now to keep the render path quiet.
    }

    @MainActor
    private func uploadAndMatch(jpegData: Data) async {
        stage = .uploading
        let dataUrl = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        guard let url = URL(string: "\(baseURL)/api/security/face/match") else {
            failMsg = "INVALID HOST"
            stage = .fail
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Lumen-Client")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["imageDataUrl": dataUrl])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if http?.statusCode == 200,
               let sessionId = (json?["sessionId"] as? String) ?? extractCookie(from: http),
               !sessionId.isEmpty {
                stage = .success
                try? await Task.sleep(nanoseconds: 500_000_000)
                onAuthenticated(sessionId)
                return
            }
            let code = json?["error"] as? String ?? ""
            failMsg = friendlyError(for: code, status: http?.statusCode ?? 0)
            stage = .fail
        } catch {
            failMsg = "CONNECTION ERROR"
            stage = .fail
        }
    }

    private func extractCookie(from http: HTTPURLResponse?) -> String? {
        guard let header = http?.value(forHTTPHeaderField: "Set-Cookie") else { return nil }
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "nx_session" { return kv[1] }
        }
        return nil
    }

    private func friendlyError(for code: String, status: Int) -> String {
        switch code {
        case "NO_FACE_DETECTED": return "NO FACE DETECTED"
        case "FACE_MISMATCH":    return "FACE NOT RECOGNIZED"
        case "NO_REFERENCE":     return "NO ENROLLED REFERENCE"
        default:                 return status >= 500 ? "SERVER ERROR" : "VERIFICATION FAILED"
        }
    }
}

// MARK: - Capture session driver

@MainActor
final class FaceCaptureSession: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    @Published var faceDetected = false

    var onFrameCaptured: (() -> Void)?
    var onLockHeld: (() -> Void)?
    var onError: ((String) -> Void)?

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "lumen.face.capture")
    private var lockStreak = 0
    private let lockStreakNeeded = 4   // ~4 frames at 30fps ≈ 130ms held → trigger
    private var lockTriggered = false
    private var photoDelegate: PhotoCaptureDelegate?

    func start() async -> Bool {
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        if auth == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { onError?("Camera permission denied"); return false }
        } else if auth != .authorized {
            onError?("Camera permission denied")
            return false
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video) else {
            onError?("No camera found")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .high
            if captureSession.canAddInput(input) { captureSession.addInput(input) }

            if captureSession.canAddOutput(videoDataOutput) {
                videoDataOutput.setSampleBufferDelegate(self, queue: queue)
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                captureSession.addOutput(videoDataOutput)
            }
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            captureSession.commitConfiguration()

            // startRunning is blocking; off the main actor
            await Task.detached { [captureSession] in
                captureSession.startRunning()
            }.value
            return true
        } catch {
            onError?("Failed to open camera: \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        Task.detached { [captureSession] in
            captureSession.stopRunning()
        }
    }

    func resetLockTimer() {
        lockStreak = 0
        lockTriggered = false
    }

    func captureStill(completion: @escaping (Data?) -> Void) {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = false
        let delegate = PhotoCaptureDelegate { [weak self] data in
            self?.photoDelegate = nil
            completion(data)
        }
        photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

extension FaceCaptureSession: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Lightweight face-rectangle detection — no descriptor compute, just
        // a "did we find a face in this frame" signal to drive the lock timer.
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self else { return }
            let count = (req.results as? [VNFaceObservation])?.count ?? 0
            Task { @MainActor in
                self.handleFaceCount(count)
            }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }

    @MainActor
    private func handleFaceCount(_ count: Int) {
        let detected = count > 0
        if detected != faceDetected { faceDetected = detected }
        guard !lockTriggered else { return }
        if detected {
            lockStreak += 1
            if lockStreak >= lockStreakNeeded {
                lockTriggered = true
                onLockHeld?()
            }
        } else {
            lockStreak = 0
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (Data?) -> Void
    init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil)
            return
        }
        // Convert HEIC/AVCapture format to JPEG via NSImage roundtrip so the
        // server sees a familiar image type. Quality 0.85 keeps the upload
        // small (~80KB at 1280x720) without hurting recognition.
        if let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            completion(jpeg)
        } else {
            completion(data)
        }
    }
}

// MARK: - Camera preview

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = PreviewView()
        view.wantsLayer = true
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        // Mirror so the camera feels like a mirror, not a video call
        view.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        view.previewLayer.connection?.isVideoMirrored = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.addSublayer(previewLayer)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}

// MARK: - Color shorthand (mirrors AuthWebView.swift)

private extension Color {
    static let cyanAccent  = Color(.sRGB, red: 0.40, green: 0.85, blue: 1.00, opacity: 1)
    static let greenAccent = Color(.sRGB, red: 0.30, green: 0.92, blue: 0.55, opacity: 1)
    static let redAccent   = Color(.sRGB, red: 1.00, green: 0.42, blue: 0.42, opacity: 1)
}
