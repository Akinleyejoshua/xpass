import AVFoundation
import AppKit
import FlutterMacOS
import Foundation
import Speech

/// On-device speech-to-text via Apple's Speech framework.
///
/// This is the default transcription path, and it should be: dictation is a
/// solved problem the OS already does locally. Sending every utterance to a
/// frontier model instead costs an API key, a network round trip per sentence
/// and a per-minute quota, for worse latency on a task the Mac performs for
/// free.
///
/// **Threading.** Audio arrives on two different capture threads (the
/// microphone tap and the ScreenCaptureKit sample queue) while sessions are
/// opened and recycled in response to recognition callbacks. All session state
/// therefore lives on one serial queue and is never touched anywhere else; the
/// capture threads only convert a buffer and hand it over. An earlier version
/// mutated the session dictionary from the main queue while reading it from the
/// capture threads, which worked until the first recycle and then quietly
/// stopped transcribing.
///
/// Method channel: `com.xpass.app/speech`
/// Event channel:  `com.xpass.app/speech_events`
final class SpeechRecognitionBridge: NSObject, FlutterStreamHandler {

  static let methodChannelName = "com.xpass.app/speech"
  static let eventChannelName = "com.xpass.app/speech_events"

  /// 16 kHz mono float — the format SFSpeechRecognizer is most reliable with.
  /// System audio arrives as 48 kHz stereo, which it will quietly decline to
  /// transcribe.
  private static let recognizerFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
  )!

  // MARK: - Tunables

  /// Silence that closes an utterance. Long enough to ride out a mid-sentence
  /// pause, short enough that the answer is not held back.
  private let silenceToEndpoint: TimeInterval = 0.7

  /// Force an endpoint on a monologue so the pipeline never stalls.
  private let maxUtterance: TimeInterval = 25

  /// Loudness that counts as speech, for endpointing only.
  private let speechThreshold = 0.010

  /// How long to wait for a final result after `endAudio()` before opening a
  /// fresh session regardless.
  private let finalResultTimeout: TimeInterval = 4

  /// Audio retained while a session finalises, replayed into the next one so
  /// the start of the following sentence is not lost.
  private let carryOverLimit = 20

  // MARK: - State

  /// Owns every field below. Nothing touches them off this queue.
  private let queue = DispatchQueue(label: "ai.xpass.speech")

  private var sessions: [String: Session] = [:]
  private var enabled = false
  private var locale = Locale(identifier: "en-US")

  /// Format conversion happens on the capture thread, before the hand-off, so
  /// these are kept separately under their own lock.
  private let converterLock = NSLock()
  private var converters: [String: Converter] = [:]

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  /// A live recognition session for one audio source.
  private final class Session {
    init(source: String) { self.source = source }

    let source: String
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?

    var heardSpeech = false
    var quietSince: Date?
    var speechStartedAt: Date?

    /// True between `endAudio()` and the final result.
    var endedAudio = false
    var watchdog: DispatchWorkItem?

    /// Invalidates callbacks from a task that has already been replaced.
    var generation = 0

    /// Buffers captured while the previous session was finalising.
    var carryOver: [AVAudioPCMBuffer] = []
  }

  /// Per-source converter, used only on that source's capture thread.
  private final class Converter {
    var converter: AVAudioConverter?
    var inputFormat: AVAudioFormat?
  }

  // MARK: - Init

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: SpeechRecognitionBridge.methodChannelName,
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: SpeechRecognitionBridge.eventChannelName,
      binaryMessenger: messenger
    )
    super.init()

    eventChannel.setStreamHandler(self)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
        ?? result(
          FlutterError(code: "disposed", message: "Speech bridge released", details: nil)
        )
    }
  }

  deinit { stopAllLocked() }

  // MARK: - FlutterStreamHandler

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

  private func emit(source: String, text: String, isFinal: Bool) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?([
        "type": "transcript",
        "source": source,
        "text": trimmed,
        "isFinal": isFinal,
      ])
    }
  }

  private func emitError(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["type": "error", "message": message])
    }
  }

  // MARK: - Dispatch

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "isAvailable":
      result(SFSpeechRecognizer(locale: currentLocale())?.isAvailable ?? false)

    case "supportsOnDevice":
      result(
        SFSpeechRecognizer(locale: currentLocale())?.supportsOnDeviceRecognition ?? false
      )

    case "authorizationStatus":
      result(SpeechRecognitionBridge.describe(SFSpeechRecognizer.authorizationStatus()))

    case "requestAuthorization":
      // xpass ships as LSUIElement, so it starts as an .accessory app: no Dock
      // icon, and no foreground context. A TCC prompt raised from an accessory
      // app is not reliably presented — NSApp.activate() alone does not fix
      // it, because an accessory app cannot truly become frontmost. Promote to
      // .regular for the duration of the request so the prompt has an app to
      // belong to, then drop straight back to staying out of the way.
      let previousPolicy = NSApp.activationPolicy()
      XpLog.write("speech: requesting authorization (policy=\(previousPolicy.rawValue))")
      if previousPolicy != .regular {
        NSApp.setActivationPolicy(.regular)
      }
      NSApp.activate(ignoringOtherApps: true)

      SFSpeechRecognizer.requestAuthorization { status in
        XpLog.write("speech: authorization -> \(status.rawValue) (3 == authorized)")
        DispatchQueue.main.async {
          if previousPolicy != .regular {
            NSApp.setActivationPolicy(previousPolicy)
          }
          result(status == .authorized)
        }
      }

    case "supportedLocales":
      result(SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted())

    case "start":
      XpLog.write(
        "speech: start requested (auth=\(SFSpeechRecognizer.authorizationStatus().rawValue))"
      )
      let requested = (args["sources"] as? [String]) ?? ["system"]
      let identifier = args["locale"] as? String
      start(sources: requested, localeIdentifier: identifier, result: result)

    case "stop":
      queue.async { [weak self] in
        self?.stopAllLocked()
        DispatchQueue.main.async { result(true) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func currentLocale() -> Locale {
    queue.sync { locale }
  }

  private static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  // MARK: - Lifecycle

  private func start(
    sources: [String],
    localeIdentifier: String?,
    result: @escaping FlutterResult
  ) {
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      result(
        FlutterError(
          code: "not_authorized",
          message: "Speech Recognition permission has not been granted",
          details: nil
        )
      )
      return
    }

    queue.async { [weak self] in
      guard let self else { return }

      if let localeIdentifier, !localeIdentifier.isEmpty {
        self.locale = Locale(identifier: localeIdentifier)
      }
      guard let probe = SFSpeechRecognizer(locale: self.locale), probe.isAvailable else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "unavailable",
              message: "No speech recogniser for \(self.locale.identifier)",
              details: nil
            )
          )
        }
        return
      }

      self.stopAllLocked()
      self.enabled = true

      self.converterLock.lock()
      self.converters = Dictionary(
        uniqueKeysWithValues: sources.map { ($0, Converter()) }
      )
      self.converterLock.unlock()

      // Sessions start idle. A recognition task is opened on the first loud
      // buffer, not here: handing a task nothing but silence makes it fail
      // immediately with "No speech detected", and reopening on that error is
      // an infinite loop that transcribes nothing and pins a core.
      for source in sources {
        self.sessions[source] = Session(source: source)
      }

      let started = Array(self.sessions.keys)
      let onDevice = probe.supportsOnDeviceRecognition
      let localeID = self.locale.identifier
      XpLog.write("speech: sessions open \(started) onDevice=\(onDevice)")

      DispatchQueue.main.async {
        result(["started": started, "onDevice": onDevice, "locale": localeID])
      }
    }
  }

  /// Opens a recognition task. Must be called on `queue`.
  private func openLocked(_ source: String) {
    guard enabled, let session = sessions[source] else { return }
    guard let recognizer = SFSpeechRecognizer(locale: locale) else { return }

    session.heardSpeech = false
    session.quietSince = nil
    session.speechStartedAt = nil
    session.endedAudio = false

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.addsPunctuation = true
    // Keep it local when the language model is installed: no network hop, no
    // audio leaving the machine, and it works on a hotel connection.
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }
    session.request = request

    let generation = session.generation
    session.task = recognizer.recognitionTask(with: request) {
      [weak self, weak session] result, error in
      guard let self else { return }
      self.queue.async {
        guard let session, session.generation == generation, self.enabled else { return }

        if let result {
          let text = result.bestTranscription.formattedString
          self.emit(source: session.source, text: text, isFinal: result.isFinal)
          if result.isFinal {
            XpLog.write("speech: \(session.source) FINAL \"\(text.prefix(60))\"")
            self.idleLocked(session)
          }
          return
        }

        if let error {
          let nsError = error as NSError
          // 1110 "No speech detected" is how the recogniser reports an
          // utterance that turned out to be silence — an ordinary outcome, not
          // a failure worth surfacing. 203/216/301 are cancellation during
          // teardown.
          let benign: Set<Int> = [203, 216, 301, 1110]
          if !benign.contains(nsError.code) {
            XpLog.write(
              "speech: \(session.source) error \(nsError.code) \(error.localizedDescription)"
            )
            self.emitError("Speech recognition: \(error.localizedDescription)")
          }
          self.idleLocked(session)
        }
      }
    }

    // Replay whatever arrived while the previous session was finalising, so
    // the first words of the next sentence are not lost.
    let carried = session.carryOver
    session.carryOver.removeAll()
    for buffer in carried {
      request.append(buffer)
    }
  }

  /// Closes the current utterance and waits for its final result.
  ///
  /// Deliberately does not cancel the task: `endAudio()` asks the recogniser to
  /// finish, while `cancel()` throws away everything recognised so far. An
  /// earlier version did both, which is why no transcript ever arrived.
  private func endUtteranceLocked(_ session: Session) {
    guard !session.endedAudio, session.request != nil else { return }
    session.endedAudio = true
    session.heardSpeech = false
    session.quietSince = nil
    session.speechStartedAt = nil
    session.request?.endAudio()

    let generation = session.generation
    let watchdog = DispatchWorkItem { [weak self, weak session] in
      guard let self, let session, session.generation == generation else { return }
      XpLog.write("speech: \(session.source) final timed out")
      self.idleLocked(session)
    }
    session.watchdog = watchdog
    queue.asyncAfter(deadline: .now() + finalResultTimeout, execute: watchdog)
  }

  /// Tears the finished task down and returns the session to idle.
  ///
  /// A new task is opened by `append` on the next loud buffer. Reopening
  /// eagerly here is what produced the "No speech detected" spin.
  private func idleLocked(_ session: Session) {
    session.watchdog?.cancel()
    session.watchdog = nil
    session.generation &+= 1

    session.task?.cancel()
    session.task = nil
    session.request = nil
    session.endedAudio = false
    session.heardSpeech = false
    session.quietSince = nil
    session.speechStartedAt = nil
  }

  private func stopAllLocked() {
    enabled = false
    for session in sessions.values {
      session.watchdog?.cancel()
      session.watchdog = nil
      session.generation &+= 1
      session.request?.endAudio()
      session.task?.cancel()
      session.request = nil
      session.task = nil
      session.carryOver.removeAll()
    }
    sessions.removeAll()

    converterLock.lock()
    converters.removeAll()
    converterLock.unlock()
  }

  var isRunning: Bool { queue.sync { enabled } }

  // MARK: - Audio in

  /// Feeds one captured buffer into that source's recogniser.
  ///
  /// Called on a capture thread. The buffer may be backed by memory that is
  /// only valid for the duration of the caller's callback — ScreenCaptureKit
  /// hands over a no-copy buffer — so it is converted into a freshly allocated
  /// one here, synchronously, before anything is handed to another queue.
  func append(buffer: AVAudioPCMBuffer, rms: Double, source: String) {
    guard let converted = convert(buffer, source: source) else { return }

    queue.async { [weak self] in
      guard let self, self.enabled, let session = self.sessions[source] else { return }

      // Idle, or finalising the previous utterance: keep a rolling pre-roll so
      // the first syllable is not clipped, and open a task once someone
      // actually speaks.
      guard let request = session.request, !session.endedAudio else {
        session.carryOver.append(converted)
        if session.carryOver.count > self.carryOverLimit {
          session.carryOver.removeFirst()
        }
        if session.request == nil, rms > self.speechThreshold {
          self.openLocked(source)
          if let opened = session.request {
            session.heardSpeech = true
            session.speechStartedAt = Date()
            session.quietSince = nil
            _ = opened
          }
        }
        return
      }

      request.append(converted)

      let now = Date()
      if rms > self.speechThreshold {
        if !session.heardSpeech {
          session.heardSpeech = true
          session.speechStartedAt = now
        }
        session.quietSince = nil
        if let started = session.speechStartedAt,
          now.timeIntervalSince(started) >= self.maxUtterance
        {
          self.endUtteranceLocked(session)
        }
        return
      }

      guard session.heardSpeech else { return }
      let quietSince = session.quietSince ?? now
      session.quietSince = quietSince
      if now.timeIntervalSince(quietSince) >= self.silenceToEndpoint {
        self.endUtteranceLocked(session)
      }
    }
  }

  /// Converts to 16 kHz mono float, always producing a new buffer.
  private func convert(_ buffer: AVAudioPCMBuffer, source: String) -> AVAudioPCMBuffer? {
    guard buffer.frameLength > 0 else { return nil }
    let target = SpeechRecognitionBridge.recognizerFormat

    converterLock.lock()
    guard let box = converters[source] else {
      converterLock.unlock()
      return nil
    }
    converterLock.unlock()

    let input = buffer.format
    if box.converter == nil || box.inputFormat != input {
      box.converter = AVAudioConverter(from: input, to: target)
      box.inputFormat = input
    }
    guard let converter = box.converter else { return nil }

    let ratio = target.sampleRate / input.sampleRate
    let capacity =
      AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
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
      return buffer
    }

    guard status != .error, error == nil, output.frameLength > 0 else { return nil }
    return output
  }
}
