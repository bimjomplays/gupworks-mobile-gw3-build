import AVFoundation
import SwiftUI
import UIKit

/// The camera on the pairing screen: a live preview that reports every QR code it reads. Nothing is recorded or saved.
final class QRScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    enum StartResult { case running, denied, noCamera }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    let previewView = PreviewView()
    /// called on the main queue with the text of each QR code in view (repeats while the code stays in view)
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.gupworks3.phone.camera")
    private var configured = false

    override init() {
        super.init()
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill
        previewView.backgroundColor = .black
    }

    func start(_ done: @escaping (StartResult) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run(done)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.run(done) : done(.denied) }
            }
        default:
            done(.denied)
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func run(_ done: @escaping (StartResult) -> Void) {
        queue.async {
            if !self.configured, !self.configure() {
                return DispatchQueue.main.async { done(.noCamera) }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { done(.running) }
        }
    }

    /// on the camera queue
    private func configure() -> Bool {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else { return false }
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: .main)
        if cam.isFocusModeSupported(.continuousAutoFocus), (try? cam.lockForConfiguration()) != nil {
            cam.focusMode = .continuousAutoFocus
            if cam.isAutoFocusRangeRestrictionSupported { cam.autoFocusRangeRestriction = .near }
            cam.unlockForConfiguration()
        }
        configured = true
        return true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects where code.type == .qr {
            if let text = code.stringValue { onCode?(text) }
        }
    }
}

/// The scanner as a SwiftUI view. `state` says whether the camera runs (the simulator has none).
struct QRCameraView: UIViewRepresentable {
    var onCode: (String) -> Void
    var onState: (QRScanner.StartResult) -> Void

    func makeCoordinator() -> QRScanner { QRScanner() }

    func makeUIView(context: Context) -> QRScanner.PreviewView {
        let scanner = context.coordinator
        scanner.onCode = onCode
        scanner.start(onState)
        return scanner.previewView
    }

    func updateUIView(_ view: QRScanner.PreviewView, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ view: QRScanner.PreviewView, coordinator: QRScanner) {
        coordinator.stop()
    }
}
