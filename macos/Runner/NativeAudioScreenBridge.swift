import AVFoundation
import AppKit
import CoreGraphics
import CoreMedia
import FlutterMacOS
import ScreenCaptureKit
import Security

// MARK: - PCM conversion

/// Converts arbitrary input buffers (48 kHz stereo float from ScreenCaptureKit,
/// whatever the default input device hands AVAudioEngine) into the single format
/// every streaming ASR endpoint wants: 16 kHz, mono, signed 16-bit LE.
final class PCMConverter {

  private let targetFormat: AVAudioFormat
  private var converter: AVAudioConverter?
  private var cachedInputFormat: AVAudioFormat?

  init(sampleRate: Double = 16_000) {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: true
      )
    else {
      fatalError("16 kHz mono Int16 is always a valid AVAudioFormat")
    }
    self.targetFormat = format
  }

  func convert(_ input: AVAudioPCMBuffer) -> Data? {
    guard input.frameLength > 0 else { return nil }

    if converter == nil || cachedInputFormat != input.format {
      converter = AVAudioConverter(from: input.format, to: targetFormat)
      converter?.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
      cachedInputFormat = input.format
    }
    guard let converter else { return nil }

    let ratio = targetFormat.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
    guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
      return nil
    }

    var delivered = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      if delivered {
        outStatus.pointee = .noDataNow
        return nil
      }
      delivered = true
      outStatus.pointee = .haveData
      return input
    }

    guard status != .error, error == nil, output.frameLength > 0,
      let channel = output.int16ChannelData
    else { return nil }

    return Data(
      bytes: channel[0],
      count: Int(output.frameLength) * MemoryLayout<Int16>.size
    )
  }

  /// Normalised 0...1 RMS of an Int16 LE buffer — the signal the Dart-side VAD
  /// segments speech with.
  static func rms(of pcm: Data) -> Double {
    let sampleCount = pcm.count / MemoryLayout<Int16>.size
    guard sampleCount > 0 else { return 0 }
    return pcm.withUnsafeBytes { raw -> Double in
      let samples = raw.bindMemory(to: Int16.self)
      var sum = 0.0
      for index in 0..<sampleCount {
        let value = Double(samples[index]) / 32_768.0
        sum += value * value
      }
      return (sum / Double(sampleCount)).squareRoot()
    }
  }
}

// MARK: - Microphone

/// Local microphone capture through CoreAudio / AVAudioEngine.
final class MicrophoneTap {

  private let engine = AVAudioEngine()
  private let converter = PCMConverter()
  private var running = false

  func start(
    onFrame: @escaping (Data, Double) -> Void,
    onBuffer: ((AVAudioPCMBuffer, Double) -> Void)? = nil
  ) throws {
    guard !running else { return }

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw NSError(
        domain: "xpass.audio", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No usable audio input device"]
      )
    }

    // ~100 ms of audio per callback: small enough for live transcription,
    // large enough that the converter and channel hop stay cheap.
    let bufferSize = AVAudioFrameCount(format.sampleRate / 10)
    input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
      guard let self, let pcm = self.converter.convert(buffer) else { return }
      let level = PCMConverter.rms(of: pcm)
      onFrame(pcm, level)
      // The Speech framework wants the native buffer, not our downsampled
      // bytes, so hand it through untouched.
      onBuffer?(buffer, level)
    }

    engine.prepare()
    try engine.start()
    running = true
  }

  func stop() {
    guard running else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    running = false
  }

  var isRunning: Bool { running }
}

// MARK: - System audio (interviewer voice)

