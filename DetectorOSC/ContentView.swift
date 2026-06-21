import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var oscManager: OSCManager
    @StateObject private var cameraManager: CameraManager
    @StateObject private var videoManager: VideoPlayerManager
    
    @State private var isShowingVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var isCameraMode = true
    
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var deviceOrientation = UIDevice.current.orientation.safeOrientation
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingOSCSettings = false
    @State private var orientationObserver: NSObjectProtocol?
    
    init() {
        let oscManager = OSCManager()
        let yoloManager = YOLOManager(oscManager: oscManager)
        _oscManager = StateObject(wrappedValue: oscManager)
        _cameraManager = StateObject(wrappedValue: CameraManager(oscManager: oscManager))
        _videoManager = StateObject(wrappedValue: VideoPlayerManager(yoloManager: yoloManager))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isCameraMode {
                    // カメラモード
                    CameraPreviewView(session: cameraManager.session)
                        .edgesIgnoringSafeArea(.all)
                    
                    DetectionOverlayView(
                        detectedObjects: cameraManager.detectedObjects,
                        viewSize: geometry.size,
                        isFrontCamera: cameraManager.isUsingFrontCamera,
                        videoAspectRatio: 16.0/9.0,
                        isCameraMode: true
                    )
                } else {
                    // ビデオモード
                    if let _ = selectedVideoURL {
                        VideoPlayerView(videoManager: videoManager, viewSize: geometry.size)
                    } else {
                        // ビデオが選択されていない場合の表示
                        VStack {
                            Text("タップして動画を選択")
                                .font(.title)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                VStack {
                    // Top Controls
                    ZStack {
                        // Top Controls
                        HStack {
                            // Left aligned Controls
                            HStack {
                                Button {
                                    showingOSCSettings.toggle()
                                } label: {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Circle())
                                }
                                
                                // モード切替ボタン
                                Button {
                                    isCameraMode.toggle()
                                    if !isCameraMode {
                                        cameraManager.session.stopRunning()
                                    } else {
                                        selectedVideoURL = nil
                                        videoManager.pause()
                                        cameraManager.session.startRunning()
                                    }
                                } label: {
                                    Image(systemName: isCameraMode ? "video" : "camera")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Circle())
                                }
                            }
                            
                            Spacer()
                            
                            if !isCameraMode {
                                HStack {
                                    Button {
                                        isShowingVideoPicker = true
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .padding(10)
                                            .background(Color.black.opacity(0.7))
                                            .clipShape(Circle())
                                    }
                                }
                                .padding(.trailing)
                            }
                        }
                        .padding(.leading)
                        
                        // Centered Detection Counter
                        if isCameraMode {
                            Text("Detected: \(cameraManager.detectedObjects.count)")
                                .font(.system(size: 17))
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 15)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(20)
                        }
                    }
                    .padding(.top, 44)
                    
                    Spacer()
                    
                    // Bottom Controls
                    if isCameraMode {
                        HStack(spacing: 20) {
                            if !cameraManager.isUsingFrontCamera {
                                Button {
                                    cameraManager.toggleZoom()
                                } label: {
                                    Text("\(String(format: "%.0fx", cameraManager.currentZoomFactor))")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Circle())
                                }
                            }
                            
                            Button {
                                cameraManager.switchCamera()
                            } label: {
                                Image(systemName: "camera.rotate")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.bottom, verticalSizeClass == .compact ? 10 : 30)
                    }
                }
            }
        }
        .sheet(isPresented: $showingOSCSettings) {
            NavigationView {
                OSCSettingsView(oscManager: oscManager)
                    .navigationTitle("OSC Settings")
                    .navigationBarItems(trailing: Button("Done") {
                        showingOSCSettings = false
                    })
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingVideoPicker) {
            VideoPickerView(selectedVideoURL: $selectedVideoURL)
        }
        .alert("カメラへのアクセスが必要です", isPresented: $cameraManager.isCameraPermissionDenied) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("閉じる", role: .cancel) { }
        } message: {
            Text("検出機能を使うにはカメラの利用を許可してください。設定アプリから変更できます。")
        }
        .onChange(of: selectedVideoURL) { newURL in
            if let url = newURL {
                videoManager.loadVideo(from: url)
            }
        }
        .onAppear {
            cameraManager.checkCameraPermission()
            setupOrientationObserver()
        }
        .onChange(of: scenePhase) { _ in
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
        cameraManager.updateOrientation(currentOrientation)

        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let newInterfaceOrientation = windowScene.interfaceOrientation
            let newDeviceOrientation = newInterfaceOrientation.deviceOrientation.safeOrientation
            deviceOrientation = newDeviceOrientation
            cameraManager.updateOrientation(newDeviceOrientation)
        }
    }
}

