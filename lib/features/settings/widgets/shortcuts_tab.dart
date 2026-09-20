import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/hotkey_binding.dart';
import '../../../core/providers.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/shortcuts/hotkey_service.dart';
import 'settings_atoms.dart';

/// Rebind the four global shortcuts.
class ShortcutsTab extends ConsumerWidget {
  const ShortcutsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsController settings = ref.watch(settingsProvider);
    final HotkeyService hotkeys = ref.watch(hotkeyServiceProvider);
    final XpSettings config = settings.value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: <Widget>[
        SettingsSection(
          title: 'GLOBAL SHORTCUTS',
          subtitle:
              'These fire anywhere in macOS, even while xpass is hidden. '
              'No Accessibility permission needed.',
          children: <Widget>[
            for (final HotkeyAction action in HotkeyAction.values)
              _BindingRow(
                action: action,
                binding:
                    config.hotkeys[action] ?? MacKeyCodes.defaults[action]!,
                failure: hotkeys.failures[action],
                onChanged: (HotkeyBinding binding) {
                  final Map<HotkeyAction, HotkeyBinding> next =
                      Map<HotkeyAction, HotkeyBinding>.from(config.hotkeys)
                        ..[action] = binding;
                  settings.mutate((XpSettings s) => s.copyWith(hotkeys: next));
                },
              ),
          ],
        ),

        SettingsSection(
          title: 'IN-WINDOW',
          subtitle: 'Only while xpass has keyboard focus.',
          children: const <Widget>[
            _StaticShortcut(
              keys: '⎋',
              label: 'Close settings, or hide the HUD',
            ),
            _StaticShortcut(
              keys: '⌘⇧C',
              label: 'Copy the answer\'s code block',
            ),
            _StaticShortcut(
              keys: '↩',
              label: 'Send the question in the ask box',
            ),
          ],
        ),

        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: XpButton(
            label: 'Restore defaults',
            icon: Icons.settings_backup_restore_rounded,
            tone: XpColors.panelRaised,
            onTap: () => settings.mutate(
              (XpSettings s) => s.copyWith(hotkeys: MacKeyCodes.defaults),
            ),
          ),
        ),

        Text(
          'If a shortcut will not bind, macOS or another app already owns it. '
          'Check System Settings › Keyboard › Keyboard Shortcuts.',
          style: XpType.bodyMuted.copyWith(
            fontSize: 11,
            color: XpColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _BindingRow extends StatefulWidget {
  const _BindingRow({
    required this.action,
    required this.binding,
    required this.onChanged,
    this.failure,
  });

  final HotkeyAction action;
  final HotkeyBinding binding;
  final String? failure;
  final ValueChanged<HotkeyBinding> onChanged;

  @override
  State<_BindingRow> createState() => _BindingRowState();
}

class _BindingRowState extends State<_BindingRow> {
  final FocusNode _focus = FocusNode();
  bool _recording = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = false);
      _focus.unfocus();
      return KeyEventResult.handled;
    }

    final int? keyCode = MacKeyCodes.fromLogicalKeyId(event.logicalKey.keyId);
    if (keyCode == null) {
      // A bare modifier, or a key with no Carbon equivalent — keep listening.
      return KeyEventResult.handled;
    }

    final Set<LogicalKeyboardKey> pressed =
        HardwareKeyboard.instance.logicalKeysPressed;
    bool held(LogicalKeyboardKey left, LogicalKeyboardKey right) =>
        pressed.contains(left) || pressed.contains(right);

    final HotkeyBinding binding = HotkeyBinding(
      keyCode: keyCode,
      command: held(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight),
      option: held(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight),
      shift: held(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight),
      control: held(
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      ),
    );

    // A global shortcut with no modifier would swallow that key system-wide.
    if (!binding.command &&
        !binding.option &&
        !binding.control &&
        keyCode < 96) {
      return KeyEventResult.handled;
    }

    widget.onChanged(binding);
    setState(() => _recording = false);
    _focus.unfocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      label: widget.action.label,
      hint:
          widget.failure ?? (_recording ? 'Press the new combination…' : null),
      controlWidth: 130,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTap: () {
            setState(() => _recording = true);
            _focus.requestFocus();
          },
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              color: XpColors.panelRaised,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _recording
                    ? XpColors.accent
                    : widget.failure != null
                    ? XpColors.statusMuted
                    : XpColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _recording ? 'Listening…' : widget.binding.display,
              style: XpType.code.copyWith(
                fontSize: 12,
                color: _recording ? XpColors.accentHover : XpColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticShortcut extends StatelessWidget {
  const _StaticShortcut({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      label: label,
      controlWidth: 130,
      child: Container(
        height: 26,
        decoration: BoxDecoration(
          color: XpColors.panelRaised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: XpColors.border),
        ),
        alignment: Alignment.center,
        child: Text(keys, style: XpType.code.copyWith(fontSize: 12)),
      ),
    );
  }
}