/// System-audio loopback through ScreenCaptureKit.
///
/// This is what picks up the interviewer: everything the machine is about to
/// play through its output device, captured before it reaches the speakers and
/// with xpass's own audio excluded.
@available(macOS 13.0, *)
final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate {

  private var stream: SCStream?
  private let converter = PCMConverter()
  private let sampleQueue = DispatchQueue(label: "ai.xpass.systemaudio", qos: .userInitiated)
  private var onFrame: ((Data, Double) -> Void)?
  private var onError: ((String) -> Void)?
  private var onBuffer: ((AVAudioPCMBuffer, Double) -> Void)?

  var isRunning: Bool { stream != nil }

  func start(
    onFrame: @escaping (Data, Double) -> Void,
    onError: @escaping (String) -> Void,
    onBuffer: ((AVAudioPCMBuffer, Double) -> Void)? = nil
  ) async throws {
    guard stream == nil else { return }
    self.onFrame = onFrame
    self.onError = onError
    self.onBuffer = onBuffer

    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    guard let display = content.displays.first else {
      throw NSError(
        domain: "xpass.audio", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "No display available for audio capture"]
      )
    }

    let ownApp = content.applications.first { $0.processID == getpid() }
    let filter = SCContentFilter(
      display: display,
      excludingApplications: ownApp.map { [$0] } ?? [],
      exceptingWindows: []
    )

    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.sampleRate = 48_000
    config.channelCount = 2
    // Never feed our own TTS / UI sounds back into the transcript.
    config.excludesCurrentProcessAudio = true
    // We only want the audio track. Pin video to a 2x2 frame at 1 fps so the
    // video path costs effectively nothing but the stream stays valid.
    config.width = 2
    config.height = 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    config.queueDepth = 3
    config.showsCursor = false

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
    try await stream.startCapture()
    self.stream = stream
  }

  func stop() async {
    guard let stream else { return }
    self.stream = nil
    try? await stream.stopCapture()
    onFrame = nil
    onError = nil
    onBuffer = nil
  }

  // MARK: SCStreamOutput

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0,
      let description = sampleBuffer.formatDescription,
      var asbd = description.audioStreamBasicDescription
    else { return }

    guard let format = AVAudioFormat(streamDescription: &asbd) else { return }

    try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: format,
          bufferListNoCopy: audioBufferList.unsafePointer
        ),
        let pcm = converter.convert(buffer)
      else { return }
      let level = PCMConverter.rms(of: pcm)
      onFrame?(pcm, level)
      onBuffer?(buffer, level)
    }
  }

  // MARK: SCStreamDelegate

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    self.stream = nil
    onError?(error.localizedDescription)
  }
}

// MARK: - Screen capture

/// Still-frame capture of whatever the user is actually looking at.
///
/// Every capture path here excludes xpass itself, so a screenshot the HUD
/// takes of a coding question never contains the HUD's own answer.
enum ScreenGrabber {

  struct Frame {
    let jpeg: Data
    let width: Int
    let height: Int
  }

  enum Mode: String {
    case display
    case activeWindow
    case region
  }

  static func capture(
    mode: Mode,
    displayID: CGDirectDisplayID?,
    region: CGRect?,
    maxWidth: Int,
    quality: Double
  ) async throws -> Frame {
    let image: CGImage

    if #available(macOS 14.0, *) {
      image = try await captureModern(mode: mode, displayID: displayID, region: region)
    } else {
      image = try captureLegacy(mode: mode, displayID: displayID, region: region)
    }

