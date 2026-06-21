import Vision
import CoreML
import UIKit
import SwiftUI

class YOLOManager: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    private var visionModel: VNCoreMLModel?
    private let oscManager: OSCManager
    private var lastAnalysis: Date = Date()
    private let minimumAnalysisInterval: TimeInterval = 1.0 / 30.0
    private let tracker = DetectionTracker()

    init(oscManager: OSCManager) {
        self.oscManager = oscManager
        setupModel()
    }
    
    private func setupModel() {
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
            print("Error setting up model: \(error.localizedDescription)")
        }
    }
    
    func detectObjects(in pixelBuffer: CVPixelBuffer) {
        let currentTime = Date()
        guard currentTime.timeIntervalSince(lastAnalysis) >= minimumAnalysisInterval else { return }
        lastAnalysis = currentTime
        
        guard let model = visionModel else {
            print("Model not loaded")
            return
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            if let error = error {
                print("Detection error: \(error.localizedDescription)")
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
            print("Failed to perform detection: \(error.localizedDescription)")
        }
    }
    
    private func processDetections(_ observations: [VNRecognizedObjectObservation]) {
        let confidenceThreshold: Float = 0.3
        
        let newDetections = observations.compactMap { observation -> DetectedObject? in
            guard let classification = observation.labels.first,
                  classification.confidence >= confidenceThreshold else {
                return nil
            }

            print("Detected object: \(classification.identifier) with confidence \(classification.confidence)")

            return DetectedObject(
                label: classification.identifier,
                confidence: classification.confidence,
                boundingBox: observation.boundingBox
            )
        }

        // フレーム間で同一オブジェクトに安定したIDを割り当ててから、1フレーム分まとめて送信
        let tracked = tracker.assignIDs(to: newDetections)
        Task { @MainActor in
            oscManager.sendDetections(tracked)
        }

        DispatchQueue.main.async {
            self.detectedObjects = tracked
            print("Total detections updated: \(tracked.count)")
        }
    }
}

struct DetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    /// DetectionTrackerが割り当てるフレーム間で安定したID(ラベルごとに1始まり)
    var trackID: Int = 0

    var color: Color {
        let hash = abs(label.hashValue)
        let hue = Double(hash % 100) / 100.0
        return Color(hue: hue, saturation: 0.9, brightness: 0.9)
    }
}

