import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/hud/controllers/hud_controller.dart';
import 'services/audio_capture_service.dart';
import 'services/gemini_service.dart';
import 'services/native_speech_service.dart';
import 'services/nvidia_nim_service.dart';
import 'services/portfolio_importer.dart';
import 'services/profile_service.dart';
import 'services/screen_capture_service.dart';
import 'services/settings_service.dart';
import 'services/window_service.dart';
import 'shortcuts/hotkey_service.dart';

/// Overridden in `main()` with the instance loaded from disk.
final Provider<SettingsController> settingsControllerProvider =
    Provider<SettingsController>(
      (Ref ref) => throw UnimplementedError(
        'settingsControllerProvider must be overridden in ProviderScope',
      ),
    );

/// Rebuilds anything watching settings whenever a value changes.
final ChangeNotifierProvider<SettingsController> settingsProvider =
    ChangeNotifierProvider<SettingsController>(
      (Ref ref) => ref.watch(settingsControllerProvider),
    );

/// Overridden in `main()` with the instance loaded from disk.
final Provider<ProfileService> profileServiceProvider =
    Provider<ProfileService>(
      (Ref ref) => throw UnimplementedError(
        'profileServiceProvider must be overridden in ProviderScope',
      ),
    );

/// Rebuilds anything watching the profile whenever an entry changes.
final ChangeNotifierProvider<ProfileService> profileProvider =
    ChangeNotifierProvider<ProfileService>(
      (Ref ref) => ref.watch(profileServiceProvider),
    );

final Provider<PortfolioImporter> portfolioImporterProvider =
    Provider<PortfolioImporter>((Ref ref) => PortfolioImporter());

final Provider<WindowService> windowServiceProvider = Provider<WindowService>(
  (Ref ref) => const WindowService(),
);

final Provider<ScreenCaptureService> screenCaptureServiceProvider =
    Provider<ScreenCaptureService>((Ref ref) => const ScreenCaptureService());

final Provider<AudioCaptureService> audioCaptureServiceProvider =
    Provider<AudioCaptureService>((Ref ref) {
      final AudioCaptureService service = AudioCaptureService();
      ref.onDispose(service.dispose);
      return service;
    });

final Provider<HotkeyService> hotkeyServiceProvider = Provider<HotkeyService>((
  Ref ref,
) {
  final HotkeyService service = HotkeyService();
  ref.onDispose(service.dispose);
  return service;
});

final Provider<NativeSpeechService> nativeSpeechServiceProvider =
    Provider<NativeSpeechService>((Ref ref) {
      final NativeSpeechService service = NativeSpeechService();
      ref.onDispose(service.dispose);
      return service;
    });

final Provider<GeminiService> geminiServiceProvider = Provider<GeminiService>(
  (Ref ref) => GeminiService(),
);

final Provider<NvidiaNimService> nvidiaNimServiceProvider =
    Provider<NvidiaNimService>((Ref ref) => NvidiaNimService());

final ChangeNotifierProvider<HudController> hudControllerProvider =
    ChangeNotifierProvider<HudController>((Ref ref) {
      return HudController(
        settings: ref.watch(settingsControllerProvider),
        window: ref.watch(windowServiceProvider),
        screen: ref.watch(screenCaptureServiceProvider),
        audio: ref.watch(audioCaptureServiceProvider),
        hotkeys: ref.watch(hotkeyServiceProvider),
        gemini: ref.watch(geminiServiceProvider),
        nim: ref.watch(nvidiaNimServiceProvider),
        profile: ref.watch(profileServiceProvider),
        portfolio: ref.watch(portfolioImporterProvider),
        speech: ref.watch(nativeSpeechServiceProvider),
      );
    });