    let cropped = crop(image, to: region, mode: mode, displayID: displayID)
    let scaled = resize(cropped, maxWidth: maxWidth)
    guard let jpeg = encodeJPEG(scaled, quality: quality) else {
      throw NSError(
        domain: "xpass.capture", code: -4,
        userInfo: [NSLocalizedDescriptionKey: "JPEG encoding failed"]
      )
    }
    return Frame(jpeg: jpeg, width: scaled.width, height: scaled.height)
  }

  // MARK: ScreenCaptureKit path (macOS 14+)

  @available(macOS 14.0, *)
  private static func captureModern(
    mode: Mode,
    displayID: CGDirectDisplayID?,
    region: CGRect?
  ) async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    let ownPID = getpid()
    let ownApp = content.applications.first { $0.processID == ownPID }

    let config = SCStreamConfiguration()
    config.showsCursor = false
    config.captureResolution = .best

    let filter: SCContentFilter

    if mode == .activeWindow,
      let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
      frontPID != ownPID,
      let window = content.windows
        .filter({
          $0.owningApplication?.processID == frontPID && $0.isOnScreen
            && $0.frame.width > 64 && $0.frame.height > 64
        })
        .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    {
      filter = SCContentFilter(desktopIndependentWindow: window)
      config.width = Int(window.frame.width * scaleFactor(for: displayID))
      config.height = Int(window.frame.height * scaleFactor(for: displayID))
    } else {
      let display = try resolveDisplay(content.displays, displayID: displayID, region: region)
      filter = SCContentFilter(
        display: display,
        excludingApplications: ownApp.map { [$0] } ?? [],
        exceptingWindows: []
      )
      config.width = Int(CGFloat(display.width) * scaleFactor(for: display.displayID))
      config.height = Int(CGFloat(display.height) * scaleFactor(for: display.displayID))
    }

    return try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: config
    )
  }

  @available(macOS 13.0, *)
  private static func resolveDisplay(
    _ displays: [SCDisplay],
    displayID: CGDirectDisplayID?,
    region: CGRect?
  ) throws -> SCDisplay {
    if let displayID, let match = displays.first(where: { $0.displayID == displayID }) {
      return match
    }
    let target = targetScreen(region: region)
    if let number = target?.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber,
      let match = displays.first(where: { $0.displayID == number.uint32Value })
    {
      return match
    }
    guard let first = displays.first else {
      throw NSError(
        domain: "xpass.capture", code: -3,
        userInfo: [NSLocalizedDescriptionKey: "No shareable display found"]
      )
    }
    return first
  }

  // MARK: CoreGraphics fallback (macOS 13)

  @available(macOS, deprecated: 14.0)
  private static func captureLegacy(
    mode: Mode,
    displayID: CGDirectDisplayID?,
    region: CGRect?
  ) throws -> CGImage {
    let id = displayID ?? activeDisplayID(region: region)
    // CGDisplayCreateImage honours NSWindow.sharingType == .none, so the HUD is
    // absent from this path too.
    guard let image = CGDisplayCreateImage(id) else {
      throw NSError(
        domain: "xpass.capture", code: -5,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Display capture failed — grant Screen Recording in System Settings › Privacy & Security"
        ]
      )
    }
    return image
  }

  // MARK: Geometry + encoding

  private static func targetScreen(region: CGRect?) -> NSScreen? {
    if let region {
      let point = CGPoint(x: region.midX, y: region.midY)
      if let match = NSScreen.screens.first(where: {
        flipped($0.frame).contains(point)
      }) {
        return match
      }
    }
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
  }

  private static func activeDisplayID(region: CGRect?) -> CGDirectDisplayID {
    if let number = targetScreen(region: region)?.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber {
      return number.uint32Value
    }
    return CGMainDisplayID()
  }

  private static func scaleFactor(for displayID: CGDirectDisplayID?) -> CGFloat {
    guard let displayID else { return NSScreen.main?.backingScaleFactor ?? 2 }
    let screen = NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        == displayID
    }
    return screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
  }

  /// AppKit screen frame (bottom-left origin) -> global top-left screen space.
  private static func flipped(_ frame: CGRect) -> CGRect {
    let totalHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? frame.maxY
    return CGRect(
      x: frame.origin.x,
      y: totalHeight - frame.maxY,
      width: frame.width,
      height: frame.height
    )
  }

  private static func crop(
    _ image: CGImage,
    to region: CGRect?,
    mode: Mode,
    displayID: CGDirectDisplayID?
  ) -> CGImage {
    guard mode == .region, let region, region.width > 1, region.height > 1 else { return image }

    let screen = targetScreen(region: region)
    let screenFrame = flipped(screen?.frame ?? .zero)
    let scale = screen?.backingScaleFactor ?? 1

    // Region arrives in global top-left points; convert to pixels relative to
    // the captured display.
    let rect = CGRect(
      x: (region.origin.x - screenFrame.origin.x) * scale,
      y: (region.origin.y - screenFrame.origin.y) * scale,
      width: region.width * scale,
      height: region.height * scale
    ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

    guard !rect.isNull, rect.width >= 1, rect.height >= 1,
      let cropped = image.cropping(to: rect)
    else { return image }
    return cropped
  }

  private static func resize(_ image: CGImage, maxWidth: Int) -> CGImage {
    guard maxWidth > 0, image.width > maxWidth else { return image }
    let scale = Double(maxWidth) / Double(image.width)
    let width = maxWidth
    let height = max(1, Int((Double(image.height) * scale).rounded()))

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else { return image }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
  }

  private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(
      using: .jpeg,
      properties: [.compressionFactor: NSNumber(value: min(max(quality, 0.1), 1.0))]
    )
  }
}

// MARK: - Flutter bridge

/// Dart <-> native bridge for screen frames and dual-source audio.
///
/// Method channel: `com.xpass.app/media`
/// Event channel:  `com.xpass.app/audio`
final class MediaBridge: NSObject, FlutterStreamHandler {

  static let methodChannelName = "com.xpass.app/media"
  static let audioChannelName = "com.xpass.app/audio"

  private let methodChannel: FlutterMethodChannel
  private let audioChannel: FlutterEventChannel
  private weak var hostWindow: NSWindow?

  private var eventSink: FlutterEventSink?

  /// Set by MainFlutterWindow. When on-device transcription is running, every
  /// captured buffer is handed to it as well as to Dart.
  weak var speech: SpeechRecognitionBridge?

  private let micTap = MicrophoneTap()
  private var systemTapStorage: AnyObject?

  @available(macOS 13.0, *)
  private var systemTap: SystemAudioTap? {
    get { systemTapStorage as? SystemAudioTap }
    set { systemTapStorage = newValue }
  }

