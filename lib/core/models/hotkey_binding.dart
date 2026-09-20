/// The four xpass actions that are bound to system-wide shortcuts.
enum HotkeyAction {
  /// Instant visibility toggle.
  panic('panic', 'Panic hide / show'),

  /// Screenshot the active region and run the deep solve pipeline.
  solve('solve', 'Capture screen & solve'),

  /// Let clicks and keystrokes fall through to the app underneath.
  clickThrough('clickThrough', 'Toggle click-through'),

  /// Wipe the HUD and start a fresh session.
  clear('clear', 'Clear context & reset');

  const HotkeyAction(this.id, this.label);

  final String id;
  final String label;

  static HotkeyAction? fromId(String id) {
    for (final HotkeyAction action in HotkeyAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// A macOS virtual key code plus its modifier mask.
class HotkeyBinding {
  const HotkeyBinding({
    required this.keyCode,
    this.command = false,
    this.option = false,
    this.shift = false,
    this.control = false,
  });

  /// Carbon `kVK_*` virtual key code. Layout-independent: this is a physical
  /// key position, so the binding survives a switch to Dvorak or AZERTY.
  final int keyCode;
  final bool command;
  final bool option;
  final bool shift;
  final bool control;

  Map<String, Object?> toChannelArgs(String id) => <String, Object?>{
    'id': id,
    'keyCode': keyCode,
    'command': command,
    'option': option,
    'shift': shift,
    'control': control,
  };

  String encode() =>
      '$keyCode:${command ? 1 : 0}${option ? 1 : 0}${shift ? 1 : 0}${control ? 1 : 0}';

  static HotkeyBinding? decode(String raw) {
    final List<String> parts = raw.split(':');
    if (parts.length != 2 || parts[1].length != 4) return null;
    final int? code = int.tryParse(parts[0]);
    if (code == null) return null;
    return HotkeyBinding(
      keyCode: code,
      command: parts[1][0] == '1',
      option: parts[1][1] == '1',
      shift: parts[1][2] == '1',
      control: parts[1][3] == '1',
    );
  }

  /// Human-readable form for the settings UI, e.g. `⌘⌥H`.
  String get display {
    final StringBuffer buffer = StringBuffer();
    if (control) buffer.write('⌃');
    if (option) buffer.write('⌥');
    if (shift) buffer.write('⇧');
    if (command) buffer.write('⌘');
    buffer.write(MacKeyCodes.nameFor(keyCode));
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is HotkeyBinding &&
      other.keyCode == keyCode &&
      other.command == command &&
      other.option == option &&
      other.shift == shift &&
      other.control == control;

  @override
  int get hashCode => Object.hash(keyCode, command, option, shift, control);
}

/// Carbon `kVK_*` virtual key codes.
///
/// These are physical key positions rather than characters, which is exactly
/// what `RegisterEventHotKey` expects.
abstract final class MacKeyCodes {
  static const int keyA = 0;
  static const int keyS = 1;
  static const int keyD = 2;
  static const int keyF = 3;
  static const int keyH = 4;
  static const int keyG = 5;
  static const int keyZ = 6;
  static const int keyX = 7;
  static const int keyC = 8;
  static const int keyV = 9;
  static const int keyB = 11;
  static const int keyQ = 12;
  static const int keyW = 13;
  static const int keyE = 14;
  static const int keyR = 15;
  static const int keyY = 16;
  static const int keyT = 17;
  static const int keyO = 31;
  static const int keyU = 32;
  static const int keyI = 34;
  static const int keyP = 35;
  static const int keyL = 37;
  static const int keyJ = 38;
  static const int keyK = 40;
  static const int keyN = 45;
  static const int keyM = 46;
  static const int keyReturn = 36;
  static const int keyTab = 48;
  static const int keySpace = 49;
  static const int keyBackspace = 51;
  static const int keyEscape = 53;
  static const int keyLeft = 123;
  static const int keyRight = 124;
  static const int keyDown = 125;
  static const int keyUp = 126;
  static const int keyF1 = 122;
  static const int keyF2 = 120;
  static const int keyF3 = 99;
  static const int keyF4 = 118;
  static const int keyF5 = 96;
  static const int keyF6 = 97;

  static const Map<int, String> _names = <int, String>{
    keyA: 'A',
    keyS: 'S',
    keyD: 'D',
    keyF: 'F',
    keyH: 'H',
    keyG: 'G',
    keyZ: 'Z',
    keyX: 'X',
    keyC: 'C',
    keyV: 'V',
    keyB: 'B',
    keyQ: 'Q',
    keyW: 'W',
    keyE: 'E',
    keyR: 'R',
    keyY: 'Y',
    keyT: 'T',
    keyO: 'O',
    keyU: 'U',
    keyI: 'I',
    keyP: 'P',
    keyL: 'L',
    keyJ: 'J',
    keyK: 'K',
    keyN: 'N',
    keyM: 'M',
    keyReturn: '↩',
    keyTab: '⇥',
    keySpace: 'Space',
    keyBackspace: '⌫',
    keyEscape: '⎋',
    keyLeft: '←',
    keyRight: '→',
    keyDown: '↓',
    keyUp: '↑',
    keyF1: 'F1',
    keyF2: 'F2',
    keyF3: 'F3',
    keyF4: 'F4',
    keyF5: 'F5',
    keyF6: 'F6',
  };

  static String nameFor(int keyCode) => _names[keyCode] ?? 'key$keyCode';

  /// Flutter logical key id -> Carbon virtual key code, for the rebinding UI.
  ///
  /// Carbon addresses physical key positions while Flutter reports logical
  /// (layout-mapped) keys, so this table assumes the standard ANSI layout. On a
  /// non-ANSI layout the shortcut still fires — it fires on the key that sits
  /// where that letter would be on ANSI.
  ///
  /// Ids verified against LogicalKeyboardKey.keyId, not guessed.
  static const Map<int, int> _logicalToVirtual = <int, int>{
    0x00000000061: keyA,
    0x00000000062: keyB,
    0x00000000063: keyC,
    0x00000000064: keyD,
    0x00000000065: keyE,
    0x00000000066: keyF,
    0x00000000067: keyG,
    0x00000000068: keyH,
    0x00000000069: keyI,
    0x0000000006a: keyJ,
    0x0000000006b: keyK,
    0x0000000006c: keyL,
    0x0000000006d: keyM,
    0x0000000006e: keyN,
    0x0000000006f: keyO,
    0x00000000070: keyP,
    0x00000000071: keyQ,
    0x00000000072: keyR,
    0x00000000073: keyS,
    0x00000000074: keyT,
    0x00000000075: keyU,
    0x00000000076: keyV,
    0x00000000077: keyW,
    0x00000000078: keyX,
    0x00000000079: keyY,
    0x0000000007a: keyZ,
    0x00100000008: keyBackspace,
    0x0010000000d: keyReturn,
    0x00000000020: keySpace,
    0x00100000009: keyTab,
    0x0010000001b: keyEscape,
    0x00100000304: keyUp,
    0x00100000301: keyDown,
    0x00100000302: keyLeft,
    0x00100000303: keyRight,
    0x00100000801: keyF1,
    0x00100000802: keyF2,
    0x00100000803: keyF3,
    0x00100000804: keyF4,
    0x00100000805: keyF5,
    0x00100000806: keyF6,
  };

  /// Returns null for keys xpass cannot bind (a bare modifier, an unmapped key).
  static int? fromLogicalKeyId(int logicalKeyId) =>
      _logicalToVirtual[logicalKeyId];

  /// The shortcuts from the spec.
  static const Map<HotkeyAction, HotkeyBinding> defaults =
      <HotkeyAction, HotkeyBinding>{
        HotkeyAction.panic: HotkeyBinding(
          keyCode: keyH,
          command: true,
          option: true,
        ),
        HotkeyAction.solve: HotkeyBinding(
          keyCode: keyC,
          command: true,
          option: true,
        ),
        HotkeyAction.clickThrough: HotkeyBinding(
          keyCode: keyT,
          command: true,
          option: true,
        ),
        HotkeyAction.clear: HotkeyBinding(
          keyCode: keyBackspace,
          command: true,
          option: true,
        ),
      };
}
