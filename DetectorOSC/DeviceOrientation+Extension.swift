import UIKit
import AVFoundation

extension UIDeviceOrientation {
    static private var lastValidOrientation: UIDeviceOrientation = .portrait
    
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .landscapeLeft:  return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default:             return .portrait
        }
    }
    
    var isValidForCamera: Bool {
        switch self {
        case .portrait, .landscapeLeft, .landscapeRight:
            return true
        default:
            return false
        }
    }
    
    var safeOrientation: UIDeviceOrientation {
        switch self {
        case .portrait, .landscapeLeft, .landscapeRight:
            UIDeviceOrientation.lastValidOrientation = self
            return self
        case .faceUp, .faceDown:
            return UIDeviceOrientation.lastValidOrientation
        default:
            return UIDeviceOrientation.lastValidOrientation
        }
    }
}

extension UIInterfaceOrientation {
    var deviceOrientation: UIDeviceOrientation {
        switch self {
        case .portrait:           return .portrait
        case .landscapeLeft:      return .landscapeLeft
        case .landscapeRight:     return .landscapeRight
        case .portraitUpsideDown: return .portrait
        @unknown default:         return .portrait
        }
    }
}


