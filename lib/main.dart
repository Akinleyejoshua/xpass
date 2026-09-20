import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/colors.dart';
import 'core/constants/typography.dart';
import 'core/providers.dart';
import 'core/services/profile_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/window_service.dart';
import 'features/hud/hud_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load everything the first frame depends on before painting, so the HUD
  // never flashes an unconfigured state on screen.
  final SettingsController settings = await SettingsController.load();
  final ProfileService profile = await ProfileService.load();

  const WindowService window = WindowService();
  await window.setSize(_hudWidth, _hudHeight);
  await window.snapTo(HudAnchor.topCenter);
  await window.setOpacity(settings.value.opacity);
  await window.show();

  runApp(
    ProviderScope(
      overrides: <Override>[
        settingsControllerProvider.overrideWithValue(settings),
        profileServiceProvider.overrideWithValue(profile),
      ],
      child: const XpassApp(),
    ),
  );
}

/// Wide enough for a code block without horizontal scrolling, short enough to
/// sit above a video call without covering a face.
const double _hudWidth = 880;
const double _hudHeight = 460;

class XpassApp extends StatelessWidget {
  const XpassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xpass',
      debugShowCheckedModeBanner: false,
      theme: buildXpassTheme(),
      // The native window is transparent; Flutter paints the rounded panel.
      color: XpColors.background,
      home: const Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(style: XpType.body, child: HudView()),
      ),
    );
  }
}
