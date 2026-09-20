import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/providers.dart';
import '../../../core/services/window_service.dart';
import '../controllers/hud_controller.dart';
import 'hud_controls.dart';

/// Which engine a typed question is sent to.
enum AskMode {
  wingman('Wingman', Icons.bolt_rounded, 'Fast conceptual answer'),
  aboutMe('You', Icons.person_outline_rounded, 'Answered from your profile'),
  screen('Screen', Icons.crop_free_rounded, 'Capture the screen and solve');

  const AskMode(this.label, this.icon, this.hint);

  final String label;
  final IconData icon;
  final String hint;
}

/// The ask box plus the four actions that matter under pressure.
class ActionToolbar extends ConsumerStatefulWidget {
  const ActionToolbar({super.key});

  @override
  ConsumerState<ActionToolbar> createState() => _ActionToolbarState();
}

class _ActionToolbarState extends ConsumerState<ActionToolbar> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  AskMode _mode = AskMode.wingman;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    ref
        .read(hudControllerProvider)
        .ask(
          text,
          withScreen: _mode == AskMode.screen,
          aboutMe: _mode == AskMode.aboutMe,
        );
    // Hand the keyboard back so the next thing typed lands in the IDE.
    ref.read(windowServiceProvider).releaseFocus();
  }

  @override
  Widget build(BuildContext context) {
    final HudController hud = ref.watch(hudControllerProvider);
    final bool hasAnswer = hud.current?.hasContent ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: XpColors.border)),
      ),
      child: Row(
        children: <Widget>[
          _ModeSwitch(
            mode: _mode,
            onChanged: (AskMode mode) {
              setState(() => _mode = mode);
              _focus.requestFocus();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AskField(
              controller: _input,
              focusNode: _focus,
              mode: _mode,
              onSubmit: _submit,
            ),
          ),
          const SizedBox(width: 6),

          // ------------------------------------------------- quick actions
          XpIconButton(
            icon: Icons.center_focus_strong_rounded,
            tooltip: 'Capture screen & solve — ⌘⌥C',
            activeColor: XpColors.statusThinking,
            onTap: () => hud.captureAndSolve(),
          ),
          XpIconButton(
            icon: Icons.code_rounded,
            tooltip: 'Copy the answer\'s code block',
            enabled: hasAnswer,
            onTap: () => hud.copyCode(),
          ),
          XpIconButton(
            icon: Icons.content_paste_rounded,
            tooltip: 'Copy the whole answer',
            enabled: hasAnswer,
            onTap: () => hud.copyAnswer(),
          ),
          const _SnapButton(),
          XpIconButton(
            icon: Icons.backspace_outlined,
            tooltip: 'Clear context & reset — ⌘⌥⌫',
            activeColor: XpColors.statusMuted,
            onTap: hud.clearSession,
          ),
        ],
      ),
    );
  }
}

class _AskField extends ConsumerWidget {
  const _AskField({
    required this.controller,
    required this.focusNode,
    required this.mode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AskMode mode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: XpColors.panelRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: XpColors.border),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: XpType.body.copyWith(fontSize: 12.5),
        cursorColor: XpColors.accent,
        cursorWidth: 1.5,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => onSubmit(),
        // Taking focus requires the window to accept key events; ask AppKit
        // for it explicitly since the HUD is normally non-activating.
        onTap: () => ref.read(windowServiceProvider).focus(),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          hintText: mode.hint,
          hintStyle: XpType.body.copyWith(
            fontSize: 12.5,
            color: XpColors.textTertiary,
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: XpIconButton(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'Send',
              size: 20,
              iconSize: 12,
              onTap: onSubmit,
            ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 20,
          ),
        ),
      ),
    );
  }
}

/// Three-way segmented control for the ask box.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final AskMode mode;
  final ValueChanged<AskMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: XpColors.panelRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: XpColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final AskMode option in AskMode.values)
            _ModeTab(
              option: option,
              selected: option == mode,
              onTap: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AskMode option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.hint,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? XpColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                option.icon,
                size: 11,
                color: selected ? Colors.white : XpColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                option.label,
                style: XpType.label.copyWith(
                  color: selected ? Colors.white : XpColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parks the HUD in a screen corner without dragging it there.
class _SnapButton extends ConsumerWidget {
  const _SnapButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<HudAnchor>(
      tooltip: 'Snap to position',
      position: PopupMenuPosition.over,
      color: XpColors.panelRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: XpColors.border),
      ),
      onSelected: (HudAnchor anchor) =>
          ref.read(hudControllerProvider).snap(anchor),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<HudAnchor>>[
        for (final HudAnchor anchor in HudAnchor.values)
          PopupMenuItem<HudAnchor>(
            value: anchor,
            height: 30,
            child: Text(
              anchor.label,
              style: XpType.bodyMuted.copyWith(fontSize: 12),
            ),
          ),
      ],
      child: const SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          Icons.open_with_rounded,
          size: 14,
          color: XpColors.textSecondary,
        ),
      ),
    );
  }
}

/// Keyboard shortcuts that work while the HUD itself has focus.
///
/// The global ⌘⌥ bindings live in the native Carbon bridge; these are the
/// in-window conveniences that only make sense when xpass is the key window.
class HudShortcuts extends ConsumerWidget {
  const HudShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.read(hudControllerProvider);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (hud.isSettingsOpen) {
            hud.closeSettings();
          } else {
            hud.hide();
          }
        },
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          meta: true,
          shift: true,
        ): () =>
            hud.copyCode(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
