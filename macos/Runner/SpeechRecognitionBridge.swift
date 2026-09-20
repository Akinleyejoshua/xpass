import AVFoundation
import FlutterMacOS
import Foundation
import Speech

/// On-device speech-to-text via Apple's Speech framework.
///
/// This is the default transcription path, and it should be: dictation is a
/// solved problem that the OS already does locally. Sending every utterance to
/// a frontier model instead costs an API key, a network round trip per
/// sentence, and a per-minute quota — for worse latency on a task the Mac
/// performs for free.
///
/// One session per audio source, because the microphone and the system-audio
/// loopback are separate conversations and must not be interleaved into one
/// transcript.
///
/// Method channel: `com.xpass.app/speech`
/// Event channel:  `com.xpass.app/speech_events`
final class SpeechRecognitionBridge: NSObject, FlutterStreamHandler {

  static let methodChannelName = "com.xpass.app/speech"
  static let eventChannelName = "com.xpass.app/speech_events"

  /// A live recognition session for one audio source.
  private final class Session {
    init(source: String, recognizer: SFSpeechRecognizer) {
      self.source = source
      self.recognizer = recognizer
    }

    let source: String
    let recognizer: SFSpeechRecognizer
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?

    /// Consecutive quiet buffers since the last speech, for endpointing.
    var quietBuffers = 0
    var heardSpeech = false
    var restarting = false
    var latest = ""
  }

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var sessions: [String: Session] = [:]
  private var locale = Locale(identifier: "en-US")
  private var enabled = false

  /// Roughly 700 ms of silence closes an utterance. Long enough to ride out a
  /// mid-sentence pause, short enough that the answer is not held back.
  private let quietBuffersToEndpoint = 7

  /// A single recognition task is not meant to run forever, so each utterance
  /// gets its own and the session restarts between them.
  private let queue = DispatchQueue(label: "ai.xpass.speech")

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
      result(SFSpeechRecognizer(locale: locale)?.isAvailable ?? false)

    case "supportsOnDevice":
      result(SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false)

    case "authorizationStatus":
      result(SpeechRecognitionBridge.describe(SFSpeechRecognizer.authorizationStatus()))

    case "requestAuthorization":
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
          result(status == .authorized)
        }
      }

    case "supportedLocales":
      result(
        SFSpeechRecognizer.supportedLocales()
          .map(\.identifier)
          .sorted()
      )

    case "start":
      if let identifier = args["locale"] as? String, !identifier.isEmpty {
        locale = Locale(identifier: identifier)
      }
      let sources = (args["sources"] as? [String]) ?? ["system"]
      start(sources: sources, result: result)

    case "stop":
      stopAll()
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
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

  // MARK: - Session lifecycle

  private func start(sources: [String], result: @escaping FlutterResult) {
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
    guard let probe = SFSpeechRecognizer(locale: locale), probe.isAvailable else {
      result(
        FlutterError(
          code: "unavailable",
          message: "No speech recogniser for \(locale.identifier)",
          details: nil
        )
      )
      return
    }

    stopAll()
    enabled = true
    for source in sources {
      openSession(for: source)
    }

    result([
      "started": Array(sessions.keys),
      "onDevice": probe.supportsOnDeviceRecognition,
      "locale": locale.identifier,
    ])
  }

  private func openSession(for source: String) {
    guard enabled, let recognizer = SFSpeechRecognizer(locale: locale) else { return }

    let session = sessions[source] ?? Session(source: source, recognizer: recognizer)
    session.quietBuffers = 0
    session.heardSpeech = false
    session.restarting = false
    session.latest = ""

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
    session.task = recognizer.recognitionTask(with: request) { [weak self, weak session] result, error in
      guard let self, let session else { return }

      if let result {
        let text = result.bestTranscription.formattedString
        session.latest = text
        self.emit(source: session.source, text: text, isFinal: result.isFinal)
        if result.isFinal {
          self.restart(session)
        }
        return
      }

      if let error {
        // A cancelled task during teardown is expected; anything else is worth
        // reporting once, then recovering from.
        let code = (error as NSError).code
        if self.enabled, code != 203, code != 216, code != 301 {
          self.emitError("Speech recognition: \(error.localizedDescription)")
        }
        self.restart(session)
      }
    }

    sessions[source] = session
  }

  /// Ends the current utterance and opens a fresh task for the next one.
  private func restart(_ session: Session) {
    guard enabled, !session.restarting else { return }
    session.restarting = true

    session.request?.endAudio()
    session.task?.cancel()
    session.request = nil
    session.task = nil

    // A short gap keeps a failing recogniser from spinning.
    queue.asyncAfter(deadline: .now() + 0.15) { [weak self, weak session] in
      guard let self, let session, self.enabled else { return }
      DispatchQueue.main.async { self.openSession(for: session.source) }
    }
  }

  private func stopAll() {
    enabled = false
    for session in sessions.values {
      session.request?.endAudio()
      session.task?.cancel()
      session.request = nil
      session.task = nil
    }
    sessions.removeAll()
  }

  // MARK: - Audio in

  /// Feeds one buffer from a capture tap into that source's recogniser.
  ///
  /// `rms` drives endpointing: the Speech framework will happily accumulate one
  /// unbounded transcription, so silence is what marks the end of a question
  /// and releases a final result.
  func append(buffer: AVAudioPCMBuffer, rms: Double, source: String) {
    guard enabled, let session = sessions[source], let request = session.request else {
      return
    }

    request.append(buffer)

    if rms > 0.015 {
      session.heardSpeech = true
      session.quietBuffers = 0
      return
    }

    guard session.heardSpeech else { return }
    session.quietBuffers += 1
    if session.quietBuffers >= quietBuffersToEndpoint {
      session.heardSpeech = false
      session.quietBuffers = 0
      restart(session)
    }
  }

  var isRunning: Bool { enabled }

  deinit {
    stopAll()
  }
}
