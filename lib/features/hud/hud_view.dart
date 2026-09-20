import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/models/assist_models.dart';
import '../../core/providers.dart';
import '../../core/services/profile_service.dart';
import '../settings/settings_view.dart';
import 'controllers/hud_controller.dart';
import 'widgets/action_toolbar.dart';
import 'widgets/hud_controls.dart';
import 'widgets/hud_header.dart';
import 'widgets/chat_panel.dart';
import 'widgets/streaming_markdown.dart';
import 'widgets/transcription_ticker.dart';

/// The floating HUD surface.
class HudView extends ConsumerStatefulWidget {
  const HudView({super.key});

  @override
  ConsumerState<HudView> createState() => _HudViewState();
}

class _HudViewState extends ConsumerState<HudView> {
  @override
  void initState() {
    super.initState();
    // Permissions and hotkeys need a live platform channel, so start after the
    // first frame rather than during construction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(hudControllerProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final HudController hud = ref.watch(hudControllerProvider);

    return HudShortcuts(
      child: Container(
        decoration: BoxDecoration(
          color: XpColors.backgroundGlass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: XpColors.border),
          boxShadow: XpColors.panelShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            const HudHeader(),
            if (hud.banner != null)
              _Banner(
                message: hud.banner!,
                isError: hud.bannerIsError,
                onDismiss: hud.dismissBanner,
              ),
            Expanded(
              child: switch (hud.pane) {
                HudPane.settings => const SettingsView(),
                HudPane.notes => const ChatPanel(),
                HudPane.answer => const _AnswerPane(),
              },
            ),
            const ActionToolbar(),
            const TranscriptionTicker(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Answer pane
// ---------------------------------------------------------------------------

class _AnswerPane extends ConsumerStatefulWidget {
  const _AnswerPane();

  @override
  ConsumerState<_AnswerPane> createState() => _AnswerPaneState();
}

class _AnswerPaneState extends ConsumerState<_AnswerPane> {
  final ScrollController _scroll = ScrollController();
  AssistTurn? _watched;

  /// Stop following the stream once the user scrolls up to re-read something.
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double distanceFromBottom =
        _scroll.position.maxScrollExtent - _scroll.offset;
    _follow = distanceFromBottom < 60;
  }

  void _attach(AssistTurn? turn) {
    if (identical(turn, _watched)) return;
    _watched?.body.removeListener(_onBodyChanged);
    _watched = turn;
    _follow = true;
    turn?.body.addListener(_onBodyChanged);
  }

  void _onBodyChanged() {
    if (!_follow || !mounted) return;
    // Jump after layout has taken the new text into account.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_follow || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _watched?.body.removeListener(_onBodyChanged);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HudController hud = ref.watch(hudControllerProvider);
    final AssistTurn? turn = hud.current;
    _attach(turn);

    if (turn == null) return const _EmptyState();

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _QueryHeader(turn: turn),
            const SizedBox(height: 8),
            if (turn.error != null)
              _ErrorCard(message: turn.error!)
            else
              StreamingMarkdown(text: turn.body, isStreaming: !turn.isDone),
            if (turn.isDone && turn.error == null && !turn.hasContent)
              Text('No answer returned.', style: XpType.bodyMuted),
          ],
        ),
      ),
    );
  }
}

/// What was asked, and what it cost.
class _QueryHeader extends StatelessWidget {
  const _QueryHeader({required this.turn});

