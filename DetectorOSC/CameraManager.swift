import AVFoundation
import UIKit
import Combine
import CoreImage
import Vision

class CameraManager: NSObject, ObservableObject {
    @Published var currentZoomFactor: Double = 1.0
    @Published var isUsingFrontCamera = false
    @Published var detectedObjects: [DetectedObject] = []
    @Published var currentOrientation: UIDeviceOrientation = .portrait
    @Published var isCameraPermissionDenied: Bool = false
    
    let availableZoomFactors = [1.0, 2.0]
    
    public let session = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var visionModel: VNCoreMLModel?
    private let processQueue = DispatchQueue(label: "com.camera.process")
    private var lastAnalysis: Date = Date()
    private let minimumAnalysisInterval: TimeInterval = 1.0 / 30.0 // Fixed 30 FPS
    
    private let oscManager: OSCManager
    private let tracker = DetectionTracker()

    init(oscManager: OSCManager) {
        self.oscManager = oscManager
        super.init()
        setupVision()
        setupSession()
    }
    
    private func setupVision() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            let modelPath = Bundle.main.path(forResource: "yolov8l", ofType: "mlmodelc")
            if let modelPath = modelPath,
               let model = try? MLModel(contentsOf: URL(fileURLWithPath: modelPath)) {
                print("Successfully loaded YOLOv8l model")
                visionModel = try VNCoreMLModel(for: model)
            } else {
                print("Failed to load YOLOv8l model")
            }
        } catch {
            print("Error setting up vision model: \(error)")
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Failed to setup camera input")
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
            deviceInput = input
            configureZoom(device)
        }
        
        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: processQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isEnabled = true
            }
        }
        
        session.sessionPreset = .hd1920x1080
        session.commitConfiguration()
        
        startSession()
    }
    
    private func startSession() {
        if !session.isRunning {
            processQueue.async { [weak self] in
                self?.session.startRunning()
            }
        }
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { [weak self] in
                self?.isCameraPermissionDenied = false
            }
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isCameraPermissionDenied = !granted
                }
                if granted {
                    self?.startSession()
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.isCameraPermissionDenied = true
            }
        @unknown default:
            break
        }
    }
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let model = visionModel else { return }
        
        let currentTime = Date()
        guard currentTime.timeIntervalSince(lastAnalysis) >= minimumAnalysisInterval else { return }
        lastAnalysis = currentTime
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            if let error = error {
                print("Detection error: \(error)")
                return
            }
            
            if let observations = request.results as? [VNRecognizedObjectObservation] {
                self?.processDetections(observations)
            }
        }
        request.imageCropAndScaleOption = .scaleFit
        
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
        } catch {
            print("Failed to perform detection: \(error)")
        }
    }
    
    private func processDetections(_ observations: [VNRecognizedObjectObservation]) {
        let threshold: Float = 0.3
        let newDetections = observations.compactMap { observation -> DetectedObject? in
            guard let classification = observation.labels.first,
                  classification.confidence >= threshold else { return nil }

            return DetectedObject(
                label: classification.identifier,
                confidence: classification.confidence,
                boundingBox: observation.boundingBox
            )
        }

        // フレーム間で同一オブジェクトに安定したIDを割り当ててから、1フレーム分まとめて送信
        let tracked = tracker.assignIDs(to: newDetections)
        Task { @MainActor in
            oscManager.sendDetections(
                tracked,
                isFrontCamera: self.isUsingFrontCamera,
                isPortrait: self.currentOrientation.isPortrait
            )
        }

        DispatchQueue.main.async {
            print("Total detections: \(tracked.count)")
            self.detectedObjects = tracked
        }
    }
    
    private func configureZoom(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(currentZoomFactor)
            if device.isRampingVideoZoom {
                device.cancelVideoZoomRamp()
            }
            device.unlockForConfiguration()
        } catch {
            print("Error configuring device zoom: \(error)")
        }
    }
    
    func switchCamera() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        
        isUsingFrontCamera.toggle()
        let position: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            deviceInput = newInput
            
            if isUsingFrontCamera {
                currentZoomFactor = 1.0
            } else {
                configureZoom(device)
            }
        }
        
        session.commitConfiguration()
        tracker.reset()
        updateOrientation(currentOrientation)
    }
    
    func toggleZoom() {
        let newZoom = currentZoomFactor == 1.0 ? 2.0 : 1.0
        setZoomFactor(newZoom)
    }
    
    func setZoomFactor(_ factor: Double) {
        guard let device = deviceInput?.device,
              !isUsingFrontCamera else { return }
        
        do {
            try device.lockForConfiguration()
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = device.maxAvailableVideoZoomFactor
            let clampedFactor = max(minZoom, min(CGFloat(factor), maxZoom))
            device.ramp(toVideoZoomFactor: clampedFactor, withRate: 4.0)
            currentZoomFactor = factor
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom factor: \(error)")
        }
    }
    
    func updateOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation.isValidForCamera else { return }
        
        currentOrientation = orientation
        
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = orientation.videoOrientation
        }

        tracker.reset()
        DispatchQueue.main.async {
            self.detectedObjects = []
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer)
    }
}


