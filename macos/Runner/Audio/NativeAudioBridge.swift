import Cocoa
import CoreAudio
import FlutterMacOS

/// Core Audio discovery and routing are isolated from Flutter and the realtime mixer.
final class NativeAudioBridge: NSObject, FlutterStreamHandler {
    private let queue = DispatchQueue(label: "hankyeon.audio.control", qos: .userInitiated)
    private let events: FlutterEventChannel
    private let methods: FlutterMethodChannel
    private var sink: FlutterEventSink?
    private var groups: [String: AudioApp] = [:]
    private var seenApps = Set(UserDefaults.standard.stringArray(forKey: "audio.seenApps") ?? [])
    private var routes: [String: UnsafeMutableRawPointer] = [:]
    private var volumes: [String: Float] = [:]
    private var authorized = false
    private var watchdog: DispatchSourceTimer?
    private var quietCycles: [String: Int] = [:]
    private var audioError: String?
    private var validatedRoutes = Set<String>()
    private var message = "앱별 볼륨을 사용하려면 오디오 접근을 허용해주세요."
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var lastPayload: NSDictionary?
    private struct AudioApp {
        let bundleID: String
        let name: String
        let processes: [AudioObjectID]
        let active: Bool
    }
    init(messenger: FlutterBinaryMessenger) {
        events = FlutterEventChannel(name: "hankyeon/audio/events", binaryMessenger: messenger)
        methods = FlutterMethodChannel(name: "hankyeon/audio/commands", binaryMessenger: messenger)
        super.init()
        events.setStreamHandler(self)
        methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        queue.async { [weak self] in
            guard let self else { return }
            self.refresh(relisten: true)
            if UserDefaults.standard.bool(forKey: "audio.capture.enabled") {
                self.authorized = HankyeonAudioProbe() == 0
                self.message = self.authorized ? "앱 오디오 연결됨" : "오디오 접근을 다시 확인해주세요."
                self.publish()
            }
        }
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        queue.async { [weak self] in self?.stop() }
        return nil
    }
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self else { return }
            var error: FlutterError?
            var response: Any?
            switch call.method {
            case "refresh": self.refresh(relisten: true)
            case "authorize":
                if #available(macOS 14.2, *) {
                    let status = HankyeonAudioProbe()
                    self.authorized = status == 0
                    response = self.authorized
                    UserDefaults.standard.set(self.authorized, forKey: "audio.capture.enabled")
                    self.message = self.authorized ? "앱 오디오 연결됨" : "시스템 오디오 접근을 허용한 뒤 다시 확인해주세요. (\(status))"
                    if !self.authorized { self.releaseRoutes() }
                    self.publish()
                }
            case "volume":
                let values = call.arguments as? [String: Any]
                if let id = values?["bundleID"] as? String,
                   let gain = values?["volume"] as? NSNumber,
                   gain.doubleValue.isFinite, (0...1).contains(gain.doubleValue),
                   let app = self.groups[id], self.authorized {
                    let volume = gain.floatValue
                    if volume == 1 {
                        if let route = self.routes.removeValue(forKey: id) { HankyeonAudioDestroy(route) }
                    } else if let route = self.routes[id] {
                        HankyeonAudioSetGain(route, volume)
                    } else if app.active {
                        var status: Int32 = 0
                        let route = app.processes.withUnsafeBufferPointer {
                            HankyeonAudioCreate($0.baseAddress, UInt32($0.count), volume, 1, &status)
                        }
                        if let route { self.routes[id] = route; self.startWatchdog(); NSLog("Hankyeon audio route engaged: %@ gain=%f", id, volume) }
                        else { error = FlutterError(code: "audio_route", message: "앱 오디오를 연결하지 못했습니다. (\(status))", details: nil) }
                    }
                    if error == nil { self.audioError = nil; self.quietCycles[id] = 0; self.volumes[id] = volume; self.publish() }
                } else {
                    error = FlutterError(code: "audio_permission", message: "오디오 접근 권한과 실행 중인 앱을 확인해주세요.", details: nil)
                }
            default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
            }
            DispatchQueue.main.async { if let error { result(error) } else { result(response) } }
        }
    }
    private func scalar<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
        var value = initial, bytes = UInt32(MemoryLayout<T>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        withUnsafeMutableBytes(of: &value) { buffer in
            _ = AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, buffer.baseAddress!)
        }
        return value
    }
    private func refresh(relisten: Bool) {
        guard #available(macOS 14.2, *) else { message = "앱별 볼륨은 macOS 14.2 이상에서 지원합니다."; publish(); return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes) == noErr else { return }
        var processes = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        let status: OSStatus = processes.isEmpty ? noErr : processes.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes, $0.baseAddress!)
        }
        guard status == noErr else { return }
        var grouped: [String: (String, [AudioObjectID], Bool, Bool)] = [:]
        for process in processes {
            let pid: pid_t = scalar(process, kAudioProcessPropertyPID, 0)
            guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid) else { continue }
            // Helpers may be a nested .app inside Discord, Chrome, etc. Use the outer app identity.
            var bundleURL = app.bundleURL
            if let url = bundleURL {
                var parent = url.deletingLastPathComponent()
                while parent.path != "/" {
                    if parent.pathExtension == "app" { bundleURL = parent }
                    parent.deleteLastPathComponent()
                }
            }
            let bundle = bundleURL.flatMap(Bundle.init(url:))
            guard let id = bundle?.bundleIdentifier ?? app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? app.localizedName ?? id
            let active: UInt32 = scalar(process, kAudioProcessPropertyIsRunningOutput, 0)
            var row = grouped[id] ?? (name, [], false, false)
            let owner = NSRunningApplication.runningApplications(withBundleIdentifier: id).first ?? app
            row.1.append(process); row.2 = row.2 || active != 0
            row.3 = row.3 || owner.activationPolicy == .regular
            grouped[id] = row
        }
        var next: [String: AudioApp] = [:]
        for (id, row) in grouped {
            if row.2 && seenApps.insert(id).inserted {
                UserDefaults.standard.set(Array(seenApps).sorted(), forKey: "audio.seenApps")
            }
            if row.2 || row.3 || routes[id] != nil || seenApps.contains(id) {
                next[id] = AudioApp(bundleID: id, name: row.0, processes: row.1.sorted(), active: row.2)
            }
        }
        // Device changes and process restarts release taps before rebuilding any route.
        for id in Array(routes.keys) where next[id]?.processes != groups[id]?.processes || next[id]?.active != true {
            if let route = routes.removeValue(forKey: id) { HankyeonAudioDestroy(route) }
        }
        groups = next
        if authorized {
            for (id, app) in groups where app.active && routes[id] == nil && (volumes[id] ?? 1) < 1 {
                var status: Int32 = 0
                let gain = volumes[id] ?? 1
                let route = app.processes.withUnsafeBufferPointer {
                    HankyeonAudioCreate($0.baseAddress, UInt32($0.count), gain, 1, &status)
                }
                if let route { routes[id] = route; startWatchdog() }
                else { volumes[id] = 1; audioError = "\(app.name)의 오디오 연결을 복원하지 못했습니다. (\(status))" }
            }
        }
        if relisten {
            removeListeners()
            listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, rebuild: true)
            listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, rebuild: true, release: true)
            for process in processes { listen(process, kAudioProcessPropertyIsRunningOutput, rebuild: false) }
        }
        publish()
    }
    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, rebuild: Bool, release: Bool = false) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            if release { self?.releaseRoutes() }
            self?.refresh(relisten: rebuild)
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr { listeners.append((object, address, block)) }
    }
    private func publish() {
        let apps: [[String: Any]] = groups.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map {
            ["bundleID": $0.bundleID, "title": $0.name, "volume": volumes[$0.bundleID] ?? 1]
        }
        let payload: NSDictionary = ["connection": authorized ? "ready" : "waiting", "message": message, "apps": apps, "errors": audioError.map { [$0] } ?? []]
        guard lastPayload != payload else { return }
        lastPayload = payload
        DispatchQueue.main.async { [weak self] in self?.sink?(payload) }
    }
    private func removeListeners() {
        for (object, var address, block) in listeners { AudioObjectRemovePropertyListenerBlock(object, &address, queue, block) }
        listeners.removeAll()
    }
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for (id, route) in Array(self.routes) {
                let peak = HankyeonAudioReadPeak(route)
                let outputPeak = HankyeonAudioReadOutputPeak(route)
                if peak > 0.0000001 && !self.validatedRoutes.contains(id) {
                    self.validatedRoutes.insert(id)
                    NSLog("Hankyeon audio DSP verified: %@ input_peak=%f output_peak=%f", id, peak, outputPeak)
                }
                self.quietCycles[id] = peak > 0.0000001 ? 0 : (self.quietCycles[id] ?? 0) + 1
                if self.quietCycles[id, default: 0] >= 3 {
                    // Permission revocation or uncapturable content must never leave an app silent.
                    HankyeonAudioDestroy(route); self.routes.removeValue(forKey: id); self.volumes[id] = 1
                    self.audioError = "오디오를 받지 못해 \(self.groups[id]?.name ?? "앱")의 원래 출력을 복원했습니다."
                    self.publish()
                }
            }
            if self.routes.isEmpty { self.watchdog?.cancel(); self.watchdog = nil }
        }
        watchdog = timer; timer.resume()
    }
    private func releaseRoutes() {
        watchdog?.cancel(); watchdog = nil; quietCycles.removeAll(); validatedRoutes.removeAll()
        routes.values.forEach { HankyeonAudioDestroy($0) }; routes.removeAll(); volumes.removeAll()
    }
    func shutdown() {
        sink = nil
        queue.sync { stop() }
    }
    private func stop() { removeListeners(); releaseRoutes(); lastPayload = nil }
    deinit { removeListeners(); releaseRoutes() }
}
