import CoreImage
import CoreVideo

extension CIImage {
    func toPixelBuffer() -> CVPixelBuffer? {
        let context = CIContext()
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        context.render(self, to: pixelBuffer)
        
        return pixelBuffer
    }
}