  init(messenger: FlutterBinaryMessenger, hostWindow: NSWindow) {
    self.methodChannel = FlutterMethodChannel(
      name: MediaBridge.methodChannelName,
      binaryMessenger: messenger
    )
    self.audioChannel = FlutterEventChannel(
      name: MediaBridge.audioChannelName,
      binaryMessenger: messenger
    )
    self.hostWindow = hostWindow
    super.init()

    audioChannel.setStreamHandler(self)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result) ?? result(
        FlutterError(code: "disposed", message: "Media bridge released", details: nil)
      )
    }
  }

  // MARK: FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(source: String, pcm: Data, rms: Double) {
    // Sinks are not thread-safe; audio arrives on capture queues.
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?([
        "type": "frame",
        "source": source,
        "pcm": FlutterStandardTypedData(bytes: pcm),
        "rms": rms,
        "sampleRate": 16_000,
      ])
    }
  }

  private func emitError(source: String, message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["type": "error", "source": source, "message": message])
    }
  }

  // MARK: Dispatch

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {

    // MARK: Permissions

    case "hasScreenPermission":
      // Ask ScreenCaptureKit, not CoreGraphics.
      //
      // CGPreflightScreenCaptureAccess() reports on the legacy CGWindowList /
      // CGDisplayStream path. Everything here captures through
      // ScreenCaptureKit, and the two do not agree: the CG preflight caches
      // per-process and commonly answers false for an app that has only ever
      // used SCK — including after the user has granted the permission. The
      // only trustworthy test is whether SCK will actually hand us content.
      if #available(macOS 13.0, *) {
        Task {
          let probe = await MediaBridge.probeScreenAccess()
          await MainActor.run { result(probe.granted) }
        }
      } else {
        result(CGPreflightScreenCaptureAccess())
      }

    case "screenPermissionDetail":
      if #available(macOS 13.0, *) {
        Task {
          let probe = await MediaBridge.probeScreenAccess()
          await MainActor.run {
            result([
              "granted": probe.granted,
              "error": probe.error ?? "",
              "legacyPreflight": CGPreflightScreenCaptureAccess(),
              "displays": probe.displays,
            ])
          }
        }
      } else {
        result([
          "granted": CGPreflightScreenCaptureAccess(),
          "error": "",
          "legacyPreflight": CGPreflightScreenCaptureAccess(),
          "displays": 0,
        ])
      }

    case "requestScreenPermission":
      // Returns false the first time and shows the system prompt; the app must
      // be relaunched once the user grants it.
      result(CGRequestScreenCaptureAccess())

    case "hasMicPermission":
      result(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)

    case "requestMicPermission":
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted) }
      }

    case "log":
      XpLog.write((args["message"] as? String) ?? "")
      result(true)

    case "launchDiagnostics":
      // macOS attributes privacy permissions to the *responsible* process. An
      // app exec'd from a shell inherits the terminal as responsible, so TCC
      // reads the terminal's Info.plist and checks the terminal's grants —
      // which is why a `flutter run` build both ignores an existing Screen
      // Recording grant and gets killed outright for a "missing" usage
      // description it actually has. A bundle launched by launchd is
      // responsible for itself.
      result([
        "launchedByLaunchd": getppid() == 1,
        "parentPid": Int(getppid()),
        "bundlePath": Bundle.main.bundlePath,
        "isAdhocSigned": MediaBridge.isAdhocSigned(),
      ])

    case "openScreenRecordingSettings":
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
      )!
      NSWorkspace.shared.open(url)
      result(true)

    // MARK: Screen capture

    case "captureScreen":
      let mode = ScreenGrabber.Mode(rawValue: args["mode"] as? String ?? "display") ?? .display
      let maxWidth = args["maxWidth"] as? Int ?? 1_600
      let quality = args["quality"] as? Double ?? 0.72
      let displayID = (args["displayId"] as? NSNumber)?.uint32Value
      var region: CGRect?
      if let x = args["x"] as? Double, let y = args["y"] as? Double,
        let width = args["width"] as? Double, let height = args["height"] as? Double
      {
        region = CGRect(x: x, y: y, width: width, height: height)
      }

      guard #available(macOS 13.0, *) else {
        result(
          FlutterError(
            code: "unsupported",
            message: "Screen capture requires macOS 13 or newer",
            details: nil
          )
        )
        return
      }

      let started = DispatchTime.now()
      Task { [weak self] in
        guard self != nil else { return }
        do {
          let frame = try await ScreenGrabber.capture(
            mode: mode,
            displayID: displayID,
            region: region,
            maxWidth: maxWidth,
            quality: quality
          )
          let elapsedMs =
            Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
          await MainActor.run {
            result([
              "jpeg": FlutterStandardTypedData(bytes: frame.jpeg),
              "width": frame.width,
              "height": frame.height,
              "bytes": frame.jpeg.count,
              "elapsedMs": elapsedMs,
            ])
          }
        } catch {
          await MainActor.run {
            result(
              FlutterError(
                code: "capture_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }

    case "listDisplays":
      result(
        NSScreen.screens.compactMap { screen -> [String: Any]? in
          guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
              as? NSNumber
          else { return nil }
          return [
            "id": number.uintValue,
            "width": Double(screen.frame.width),
            "height": Double(screen.frame.height),
            "scale": Double(screen.backingScaleFactor),
            "isMain": screen == NSScreen.main,
          ]
        }
      )

    // MARK: Audio

    case "startAudio":
      let wantsMic = args["mic"] as? Bool ?? true
      let wantsSystem = args["system"] as? Bool ?? true
      startAudio(mic: wantsMic, system: wantsSystem, result: result)

    case "stopAudio":
      stopAudio(result: result)

    case "audioStatus":
      var status: [String: Any] = ["mic": micTap.isRunning, "system": false]
      if #available(macOS 13.0, *) { status["system"] = systemTap?.isRunning ?? false }
      result(status)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The authoritative screen-recording check: can ScreenCaptureKit actually
  /// enumerate content?
  ///
  /// This does not prompt — an ungranted app gets an error instead. Requesting
  /// is still CGRequestScreenCaptureAccess()'s job.
  @available(macOS 13.0, *)
  static func probeScreenAccess() async -> (granted: Bool, error: String?, displays: Int) {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
      )
      XpLog.write(
        "screen: GRANTED (\(content.displays.count) displays, legacy=\(CGPreflightScreenCaptureAccess()))"
      )
      return (true, nil, content.displays.count)
    } catch {
      XpLog.write(
        "screen: DENIED \(error.localizedDescription) (legacy=\(CGPreflightScreenCaptureAccess()), ppid=\(getppid()))"
      )
      return (false, error.localizedDescription, 0)
    }
  }

  /// An ad-hoc signature changes on every rebuild, and TCC keys grants on the
  /// signature — so each build looks like a different app and has to be
  /// re-authorised.
  static func isAdhocSigned() -> Bool {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
      let code
    else { return false }

    var info: CFDictionary?
    guard
      SecCodeCopySigningInformation(code, SecCSFlags(rawValue: 0), &info) == errSecSuccess,
      let signing = info as? [String: Any]
    else { return false }

    // A Developer ID / Apple Development signature carries a team identifier;
    // an ad-hoc one does not.
    return signing["teamid"] == nil
  }

  private func startAudio(mic: Bool, system: Bool, result: @escaping FlutterResult) {
    var started: [String: Any] = ["mic": false, "system": false]

    if mic {
      do {
        try micTap.start(
          onFrame: { [weak self] pcm, rms in
            self?.emit(source: "mic", pcm: pcm, rms: rms)
          },
          onBuffer: { [weak self] buffer, rms in
            self?.speech?.append(buffer: buffer, rms: rms, source: "mic")
          }
        )
        started["mic"] = true
      } catch {
        started["micError"] = error.localizedDescription
      }
    }

    guard system else {
      result(started)
      return
    }

    guard #available(macOS 13.0, *) else {
      started["systemError"] = "System audio capture requires macOS 13 or newer"
      result(started)
      return
    }

    // Snapshot the mic outcome so the concurrent closure below never captures
    // a mutable local.
    let micOutcome = started
    let tap = systemTap ?? SystemAudioTap()
    systemTap = tap
    Task { [weak self] in
      guard let self else { return }
      var outcome = micOutcome
      do {
        try await tap.start(
          onFrame: { [weak self] pcm, rms in
            self?.emit(source: "system", pcm: pcm, rms: rms)
          },
          onError: { [weak self] message in
            self?.emitError(source: "system", message: message)
          },
          onBuffer: { [weak self] buffer, rms in
            self?.speech?.append(buffer: buffer, rms: rms, source: "system")
          }
        )
        outcome["system"] = true
      } catch {
        self.systemTap = nil
        outcome["systemError"] = error.localizedDescription
      }
      let finalOutcome = outcome
      await MainActor.run { result(finalOutcome) }
    }
  }

  private func stopAudio(result: @escaping FlutterResult) {
    micTap.stop()
    guard #available(macOS 13.0, *), let tap = systemTap else {
      result(true)
      return
    }
    systemTap = nil
    Task {
      await tap.stop()
      await MainActor.run { result(true) }
    }
  }
}