  final AssistTurn turn;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (turn.thumbnail != null) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              turn.thumbnail!,
              width: 46,
              height: 30,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            turn.query,
            style: XpType.bodyMuted.copyWith(
              fontSize: 11.5,
              color: XpColors.textTertiary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: XpColors.statusMuted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: XpColors.statusMuted.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: XpColors.statusMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: XpType.bodyMuted.copyWith(color: XpColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.watch(hudControllerProvider);
    final ProfileService profile = ref.watch(profileProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Ready.', style: XpType.verbal),
          const SizedBox(height: 3),
          Text(
            hud.isListening
                ? 'xpass is listening to the call and will answer questions as they land.'
                : 'Capture is paused. Start listening, or ask something directly below.',
            style: XpType.bodyMuted,
          ),
          const SizedBox(height: 14),

          const _ShortcutRow(
            keys: '⌘⌥C',
            label: 'Capture the screen and solve it',
          ),
          const _ShortcutRow(keys: '⌘⌥H', label: 'Panic hide / show'),
          const _ShortcutRow(
            keys: '⌘⌥T',
            label: 'Click-through — type into the app below',
          ),
          const _ShortcutRow(keys: '⌘⌥⌫', label: 'Clear context and reset'),

          const SizedBox(height: 14),
          if (!hud.launch.launchedByLaunchd) const _LaunchWarning(),
          const _PipelineReadout(),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              XpChip(
                label: 'INVISIBLE TO SCREEN SHARE',
                icon: Icons.visibility_off_rounded,
                color: XpColors.statusLive,
              ),
              XpChip(
                label: profile.profile.isConfigured
                    ? '${profile.factCount} PROFILE FACTS'
                    : 'NO PROFILE YET',
                icon: Icons.person_outline_rounded,
                color: profile.profile.isConfigured
                    ? XpColors.accentHover
                    : XpColors.statusThinking,
              ),
              if (!hud.hasScreenPermission)
                XpChip(
                  label: 'SCREEN RECORDING NOT GRANTED',
                  icon: Icons.warning_amber_rounded,
                  color: XpColors.statusMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: XpColors.panelRaised,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: XpColors.border),
            ),
            alignment: Alignment.center,
            child: Text(
              keys,
              style: XpType.metric.copyWith(color: XpColors.textPrimary),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label, style: XpType.bodyMuted.copyWith(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner
// ---------------------------------------------------------------------------

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final Color tint = isError ? XpColors.statusMuted : XpColors.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        border: Border(bottom: BorderSide(color: tint.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 13,
            color: tint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: XpType.bodyMuted.copyWith(
                fontSize: 11.5,
                color: XpColors.textPrimary,
              ),
            ),
          ),
          XpIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Dismiss',
            size: 20,
            iconSize: 11,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline readout
// ---------------------------------------------------------------------------

/// Live count for each stage between the call and an answer.
///
/// Silence is the worst failure mode for a tool used under pressure: if the
/// HUD shows nothing, there is no way to tell whether the audio never arrived,
/// the speech was never detected, the transcription failed, or the model did.
/// This names the stage that stalled.
class _PipelineReadout extends ConsumerWidget {
  const _PipelineReadout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.watch(hudControllerProvider);

    final List<({String label, int value, String stalled})> stages =
        <({String label, int value, String stalled})>[
          (
            label: 'Audio in',
            value: hud.systemFrames + hud.micFrames,
            stalled:
                'No audio at all. Start listening, and grant Screen Recording '
                'then relaunch.',
          ),
          (
            label: 'Them heard',
            value: hud.systemFrames,
            stalled:
                'Nothing from system audio. Check the call is playing through '
                'this Mac and that Screen Recording is granted.',
          ),
          (
            label: 'Speech detected',
            value: hud.speechSegments,
            stalled:
                'Audio is arriving but reads as silence. Turn the call volume '
                'up.',
          ),
          (
            label: 'Transcribed',
            value: hud.transcriptLines,
            stalled: hud.speechReady
                ? 'Speech detected but nothing came back. Check the '
                      'transcription backend under Settings › Capture.'
                : 'Speech Recognition is not granted, so nothing can be '
                      'transcribed. Accept the macOS prompt, or use the Grant '
                      'button under Settings › Capture.',
          ),
          (
            label: 'Answered',
            value: hud.answersStarted,
            stalled:
                'Transcribed, but nothing read as a question. Type it into '
                'the ask box instead.',
          ),
        ];

    // The first empty stage whose predecessor has data is where it broke.
    int stalledAt = -1;
    for (int i = 0; i < stages.length; i++) {
      if (stages[i].value == 0 && (i == 0 || stages[i - 1].value > 0)) {
        stalledAt = i;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: XpColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: XpColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('LISTEN PIPELINE', style: XpType.label),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (int i = 0; i < stages.length; i++) ...<Widget>[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 12,
                      color: XpColors.textTertiary,
                    ),
                  ),
                _Stage(
                  label: stages[i].label,
                  value: stages[i].value,
                  isStall: i == stalledAt,
                ),
              ],
            ],
          ),
          if (stalledAt >= 0) ...<Widget>[
            const SizedBox(height: 9),
            Text(
              stages[stalledAt].stalled,
              style: XpType.bodyMuted.copyWith(
                fontSize: 11,
                height: 1.45,
                color: XpColors.statusThinking,
              ),
            ),
          ],
          if (hud.pipelineError != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 12,
                  color: XpColors.statusMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hud.pipelineError!,
                    style: XpType.bodyMuted.copyWith(
                      fontSize: 11,
                      height: 1.45,
                      color: XpColors.statusMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.label,
    required this.value,
    required this.isStall,
  });

  final String label;
  final int value;
  final bool isStall;

  @override
  Widget build(BuildContext context) {
    final Color tone = isStall
        ? XpColors.statusMuted
        : value > 0
        ? XpColors.statusLive
        : XpColors.textTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value > 999 ? '${(value / 1000).toStringAsFixed(1)}k' : '$value',
          style: XpType.metric.copyWith(
            fontSize: 13,
            color: tone,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(label, style: XpType.label.copyWith(fontSize: 8, color: tone)),
      ],
    );
  }
}

/// Shown when the app was exec'd from a terminal rather than launched by
/// launchd, which silently breaks every macOS privacy permission.
class _LaunchWarning extends ConsumerWidget {
  const _LaunchWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.watch(hudControllerProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: XpColors.statusMuted.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: XpColors.statusMuted.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.terminal_rounded,
                size: 14,
                color: XpColors.statusMuted,
              ),
              const SizedBox(width: 7),
              Text(
                'Launched from a terminal — permissions will not work',
                style: XpType.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'macOS applies privacy permissions to whichever process launched '
            'this one. Screen Recording will read as denied however many times '
            'you grant it, and asking for Speech Recognition will terminate '
            'xpass. Quit and relaunch the bundle directly:',
            style: XpType.bodyMuted.copyWith(fontSize: 11.5, height: 1.45),
          ),
          const SizedBox(height: 7),
          SelectableText(
            'open ${hud.launch.bundlePath}',
            style: XpType.code.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
