import Foundation
import SafariServices

/// Safari의 JS와 공유 저장소 사이만 연결합니다. 앱 프로세스나 Flutter 객체를 직접 호출하지 않습니다.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply(to: message)]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func reply(to message: [String: Any]?) -> [String: Any] {
        do {
            guard let message, let type = message["type"] as? String else {
                throw MediaBridgeStore.failure("잘못된 확장 요청입니다.")
            }
            let store = try MediaBridgeStore()
            switch type {
            case "hankyeon-snapshot":
                guard let list = message["mediaList"] as? [[String: Any]] else {
                    throw MediaBridgeStore.failure("미디어 목록이 없습니다.")
                }
                try store.saveSnapshot(mediaList: list, errors: message["errors"] as? [String] ?? [])
                return ["ok": true, "count": list.count, "stage": "shared-storage"]
            case "hankyeon-command-result":
                try store.saveResult(message)
                return ["ok": true]
            default:
                throw MediaBridgeStore.failure("지원하지 않는 확장 요청입니다.")
            }
        } catch { return ["ok": false, "error": error.localizedDescription] }
    }
}
