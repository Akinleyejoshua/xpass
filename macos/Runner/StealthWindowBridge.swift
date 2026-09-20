import Cocoa
import FlutterMacOS

/// Dart <-> AppKit bridge for every runtime window mode the HUD exposes.
///
/// Channel: `com.xpass.app/window`
final class StealthWindowBridge: NSObject {

  static let channelName = "com.xpass.app/window"

  private weak var window: MainFlutterWindow?
  private let channel: FlutterMethodChannel

  /// The app that owned the keyboard before the HUD took focus, so
  /// `releaseFocus` can hand it straight back to the IDE / browser.
  private var previousFrontmostApp: NSRunningApplication?

  private var isClickThrough = false
  private var opacity: Double = 1.0

  init(window: MainFlutterWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    self.channel = FlutterMethodChannel(
      name: StealthWindowBridge.channelName,
      binaryMessenger: messenger
    )
    super.init()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "disposed", message: "Window bridge released", details: nil))
        return
      }
      // AppKit is main-thread-only; the platform channel already delivers on
      // main, but assert it so a future background invoke can't corrupt state.
      if Thread.isMainThread {
        self.handle(call, result)
      } else {
        DispatchQueue.main.async { self.handle(call, result) }
      }
    }
  }

  // MARK: - Dispatch

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let window else {
      result(FlutterError(code: "no_window", message: "Host window deallocated", details: nil))
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {

    // MARK: Click-through

    case "setClickThrough":
      let enabled = args["enabled"] as? Bool ?? false
      apply(clickThrough: enabled, to: window)
      result(enabled)

    case "toggleClickThrough":
      apply(clickThrough: !isClickThrough, to: window)
      result(isClickThrough)

    case "isClickThrough":
      result(isClickThrough)

    // MARK: Opacity

    case "setOpacity":
      let raw = args["opacity"] as? Double ?? 1.0
      opacity = min(max(raw, 0.2), 1.0)
      window.alphaValue = CGFloat(opacity)
      result(opacity)

    case "getOpacity":
      result(Double(window.alphaValue))

    // MARK: Visibility / panic

    case "show":
      show(window)
      result(true)

    case "hide":
      window.orderOut(nil)
      result(false)

    case "setVisible":
      let visible = args["visible"] as? Bool ?? true
      if visible { show(window) } else { window.orderOut(nil) }
      result(visible)

    case "toggleVisibility":
      let willShow = !window.isVisible
      if willShow { show(window) } else { window.orderOut(nil) }
      result(willShow)

    case "isVisible":
      result(window.isVisible)

    case "minimize":
      window.miniaturize(nil)
      result(true)

    // MARK: Capture exclusion

    case "setStealth":
      let enabled = args["enabled"] as? Bool ?? true
      window.sharingType = enabled ? .none : .readOnly
      result(enabled)

    case "isStealth":
      result(window.sharingType == .none)

    // MARK: Window level

    case "setLevel":
      let name = args["level"] as? String ?? "floating"
      window.level = StealthWindowBridge.level(named: name)
      result(name)

    case "setAlwaysOnTop":
      let enabled = args["enabled"] as? Bool ?? true
      window.level = enabled ? .floating : .normal
      result(enabled)

    // MARK: Focus

    case "setFocusable":
      let focusable = args["focusable"] as? Bool ?? true
      window.allowsKeyStatus = focusable
      if !focusable, window.isKeyWindow { window.resignKey() }
      result(focusable)

    case "focus":
      previousFrontmostApp = NSWorkspace.shared.frontmostApplication
      window.allowsKeyStatus = true
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      result(true)

    case "releaseFocus":
      window.resignKey()
      if let previous = previousFrontmostApp, previous.processIdentifier != getpid() {
        previous.activate(options: [])
      } else {
        NSApp.hide(nil)
        window.orderFrontRegardless()
      }
      previousFrontmostApp = nil
      result(true)

    // MARK: Geometry

    case "getBounds":
      result(bounds(of: window))

    case "setBounds":
      guard
        let x = args["x"] as? Double, let y = args["y"] as? Double,
        let width = args["width"] as? Double, let height = args["height"] as? Double
      else {
        result(FlutterError(code: "bad_args", message: "setBounds needs x, y, width, height", details: nil))
        return
      }
      window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
      result(bounds(of: window))

    case "setSize":
      guard let width = args["width"] as? Double, let height = args["height"] as? Double else {
        result(FlutterError(code: "bad_args", message: "setSize needs width, height", details: nil))
        return
      }
      var frame = window.frame
      // Grow downward from the current top edge so the header never jumps.
      frame.origin.y += frame.size.height - CGFloat(height)
      frame.size = NSSize(width: width, height: height)
      window.setFrame(frame, display: true, animate: false)
      result(bounds(of: window))

    case "moveBy":
      let dx = args["dx"] as? Double ?? 0
      let dy = args["dy"] as? Double ?? 0
      var origin = window.frame.origin
      origin.x += CGFloat(dx)
      origin.y -= CGFloat(dy)  // Dart uses screen-space (y grows downward).
      window.setFrameOrigin(origin)
      result(bounds(of: window))

    case "snapTo":
      let position = args["position"] as? String ?? "topCenter"
      snap(window, to: position)
      result(bounds(of: window))

    case "startDrag":
      if let event = NSApp.currentEvent {
        window.performDrag(with: event)
      }
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Helpers

  private func show(_ window: MainFlutterWindow) {
    // `orderFrontRegardless` shows the HUD without activating xpass, so the
    // interviewer-facing app underneath keeps keyboard focus and its own
    // "is this window active" state never flickers.
    window.orderFrontRegardless()
  }

  private func apply(clickThrough enabled: Bool, to window: MainFlutterWindow) {
    isClickThrough = enabled
    window.ignoresMouseEvents = enabled
    // A click-through HUD must also be unfocusable, otherwise a stray
    // activation would swallow the keystrokes meant for the IDE underneath.
    window.allowsKeyStatus = !enabled
    if enabled, window.isKeyWindow {
      window.resignKey()
      previousFrontmostApp?.activate(options: [])
    }
  }

  private func bounds(of window: NSWindow) -> [String: Double] {
    let frame = window.frame
    let screenHeight = (window.screen ?? NSScreen.main)?.frame.height ?? frame.maxY
    return [
      "x": Double(frame.origin.x),
      // Convert AppKit's bottom-left origin to Flutter's top-left screen space.
      "y": Double(screenHeight - frame.maxY),
      "width": Double(frame.width),
      "height": Double(frame.height),
    ]
  }

  private func snap(_ window: NSWindow, to position: String) {
    let screen = screenUnderCursor()
    let area = screen.visibleFrame
    let size = window.frame.size
    let inset: CGFloat = 16

    var origin = CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - inset)
    switch position {
    case "topLeft":
      origin = CGPoint(x: area.minX + inset, y: area.maxY - size.height - inset)
    case "topRight":
      origin = CGPoint(x: area.maxX - size.width - inset, y: area.maxY - size.height - inset)
    case "center":
      origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
    case "bottomLeft":
      origin = CGPoint(x: area.minX + inset, y: area.minY + inset)
    case "bottomCenter":
      origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + inset)
    case "bottomRight":
      origin = CGPoint(x: area.maxX - size.width - inset, y: area.minY + inset)
    default:  // topCenter
      break
    }
    window.setFrameOrigin(origin)
  }

  private func screenUnderCursor() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens[0]
  }

  private static func level(named name: String) -> NSWindow.Level {
    switch name {
    case "normal": return .normal
    case "status": return .statusBar
    case "popUpMenu": return .popUpMenu
    case "screenSaver": return .screenSaver
    case "mainMenu": return .mainMenu
    default: return .floating
    }
  }
}
