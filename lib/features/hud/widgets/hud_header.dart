import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/assist_models.dart';
import '../../../core/providers.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/window_service.dart';
import '../controllers/hud_controller.dart';
import 'hud_controls.dart';

/// The draggable top bar: identity, live status, latency, window controls.
class HudHeader extends ConsumerWidget {
  const HudHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.watch(hudControllerProvider);
    final XpSettings config = ref.watch(settingsProvider).value;
    final AssistTurn? turn = hud.current;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Hand the drag to AppKit: the window tracks the pointer at compositor
      // level instead of chasing it one frame behind.
      onPanStart: (_) => ref.read(windowServiceProvider).startDrag(),
      onDoubleTap: () =>
          ref.read(windowServiceProvider).snapTo(HudAnchor.topCenter),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: XpColors.border)),
        ),
        child: Row(
          children: <Widget>[
            // -------------------------------------------------- identity
            const _Wordmark(),
            const SizedBox(width: 10),
            Container(width: 1, height: 14, color: XpColors.border),
            const SizedBox(width: 10),

            // ---------------------------------------------------- status
            StatusDot(status: hud.status),
            const SizedBox(width: 6),
            Text(
              hud.status.label,
              style: XpType.label.copyWith(
                color: statusColor(hud.status),
                fontWeight: FontWeight.w700,
              ),
            ),

            if (turn != null) ...<Widget>[
              const SizedBox(width: 8),
              XpChip(
                label: turn.tier.label,
                color: turn.tier == AssistTier.fast
                    ? XpColors.accentHover
                    : XpColors.statusThinking,
                borderColor: turn.tier == AssistTier.fast
                    ? XpColors.accent
                    : XpColors.statusThinking,
                background: XpColors.panel,
              ),
            ],

            const Spacer(),

            // --------------------------------------------------- metrics
            if (turn != null) _LatencyReadout(turn: turn),

            const SizedBox(width: 8),
            XpChip(
              label: config.useDeepReasoning ? 'DEEP' : 'FAST',
              icon: config.useDeepReasoning
                  ? Icons.psychology_outlined
                  : Icons.bolt_rounded,
              color: config.useDeepReasoning
                  ? XpColors.statusThinking
                  : XpColors.accentHover,
            ),

            const SizedBox(width: 8),
            Container(width: 1, height: 14, color: XpColors.border),
            const SizedBox(width: 4),

            // ------------------------------------------------- controls
            XpIconButton(
              icon: hud.isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
              tooltip: hud.isListening ? 'Mute capture' : 'Start listening',
              active: hud.isListening,
              activeColor: XpColors.statusLive,
              onTap: hud.toggleListening,
            ),
            XpIconButton(
              icon: hud.isClickThrough
                  ? Icons.layers_clear_rounded
                  : Icons.layers_rounded,
              tooltip: hud.isClickThrough
                  ? 'Click-through on — ⌘⌥T'
                  : 'Click-through off — ⌘⌥T',
              active: hud.isClickThrough,
              onTap: hud.toggleClickThrough,
            ),
            const _OpacityControl(),
            _NotesButton(count: hud.notes.length, active: hud.isNotesOpen),
            XpIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Settings',
              active: hud.isSettingsOpen,
              onTap: hud.toggleSettings,
            ),
            XpIconButton(
              icon: Icons.visibility_off_rounded,
              tooltip: 'Panic hide — ⌘⌥H',
              activeColor: XpColors.statusMuted,
              onTap: hud.hide,
            ),
            const _QuitButton(),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[XpColors.accentHover, XpColors.accentActive],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: const Text(
            'x',
            style: TextStyle(
              fontFamily: XpType.displayFamily,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 7),
        const Text('xpass', style: XpType.title),
      ],
    );
  }
}

/// Time to first token, then total. TTFT is the number that decides whether the
/// user can keep talking or has to stall.
class _LatencyReadout extends StatelessWidget {
  const _LatencyReadout({required this.turn});

