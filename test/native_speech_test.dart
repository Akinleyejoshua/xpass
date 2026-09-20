import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/models/audio_models.dart';
import 'package:xpass/core/services/gemini_service.dart';
import 'package:xpass/core/services/native_speech_service.dart';
import 'package:xpass/core/services/platform_channels.dart';
import 'package:xpass/core/services/settings_service.dart';
import 'package:xpass/core/services/transcription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _migrationAndFallbackTests();

  group('backend selection', () {
    Transcriber build(TranscriptionBackend backend, {XpSettings? settings}) =>
        buildTranscriber(
          backend: backend,
          settings: (settings ?? const XpSettings()).copyWith(
            transcriptionBackend: backend,
          ),
          gemini: GeminiService(),
          speech: NativeSpeechService(),
        );

    test('on-device is the default', () {
      expect(
        const XpSettings().transcriptionBackend,
        TranscriptionBackend.appleOnDevice,
      );
      expect(
        TranscriptionBackend.fromName(null),
        TranscriptionBackend.appleOnDevice,
      );
      expect(
        TranscriptionBackend.fromName('nonsense'),
        TranscriptionBackend.appleOnDevice,
      );
    });

    test('the default needs no cloud key', () {
      expect(const XpSettings().transcriptionNeedsGeminiKey, isFalse);
      expect(
        const XpSettings(
          transcriptionBackend: TranscriptionBackend.geminiBatch,
        ).transcriptionNeedsGeminiKey,
        isTrue,
      );
      expect(
        const XpSettings(
          transcriptionBackend: TranscriptionBackend.geminiLive,
        ).transcriptionNeedsGeminiKey,
        isTrue,
      );
      expect(
        const XpSettings(
          transcriptionBackend: TranscriptionBackend.rivaNim,
        ).transcriptionNeedsGeminiKey,
        isFalse,
      );
    });

    test('each backend builds its own transcriber', () {
      expect(
        build(TranscriptionBackend.appleOnDevice),
        isA<NativeSpeechTranscriber>(),
      );
      expect(
        build(TranscriptionBackend.geminiBatch),
        isA<GeminiBatchTranscriber>(),
      );
      expect(build(TranscriptionBackend.rivaNim), isA<RivaNimTranscriber>());
    });

    test('listens to the other side only, by default', () {
      // The whole point: on a call, system audio is the other participants,
      // already mixed and without room echo. The microphone adds nothing to
      // answer with, and on speakers it re-captures them as if they were you.
      final NativeSpeechTranscriber themOnly =
          build(TranscriptionBackend.appleOnDevice) as NativeSpeechTranscriber;
      expect(themOnly.sources, <AudioSource>[AudioSource.system]);
    });

    test('adds the microphone only when explicitly asked for both', () {
      final NativeSpeechTranscriber both =
          build(
                TranscriptionBackend.appleOnDevice,
                settings: const XpSettings(
                  micEnabled: true,
                  transcribeMic: true,
                ),
              )
              as NativeSpeechTranscriber;
      expect(both.sources, <AudioSource>[AudioSource.mic, AudioSource.system]);
    });
  });

  group('NativeSpeechService', () {
    final List<MethodCall> calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(XpChannels.speech, (MethodCall call) async {
            calls.add(call);
            return switch (call.method) {
              'isAvailable' ||
              'supportsOnDevice' ||
              'requestAuthorization' => true,
              'authorizationStatus' => 'authorized',
              'supportedLocales' => <Object?>['en-US', 'fr-FR'],
              'start' => <String, Object?>{
                'started': <Object?>['system'],
                'onDevice': true,
                'locale': 'en-US',
              },
              _ => true,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(XpChannels.speech, null);
    });

    test('reads availability and authorization', () async {
      final NativeSpeechService service = NativeSpeechService();
      expect(await service.isAvailable(), isTrue);
      expect(await service.supportsOnDevice(), isTrue);
      expect(
        await service.authorizationStatus(),
        SpeechAuthorization.authorized,
      );
      expect(await service.supportedLocales(), contains('en-US'));
    });

    test('passes the sources and locale through to native', () async {
      final NativeSpeechService service = NativeSpeechService();
      final SpeechStartResult result = await service.start(
        sources: <String>['system'],
        locale: 'en-GB',
      );

      expect(result.onDevice, isTrue);
      expect(result.started, <String>['system']);

      final MethodCall start = calls.firstWhere(
        (MethodCall c) => c.method == 'start',
      );
      final Map<Object?, Object?> args =
          start.arguments as Map<Object?, Object?>;
      expect(args['sources'], <String>['system']);
      expect(args['locale'], 'en-GB');
    });

    test('maps every authorization state', () {
      expect(
        SpeechAuthorization.fromName('denied'),
        SpeechAuthorization.denied,
      );
      expect(
        SpeechAuthorization.fromName('restricted'),
        SpeechAuthorization.restricted,
      );
      expect(
        SpeechAuthorization.fromName(null),
        SpeechAuthorization.notDetermined,
      );
      expect(SpeechAuthorization.denied.isGranted, isFalse);
      expect(SpeechAuthorization.authorized.isGranted, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Migration + fallback signalling
// ---------------------------------------------------------------------------

void _migrationAndFallbackTests() {
  group('TranscriberIssue', () {
    test('a plain failure does not demand a fallback', () {
      expect(const TranscriberIssue('hiccup').requiresFallback, isFalse);
    });

    test('a quota failure does', () {
      expect(
        const TranscriberIssue(
          'rate limited',
          requiresFallback: true,
        ).requiresFallback,
        isTrue,
      );
    });
  });
}
