import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/models/hotkey_binding.dart';

void main() {
  group('HotkeyBinding', () {
    test('survives an encode/decode round trip', () {
      const HotkeyBinding binding = HotkeyBinding(
        keyCode: MacKeyCodes.keyH,
        command: true,
        option: true,
        shift: false,
        control: true,
      );

      expect(HotkeyBinding.decode(binding.encode()), binding);
    });

    test('rejects malformed stored values', () {
      expect(HotkeyBinding.decode('garbage'), isNull);
      expect(HotkeyBinding.decode('4:11'), isNull);
      expect(HotkeyBinding.decode('notanint:1100'), isNull);
    });

    test('renders modifiers in macOS order', () {
      const HotkeyBinding binding = HotkeyBinding(
        keyCode: MacKeyCodes.keyC,
        command: true,
        option: true,
        shift: true,
        control: true,
      );

      expect(binding.display, '⌃⌥⇧⌘C');
    });

    test('names special keys', () {
      expect(
        const HotkeyBinding(keyCode: MacKeyCodes.keyBackspace).display,
        '⌫',
      );
    });

    test('builds channel arguments the Swift side expects', () {
      final Map<String, Object?> args = const HotkeyBinding(
        keyCode: MacKeyCodes.keyT,
        command: true,
        option: true,
      ).toChannelArgs('clickThrough');

      expect(args['id'], 'clickThrough');
      expect(args['keyCode'], MacKeyCodes.keyT);
      expect(args['command'], isTrue);
      expect(args['option'], isTrue);
      expect(args['shift'], isFalse);
      expect(args['control'], isFalse);
    });
  });

  group('defaults', () {
    test('match the documented shortcuts', () {
      expect(MacKeyCodes.defaults[HotkeyAction.panic]!.display, '⌥⌘H');
      expect(MacKeyCodes.defaults[HotkeyAction.solve]!.display, '⌥⌘C');
      expect(MacKeyCodes.defaults[HotkeyAction.clickThrough]!.display, '⌥⌘T');
      expect(MacKeyCodes.defaults[HotkeyAction.clear]!.display, '⌥⌘⌫');
    });

    test('cover every action', () {
      for (final HotkeyAction action in HotkeyAction.values) {
        expect(MacKeyCodes.defaults[action], isNotNull, reason: action.id);
      }
    });

    test('are all distinct', () {
      final Set<String> encoded = MacKeyCodes.defaults.values
          .map((HotkeyBinding b) => b.encode())
          .toSet();
      expect(encoded.length, MacKeyCodes.defaults.length);
    });
  });

  group('HotkeyAction.fromId', () {
    test('round trips every action', () {
      for (final HotkeyAction action in HotkeyAction.values) {
        expect(HotkeyAction.fromId(action.id), action);
      }
    });

    test('returns null for an unknown id', () {
      expect(HotkeyAction.fromId('nope'), isNull);
    });
  });

  group('fromLogicalKeyId', () {
    test('maps the keys used by the default bindings', () {
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.keyH.keyId),
        MacKeyCodes.keyH,
      );
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.keyC.keyId),
        MacKeyCodes.keyC,
      );
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.keyT.keyId),
        MacKeyCodes.keyT,
      );
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.backspace.keyId),
        MacKeyCodes.keyBackspace,
      );
    });

    test('maps the arrow keys to the right positions', () {
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.arrowUp.keyId),
        MacKeyCodes.keyUp,
      );
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.arrowDown.keyId),
        MacKeyCodes.keyDown,
      );
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.arrowLeft.keyId),
        MacKeyCodes.keyLeft,
      );
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.arrowRight.keyId),
        MacKeyCodes.keyRight,
      );
    });

    test('maps every A–Z key', () {
      const List<LogicalKeyboardKey> letters = <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyG,
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyO,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyY,
        LogicalKeyboardKey.keyZ,
      ];
      for (final LogicalKeyboardKey key in letters) {
        expect(
          MacKeyCodes.fromLogicalKeyId(key.keyId),
          isNotNull,
          reason: key.debugName,
        );
      }
    });

    test('returns null for a key with no Carbon equivalent', () {
      expect(
        MacKeyCodes.fromLogicalKeyId(LogicalKeyboardKey.metaLeft.keyId),
        isNull,
      );
    });
  });
}
