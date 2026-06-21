import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @ObservedObject var videoManager: VideoPlayerManager
    let viewSize: CGSize
    @State private var deviceOrientation = UIDevice.current.orientation.safeOrientation
    @State private var orientationObserver: NSObjectProtocol?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player
                if let player = videoManager.player {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .onAppear {
                            setupOrientationObserver()
                        }
                        .onDisappear {
                            if let observer = orientationObserver {
                                NotificationCenter.default.removeObserver(observer)
                                orientationObserver = nil
                            }
                            UIDevice.current.endGeneratingDeviceOrientationNotifications()
                        }
                }
                
                DetectionOverlayView(
                    detectedObjects: videoManager.yoloManager.detectedObjects,
                    viewSize: geometry.size,
                    isFrontCamera: false,
                    videoAspectRatio: videoManager.videoAspectRatio,
                    isCameraMode: false
                )
                
                // Detection Counter
                VStack {
                    Text("Detected: \(videoManager.yoloManager.detectedObjects.count)")
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 15)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(20)
                        .padding(.top, 44)
                    
                    Spacer()
                }
            }
        }
    }
    
    private func setupOrientationObserver() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        if let existing = orientationObserver {
            NotificationCenter.default.removeObserver(existing)
            orientationObserver = nil
        }

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        let currentOrientation = windowScene.interfaceOrientation.deviceOrientation.safeOrientation
        deviceOrientation = currentOrientation

        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let newInterfaceOrientation = windowScene.interfaceOrientation
            let newDeviceOrientation = newInterfaceOrientation.deviceOrientation.safeOrientation
            deviceOrientation = newDeviceOrientation
        }
    }
}

