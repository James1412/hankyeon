import Cocoa
import QuartzCore
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var mediaBridge: SafariMediaBridge?
  private var audioBridge: NativeAudioBridge?
  private var notch: NotchWindowController?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown && !isKeyWindow {
      if #available(macOS 14.0, *) { NSApp.activate() }
      else { NSApp.activate(ignoringOtherApps: true) }
      makeKey()
    }
    if notch?.handleScroll(event) == true { return }
    super.sendEvent(event)
  }
  func stopAudio() { audioBridge?.shutdown() }
  override func awakeFromNib() {
    let controller = FlutterViewController()
    contentViewController = controller
    RegisterGeneratedPlugins(registry: controller)
    mediaBridge = SafariMediaBridge(messenger: controller.engine.binaryMessenger)
    audioBridge = NativeAudioBridge(messenger: controller.engine.binaryMessenger)
    notch = NotchWindowController(window: self, controller: controller)
    super.awakeFromNib()
    notch?.configure()
  }
}

/// 위치·Spaces·메뉴바는 AppKit, 콘텐츠는 Flutter가 담당합니다.
final class NotchWindowController: NSObject {
  private weak var window: NSWindow?
  private let controller: FlutterViewController
  private let channel: FlutterMethodChannel
  private var item: NSStatusItem?
  private var screenObserver: NSObjectProtocol?
  private var expanded = false
  private var normal = false
  private var hovered = false
  private var scrollDistance: CGFloat = 0
  private var gestureConsumed = false
  private var hoverExit: DispatchWorkItem?
  private var glass: NSView?
  private var pointerScreen = NSRect.zero
  private var pointerBase = NSRect.zero
  private var lastPointerPoint = NSEvent.mouseLocation
  private var accessibilityObserver: NSObjectProtocol?
  private var localPointerMonitor: Any?
  private var globalPointerMonitor: Any?
  init(window: NSWindow, controller: FlutterViewController) {
    self.window = window; self.controller = controller
    channel = FlutterMethodChannel(name: "hankyeon/window", binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "connectionDirectory":
        result(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("hankyeon").path)
      case "layout": self.position(); result(self.layout())
      case "hover": result(nil) // Native screen geometry owns hover; no resize feedback loop.
      case "expand": self.expanded = call.arguments as? Bool ?? false; self.position(); result(nil)
      case "normal": self.setNormal(call.arguments as? Bool ?? false); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func configure() {
    guard let window else { return }
    NSApp.setActivationPolicy(.accessory)
    window.isReleasedWhenClosed = false
    controller.backgroundColor = .clear
    window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
    window.styleMask = [.borderless]; window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item?.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hankyeon")
    let menu = NSMenu()
    for (title, action) in [("노치 열기", #selector(showNotch)), ("일반 창", #selector(showNormal)), ("종료", #selector(quit))] {
      let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
      entry.target = self; menu.addItem(entry)
    }
    item?.menu = menu
    if let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu {
      let connection = NSMenuItem(title: "브라우저 및 앱 오디오 연결", action: #selector(showConnections), keyEquivalent: ",")
      connection.target = self; viewMenu.addItem(connection)
    }
    screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
      self?.position(); self?.channel.invokeMethod("layoutChanged", arguments: self?.layout())
    }
    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.position(); self?.channel.invokeMethod("layoutChanged", arguments: self?.layout())
    }
    let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
    globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] _ in self?.pointerChanged() }
    localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union([.leftMouseDown, .rightMouseDown, .scrollWheel])) { [weak self] event in
      if let source = event.window {
        self?.pointerChanged(source.convertPoint(toScreen: event.locationInWindow))
      }
      return event
    }
    let root = NSView(frame: controller.view.frame)
    root.autoresizingMask = [.width, .height]
    root.appearance = NSAppearance(named: .darkAqua)
    if #available(macOS 26.0, *) {
      let effect = NSGlassEffectView()
      effect.style = .regular
      effect.cornerRadius = 24
      effect.tintColor = NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.28, alpha: 0.18)
      root.addSubview(effect); glass = effect
    } else {
      let effect = NSVisualEffectView()
      effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
      effect.wantsLayer = true; effect.layer?.cornerRadius = 24; effect.layer?.masksToBounds = true
      root.addSubview(effect); glass = effect
    }
    controller.view.removeFromSuperview()
    controller.view.frame = root.bounds
    controller.view.autoresizingMask = [.width, .height]
    root.addSubview(controller.view)
    window.contentView = root
    window.acceptsMouseMovedEvents = true
    position(); window.orderFrontRegardless()
  }
  private var display: NSScreen? { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main }
  /// 하드웨어 영역은 추정하지 않고 화면이 보고하는 좌우 안전 영역의 사이로 계산합니다.
  private var hardwareRect: NSRect? {
    guard let screen = display, screen.safeAreaInsets.top > 0,
          let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
          right.minX > left.maxX else { return nil }
    return NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                  width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
  }
  private func layout() -> [String: Any] {
    let screen = display
    let rect = hardwareRect
    return ["topInset": rect?.height ?? 32, "holeWidth": rect?.width ?? 160,
            "collapsedWidth": rect?.width ?? 160, "hasNotch": rect != nil,
            "nativeHover": true, "normal": normal, "expanded": expanded,
            "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "expandedHeight": min(460, (screen?.frame.height ?? 620) - 80)]
  }
  private func setHovered(_ value: Bool, notifyFlutter: Bool) {
    guard hovered != value else { return }
    hovered = value
    if !expanded { position() }
    if notifyFlutter { channel.invokeMethod("hoverChanged", arguments: value) }
  }
  private func pointerChanged(_ point: NSPoint = NSEvent.mouseLocation) {
    lastPointerPoint = point
    guard !normal, !pointerScreen.isEmpty else { return }
    let idle = pointerBase
    let screenFrame = pointerScreen
    let size = NSSize(width: expanded ? 420 : idle.width + (hovered ? 100 : 0),
                      height: expanded ? min(460, screenFrame.height - 80) : max(32, idle.height))
    let visible = NSRect(x: idle.midX - size.width / 2, y: screenFrame.maxY - size.height,
                         width: size.width, height: size.height)
    // A forgiving entrance and a larger exit boundary prevent edge flicker.
    let hit = visible.insetBy(dx: hovered ? -12 : -8, dy: hovered ? -10 : -6)
    let inside = screenFrame.contains(point) && hit.contains(point)
    let ignore = !visible.contains(point)
    if window?.ignoresMouseEvents != ignore { window?.ignoresMouseEvents = ignore }
    if inside {
      hoverExit?.cancel(); hoverExit = nil
      setHovered(true, notifyFlutter: true)
    } else if hovered && hoverExit == nil {
      let work = DispatchWorkItem { [weak self] in
        self?.hoverExit = nil; self?.setHovered(false, notifyFlutter: true)
      }
      hoverExit = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }
  }
  private func position() {
    guard let window, let screen = display, !normal else { return }
    let top = hardwareRect?.height ?? 32
    let hole = hardwareRect?.width ?? 160
    let height = min(460, screen.frame.height - 80)
    let center = hardwareRect?.midX ?? screen.frame.midX
    pointerScreen = screen.frame
    pointerBase = hardwareRect ?? NSRect(x: center - hole / 2, y: screen.frame.maxY - top, width: hole, height: top)
    // The Flutter render surface stays fixed. Only the visible material changes size.
    let host = NSRect(x: center - 210, y: screen.frame.maxY - height, width: 420, height: height)
    if window.frame != host { window.setFrame(host, display: true) }
    // Glass is only rendered for the open player, never during the black hover peek.
    glass?.isHidden = !expanded
    glass?.frame = NSRect(x: 0, y: 0, width: 420, height: height)
    glass?.alphaValue = 1
    pointerChanged(lastPointerPoint)
  }
  func handleScroll(_ event: NSEvent) -> Bool {
    guard !normal, event.type == .scrollWheel, let window else { return false }
    // 목록 스크롤은 Flutter에 맡깁니다. 노치 상단에서 시작한 제스처만 창을 제어합니다.
    let header = layout()["topInset"] as! CGFloat
    guard !expanded || event.locationInWindow.y >= window.frame.height - header else { return false }
    if event.phase == .began || event.phase == .mayBegin { scrollDistance = 0; gestureConsumed = false }
    if !event.momentumPhase.isEmpty { return true }
    guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return false }
    let downward = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
    scrollDistance += downward * (event.hasPreciseScrollingDeltas ? 1 : 32)
    if !gestureConsumed && ((!expanded && scrollDistance > 24) || (expanded && scrollDistance < -24)) {
      expanded.toggle(); gestureConsumed = true
      position(); channel.invokeMethod("gesture", arguments: expanded)
    }
    if event.phase == .ended || event.phase == .cancelled || event.phase.isEmpty {
      scrollDistance = 0; gestureConsumed = false
    }
    return true
  }

  private func setNormal(_ value: Bool) {
    guard let window else { return }
    hoverExit?.cancel()
    normal = value
    if value {
      window.ignoresMouseEvents = false
      glass?.isHidden = true
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.level = .normal; window.hasShadow = true
      window.setContentSize(NSSize(width: 800, height: 640)); window.center(); window.makeKeyAndOrderFront(nil)
    } else {
      window.styleMask = [.borderless]; window.level = .statusBar; window.hasShadow = false
      position(); window.orderFrontRegardless()
    }
    channel.invokeMethod("layoutChanged", arguments: layout())
  }
  @objc private func showNotch() { expanded = true; setNormal(false) }
  @objc private func showConnections() {
    expanded = true; setNormal(false)
    channel.invokeMethod("settings", arguments: nil)
  }
  @objc private func showNormal() { setNormal(true) }
  @objc private func quit() { NSApp.terminate(nil) }
  deinit {
    hoverExit?.cancel()
    if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
    if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
  }
}
