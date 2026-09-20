import Cocoa
import FlutterMacOS

/// The xpass HUD window.
///
/// Everything that makes the HUD "invisible" lives here:
///
///  * `sharingType = .none` removes the window from every screen-capture path
///    macOS exposes — ScreenCaptureKit, CGWindowList, AVFoundation display
///    capture and the browser `getDisplayMedia()` pipeline that Zoom, Google
///    Meet, Microsoft Teams and Slack use. The compositor never hands our
///    surface to a capturing client, so the window is absent from the frames
///    themselves rather than merely painted over.
///  * `.floating` level plus `[.canJoinAllSpaces, .fullScreenAuxiliary]` keeps
///    the HUD above full-screen IDEs and browsers and follows the user across
///    Spaces without triggering a Space switch animation.
///  * A transparent, shadowed, chrome-less frame so Flutter paints the entire
///    surface.
final class MainFlutterWindow: NSWindow {

  /// Gate for `canBecomeKey` / `canBecomeMain`. Flipped off while the HUD is in
  /// click-through mode so it can never steal focus from the app underneath.
  var allowsKeyStatus: Bool = true

  private var stealthBridge: StealthWindowBridge?
  private var mediaBridge: MediaBridge?
  private var hotkeyBridge: GlobalHotkeyBridge?
  private var speechBridge: SpeechRecognitionBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    applyStealthConfiguration()
    makeContentTransparent(flutterViewController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger
    stealthBridge = StealthWindowBridge(window: self, messenger: messenger)
    let media = MediaBridge(messenger: messenger, hostWindow: self)
    let speech = SpeechRecognitionBridge(messenger: messenger)
    // The capture taps live in MediaBridge; the recogniser needs their buffers.
    media.speech = speech
    mediaBridge = media
    speechBridge = speech
    hotkeyBridge = GlobalHotkeyBridge(messenger: messenger)

    super.awakeFromNib()
  }

  // MARK: - Stealth configuration

  private func applyStealthConfiguration() {
    // 1. Excluded from every screen capture / screen share feed.
    self.sharingType = .none

    // 2. Float above IDEs, browsers and full-screen conferencing windows.
    self.level = .floating

    // 3. Persist across Spaces and sit alongside full-screen apps.
    self.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]

    // 4. Transparent frame with a soft shadow; Flutter paints everything.
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.hasShadow = true

    // 5. Chrome-less but still titled, so resize/drag and shadow stay native.
    self.styleMask = [.titled, .fullSizeContentView, .resizable, .miniaturizable, .closable]
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true
    self.isMovableByWindowBackground = true

    // 6. Latency + lifecycle: no show/hide animation, never auto-hide, never
    //    deallocate on close (panic-hide reuses the same window).
    self.animationBehavior = .none
    self.hidesOnDeactivate = false
    self.isReleasedWhenClosed = false

    // 7. Stay out of window-restoration state on disk.
    self.isRestorable = false

    self.minSize = NSSize(width: 360, height: 120)
  }

  private func makeContentTransparent(_ controller: FlutterViewController) {
    controller.backgroundColor = NSColor.clear
    controller.view.wantsLayer = true
    controller.view.layer?.backgroundColor = NSColor.clear.cgColor
  }

  // MARK: - Focus policy

  override var canBecomeKey: Bool { allowsKeyStatus }
  override var canBecomeMain: Bool { allowsKeyStatus }
}
