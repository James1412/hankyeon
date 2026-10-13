import Cocoa
import FlutterMacOS
import SafariServices

/// Flutter 채널, 공유 폴더 이벤트, Safari 명령의 수명주기를 한곳에서 관리합니다.
final class SafariMediaBridge: NSObject, FlutterStreamHandler {
    private let events: FlutterEventChannel
    private let methods: FlutterMethodChannel
    private let observer = SharedDirectoryObserver()
    private var store: MediaBridgeStore?
    private var sink: FlutterEventSink?
    private var lastSnapshot: [String: Any]?
    private var lastSnapshotData: Data?
    private var status = "waiting"
    private var statusMessage = "Safari 확장 연결을 확인하고 있습니다."
    private var pending: [String: FlutterResult] = [:]
    private var timeouts: [String: DispatchWorkItem] = [:]
    private var workspaceObserver: NSObjectProtocol?

    init(messenger: FlutterBinaryMessenger) {
        events = FlutterEventChannel(name: "hankyeon/media/events", binaryMessenger: messenger)
        methods = FlutterMethodChannel(name: "hankyeon/media/commands", binaryMessenger: messenger)
        super.init()
        events.setStreamHandler(self)
        methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.Safari" {
                self?.setStatus("unavailable", "Safari가 종료됐습니다. 마지막으로 받은 목록입니다.")
                self?.failPending("Safari가 종료됐습니다.")
            }
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        do {
            let store = try MediaBridgeStore()
            self.store = store
            try observer.start(at: store.directory) { [weak self] in self?.readChanges() }
            readChanges()
            publish()
            refresh { _ in }
        } catch { setStatus("error", error.localizedDescription) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        observer.stop()
        return nil
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "refresh": refresh(result)
        case "control":
            guard let arguments = call.arguments as? [String: Any],
                  MediaBridgeStore.hasIdentity(arguments),
                  let action = arguments["action"] as? String,
                  ["play", "pause", "mute", "unmute", "volume", "seek"].contains(action),
                  status == "ready" else {
                result(FlutterError(code: "invalid_target", message: "연결 상태와 미디어 대상을 확인해주세요.", details: nil))
                return
            }
            dispatch(arguments, result: result)
        case "openSafariSettings":
            SFSafariApplication.showPreferencesForExtension(withIdentifier: MediaBridgeStore.extensionID) { error in
                DispatchQueue.main.async {
                    if let error { result(Self.flutterError(error.localizedDescription)) } else { result(nil) }
                }
            }
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func refresh(_ result: @escaping FlutterResult) {
        readChanges()
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: MediaBridgeStore.extensionID) { [weak self] state, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.setStatus("unavailable", "Safari 확장 상태를 확인할 수 없습니다: \(error.localizedDescription)")
                    result(Self.flutterError(self.statusMessage))
                } else if state?.isEnabled != true {
                    self.setStatus("unavailable", "Safari 설정에서 Hankyeon 확장을 켜고 사용할 사이트의 접근을 허용해주세요.")
                    result(Self.flutterError(self.statusMessage))
                } else {
                    self.dispatch(["action": "refresh"], result: result)
                }
            }
        }
    }

    private func dispatch(_ arguments: [String: Any], result: @escaping FlutterResult) {
        let id = UUID().uuidString
        var command = arguments
        command["requestId"] = id
        pending[id] = result
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 앱이 백그라운드에서 잠든 동안 도착한 결과를 먼저 확인합니다.
            self.readChanges()
            guard self.pending[id] != nil else { return }
            self.complete(id, value: Self.flutterError("Safari 응답이 지연됐습니다. 확장 연결과 사이트 권한을 확인해주세요."))
            self.setStatus("unavailable", "Safari 응답이 없습니다. 연결을 다시 확인해주세요.")
        }
        timeouts[id] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        SFSafariApplication.dispatchMessage(withName: MediaBridgeStore.commandName,
            toExtensionWithIdentifier: MediaBridgeStore.extensionID, userInfo: command) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.complete(id, value: Self.flutterError(error.localizedDescription))
                self?.setStatus("unavailable", "Safari 확장에 연결할 수 없습니다: \(error.localizedDescription)")
            }
        }
    }

    private func readChanges() {
        guard let store else { return }
        do {
            if let snapshot = try store.readSnapshot() {
                let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
                if data != lastSnapshotData {
                    lastSnapshotData = data
                    lastSnapshot = snapshot
                    publish()
                }
            }
            for id in Array(pending.keys) {
                guard let reply = try store.takeResult(id) else { continue }
                if reply["ok"] as? Bool == true {
                    setStatus("ready", "Safari 미디어 연결됨")
                    complete(id, value: nil)
                } else { complete(id, value: Self.flutterError(reply["error"] as? String ?? "미디어 제어 실패")) }
            }
        } catch { setStatus("error", error.localizedDescription) }
    }

    private func publish() {
        var value = lastSnapshot ?? ["mediaList": [[String: Any]](), "errors": [String]()]
        value["status"] = status
        value["message"] = statusMessage
        sink?(value)
    }

    private func setStatus(_ value: String, _ message: String) {
        status = value; statusMessage = message; publish()
    }

    private func complete(_ id: String, value: Any?) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?(value)
    }

    private func failPending(_ message: String) {
        for id in Array(pending.keys) { complete(id, value: Self.flutterError(message)) }
    }

    private static func flutterError(_ message: String) -> FlutterError {
        FlutterError(code: "safari_bridge", message: message, details: nil)
    }

    deinit {
        observer.stop()
        for timeout in timeouts.values { timeout.cancel() }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }
}
