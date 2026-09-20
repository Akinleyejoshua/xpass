import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xpass/core/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('settings migration', () {
    test('moves an old install off cloud transcription', () async {
      // v1 shipped geminiBatch as the default, so this is what an existing
      // install has stored — and why it kept hitting a quota after the default
      // changed.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'transcriptionBackend': 'geminiBatch',
      });

      final SettingsController controller = await SettingsController.load();

      expect(
        controller.value.transcriptionBackend,
        TranscriptionBackend.appleOnDevice,
      );
      expect(controller.value.transcriptionNeedsGeminiKey, isFalse);
    });

    test('runs once, so a deliberate later choice sticks', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'transcriptionBackend': 'geminiBatch',
        'settingsVersion': SettingsController.schemaVersion,
      });

      final SettingsController controller = await SettingsController.load();

      expect(
        controller.value.transcriptionBackend,
        TranscriptionBackend.geminiBatch,
        reason: 'already migrated — this is now an explicit choice',
      );
    });

    test('leaves other backends alone', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'transcriptionBackend': 'rivaNim',
      });

      final SettingsController controller = await SettingsController.load();

      expect(
        controller.value.transcriptionBackend,
        TranscriptionBackend.rivaNim,
      );
    });

    test('stops capturing the microphone on an existing install', () async {
      // v1 and v2 captured the mic by default. Only system audio is worth
      // transcribing, so an upgrade should stop.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'micEnabled': true,
        'settingsVersion': 2,
      });

      final SettingsController controller = await SettingsController.load();
      expect(controller.value.micEnabled, isFalse);
    });

    test(
      'keeps the microphone for anyone who asked to transcribe it',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'micEnabled': true,
          'transcribeMic': true,
          'settingsVersion': 2,
        });

        final SettingsController controller = await SettingsController.load();
        expect(controller.value.micEnabled, isTrue);
      },
    );

    test('a fresh install captures system audio only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SettingsController fresh = await SettingsController.load();

      expect(fresh.value.systemAudioEnabled, isTrue);
      expect(fresh.value.micEnabled, isFalse);
      expect(fresh.value.transcribeMic, isFalse);
    });

    test('a fresh install lands on-device', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final SettingsController controller = await SettingsController.load();

      expect(
        controller.value.transcriptionBackend,
        TranscriptionBackend.appleOnDevice,
      );
    });

    test('stamps the schema version', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SettingsController.load();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('settingsVersion'), SettingsController.schemaVersion);
    });
  });
}
