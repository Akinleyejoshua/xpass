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
