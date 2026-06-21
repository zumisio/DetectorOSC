import Foundation
import CoreGraphics

/// フレーム間で検出オブジェクトを対応付け、ラベルごとに安定したトラックIDを割り当てる簡易トラッカー。
/// 中心点の距離による貪欲マッチング。IDは1始まりで、空いている最小の番号を再利用する
/// (例: person 2 が退場したら、次に現れた人が person 2 になる)。
final class DetectionTracker {
    private struct Track {
        let id: Int
        var boundingBox: CGRect
        var missedFrames: Int
    }

    /// 見失ったトラックを保持するフレーム数(30fpsで約1秒)
    private let maxMissedFrames: Int
    /// 同一オブジェクトとみなす中心点間の最大距離(正規化座標)
    private let maxMatchDistance: CGFloat

    private var tracksByLabel: [String: [Track]] = [:]
    /// 映像処理キューとメインスレッド(reset)の両方から呼ばれるため排他する
    private let lock = NSLock()

    init(maxMissedFrames: Int = 30, maxMatchDistance: CGFloat = 0.15) {
        self.maxMissedFrames = maxMissedFrames
        self.maxMatchDistance = maxMatchDistance
    }

    /// 1フレーム分の検出結果にトラックIDを割り当てて返す。
    /// 検出が空のフレームでも呼ぶこと(見失ったトラックの寿命管理のため)。
    func assignIDs(to detections: [DetectedObject]) -> [DetectedObject] {
        lock.lock()
        defer { lock.unlock() }

        let detectionsByLabel = Dictionary(grouping: detections, by: { $0.label })
        var result: [DetectedObject] = []

        // 今フレームに存在するラベルのマッチング
        for (label, labelDetections) in detectionsByLabel {
            result.append(contentsOf: match(labelDetections, label: label))
        }

        // 今フレームに1件もなかったラベルのトラックを老化させる
        for label in tracksByLabel.keys where detectionsByLabel[label] == nil {
            age(label: label, matchedIDs: [])
        }

        return result
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        tracksByLabel.removeAll()
    }

    private func match(_ detections: [DetectedObject], label: String) -> [DetectedObject] {
        let tracks = tracksByLabel[label] ?? []

        // 全トラック×全検出の距離ペアを近い順に走査して貪欲に対応付け
        var pairs: [(trackIndex: Int, detectionIndex: Int, distance: CGFloat)] = []
        for (t, track) in tracks.enumerated() {
            for (d, detection) in detections.enumerated() {
                let distance = hypot(
                    track.boundingBox.midX - detection.boundingBox.midX,
                    track.boundingBox.midY - detection.boundingBox.midY
                )
                if distance <= maxMatchDistance {
                    pairs.append((t, d, distance))
                }
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var trackForDetection: [Int: Int] = [:]  // detectionIndex -> trackIndex
        var usedTracks = Set<Int>()
        for pair in pairs {
            guard !usedTracks.contains(pair.trackIndex),
                  trackForDetection[pair.detectionIndex] == nil else { continue }
            usedTracks.insert(pair.trackIndex)
            trackForDetection[pair.detectionIndex] = pair.trackIndex
        }

        var matchedIDs = Set<Int>()
        var assigned: [DetectedObject] = []
        var newDetectionIndices: [Int] = []

        for (d, detection) in detections.enumerated() {
            if let t = trackForDetection[d] {
                var updated = detection
                updated.trackID = tracks[t].id
                assigned.append(updated)
                matchedIDs.insert(tracks[t].id)
            } else {
                newDetectionIndices.append(d)
            }
        }

        age(label: label, matchedIDs: matchedIDs, updatedBoxes: Dictionary(
            uniqueKeysWithValues: assigned.map { ($0.trackID, $0.boundingBox) }
        ))

        // 新規検出には空いている最小のIDを割り当てる
        for d in newDetectionIndices {
            var detection = detections[d]
            detection.trackID = smallestFreeID(for: label)
            tracksByLabel[label, default: []].append(
                Track(id: detection.trackID, boundingBox: detection.boundingBox, missedFrames: 0)
            )
            assigned.append(detection)
        }

        return assigned
    }

    /// マッチしたトラックは位置を更新、しなかったトラックは寿命を減らして期限切れを削除する。
    private func age(label: String, matchedIDs: Set<Int>, updatedBoxes: [Int: CGRect] = [:]) {
        guard var tracks = tracksByLabel[label] else { return }

        tracks = tracks.compactMap { track in
            var track = track
            if matchedIDs.contains(track.id) {
                track.missedFrames = 0
                if let box = updatedBoxes[track.id] {
                    track.boundingBox = box
                }
                return track
            }
            track.missedFrames += 1
            return track.missedFrames <= maxMissedFrames ? track : nil
        }

        if tracks.isEmpty {
            tracksByLabel.removeValue(forKey: label)
        } else {
            tracksByLabel[label] = tracks
        }
    }

    private func smallestFreeID(for label: String) -> Int {
        let used = Set((tracksByLabel[label] ?? []).map(\.id))
        var id = 1
        while used.contains(id) { id += 1 }
        return id
    }
}
