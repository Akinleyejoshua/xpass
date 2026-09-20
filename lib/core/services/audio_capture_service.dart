import 'dart:async';

import 'package:flutter/services.dart';

import '../models/audio_models.dart';
import 'platform_channels.dart';

/// Outcome of trying to bring both capture paths up.
class AudioStartResult {
  const AudioStartResult({
    required this.micStarted,
    required this.systemStarted,
    this.micError,
    this.systemError,
  });

  final bool micStarted;
  final bool systemStarted;
  final String? micError;
  final String? systemError;

  bool get anyStarted => micStarted || systemStarted;

  /// The single message worth showing the user, if anything went wrong.
  String? get firstError => micError ?? systemError;

  static AudioStartResult fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const AudioStartResult(micStarted: false, systemStarted: false);
    }
    return AudioStartResult(
      micStarted: map['mic'] as bool? ?? false,
      systemStarted: map['system'] as bool? ?? false,
      micError: map['micError'] as String?,
      systemError: map['systemError'] as String?,
    );
  }
}

/// Dart-side facade over the CoreAudio + ScreenCaptureKit audio half of
/// `NativeAudioScreenBridge.swift`.
///
/// Exposes one broadcast stream carrying both sources, tagged — downstream the
/// VAD keeps a separate detector per source.
class AudioCaptureService {
  AudioCaptureService();

  Stream<Object?>? _raw;
  final StreamController<AudioFrame> _frames =
      StreamController<AudioFrame>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  StreamSubscription<Object?>? _subscription;
  bool _running = false;

  Stream<AudioFrame> get frames => _frames.stream;
  Stream<String> get errors => _errors.stream;
  bool get isRunning => _running;

  // -------------------------------------------------------------- permissions
  Future<bool> hasMicPermission() async {
    try {
      return await XpChannels.media.invokeMethod<bool>('hasMicPermission') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestMicPermission() async {
    try {
      return await XpChannels.media.invokeMethod<bool>(
            'requestMicPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  // ------------------------------------------------------------------ control
  Future<AudioStartResult> start({bool mic = true, bool system = true}) async {
    _attach();
    try {
      final Map<Object?, Object?>? result = await XpChannels.media
          .invokeMethod<Map<Object?, Object?>>('startAudio', <String, Object?>{
            'mic': mic,
            'system': system,
          });
      final AudioStartResult parsed = AudioStartResult.fromMap(result);
      _running = parsed.anyStarted;
      return parsed;
    } on PlatformException catch (error) {
      _running = false;
      return AudioStartResult(
        micStarted: false,
        systemStarted: false,
        micError: error.message,
      );
    }
  }

  Future<void> stop() async {
    _running = false;
    try {
      await XpChannels.media.invokeMethod<bool>('stopAudio');
    } on PlatformException {
      // Already down.
    }
  }

  void _attach() {
    if (_subscription != null) return;
    _raw = XpChannels.audio.receiveBroadcastStream();
    _subscription = _raw!.listen(
      (Object? event) {
        if (event is! Map<Object?, Object?>) return;
        if (event['type'] == 'error') {
          _running = false;
          _errors.add(event['message'] as String? ?? 'Audio capture stopped.');
          return;
        }
        if (_frames.isClosed) return;
        _frames.add(AudioFrame.fromEvent(event));
      },
      onError: (Object error) {
        _running = false;
        if (!_errors.isClosed) _errors.add(error.toString());
      },
      cancelOnError: false,
    );
  }

  Future<void> dispose() async {
    await stop();
    await _subscription?.cancel();
    _subscription = null;
    await _frames.close();
    await _errors.close();
  }
}
