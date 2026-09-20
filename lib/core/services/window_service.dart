import 'package:flutter/services.dart';

import 'platform_channels.dart';

/// Window geometry in Flutter screen space (top-left origin).
class WindowBounds {
  const WindowBounds(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  static WindowBounds fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const WindowBounds(0, 0, 0, 0);
    double read(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return WindowBounds(read('x'), read('y'), read('width'), read('height'));
  }

  Size get size => Size(width, height);
}

/// Where the HUD can park itself on screen.
enum HudAnchor {
  topLeft('Top left'),
  topCenter('Top center'),
  topRight('Top right'),
  center('Center'),
  bottomLeft('Bottom left'),
  bottomCenter('Bottom center'),
  bottomRight('Bottom right');

  const HudAnchor(this.label);
  final String label;
}

/// Dart-side facade over `StealthWindowBridge.swift`.
///
/// Every call is best-effort: a platform exception here must never take the HUD
/// down mid-interview, so failures resolve to a sensible fallback instead of
/// propagating.
class WindowService {
  const WindowService();

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await XpChannels.window.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // ------------------------------------------------------------ click-through
  Future<bool> setClickThrough(bool enabled) async =>
      await _invoke<bool>('setClickThrough', <String, Object?>{
        'enabled': enabled,
      }) ??
      enabled;

  Future<bool> toggleClickThrough() async =>
      await _invoke<bool>('toggleClickThrough') ?? false;

  Future<bool> isClickThrough() async =>
      await _invoke<bool>('isClickThrough') ?? false;

  // ------------------------------------------------------------------ opacity
  Future<double> setOpacity(double opacity) async {
    final double clamped = opacity.clamp(0.2, 1.0);
    return await _invoke<double>('setOpacity', <String, Object?>{
          'opacity': clamped,
        }) ??
        clamped;
  }

  // --------------------------------------------------------------- visibility
  Future<bool> show() async => await _invoke<bool>('show') ?? true;

  Future<bool> hide() async => await _invoke<bool>('hide') ?? false;

  Future<bool> setVisible(bool visible) async =>
      await _invoke<bool>('setVisible', <String, Object?>{
        'visible': visible,
      }) ??
      visible;

  /// Panic toggle. Returns the new visibility.
  Future<bool> toggleVisibility() async =>
      await _invoke<bool>('toggleVisibility') ?? true;

  Future<bool> isVisible() async => await _invoke<bool>('isVisible') ?? true;

  Future<void> minimize() => _invoke<bool>('minimize');

  // ---------------------------------------------------------- capture exclusion
  Future<bool> setStealth(bool enabled) async =>
      await _invoke<bool>('setStealth', <String, Object?>{
        'enabled': enabled,
      }) ??
      enabled;

  Future<bool> isStealth() async => await _invoke<bool>('isStealth') ?? true;

  // -------------------------------------------------------------------- level
  Future<void> setLevel(String level) =>
      _invoke<String>('setLevel', <String, Object?>{'level': level});

  Future<void> setAlwaysOnTop(bool enabled) =>
      _invoke<bool>('setAlwaysOnTop', <String, Object?>{'enabled': enabled});

  // -------------------------------------------------------------------- focus
  Future<void> setFocusable(bool focusable) =>
      _invoke<bool>('setFocusable', <String, Object?>{'focusable': focusable});

  /// Pull keyboard focus to the HUD (for the ask box), remembering what had it.
  Future<void> focus() => _invoke<bool>('focus');

  /// Hand focus straight back to the app the user was really working in.
  Future<void> releaseFocus() => _invoke<bool>('releaseFocus');

  // ----------------------------------------------------------------- geometry
  Future<WindowBounds> getBounds() async =>
      WindowBounds.fromMap(await _invoke<Map<Object?, Object?>>('getBounds'));

  Future<WindowBounds> setBounds(WindowBounds bounds) async =>
      WindowBounds.fromMap(
        await _invoke<Map<Object?, Object?>>('setBounds', <String, Object?>{
          'x': bounds.x,
          'y': bounds.y,
          'width': bounds.width,
          'height': bounds.height,
        }),
      );

  Future<WindowBounds> setSize(double width, double height) async =>
      WindowBounds.fromMap(
        await _invoke<Map<Object?, Object?>>('setSize', <String, Object?>{
          'width': width,
          'height': height,
        }),
      );

  Future<WindowBounds> moveBy(double dx, double dy) async =>
      WindowBounds.fromMap(
        await _invoke<Map<Object?, Object?>>('moveBy', <String, Object?>{
          'dx': dx,
          'dy': dy,
        }),
      );

  Future<WindowBounds> snapTo(HudAnchor anchor) async => WindowBounds.fromMap(
    await _invoke<Map<Object?, Object?>>('snapTo', <String, Object?>{
      'position': anchor.name,
    }),
  );

  /// Native window drag — smoother than repositioning per pointer event.
  Future<void> startDrag() => _invoke<bool>('startDrag');
}
