// NativeFaceCaptureView.swift
// Native iOS face capture — no WebView. Mirrors Lumen Desktop's
// NativeFaceCaptureView (AVFoundation + Vision) but with UIKit/iOS APIs.
//
// Flow:
//   1. AVCaptureSession on the front camera, fed into a preview layer
//   2. Vision framework's lightweight face-rectangle detector ("are they
//      looking at the camera?") on every frame
//   3. After a face has been detected for ~600ms, capture a still photo
//   4. POST the JPEG (as a data URL) to /api/security/face/match — server
//      runs face-api.js descriptor extraction and matches against stored
//      humans. On success, returns the session id we use to authenticate.
//
// Why this instead of the WebView at /auth/face: the iOS Simulator has
// no `getUserMedia` support reliable enough for face-api in a WKWebView,
// and the WebView path adds 5+MB of JS model loading on every cold start.
// Running everything natively means face capture works the same way the
// desktop app does, and the simulator's camera passthrough (Simulator
// menu → Device → Connect Hardware → Camera) makes sim testing real.

import SwiftUI
import Combine
import AVFoundation
import Vision
import UIKit

// MARK: - Public sheet

struct NativeFaceCaptureSheet: View {
    let onAuthenticated: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("FACE AUTHENTICATION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2).foregroundColor(.indigo)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)

                NativeFaceCaptureView { sid in
                    onAuthenticated(sid)
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Capture view (SwiftUI shell)

struct NativeFaceCaptureView: View {
    let onAuthenticated: (String) -> Void
    @StateObject private var capture = FaceCaptureSession()
    @State private var stage: Stage = .starting
    @State private var statusMsg: String = "Starting camera…"
    @State private var failMsg: String = ""

    enum Stage { case starting, ready, capturing, uploading, success, fail, no_camera }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if stage == .no_camera {
                    noCameraOverlay
                } else {
                    CameraPreview(session: capture.captureSession)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(borderColor, lineWidth: 1.5)
                        )
                        .overlay(scanOverlay)
                        .overlay(faceLockBadge, alignment: .topTrailing)
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
            .padding(.horizontal, 18)

            Text(statusMsg)
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(stage == .fail ? .red.opacity(0.8) : .white.opacity(0.7))
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)

            if !failMsg.isEmpty {
                Text(failMsg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.6))
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .onAppear {
            capture.onLockHeld = { jpeg in Task { await uploadCapture(jpeg) } }
            capture.onError = { msg in
                stage = .no_camera
                failMsg = msg
            }
            Task {
                let ok = await capture.start()
                stage = ok ? .ready : .no_camera
                statusMsg = ok ? "Look at the camera" : "Camera unavailable"
            }
        }
        .onDisappear { capture.stop() }
    }

    // MARK: Subviews

    private var borderColor: Color {
        switch stage {
        case .success: return .green
        case .fail:    return .red
        default:       return .indigo.opacity(0.45)
        }
    }

    @ViewBuilder
    private var faceLockBadge: some View {
        if stage == .ready && capture.faceDetected {
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text("FACE LOCK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            .padding(10)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var scanOverlay: some View {
        if stage == .capturing || stage == .uploading {
            ZStack {
                Color.black.opacity(0.35)
                VStack(spacing: 10) {
                    ProgressView().tint(.indigo)
                    Text(stage == .uploading ? "MATCHING…" : "CAPTURING…")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var noCameraOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 36))
                .foregroundColor(.gray)
            Text("Camera unavailable")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Text("On the simulator, enable the host camera:\nSimulator menu → Device → Connect Hardware → FaceTime HD Camera")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Upload

    private func uploadCapture(_ jpeg: Data) async {
        await MainActor.run { stage = .uploading; statusMsg = "Matching against enrolled faces…" }
        do {
            let sid = try await NexusAPIClient.shared.authenticateWithFace(jpeg: jpeg)
            await MainActor.run {
                stage = .success
                statusMsg = "Authenticated"
            }
            // Brief pause so user sees the green ring before dismiss.
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run { onAuthenticated(sid) }
        } catch let NexusAPIClient.APIError.requestFailed(reason) {
            await MainActor.run {
                stage = .fail
                statusMsg = "Match failed"
                failMsg = reason
            }
            // Allow the user to retry — re-arm the lock-held trigger after a moment.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                stage = .ready
                statusMsg = "Try again — look directly at the camera"
                capture.armNextCapture()
            }
        } catch {
            await MainActor.run {
                stage = .fail
                statusMsg = "Network error"
                failMsg = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                stage = .ready
                statusMsg = "Try again"
                capture.armNextCapture()
            }
        }
    }
}

// MARK: - Camera preview (UIKit bridge)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Capture session driver

@MainActor
final class FaceCaptureSession: NSObject, ObservableObject,
                                AVCaptureVideoDataOutputSampleBufferDelegate,
                                AVCapturePhotoCaptureDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoQueue = DispatchQueue(label: "io.talkcircles.nexus.face.video")

    @Published var faceDetected = false
    private var lockStartedAt: Date?
    private var didFireLock = false

    var onLockHeld: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
    }

    /// Boots the capture session. Returns true on success. Failures land in
    /// `onError` so the SwiftUI shell can show a friendly "no camera" state.
    func start() async -> Bool {
        let granted = await requestCameraPermission()
        guard granted else {
            onError?("Camera permission denied")
            return false
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Front camera — match the desktop's enrollment angle.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            captureSession.commitConfiguration()
            onError?("No camera found. On the simulator, connect the host camera via the Device menu.")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) { captureSession.addInput(input) }
            else { throw NSError(domain: "FaceCapture", code: 1) }
        } catch {
            captureSession.commitConfiguration()
            onError?("Couldn't open camera: \(error.localizedDescription)")
            return false
        }

        // Live frame output for face-detection scanning.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        // Still photo output for the high-quality JPEG we send to /face/match.
        if captureSession.canAddOutput(photoOutput) { captureSession.addOutput(photoOutput) }

        // Pin orientation to portrait + selfie mirror on the actual capture
        // connections. Without this, the device delivers buffers in its
        // native landscape-right layout and the Vision face detector has to
        // guess rotation, which it gets wrong often enough to look broken.
        // Configured BEFORE commitConfiguration so the change takes.
        if let videoConn = videoOutput.connection(with: .video) {
            if videoConn.isVideoOrientationSupported {
                videoConn.videoOrientation = .portrait
            }
            if videoConn.isVideoMirroringSupported {
                videoConn.automaticallyAdjustsVideoMirroring = false
                videoConn.isVideoMirrored = true
            }
        }
        if let photoConn = photoOutput.connection(with: .video) {
            if photoConn.isVideoOrientationSupported {
                photoConn.videoOrientation = .portrait
            }
            if photoConn.isVideoMirroringSupported {
                photoConn.automaticallyAdjustsVideoMirroring = false
                photoConn.isVideoMirrored = true
            }
        }

        captureSession.commitConfiguration()

        // Run startRunning off the main thread — Apple flags it as blocking
        // on iOS 16+ if called on .main and prints a runtime warning.
        await Task.detached { [captureSession] in captureSession.startRunning() }.value

        return true
    }

    func stop() {
        Task.detached { [captureSession] in captureSession.stopRunning() }
    }

    /// Reset the lock-held state so the user can retry after a failed match.
    func armNextCapture() {
        lockStartedAt = nil
        didFireLock = false
    }

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
        default: return false
        }
    }

    // MARK: - Per-frame face detection

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self else { return }
            let detected = !((req.results as? [VNFaceObservation])?.isEmpty ?? true)
            Task { @MainActor in self.handleDetection(detected) }
        }
        // Connection is now pinned to .portrait + mirrored, so the buffer
        // arrives upright. `.up` is the matching Vision hint. Previously
        // `.leftMirrored` papered over a missing connection-orientation
        // setup and broke on some device/iOS combos.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }

    private func handleDetection(_ detected: Bool) {
        faceDetected = detected
        guard !didFireLock else { return }

        if detected {
            if lockStartedAt == nil { lockStartedAt = Date() }
            else if let started = lockStartedAt, Date().timeIntervalSince(started) >= 0.6 {
                didFireLock = true
                snapStill()
            }
        } else {
            lockStartedAt = nil
        }
    }

    // MARK: - Still capture

    private func snapStill() {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = false  // 1080p face is plenty
        // Front cam is auto-mirrored on capture — server handles either
        // orientation since face-api works on raw pixels.
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.onError?(error.localizedDescription) }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.onError?("Couldn't read captured photo") }
            return
        }
        // file representation is HEIC by default; we want JPEG. Convert via UIImage.
        let jpeg: Data
        if let uiImage = UIImage(data: data),
           let j = uiImage.jpegData(compressionQuality: 0.85) {
            jpeg = j
        } else {
            jpeg = data
        }
        Task { @MainActor in self.onLockHeld?(jpeg) }
    }
}
