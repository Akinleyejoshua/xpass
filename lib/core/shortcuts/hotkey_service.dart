import 'package:flutter/services.dart';

import '../models/hotkey_binding.dart';
import '../services/platform_channels.dart';

/// Registers the four global shortcuts and routes presses back to the HUD.
///
/// Registration goes through Carbon in `GlobalHotkeyBridge.swift`, so these
/// fire while xpass is hidden and unfocused, and need no Accessibility grant.
/// A binding macOS or another app has already claimed simply fails to
/// register — that is surfaced in [failures] rather than thrown, so one bad
/// shortcut never stops the other three from working.
class HotkeyService {
  HotkeyService() {
    XpChannels.hotkeys.setMethodCallHandler(_onNativeCall);
  }

  final Map<HotkeyAction, VoidCallback> _handlers =
      <HotkeyAction, VoidCallback>{};
  final Map<HotkeyAction, String> _failures = <HotkeyAction, String>{};

  Map<HotkeyAction, HotkeyBinding> _bindings = MacKeyCodes.defaults;

  /// Bindings that could not be claimed, with the reason.
  Map<HotkeyAction, String> get failures =>
      Map<HotkeyAction, String>.unmodifiable(_failures);

  Map<HotkeyAction, HotkeyBinding> get bindings =>
      Map<HotkeyAction, HotkeyBinding>.unmodifiable(_bindings);

  /// Wire an action to its handler. Safe to call before [applyBindings].
  void on(HotkeyAction action, VoidCallback handler) {
    _handlers[action] = handler;
  }

  /// Registers (or re-registers) every binding. Idempotent.
  Future<void> applyBindings(Map<HotkeyAction, HotkeyBinding> bindings) async {
    _bindings = bindings;
    _failures.clear();

    for (final MapEntry<HotkeyAction, HotkeyBinding> entry
        in bindings.entries) {
      try {
        await XpChannels.hotkeys.invokeMethod<bool>(
          'register',
          entry.value.toChannelArgs(entry.key.id),
        );
      } on PlatformException catch (error) {
        _failures[entry.key] =
            error.message ?? '${entry.value.display} is already in use.';
      } on MissingPluginException {
        _failures[entry.key] = 'Hotkey bridge unavailable.';
      }
    }
  }

  Future<void> unregisterAll() async {
    try {
      await XpChannels.hotkeys.invokeMethod<bool>('unregisterAll');
    } on PlatformException {
      // Nothing registered.
    } on MissingPluginException {
      // Running without the native side (tests).
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onHotkey') return;
    final Map<Object?, Object?>? args =
        call.arguments as Map<Object?, Object?>?;
    final String? id = args?['id'] as String?;
    if (id == null) return;

    final HotkeyAction? action = HotkeyAction.fromId(id);
    if (action == null) return;
    _handlers[action]?.call();
  }

  void dispose() {
    XpChannels.hotkeys.setMethodCallHandler(null);
    _handlers.clear();
  }
}
