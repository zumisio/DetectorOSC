import Foundation
import OSCKit
import SwiftUI

/// OSC lifecycle and send/receive manager.
@MainActor
final class OSCManager: ObservableObject, Sendable {
    private static let ipDefaultsKey = "osc.ipAddress"
    private static let portDefaultsKey = "osc.port"
    private static let defaultIP = "192.168.1.84"
    private static let defaultPort: UInt16 = 8000

    private let client = OSCClient()
    private let server = OSCServer(port: 8000)

    @Published var ipAddress: String
    @Published var port: UInt16

    /// 直前のフレームで送信したラベルごとの検出数(0件になった通知を一度だけ送るために保持)
    private var lastSentCounts: [String: Int] = [:]

    init() {
        let defaults = UserDefaults.standard
        self.ipAddress = defaults.string(forKey: Self.ipDefaultsKey) ?? Self.defaultIP
        let storedPort = defaults.integer(forKey: Self.portDefaultsKey)
        self.port = (storedPort > 0 && storedPort <= Int(UInt16.max))
            ? UInt16(storedPort)
            : Self.defaultPort
        start()
    }
}

// MARK: - Lifecycle

extension OSCManager {
    func start() {
        do {
            try client.start()
        } catch {
            print("Client start error: \(error)")
        }
        
        server.setHandler { [weak self] message, timeTag, host, port in
            // MainActorでラップして非同期タスクとして実行
            Task { @MainActor [self] in
                self?.handle(message: message, timeTag: timeTag, host: host, port: port)
            }
        }
        
        do {
            try server.start()
        } catch {
            print("Server start error: \(error)")
        }
    }
    
    func stop() {
        client.stop()
        server.stop()
    }
}

// MARK: - Receive

extension OSCManager {
    func handle(message: OSCMessage, timeTag: OSCTimeTag, host: String, port: UInt16) {
        print("\(message) with time tag: \(timeTag) from: \(host):\(port)")
    }
}

// MARK: - Send

extension OSCManager {
    func send(_ message: OSCMessage, to host: String, port: UInt16) {
        do {
            try client.send(message, to: host, port: port)
        } catch {
            print("Send error: \(error)")
        }
    }
    
    /// 1フレーム分の検出結果をOSCバンドルとしてまとめて送信する。
    ///
    /// 送信フォーマット:
    /// - `/<label>/count [n]` : ラベルごとの検出数(0件になったフレームでも一度だけ0を送る)
    /// - `/<label>/<trackID>/x|y|w|h|confidence [float]` : 値ごとに個別アドレスで送る。
    ///   座標は正規化(0〜1)・左上原点。TouchDesignerのOSC In CHOPでそのまま
    ///   `person/1/x` のようなチャンネル名になるよう、複数引数ではなく1値1アドレスにしている。
    ///
    /// `isFrontCamera` / `isPortrait` はDetectionOverlayViewの画面描画と同じ向き補正を
    /// 適用するためのフラグ。動画ファイルモードは省略値(バックカメラ+縦向き相当)でよい。
    func sendDetections(_ detections: [DetectedObject], isFrontCamera: Bool = false, isPortrait: Bool = true) {
        var countMessages: [OSCMessage] = []
        var detectionMessages: [OSCMessage] = []

        var counts: [String: Int] = [:]
        for detection in detections {
            counts[detection.label.lowercased(), default: 0] += 1
        }
        // 前フレームに存在して今回消えたラベルには0を送り、受信側がリセットできるようにする
        for label in lastSentCounts.keys where counts[label] == nil {
            counts[label] = 0
        }
        for (label, count) in counts {
            countMessages.append(OSCMessage("/\(label)/count", values: [Int32(count)]))
        }
        lastSentCounts = counts.filter { $0.value > 0 }

        for detection in detections {
            let label = detection.label.lowercased()
            let box = screenRect(
                for: detection.boundingBox,
                isFrontCamera: isFrontCamera,
                isPortrait: isPortrait
            )
            let prefix = "/\(label)/\(detection.trackID)"

            detectionMessages.append(OSCMessage("\(prefix)/x", values: [Float(box.origin.x)]))
            detectionMessages.append(OSCMessage("\(prefix)/y", values: [Float(box.origin.y)]))
            detectionMessages.append(OSCMessage("\(prefix)/w", values: [Float(box.width)]))
            detectionMessages.append(OSCMessage("\(prefix)/h", values: [Float(box.height)]))
            detectionMessages.append(OSCMessage("\(prefix)/confidence", values: [detection.confidence]))
        }

        let messages = countMessages + detectionMessages
        guard !messages.isEmpty else { return }

        do {
            try client.send(OSCBundle(messages), to: ipAddress, port: port)
        } catch {
            print("Send error: \(error)")
        }
    }
    
    /// Visionの正規化座標(左下原点)を、画面に表示されている向きと一致する
    /// 左上原点の座標に変換する。反転の組み合わせはDetectionOverlayViewの
    /// 画面描画補正と対応している(横向き時はカメラバッファが180°回転して届くため)。
    private func screenRect(for box: CGRect, isFrontCamera: Bool, isPortrait: Bool) -> CGRect {
        var rect = box
        switch (isFrontCamera, isPortrait) {
        case (false, true):
            // バックカメラ+縦: 上下反転のみ(左下原点→左上原点)
            rect.origin.y = 1.0 - box.origin.y - box.height
        case (false, false):
            // バックカメラ+横: 左右反転のみ
            rect.origin.x = 1.0 - box.origin.x - box.width
        case (true, true):
            // フロントカメラ+縦: 上下左右反転
            rect.origin.x = 1.0 - box.origin.x - box.width
            rect.origin.y = 1.0 - box.origin.y - box.height
        case (true, false):
            // フロントカメラ+横: 反転なし
            break
        }
        return rect
    }

    func updateSettings(ipAddress: String, port: UInt16) {
        self.ipAddress = ipAddress
        self.port = port

        let defaults = UserDefaults.standard
        defaults.set(ipAddress, forKey: Self.ipDefaultsKey)
        defaults.set(Int(port), forKey: Self.portDefaultsKey)
    }
}
