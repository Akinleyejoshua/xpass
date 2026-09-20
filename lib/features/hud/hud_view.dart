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
import 'widgets/notes_panel.dart';
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
                HudPane.notes => const NotesPanel(),
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
