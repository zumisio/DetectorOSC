import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewOrientation()
    }
    
    private func updatePreviewOrientation() {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        
        let orientation = UIDevice.current.orientation
        guard orientation.isValidForCamera else { return }
        
        connection.videoOrientation = orientation.videoOrientation
    }
}


