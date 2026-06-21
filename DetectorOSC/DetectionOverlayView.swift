import SwiftUI
import Vision

struct DetectionOverlayView: View {
    // MARK: - Properties
    let detectedObjects: [DetectedObject]
    let viewSize: CGSize
    let isFrontCamera: Bool
    let videoAspectRatio: CGFloat
    let isCameraMode: Bool  // 追加
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ForEach(detectedObjects) { object in
                let adjustedBox = calculateAdjustedBoundingBox(
                    object.boundingBox,
                    viewSize: geometry.size
                )
                
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(object.color, lineWidth: 2)
                        .frame(width: adjustedBox.width, height: adjustedBox.height)
                    
                    Text("\(object.label) #\(object.trackID) \(Int(object.confidence * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .padding(4)
                        .background(
                            Rectangle()
                                .fill(object.color)
                                .opacity(0.7)
                        )
                        .foregroundColor(.white)
                        .offset(y: -24)
                }
                .position(
                    x: adjustedBox.midX,
                    y: adjustedBox.midY
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    private func calculateAdjustedBoundingBox(_ box: CGRect, viewSize: CGSize) -> CGRect {
        let width = viewSize.width
        let height = viewSize.height
        let orientation = UIDevice.current.orientation.safeOrientation
        var scaledRect = box
        
        if isCameraMode {  // 変更：明示的なモード判定
            // カメラモード用の計算
            let cameraAspectRatio: CGFloat = 16.0 / 9.0
            let (scaleWidth, scaleHeight, xOffset, yOffset) = orientation.isPortrait
            ? (width, width * cameraAspectRatio, CGFloat(0), (height - width * cameraAspectRatio) / 2.0)
            : (height * cameraAspectRatio, height, (width - height * cameraAspectRatio) / 2.0, CGFloat(0))
            
            // バウンディングボックスのスケーリングと位置調整
            scaledRect.origin.x = (scaledRect.origin.x * scaleWidth) + xOffset
            scaledRect.origin.y = (scaledRect.origin.y * scaleHeight) + yOffset
            scaledRect.size.width *= scaleWidth
            scaledRect.size.height *= scaleHeight
            
            if isFrontCamera {
                if orientation.isPortrait {
                    // フロントカメラ + 縦向き：上下と左右反転
                    let normalizedX = (scaledRect.origin.x - xOffset) / scaleWidth
                    scaledRect.origin.x = scaleWidth - (normalizedX * scaleWidth) - scaledRect.size.width + xOffset
                    
                    let normalizedY = (scaledRect.origin.y - yOffset) / scaleHeight
                    scaledRect.origin.y = scaleHeight - (normalizedY * scaleHeight) - scaledRect.size.height + yOffset
                }
            } else {
                if orientation.isPortrait {
                    // バックカメラ + 縦向き：上下反転
                    let normalizedY = (scaledRect.origin.y - yOffset) / scaleHeight
                    scaledRect.origin.y = scaleHeight - (normalizedY * scaleHeight) - scaledRect.size.height + yOffset
                } else {
                    // バックカメラ + 横向き：左右反転
                    let normalizedX = (scaledRect.origin.x - xOffset) / scaleWidth
                    scaledRect.origin.x = scaleWidth - (normalizedX * scaleWidth) - scaledRect.size.width + xOffset
                }
            }
        } else {
            // ビデオモードの計算
            let (scaleWidth, scaleHeight, xOffset, yOffset): (CGFloat, CGFloat, CGFloat, CGFloat)
            let isHorizontalVideo = videoAspectRatio > 1
            
            if orientation.isPortrait {
                if isHorizontalVideo {
                    // 横動画を縦向きで表示
                    let videoHeight = width / videoAspectRatio
                    scaleWidth = width
                    scaleHeight = videoHeight
                    xOffset = 0
                    yOffset = (height - videoHeight) / 2
                } else {
                    // 縦動画を縦向きで表示
                    scaleWidth = width
                    scaleHeight = height
                    xOffset = 0
                    yOffset = 0
                }
            } else {
                if isHorizontalVideo {
                    // 横動画を横向きで表示
                    scaleWidth = height * videoAspectRatio
                    scaleHeight = height
                    xOffset = (width - scaleWidth) / 2
                    yOffset = 0
                } else {
                    // 縦動画を横向きで表示
                    let videoWidth = height * videoAspectRatio
                    scaleWidth = videoWidth
                    scaleHeight = height
                    xOffset = (width - videoWidth) / 2
                    yOffset = 0
                }
            }
            
            // バウンディングボックスのスケーリングと位置調整
            scaledRect.origin.x = (scaledRect.origin.x * scaleWidth) + xOffset
            scaledRect.origin.y = (scaledRect.origin.y * scaleHeight) + yOffset
            scaledRect.size.width *= scaleWidth
            scaledRect.size.height *= scaleHeight
            
            // 常に上下反転を適用
            let normalizedY = (scaledRect.origin.y - yOffset) / scaleHeight
            scaledRect.origin.y = scaleHeight - (normalizedY * scaleHeight) - scaledRect.size.height + yOffset
            
        }
        
        return scaledRect
    }
}


