import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/core/services/audio_capture_service.dart';
import 'package:xpass/core/services/gemini_service.dart';
import 'package:xpass/core/services/native_speech_service.dart';
import 'package:xpass/core/services/nvidia_nim_service.dart';
import 'package:xpass/core/services/platform_channels.dart';
import 'package:xpass/core/services/portfolio_importer.dart';
import 'package:xpass/core/services/profile_service.dart';
import 'package:xpass/core/services/screen_capture_service.dart';
import 'package:xpass/core/services/settings_service.dart';
import 'package:xpass/core/services/window_service.dart';
import 'package:xpass/core/models/profile_models.dart';
import 'package:xpass/core/shortcuts/hotkey_service.dart';
import 'package:xpass/features/hud/controllers/hud_controller.dart';

/// Mocks every platform channel. `speechAuthorized` controls whether the
/// on-device recogniser can start — the case that used to take the whole HUD
/// down with it.
void mockChannels({required bool speechAuthorized}) {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    XpChannels.window,
    (MethodCall call) async => switch (call.method) {
      'setOpacity' => 0.96,
      'getBounds' || 'setBounds' || 'setSize' || 'snapTo' => <String, Object?>{
        'x': 0.0,
        'y': 0.0,
        'width': 880.0,
        'height': 460.0,
      },
      _ => true,
    },
  );

  messenger.setMockMethodCallHandler(
    XpChannels.media,
    (MethodCall call) async => switch (call.method) {
      'startAudio' => <String, Object?>{'mic': true, 'system': true},
      'listDisplays' => <Object?>[],
      _ => true,
    },
  );

  messenger.setMockMethodCallHandler(
    XpChannels.hotkeys,
    (MethodCall call) async => true,
  );

  messenger.setMockMethodCallHandler(XpChannels.speech, (
    MethodCall call,
  ) async {
    switch (call.method) {
      case 'isAvailable':
      case 'supportsOnDevice':
        return true;
      case 'authorizationStatus':
        return speechAuthorized ? 'authorized' : 'denied';
      case 'requestAuthorization':
        return speechAuthorized;
      case 'start':
        if (!speechAuthorized) {
          throw PlatformException(
            code: 'not_authorized',
            message: 'Speech Recognition permission has not been granted',
          );
        }
        return <String, Object?>{
          'started': <Object?>['system'],
          'onDevice': true,
          'locale': 'en-US',
        };
      default:
        return true;
    }
  });

  messenger.setMockMethodCallHandler(
    const MethodChannel('com.xpass.app/audio'),
    (MethodCall call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.xpass.app/speech_events'),
    (MethodCall call) async => null,
  );
}

Future<HudController> buildController() async {
  final SettingsController settings = await SettingsController.load();
  return HudController(
    settings: settings,
    window: const WindowService(),
    screen: const ScreenCaptureService(),
    audio: AudioCaptureService(),
    hotkeys: HotkeyService(),
    gemini: GeminiService(),
    nim: NvidiaNimService(),
    profile: ProfileService.inMemory(const UserProfile()),
    portfolio: PortfolioImporter(),
    speech: NativeSpeechService(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('capture survives a transcription failure', () async {
    // The regression this guards: an ungranted Speech Recognition prompt used
    // to return early from startListening, before the audio subscription was
    // attached — so the level meters never moved and the HUD looked dead.
    mockChannels(speechAuthorized: false);

    final HudController hud = await buildController();
    await hud.startListening();

    expect(hud.isListening, isTrue, reason: 'audio must keep running');
    expect(hud.micActive, isTrue);
    expect(hud.systemAudioActive, isTrue);
    expect(hud.status, isNot(HudStatus.error));
    expect(
      hud.pipelineError,
      contains('still being captured'),
      reason: 'the user needs to know it is degraded, not dead',
    );

    hud.dispose();
  });

  test('everything comes up when speech is granted', () async {
    mockChannels(speechAuthorized: true);

    final HudController hud = await buildController();
    await hud.startListening();

    expect(hud.isListening, isTrue);
    expect(hud.status, HudStatus.listening);
    expect(hud.pipelineError, isNull);

    hud.dispose();
  });

  test('listening does not require an API key', () async {
    // Transcription is local now, so there is no reason to sit deaf waiting
    // for a key that only gates answering.
    mockChannels(speechAuthorized: true);

    final HudController hud = await buildController();
    // The machine running the tests may have keys exported, so clear them
    // explicitly rather than assuming an empty environment.
    await hud.settings.update(
      hud.settings.value.copyWith(nvidiaApiKey: '', geminiApiKey: ''),
    );
    expect(hud.settings.value.isConfigured, isFalse);

    await hud.startListening();
    expect(hud.isListening, isTrue);

    hud.dispose();
  });

  test('stopListening tears everything down', () async {
    mockChannels(speechAuthorized: true);

    final HudController hud = await buildController();
    await hud.startListening();
    await hud.stopListening();

    expect(hud.isListening, isFalse);
    expect(hud.micActive, isFalse);
    expect(hud.systemAudioActive, isFalse);
    expect(hud.status, HudStatus.muted);

    hud.dispose();
  });
}
