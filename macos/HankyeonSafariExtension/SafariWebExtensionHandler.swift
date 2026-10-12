import SafariServices
import os.log

/// Safari's native extension entry point. This is a separate process from Flutter.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let snapshotMessageType = "hankyeon-snapshot"
    private let maximumMediaCount = 2000

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: makeReply(to: message)]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func makeReply(to message: [String: Any]?) -> [String: Any] {
        guard let message,
              message["type"] as? String == snapshotMessageType,
              let mediaList = message["mediaList"] as? [[String: Any]],
              mediaList.count <= maximumMediaCount,
              mediaList.allSatisfy(hasValidIdentity) else {
            return ["ok": false, "error": "잘못된 미디어 목록 요청입니다."]
        }

        // Log counts only; browsing titles and URLs should not enter system logs.
        os_log("Hankyeon Swift received %d media items", mediaList.count)
        return ["ok": true, "count": mediaList.count, "stage": "native-extension"]
    }

    private func hasValidIdentity(_ media: [String: Any]) -> Bool {
        return media["mediaId"] is String
            && media["tabId"] is NSNumber
            && media["mediaUrl"] is String
    }
}
