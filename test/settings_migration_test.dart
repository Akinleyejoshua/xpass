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
