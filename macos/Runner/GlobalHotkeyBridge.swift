import AppKit
import Carbon.HIToolbox
import FlutterMacOS

/// Process-wide global hotkeys via Carbon's `RegisterEventHotKey`.
///
/// Chosen over a `CGEventTap` deliberately: Carbon hotkeys are delivered by
/// WindowServer without the Accessibility (`AXIsProcessTrusted`) permission, so
/// xpass never has to appear in the Accessibility list — and they keep firing
/// while the app is unfocused and hidden, which is the whole point.
///
/// Channel: `com.xpass.app/hotkeys`
///   Dart -> native : register / unregister / unregisterAll
///   native -> Dart : onHotkey { id }
final class GlobalHotkeyBridge: NSObject {

  static let channelName = "com.xpass.app/hotkeys"

  private let channel: FlutterMethodChannel

  private struct Registration {
    let ref: EventHotKeyRef
    let identifier: String
  }

  /// Carbon addresses hotkeys by a four-char signature + UInt32 id, so we keep
  /// our own map from that id back to the Dart-facing string identifier.
  private var registrations: [UInt32: Registration] = [:]
  private var identifierToCarbonID: [String: UInt32] = [:]
  private var nextCarbonID: UInt32 = 1
  private var eventHandler: EventHandlerRef?

  private static let signature: OSType = 0x5850_5353  // 'XPSS'

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: GlobalHotkeyBridge.channelName,
      binaryMessenger: messenger
    )
    super.init()

    installEventHandler()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "disposed", message: "Hotkey bridge released", details: nil))
        return
      }
      self.handle(call, result)
    }
  }

  deinit {
    unregisterAll()
    if let eventHandler { RemoveEventHandler(eventHandler) }
  }

  // MARK: - Carbon plumbing

  private func installEventHandler() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let context = Unmanaged.passUnretained(self).toOpaque()

    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData -> OSStatus in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == GlobalHotkeyBridge.signature else {
          return OSStatus(eventNotHandledErr)
        }
        let bridge = Unmanaged<GlobalHotkeyBridge>.fromOpaque(userData).takeUnretainedValue()
        bridge.fire(carbonID: hotKeyID.id)
        return noErr
      },
      1,
      &spec,
      context,
      &eventHandler
    )
  }

  private func fire(carbonID: UInt32) {
    guard let registration = registrations[carbonID] else { return }
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onHotkey", arguments: ["id": registration.identifier])
    }
  }

  // MARK: - Dispatch

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "register":
      guard let identifier = args["id"] as? String, let keyCode = args["keyCode"] as? Int else {
        result(FlutterError(code: "bad_args", message: "register needs id and keyCode", details: nil))
        return
      }
      let modifiers = carbonModifiers(from: args)
      do {
        try register(identifier: identifier, keyCode: UInt32(keyCode), modifiers: modifiers)
        result(true)
      } catch {
        result(
          FlutterError(
            code: "register_failed",
            message: "Could not bind \(identifier) — the shortcut is already claimed by macOS or another app",
            details: error.localizedDescription
          )
        )
      }

    case "unregister":
      guard let identifier = args["id"] as? String else {
        result(FlutterError(code: "bad_args", message: "unregister needs id", details: nil))
        return
      }
      unregister(identifier: identifier)
      result(true)

    case "unregisterAll":
      unregisterAll()
      result(true)

    case "registeredIds":
      result(Array(identifierToCarbonID.keys))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func carbonModifiers(from args: [String: Any]) -> UInt32 {
    var modifiers: UInt32 = 0
    if args["command"] as? Bool ?? false { modifiers |= UInt32(cmdKey) }
    if args["option"] as? Bool ?? false { modifiers |= UInt32(optionKey) }
    if args["shift"] as? Bool ?? false { modifiers |= UInt32(shiftKey) }
    if args["control"] as? Bool ?? false { modifiers |= UInt32(controlKey) }
    return modifiers
  }

  // MARK: - Registration

  private func register(identifier: String, keyCode: UInt32, modifiers: UInt32) throws {
    // Re-registering the same identifier rebinds it (used by the settings UI).
    unregister(identifier: identifier)

    let carbonID = nextCarbonID
    nextCarbonID &+= 1

    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: GlobalHotkeyBridge.signature, id: carbonID)
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )

    guard status == noErr, let ref else {
      throw NSError(
        domain: NSOSStatusErrorDomain,
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "RegisterEventHotKey failed (OSStatus \(status))"]
      )
    }

    registrations[carbonID] = Registration(ref: ref, identifier: identifier)
    identifierToCarbonID[identifier] = carbonID
  }

  private func unregister(identifier: String) {
    guard let carbonID = identifierToCarbonID.removeValue(forKey: identifier),
      let registration = registrations.removeValue(forKey: carbonID)
    else { return }
    UnregisterEventHotKey(registration.ref)
  }

  private func unregisterAll() {
    for registration in registrations.values {
      UnregisterEventHotKey(registration.ref)
    }
    registrations.removeAll()
    identifierToCarbonID.removeAll()
  }
}
