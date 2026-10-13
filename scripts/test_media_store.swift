import Foundation

@main
struct MediaStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MediaBridgeStore(directory: directory)
        let initial = try store.readSnapshot(); assert(initial == nil)
        let media: [String: Any] = ["mediaId": "a", "tabId": 1, "frameId": 0,
            "tabUrl": "https://example.com", "mediaUrl": "https://example.com", "title": "A"]
        try store.saveSnapshot(mediaList: [media], errors: ["permission unavailable"])
        let snapshot = try store.readSnapshot()!
        assert((snapshot["mediaList"] as? [[String: Any]])?.count == 1)
        assert(snapshot["source"] as? String == "safari")
        try store.saveSnapshot(mediaList: [], errors: [])
        let empty = try store.readSnapshot(); assert((empty?["mediaList"] as? [[String: Any]])?.isEmpty == true)
        let id = UUID().uuidString
        try store.saveResult(["requestId": id, "ok": true])
        let result = try store.takeResult(id); assert(result?["ok"] as? Bool == true)
        let consumed = try store.takeResult(id); assert(consumed == nil)
        do { try store.saveResult(["requestId": "../escape", "ok": true]); fatalError("unsafe identity accepted") }
        catch { }
        do { try store.saveSnapshot(mediaList: [["title": "bad"]], errors: []); fatalError("invalid media accepted") }
        catch { }
        let semaphore = DispatchSemaphore(value: 0)
        let watcher = SharedDirectoryObserver()
        try watcher.start(at: directory, queue: DispatchQueue(label: "store-test")) { semaphore.signal() }
        try store.saveSnapshot(mediaList: [media], errors: [])
        assert(semaphore.wait(timeout: .now() + 3) == .success, "atomic replace did not emit folder event")
        watcher.stop()
        print("Shared store: snapshot, empty list, result acknowledgement, identity guards passed")
    }
}
