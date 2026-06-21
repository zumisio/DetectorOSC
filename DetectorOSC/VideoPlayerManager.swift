import AVFoundation
import CoreML
import Vision
import UIKit

class VideoPlayerManager: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var duration: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var videoAspectRatio: CGFloat = 16.0 / 9.0
    
    let yoloManager: YOLOManager
    private var timeObserverToken: Any?
    private var asset: AVAsset?
    private var playerItem: AVPlayerItem?
    private var imageGenerator: AVAssetImageGenerator?
    
    init(yoloManager: YOLOManager) {
        self.yoloManager = yoloManager
        super.init()
    }
    
    private func setupImageGenerator(with asset: AVAsset) {
        imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator?.appliesPreferredTrackTransform = true
        imageGenerator?.requestedTimeToleranceBefore = .zero
        imageGenerator?.requestedTimeToleranceAfter = .zero
    }
    
    func loadVideo(from url: URL) {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        imageGenerator = nil

        asset = AVAsset(url: url)
        guard let asset = asset else { return }
        
        setupImageGenerator(with: asset)
        
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Get video track dimensions
        Task {
            do {
                let tracks = try await asset.load(.tracks)
                if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                    let size = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    let videoRect = CGRect(origin: .zero, size: size).applying(transform)
                    let width = abs(videoRect.width)
                    let height = abs(videoRect.height)
                    await MainActor.run {
                        self.videoAspectRatio = width / height
                    }
                }
            } catch {
                print("Error loading video track info: \(error)")
            }
        }
        
        // Set up time observer
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.processCurrentFrame(at: time)
        }
        
        // Get video duration
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = duration.seconds
                }
            } catch {
                print("Error loading duration: \(error)")
            }
        }
    }
    
    func play() {
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        processCurrentFrame(at: cmTime)
    }
    
    private func processCurrentFrame(at time: CMTime) {
        guard let imageGenerator = imageGenerator else { return }
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let ciImage = CIImage(cgImage: cgImage)
            
            guard let pixelBuffer = ciImage.toPixelBuffer() else {
                print("Failed to convert CIImage to CVPixelBuffer")
                return
            }
            
            print("Processing frame at time: \(time.seconds)")
            yoloManager.detectObjects(in: pixelBuffer)
            
        } catch {
            print("Error generating image: \(error)")
        }
    }
    
    deinit {
        if let timeObserverToken = timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
        }
    }
}

