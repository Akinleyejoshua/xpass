import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xpass/core/constants/typography.dart';
import 'package:xpass/core/models/profile_models.dart';
import 'package:xpass/core/providers.dart';
import 'package:xpass/core/services/platform_channels.dart';
import 'package:xpass/core/services/profile_service.dart';
import 'package:xpass/core/services/settings_service.dart';
import 'package:xpass/features/hud/hud_view.dart';

/// Records what the HUD asked the native layer to do.
final List<String> nativeCalls = <String>[];

void mockChannels(WidgetTester tester) {
  final TestDefaultBinaryMessenger messenger =
      tester.binding.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(XpChannels.window, (MethodCall call) async {
    nativeCalls.add('window.${call.method}');
    return switch (call.method) {
      'getBounds' || 'setBounds' || 'setSize' || 'snapTo' || 'moveBy' =>
        <String, Object?>{'x': 0.0, 'y': 0.0, 'width': 880.0, 'height': 460.0},
      'setOpacity' => 0.96,
      'isVisible' || 'show' || 'toggleVisibility' => true,
      _ => false,
    };
  });

  messenger.setMockMethodCallHandler(XpChannels.media, (MethodCall call) async {
    nativeCalls.add('media.${call.method}');
    return switch (call.method) {
      'hasScreenPermission' || 'hasMicPermission' => true,
      'startAudio' => <String, Object?>{'mic': true, 'system': true},
      'listDisplays' => <Object?>[],
      _ => true,
    };
  });

  messenger.setMockMethodCallHandler(XpChannels.hotkeys, (MethodCall call) async {
    nativeCalls.add('hotkeys.${call.method}');
    return true;
  });

  // EventChannel handshakes arrive on a method channel of the same name.
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.xpass.app/audio'),
    (MethodCall call) async => null,
  );
}

Future<Widget> buildHud({UserProfile? profile}) async {
  final SettingsController settings = await SettingsController.load();
  final ProfileService profileService =
      ProfileService.inMemory(profile ?? const UserProfile());

  return ProviderScope(
    overrides: <Override>[
      settingsControllerProvider.overrideWithValue(settings),
      profileServiceProvider.overrideWithValue(profileService),
    ],
    child: MaterialApp(
      theme: buildXpassTheme(),
      home: const Material(
        type: MaterialType.transparency,
        child: HudView(),
      ),
    ),
  );
}

void main() {
  setUp(() {
    nativeCalls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders the HUD chrome', (WidgetTester tester) async {
    mockChannels(tester);
    await tester.binding.setSurfaceSize(const Size(900, 500));

    await tester.pumpWidget(await buildHud());
    await tester.pump();

    expect(find.text('xpass'), findsOneWidget);
    expect(find.text('Ready.'), findsOneWidget);
    expect(find.text('Wingman'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Screen'), findsOneWidget);
  });

  testWidgets('shows the global shortcut cheat sheet', (WidgetTester tester) async {
    mockChannels(tester);
    await tester.binding.setSurfaceSize(const Size(900, 500));

    await tester.pumpWidget(await buildHud());
    await tester.pump();

    expect(find.text('⌘⌥C'), findsOneWidget);
    expect(find.text('⌘⌥H'), findsOneWidget);
    expect(find.text('⌘⌥T'), findsOneWidget);
    expect(find.text('⌘⌥⌫'), findsOneWidget);
  });

  testWidgets('registers every global hotkey on startup',
      (WidgetTester tester) async {
    mockChannels(tester);
    await tester.binding.setSurfaceSize(const Size(900, 500));

    await tester.pumpWidget(await buildHud());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      nativeCalls.where((String c) => c == 'hotkeys.register').length,
      4,
      reason: 'panic, solve, click-through and clear',
    );
  });

  testWidgets('opens settings with no API key configured',
      (WidgetTester tester) async {
    mockChannels(tester);
    await tester.binding.setSurfaceSize(const Size(900, 500));

    await tester.pumpWidget(await buildHud());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // With nothing configured, the HUD lands on Settings rather than pretending
    // it is ready to answer.
    expect(find.text('API KEYS'), findsOneWidget);
  });

  testWidgets('reports how many profile facts are loaded',
      (WidgetTester tester) async {
    mockChannels(tester);
    await tester.binding.setSurfaceSize(const Size(900, 500));

    await tester.pumpWidget(
      await buildHud(
        profile: const UserProfile(
          name: 'Joshua Akinleye',
          headline: 'Full Stack Developer',
          entries: <ProfileEntry>[
            ProfileEntry(
              id: 'a',
              kind: ProfileEntryKind.experience,
              title: 'Full Stack Developer',
              organization: 'Corvendra',
            ),
            ProfileEntry(
              id: 'b',
              kind: ProfileEntryKind.project,
              title: 'xMachine',
              summary: 'Browser ML platform',
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2 PROFILE FACTS'), findsOneWidget);
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.ensureInitialized().setSurfaceSize(null);
  });
}
