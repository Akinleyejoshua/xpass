import 'package:flutter/services.dart';

/// Every channel name shared with the native macOS layer, in one place so the
/// Swift and Dart sides can never drift apart silently.
abstract final class XpChannels {
  /// `macos/Runner/StealthWindowBridge.swift`
  static const MethodChannel window = MethodChannel('com.xpass.app/window');

  /// `macos/Runner/NativeAudioScreenBridge.swift`
  static const MethodChannel media = MethodChannel('com.xpass.app/media');

  /// PCM frames from the microphone and the system-audio loopback.
  static const EventChannel audio = EventChannel('com.xpass.app/audio');

  /// `macos/Runner/GlobalHotkeyBridge.swift`
  static const MethodChannel hotkeys = MethodChannel('com.xpass.app/hotkeys');

  /// `macos/Runner/SpeechRecognitionBridge.swift`
  static const MethodChannel speech = MethodChannel('com.xpass.app/speech');

  /// Partial and final transcripts from the on-device recogniser.
  static const EventChannel speechEvents = EventChannel(
    'com.xpass.app/speech_events',
  );
}
