//
//  CameraView.swift
//  retrytech_plugin
//
//  Created by Aniket Vaddoriya on 19/04/25.
//

import Foundation
import AVKit

class CameraView: NSObject, FlutterPlatformView {
    private let _view: UIView
    private let deviceWidth = UIScreen.main.bounds.size.width
    private var isBackCamera = true
    private var isTouchOn = false
    private var isRecording = false
    private var videoURLArray: [URL] = []
    private let cameraManager = CameraManager()

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, binaryMessenger: FlutterBinaryMessenger?, channel: FlutterMethodChannel) {
        self._view = UIView(frame: CGRect(x: 0, y: 0, width: deviceWidth, height: deviceWidth * 1.77))
        super.init()
        setupChannel(channel)
    }

    func view() -> UIView {
        return _view
    }

    deinit {
        cameraManager.stopSession()
    }

    private func setupChannel(_ channel: FlutterMethodChannel) {
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            print("Mothod name: \(call.method)")
            switch call.method {
            case "init":
                self.setupView()
            case "toggle":
                self.toggleCamera()
            case "flash":
                self.toggleFlash()
            case "start":
                self.startRecording()
            case "pause":
                self.stopRecording(result: result)
            case "resume":
                self.startRecording()
            case "stop":
                self.stopRecording(isVideoCompleted: true, result: result)
            case "dispose":
                self.cameraManager.stopSession()
                result(true)
            case "capture_image":
                self.captureImage(result: result)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func setupView() {
        _view.backgroundColor = .black
#if !targetEnvironment(simulator)
        cameraManager.checkPermissions { status in
            if status {
                DispatchQueue.main.async {
                    self.addCameraPreview()
                }
            }
        }
#endif

    }


    private func addCameraPreview() {
        cameraManager.startSession()
        if let layer = cameraManager.previewLayer {
            layer.frame = UIScreen.main.bounds
            _view.layer.addSublayer(layer)
        }
    }

    private func toggleCamera() {
        cameraManager.switchCamera()
    }

    private func captureImage(result: FlutterResult? = nil){

        cameraManager.capturePhoto { image in
            guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("Directory not found")
                return
            }
            if let data = image?.jpegData(compressionQuality: 1) {
                print("Captured")
                let outputURL = documentDirectory.appendingPathComponent("captured.jpg")
                try? FileManager.default.removeItem(at: outputURL) // Clean existing file if needed
                do {
                    try data.write(to: outputURL)
                    result?(outputURL.path)
                } catch {
                    print(error.localizedDescription)
                }
            } else {
                print("No image-data found in content.")
            }
        }
    }

    private func toggleFlash() {
        guard isBackCamera else {
            isTouchOn = false
            return
        }
        isTouchOn.toggle()
        toggleTorch(on: isTouchOn)
    }

    private func toggleTorch(on: Bool) {
        cameraManager.setTorch(active: on)
    }

    private func startRecording() {
        isRecording = true
        cameraManager.startRecording()
        if isBackCamera && isTouchOn {
            DispatchQueue.main.async {
                self.toggleTorch(on: true)
            }
        }
    }

    private func stopRecording(isVideoCompleted: Bool = false, result: FlutterResult? = nil) {
        if isVideoCompleted && !isRecording {
            mergeAndReturnFinalVideo(result: result)
            return
        }

        cameraManager.stopRecording { [weak self] videoURL in
            guard let self = self else { return }
            self.isRecording = false

            if let videoURL = videoURL {
                self.videoURLArray.append(videoURL)
                if isVideoCompleted &&  result != nil {
                    self.mergeAndReturnFinalVideo(result: result)
                } else {
                    result?(nil)
                }
            } else {
                print("Stop error: Video Record")
            }
        }
    }

    private func mergeAndReturnFinalVideo(result: FlutterResult?) {
        AVMutableComposition().mergeVideo(self.videoURLArray) { url, error in
            self.videoURLArray.removeAll()
            result?(url?.path ?? "")
        }
    }

    // Unused helper (optional)
    private func videoQueue() -> DispatchQueue {
        return DispatchQueue.main
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        return .portrait
    }
}



import Flutter
import UIKit

class CameraViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    private var channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger, channel: FlutterMethodChannel) {
        self.messenger = messenger
        self.channel = channel
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return CameraView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger,
            channel: channel
        )
    }
}


extension AVMutableComposition {

