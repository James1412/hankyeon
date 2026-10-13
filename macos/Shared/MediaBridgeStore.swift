import Foundation

/// 앱과 Safari 확장이 공유하는 파일 형식과 저장 위치입니다. Flutter에는 의존하지 않습니다.
final class MediaBridgeStore {
    static let groupID = "group.com.jiganglee1412.hankyeon.shared"
    static let extensionID = "com.jiganglee1412.hankyeon.HankyeonSafariExtension"
    static let commandName = "hankyeon-command"
    static let changeNotification = Notification.Name("group.com.jiganglee1412.hankyeon.shared.mediaChanged")
    let directory: URL
    private let maximumBytes = 10 * 1024 * 1024

    convenience init() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID
        ) else { throw Self.failure("App Group 공유 폴더에 접근할 수 없습니다.") }
        try self.init(directory: container.appendingPathComponent("MediaBridge", isDirectory: true))
    }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeExpiredResults()
    }

    func saveSnapshot(mediaList: [[String: Any]], errors: [String]) throws {
        guard mediaList.count <= 2000, mediaList.allSatisfy(Self.hasIdentity) else {
            throw Self.failure("미디어 목록의 식별자가 올바르지 않습니다.")
        }
        try write([
            "version": 1, "source": "safari", "mediaList": mediaList,
            "errors": Array(errors.prefix(100)),
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ], to: directory.appendingPathComponent("snapshot.json"))
    }

    func readSnapshot() throws -> [String: Any]? {
        let url = directory.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try read(url)
        guard value["version"] as? Int == 1,
              let list = value["mediaList"] as? [[String: Any]],
              list.count <= 2000, list.allSatisfy(Self.hasIdentity) else {
            throw Self.failure("저장된 미디어 목록의 형식이 올바르지 않습니다.")
        }
        return value
    }

    func saveResult(_ result: [String: Any]) throws {
        guard let id = result["requestId"] as? String, UUID(uuidString: id) != nil,
              result["ok"] is Bool else { throw Self.failure("명령 응답이 올바르지 않습니다.") }
        try write(result, to: resultURL(id))
    }

    func takeResult(_ id: String) throws -> [String: Any]? {
        guard UUID(uuidString: id) != nil else { throw Self.failure("요청 ID가 올바르지 않습니다.") }
        let url = resultURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try read(url)
        try FileManager.default.removeItem(at: url)
        return value
    }

    private func resultURL(_ id: String) -> URL {
        directory.appendingPathComponent("result-\(id).json")
    }

    private func write(_ value: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(value) else { throw Self.failure("JSON 변환 실패") }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw Self.failure("미디어 데이터가 너무 큽니다.") }
        try data.write(to: url, options: .atomic)
        // 알림에는 데이터를 넣지 않습니다. 수신자는 검증된 공유 파일을 다시 읽습니다.
        DistributedNotificationCenter.default().postNotificationName(
            Self.changeNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private func read(_ url: URL) throws -> [String: Any] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw Self.failure("저장된 데이터가 너무 큽니다.") }
        let data = try Data(contentsOf: url)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Self.failure("저장된 데이터가 올바르지 않습니다.")
        }
        return value
    }

    private func removeExpiredResults() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files where file.lastPathComponent.hasPrefix("result-") {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let date = modified, Date().timeIntervalSince(date) > 60 { try? FileManager.default.removeItem(at: file) }
        }
    }

    static func hasIdentity(_ media: [String: Any]) -> Bool {
        guard let id = media["mediaId"] as? String, !id.isEmpty,
              let tab = media["tabId"] as? NSNumber, tab.doubleValue.isFinite,
              tab.doubleValue.rounded() == tab.doubleValue,
              let frame = media["frameId"] as? NSNumber, frame.doubleValue >= 0,
              frame.doubleValue.rounded() == frame.doubleValue,
              let mediaURL = media["mediaUrl"] as? String,
              let tabURL = media["tabUrl"] as? String else { return false }
        return [mediaURL, tabURL].allSatisfy { ["http", "https"].contains(URL(string: $0)?.scheme ?? "") }
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "Hankyeon.MediaBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