  final AssistTurn turn;

  @override
  Widget build(BuildContext context) {
    final Duration? ttft = turn.firstTokenLatency;
    if (ttft == null) {
      return Text('— ms', style: XpType.metric);
    }

    final int ms = ttft.inMilliseconds;
    final Color color = ms < 600
        ? XpColors.statusLive
        : ms < 1500
        ? XpColors.statusThinking
        : XpColors.statusMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('TTFT', style: XpType.metric),
        const SizedBox(width: 4),
        Text(
          '${ms}ms',
          style: XpType.metric.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (turn.totalLatency != null) ...<Widget>[
          Text(' · ', style: XpType.metric),
          Text(
            '${(turn.totalLatency!.inMilliseconds / 1000).toStringAsFixed(1)}s',
            style: XpType.metric,
          ),
        ],
      ],
    );
  }
}

/// Opacity stepper — a slider is too fiddly to hit mid-interview, so this
/// cycles through four presets on click and exposes the full range on hover.
class _OpacityControl extends ConsumerStatefulWidget {
  const _OpacityControl();

  @override
  ConsumerState<_OpacityControl> createState() => _OpacityControlState();
}

class _OpacityControlState extends ConsumerState<_OpacityControl> {
  static const List<double> _presets = <double>[1.0, 0.85, 0.6, 0.35];

  @override
  Widget build(BuildContext context) {
    final HudController hud = ref.watch(hudControllerProvider);
    final double opacity = ref.watch(settingsProvider).value.opacity;

    return Tooltip(
      message: 'Opacity ${(opacity * 100).round()}% — click to cycle',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          final int index = _presets.indexWhere(
            (double p) => (p - opacity).abs() < 0.02,
          );
          final double next = _presets[(index + 1) % _presets.length];
          hud.setOpacity(next);
        },
        child: SizedBox(
          width: 30,
          height: 26,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.opacity_rounded,
                size: 13,
                color: XpColors.textSecondary,
              ),
              const SizedBox(height: 1),
              Text(
                '${(opacity * 100).round()}',
                style: XpType.metric.copyWith(fontSize: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notes toggle with a live count of what has been asked.
class _NotesButton extends ConsumerWidget {
  const _NotesButton({required this.count, required this.active});

  final int count;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        XpIconButton(
          icon: Icons.notes_rounded,
          tooltip: 'Questions asked so far',
          active: active,
          onTap: ref.read(hudControllerProvider).toggleNotes,
        ),
        if (count > 0)
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: XpColors.accent,
                borderRadius: BorderRadius.circular(5),
              ),
              constraints: const BoxConstraints(minWidth: 11),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: XpType.metric.copyWith(
                  fontSize: 7.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Quit, behind a confirmation.
///
/// xpass has no Dock icon and no menu bar, so this is the only way out of the
/// app — but it sits one pixel from Panic hide, and quitting mid-interview by
/// accident would be worse than not being able to quit at all. Hence two
/// clicks, with the second only accepted for a couple of seconds.
class _QuitButton extends ConsumerStatefulWidget {
  const _QuitButton();

  @override
  ConsumerState<_QuitButton> createState() => _QuitButtonState();
}

class _QuitButtonState extends ConsumerState<_QuitButton> {
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  void _onTap() {
    if (_armed) {
      _disarm?.cancel();
      ref.read(hudControllerProvider).quit();
      return;
    }
    setState(() => _armed = true);
    _disarm?.cancel();
    _disarm = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _armed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_armed) {
      return XpIconButton(
        icon: Icons.power_settings_new_rounded,
        tooltip: 'Quit xpass — ⌘Q',
        activeColor: XpColors.statusMuted,
        onTap: _onTap,
      );
    }

    return Tooltip(
      message: 'Click again to quit',
      child: GestureDetector(
        onTap: _onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: XpColors.statusMuted,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              'QUIT?',
              style: XpType.label.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