    func mergeVideo(_ urls: [URL], completion: @escaping (_ url: URL?, _ error: Error?) -> Void) {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(nil, NSError(domain: "AVMutableComposition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access document directory"]))
            return
        }

        let outputURL = documentDirectory.appendingPathComponent("finalvideo.mp4")
        try? FileManager.default.removeItem(at: outputURL) // Clean existing file if needed

        let maxRenderSize = CGSize(width: 1280, height: 720)
        var renderSize = CGSize.zero
        var currentTime = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for (index, url) in urls.enumerated() {
            let asset = AVAsset(url: url)
            guard let assetTrack = asset.tracks(withMediaType: .video).first else {
                completion(nil, NSError(domain: "AVMutableComposition", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing video track in asset"]))
                return
            }

            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            let (instruction, isPortrait) = AVMutableComposition.instruction(for: assetTrack, asset: asset, at: currentTime, duration: asset.duration, maxRenderSize: maxRenderSize)
            instructions.append(instruction)

            if index == 0 {
                renderSize = isPortrait
                    ? CGSize(width: maxRenderSize.height, height: maxRenderSize.width)
                    : maxRenderSize
            }

            do {
                try insertTimeRange(timeRange, of: asset, at: currentTime)
                currentTime = CMTimeAdd(currentTime, asset.duration)
            } catch {
                completion(nil, error)
                return
            }
        }

        // Configure video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize

        // Export session
        guard let exporter = AVAssetExportSession(asset: self, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil, NSError(domain: "AVMutableComposition", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create exporter"]))
            return
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                completion(exporter.status == .completed ? outputURL : nil, exporter.error)
            }
        }
    }

    static func instruction(for assetTrack: AVAssetTrack, asset: AVAsset, at time: CMTime, duration: CMTime, maxRenderSize: CGSize)
        -> (AVMutableVideoCompositionInstruction, Bool) {

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetTrack)
        let assetInfo = orientation(from: assetTrack.preferredTransform)

        let scaleRatio: CGFloat = assetInfo.isPortrait
            ? maxRenderSize.height / assetTrack.naturalSize.height
            : maxRenderSize.width / assetTrack.naturalSize.width

        var transform = CGAffineTransform(scaleX: scaleRatio, y: scaleRatio)
        transform = assetTrack.preferredTransform.concatenating(transform)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: time, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        return (instruction, assetInfo.isPortrait)
    }

    static func orientation(from transform: CGAffineTransform) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): return (.right, true)
        case (0, -1, 1, 0): return (.left, true)
        case (1, 0, 0, 1): return (.up, false)
        case (-1, 0, 0, -1): return (.down, false)
        default: return (.up, false)
        }
    }
}

//MARK: - CameraManager
class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isRecording = false

    private var currentVideoURL: URL?
    private var videoRecordingCompletion: ((URL?) -> Void)?
    private var photoCaptureDelegate: AVCapturePhotoCaptureDelegate?

    private(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    var isFlashOn: Bool = false


    override init() {
        super.init()
        configureSession()
    }

    func checkPermissions(completion: @escaping (Bool) -> Void) {
        // Check camera permission
        let videoAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch videoAuthStatus {
        case .authorized:
            // Camera permission already granted, now check for microphone permission
            checkMicrophonePermission(completion: completion)
        case .notDetermined:
            // Request camera permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.checkMicrophonePermission(completion: completion)
                } else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let microphoneAuthStatus = AVAudioSession.sharedInstance().recordPermission
        switch microphoneAuthStatus {
        case .granted:
            completion(true)  // Microphone permission granted
        case .denied:
            completion(false)  // Microphone permission denied
        case .undetermined:
            // Request microphone permission
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }


    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            print("Failed to add video input")
            return
        }
        session.addInput(videoInput)
        videoDeviceInput = videoInput

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Add outputs
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
    }

    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func switchCamera() {
        session.beginConfiguration()

        if let currentInput = videoDeviceInput {
            session.removeInput(currentInput)
        }

        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
           let newInput = try? AVCaptureDeviceInput(device: device) {

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoDeviceInput = newInput
                currentCameraPosition = newPosition
            }
        }

        session.commitConfiguration()

        if currentCameraPosition == .front {
            isFlashOn = false
            setTorch(active: false)
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let settings = AVCapturePhotoSettings()

        let delegate = PhotoCaptureDelegate { [weak self] image in
            DispatchQueue.main.async {
                completion(image)
            }
            self?.photoCaptureDelegate = nil
        }

        photoCaptureDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    private var currentDevice: AVCaptureDevice? {
        return videoDeviceInput?.device
    }

    func setTorch(active: Bool) {
        guard currentCameraPosition == .back else {
            print("Torch is not available on front camera.")
            return
        }

        guard let device = currentDevice, device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = active ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used: \(error.localizedDescription)")
        }
    }



    func startRecording() {
        guard !movieOutput.isRecording else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mov"
        let tempURL = tempDir.appendingPathComponent(fileName)

        currentVideoURL = tempURL
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true

    }


    func stopRecording(_ completion: @escaping (URL?) -> Void) {
        guard movieOutput.isRecording else {
            completion(nil)
            return
        }
        videoRecordingCompletion = completion
        movieOutput.stopRecording()
        isRecording = false
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
            videoRecordingCompletion?(nil)
        } else {
            videoRecordingCompletion?(currentVideoURL)
        }

        videoRecordingCompletion = nil
        currentVideoURL = nil
    }
}

// MARK: - AVCapturePhotoCaptureDelegate Helper

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        print(#function)
        if let data = photo.fileDataRepresentation(),
           let image = UIImage(data: data) {
            completion(image)

        } else {
            completion(nil)
        }
    }
}
