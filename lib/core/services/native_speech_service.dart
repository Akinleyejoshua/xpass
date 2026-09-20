import 'dart:async';

import 'package:flutter/services.dart';

import '../models/assist_models.dart';
import 'platform_channels.dart';

/// Whether the OS will let us transcribe.
enum SpeechAuthorization {
  authorized,
  denied,
  restricted,
  notDetermined;

  static SpeechAuthorization fromName(String? name) => switch (name) {
    'authorized' => SpeechAuthorization.authorized,
    'denied' => SpeechAuthorization.denied,
    'restricted' => SpeechAuthorization.restricted,
    _ => SpeechAuthorization.notDetermined,
  };

  bool get isGranted => this == SpeechAuthorization.authorized;
}

/// Result of bringing the recogniser up.
class SpeechStartResult {
  const SpeechStartResult({
    required this.started,
    required this.onDevice,
    required this.locale,
  });

  final List<String> started;

  /// False when the language model is not installed and Apple fell back to
  /// server-side recognition.
  final bool onDevice;
  final String locale;

  static SpeechStartResult fromMap(Map<Object?, Object?>? map) =>
      SpeechStartResult(
        started: (map?['started'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(),
        onDevice: map?['onDevice'] as bool? ?? false,
        locale: map?['locale'] as String? ?? 'en-US',
      );
}

/// One transcript update from the native recogniser.
class NativeSpeechEvent {
  const NativeSpeechEvent({
    required this.source,
    required this.text,
    required this.isFinal,
  });

  final String source;
  final String text;
  final bool isFinal;
}

/// Dart facade over `SpeechRecognitionBridge.swift`.
class NativeSpeechService {
  NativeSpeechService();

  Stream<Object?>? _raw;
  StreamSubscription<Object?>? _subscription;
  final StreamController<NativeSpeechEvent> _events =
      StreamController<NativeSpeechEvent>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();

  Stream<NativeSpeechEvent> get events => _events.stream;
  Stream<String> get errors => _errors.stream;

  Future<bool> isAvailable() async =>
      await _invoke<bool>('isAvailable') ?? false;

  Future<bool> supportsOnDevice() async =>
      await _invoke<bool>('supportsOnDevice') ?? false;

  Future<SpeechAuthorization> authorizationStatus() async =>
      SpeechAuthorization.fromName(
        await _invoke<String>('authorizationStatus'),
      );

  Future<bool> requestAuthorization() async =>
      await _invoke<bool>('requestAuthorization') ?? false;

  Future<List<String>> supportedLocales() async =>
      (await _invoke<List<Object?>>('supportedLocales') ?? const <Object?>[])
          .whereType<String>()
          .toList();

  Future<SpeechStartResult> start({
    required List<String> sources,
    String locale = 'en-US',
  }) async {
    _attach();
    try {
      final Map<Object?, Object?>? result = await XpChannels.speech
          .invokeMethod<Map<Object?, Object?>>('start', <String, Object?>{
            'sources': sources,
            'locale': locale,
          });
      return SpeechStartResult.fromMap(result);
    } on PlatformException catch (error) {
      throw AiServiceException(
        error.code == 'not_authorized'
            ? 'Speech Recognition permission is not granted. Enable xpass '
                  'under Privacy & Security › Speech Recognition.'
            : error.message ?? 'Could not start speech recognition.',
        provider: 'macOS Speech',
      );
    }
  }

  Future<void> stop() async {
    try {
      await XpChannels.speech.invokeMethod<bool>('stop');
    } on PlatformException {
      // Already stopped.
    }
  }

  void _attach() {
    if (_subscription != null) return;
    _raw = XpChannels.speechEvents.receiveBroadcastStream();
    _subscription = _raw!.listen(
      (Object? event) {
        if (event is! Map<Object?, Object?>) return;
        if (event['type'] == 'error') {
          if (!_errors.isClosed) {
            _errors.add(event['message'] as String? ?? 'Speech error.');
          }
          return;
        }
        if (_events.isClosed) return;
        _events.add(
          NativeSpeechEvent(
            source: event['source'] as String? ?? 'system',
            text: event['text'] as String? ?? '',
            isFinal: event['isFinal'] as bool? ?? false,
          ),
        );
      },
      onError: (Object error) {
        if (!_errors.isClosed) _errors.add(error.toString());
      },
      cancelOnError: false,
    );
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await XpChannels.speech.invokeMethod<T>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _subscription?.cancel();
    _subscription = null;
    await _events.close();
    await _errors.close();
  }
}
