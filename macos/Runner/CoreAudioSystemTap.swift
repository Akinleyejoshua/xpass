import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// System-audio capture via a Core Audio process tap.
///
/// This is how xpass hears the other side of a call. It replaces the earlier
/// ScreenCaptureKit route for one reason: on macOS, ScreenCaptureKit's audio
/// lives behind the *Screen Recording* permission, so simply listening to a
/// call required the same grant as reading the screen. A Core Audio process tap
/// (macOS 14.2+) is gated on Audio Capture instead, which keeps the two
/// concerns separate — screen solving can be declined without going deaf.
///
/// The shape of it: a global tap that excludes our own process is attached to a
/// private aggregate device wrapping the current default output, and an IO proc
/// on that device receives everything the machine is about to play.
@available(macOS 14.2, *)
final class CoreAudioSystemTap {

  private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
  private var ioProcID: AudioDeviceIOProcID?
  private var tapFormat: AVAudioFormat?

  private let converter = PCMConverter()
  private let callbackQueue = DispatchQueue(label: "ai.xpass.coreaudiotap")

  private var onFrame: ((Data, Double) -> Void)?
  private var onBuffer: ((AVAudioPCMBuffer, Double) -> Void)?

  /// Called once if the tap turns out to be delivering nothing but silence.
  var onSilentStream: (() -> Void)?

  // Diagnostics: distinguishes "the IO proc never fires" from "it fires but
  // the audio is silent", which have completely different causes.
  private var callbackCount = 0
  private var framesSeen = 0
  private var peakLevel = 0.0
  private var lastReport = Date()

  private(set) var isRunning = false

  // MARK: - Lifecycle

  func start(
    onFrame: @escaping (Data, Double) -> Void,
    onBuffer: ((AVAudioPCMBuffer, Double) -> Void)? = nil
  ) throws {
    guard !isRunning else { return }
    self.onFrame = onFrame
    self.onBuffer = onBuffer

    try createTap()
    try createAggregateDevice()
    try startIO()

    isRunning = true
    XpLog.write(
      "coreaudio: system tap running (format \(tapFormat?.sampleRate ?? 0) Hz, "
        + "\(tapFormat?.channelCount ?? 0) ch)"
    )
  }

  func stop() {
    if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
      AudioDeviceStop(aggregateID, ioProcID)
      AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
    }
    ioProcID = nil

    if aggregateID != AudioObjectID(kAudioObjectUnknown) {
      AudioHardwareDestroyAggregateDevice(aggregateID)
      aggregateID = AudioObjectID(kAudioObjectUnknown)
    }
    if tapID != AudioObjectID(kAudioObjectUnknown) {
      AudioHardwareDestroyProcessTap(tapID)
      tapID = AudioObjectID(kAudioObjectUnknown)
    }

    onFrame = nil
    onBuffer = nil
    tapFormat = nil
    isRunning = false
  }

  deinit { stop() }

  // MARK: - Tap

  private func createTap() throws {
    // Everything the machine plays, minus our own output, so an answer read
    // aloud can never be fed back in as a question.
    //
    // The exclusion list takes Core Audio *process object* ids, not pids, so
    // our own pid has to be translated first.
    let excluded = CoreAudioSystemTap.processObject(for: getpid())
    let description = CATapDescription(
      stereoGlobalTapButExcludeProcesses: excluded.map { [$0] } ?? []
    )
    description.uuid = UUID()
    description.name = "xpass system audio"
    description.isPrivate = true
    description.isExclusive = false
    // Leave the user's audio audible; this is a tap, not a redirect.
    description.muteBehavior = CATapMuteBehavior.unmuted

    // Creating the tap is what triggers the Audio Capture TCC prompt, and a
    // prompt cannot be presented by an .accessory app — xpass ships as
    // LSUIElement, so without this the request is never shown and macOS
    // silently delivers zeroed audio instead of failing. Promote for the call,
    // then drop straight back to staying out of the way.
    let previousPolicy = NSApp.activationPolicy()
    if previousPolicy != .regular {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    }
    defer {
      if previousPolicy != .regular {
        NSApp.setActivationPolicy(previousPolicy)
      }
    }

    var id = AudioObjectID(kAudioObjectUnknown)
    let status = AudioHardwareCreateProcessTap(description, &id)
    guard status == noErr, id != AudioObjectID(kAudioObjectUnknown) else {
      throw CoreAudioTapError.failed(
        "Could not create the audio tap (OSStatus \(status)). Grant Audio "
          + "Recording under Privacy & Security, then relaunch.",
        status
      )
    }
    tapID = id
    tapFormat = try readTapFormat(id)
    tapUUID = description.uuid
  }

  private var tapUUID: UUID?

  /// Translates a pid into the Core Audio process object that represents it.
  private static func processObject(for pid: pid_t) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var input = pid
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      UInt32(MemoryLayout<pid_t>.size),
      &input,
      &size,
      &object
    )
    guard status == noErr, object != AudioObjectID(kAudioObjectUnknown) else {
      return nil
    }
    return object
  }

  private func readTapFormat(_ id: AudioObjectID) throws -> AVAudioFormat {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &asbd)
    guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
      throw CoreAudioTapError.failed("Could not read the tap format", status)
    }
    return format
  }

  // MARK: - Aggregate device

  private func createAggregateDevice() throws {
    guard let tapUUID else {
      throw CoreAudioTapError.failed("Tap was not created", -1)
    }
    let outputUID = try defaultOutputDeviceUID()
    let aggregateUID = UUID().uuidString

    // Private, so it never appears in Sound preferences or in another app's
    // device list.
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "xpass Aggregate",
      kAudioAggregateDeviceUIDKey: aggregateUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: outputUID]
      ],
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapUIDKey: tapUUID.uuidString,
          kAudioSubTapDriftCompensationKey: true,
        ]
      ],
    ]

    var id = AudioObjectID(kAudioObjectUnknown)
    let status = AudioHardwareCreateAggregateDevice(
      description as CFDictionary,
      &id
    )
    guard status == noErr, id != AudioObjectID(kAudioObjectUnknown) else {
      throw CoreAudioTapError.failed(
        "Could not create the aggregate device (OSStatus \(status))",
        status
      )
    }
    aggregateID = id
  }

  private func defaultOutputDeviceUID() throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
      throw CoreAudioTapError.failed("No default output device", status)
    }

    address.mSelector = kAudioDevicePropertyDeviceUID
    var uid: CFString = "" as CFString
    var uidSize = UInt32(MemoryLayout<CFString?>.size)
    status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &uidSize, &uid)
    guard status == noErr else {
      throw CoreAudioTapError.failed("Could not read the output device UID", status)
    }
    return uid as String
  }

  // MARK: - IO

  private func startIO() throws {
    guard let format = tapFormat else {
      throw CoreAudioTapError.failed("Tap format unavailable", -1)
    }

    var procID: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(
      &procID,
      aggregateID,
      callbackQueue
    ) { [weak self] _, inputData, _, _, _ in
      self?.handle(inputData, format: format)
    }
    guard status == noErr, let procID else {
      throw CoreAudioTapError.failed(
        "Could not attach to the aggregate device (OSStatus \(status))",
        status
      )
    }
    ioProcID = procID

    let startStatus = AudioDeviceStart(aggregateID, procID)
    guard startStatus == noErr else {
      throw CoreAudioTapError.failed(
        "Could not start the aggregate device (OSStatus \(startStatus))",
        startStatus
      )
    }
  }

  private func handle(
    _ inputData: UnsafePointer<AudioBufferList>,
    format: AVAudioFormat
  ) {
    callbackCount += 1

    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        bufferListNoCopy: inputData
      ),
      buffer.frameLength > 0,
      let pcm = converter.convert(buffer)
    else {
      report()
      return
    }

    let level = PCMConverter.rms(of: pcm)
    framesSeen += Int(buffer.frameLength)
    peakLevel = max(peakLevel, level)
    report()

    onFrame?(pcm, level)
    // The buffer is only valid for this callback, so anything downstream must
    // copy synchronously — which the speech bridge does.
    onBuffer?(buffer, level)
  }

  /// Set when the tap delivers audio that is audibly present.
  private(set) var hasHeardAudio = false

  /// Set when the tap has been running for a while and produced only silence —
  /// which is how macOS denies audio capture, rather than returning an error.
  private(set) var looksDenied = false

  private var silentReports = 0

  private func report() {
    let now = Date()
    guard now.timeIntervalSince(lastReport) >= 3 else { return }
    lastReport = now

    if peakLevel > 0 {
      hasHeardAudio = true
      looksDenied = false
      silentReports = 0
    } else if framesSeen > 0 {
      silentReports += 1
      // Three reporting windows of frames that are all exactly zero is not a
      // quiet room; a quiet room still has a noise floor.
      if silentReports >= 3, !hasHeardAudio, !looksDenied {
        looksDenied = true
        XpLog.write(
          "coreaudio: receiving frames but every sample is zero — Audio "
            + "Capture is almost certainly not granted"
        )
        onSilentStream?()
      }
    }
    XpLog.write(
      "coreaudio: \(callbackCount) callbacks, \(framesSeen) frames, peak rms "
        + String(format: "%.4f", peakLevel)
    )
    callbackCount = 0
    framesSeen = 0
    peakLevel = 0
  }
}

enum CoreAudioTapError: LocalizedError {
  case failed(String, OSStatus)

  var errorDescription: String? {
    switch self {
    case let .failed(message, _): return message
    }
  }
}
