import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/assist_models.dart';
import '../../../core/providers.dart';
import '../controllers/hud_controller.dart';
import 'hud_controls.dart';

/// The running record of the conversation: every question asked, which engine
/// answered it, and the one line that was said back.
///
/// This is what makes the HUD usable over a 45-minute call. An answer that
/// scrolled away five minutes ago is otherwise unreachable, and "so, do you
/// have questions for us?" is much easier to field when you can see what
/// ground has already been covered.
class NotesPanel extends ConsumerWidget {
  const NotesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.watch(hudControllerProvider);
    final List<AssistTurn> notes = hud.notes;

    if (notes.isEmpty) {
      return const _EmptyNotes();
    }

    final int heard = notes.where((AssistTurn t) => t.wasHeard).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: XpColors.border)),
          ),
          child: Row(
            children: <Widget>[
              Text(
                '${notes.length} question${notes.length == 1 ? '' : 's'}',
                style: XpType.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (heard > 0) ...<Widget>[
                const SizedBox(width: 8),
                XpChip(
                  label: '$heard FROM THE CALL',
                  icon: Icons.hearing_rounded,
                  color: XpColors.statusLive,
                ),
              ],
              const Spacer(),
              Text('Click one to reopen it', style: XpType.metric),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: notes.length,
            itemBuilder: (BuildContext context, int index) {
              final AssistTurn turn = notes[index];
              return _NoteRow(
                turn: turn,
                isCurrent: identical(turn, hud.current),
                onTap: () => hud.restoreTurn(turn.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NoteRow extends StatefulWidget {
  const _NoteRow({
    required this.turn,
    required this.isCurrent,
    required this.onTap,
  });

  final AssistTurn turn;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AssistTurn turn = widget.turn;
    final Color tone = _toneFor(turn.tier);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: widget.isCurrent
                ? XpColors.accentSoft
                : _hovered
                ? XpColors.panelRaised
                : XpColors.panel,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: widget.isCurrent ? XpColors.accent : XpColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    turn.tier.label,
                    style: XpType.label.copyWith(color: tone, fontSize: 9),
                  ),
                  const SizedBox(width: 7),
                  Icon(
                    turn.wasHeard
                        ? Icons.hearing_rounded
                        : Icons.keyboard_rounded,
                    size: 10,
                    color: XpColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    turn.wasHeard ? 'heard' : 'typed',
                    style: XpType.metric.copyWith(fontSize: 9),
                  ),
                  const Spacer(),
                  if (turn.firstTokenLatency != null)
                    Text(
                      '${turn.firstTokenLatency!.inMilliseconds}ms',
                      style: XpType.metric.copyWith(fontSize: 9),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _clock(turn.startedAt),
                    style: XpType.metric.copyWith(fontSize: 9),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                turn.query,
                style: XpType.body.copyWith(fontSize: 12.5, height: 1.35),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              // The body notifier updates as tokens stream in, so the gist
              // fills itself in without rebuilding the whole list.
              ValueListenableBuilder<String>(
                valueListenable: turn.body,
                builder: (BuildContext context, _, _) {
                  if (turn.error != null) {
                    return Text(
                      turn.error!,
                      style: XpType.bodyMuted.copyWith(
                        fontSize: 11,
                        color: XpColors.statusMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }
                  final String gist = turn.gist;
                  return Text(
                    gist.isEmpty
                        ? (turn.isDone ? 'No answer returned.' : 'Answering…')
                        : gist,
                    style: XpType.bodyMuted.copyWith(
                      fontSize: 11,
                      height: 1.4,
                      color: XpColors.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _toneFor(AssistTier tier) => switch (tier) {
    AssistTier.fast => XpColors.accentHover,
    AssistTier.profile => XpColors.statusLive,
    AssistTier.deep => XpColors.statusThinking,
  };

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.notes_rounded,
              size: 22,
              color: XpColors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              'Nothing asked yet.',
              style: XpType.body.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Every question xpass hears or you type lands here, with the '
              'answer it gave — so nothing scrolls away mid-call.',
              textAlign: TextAlign.center,
              style: XpType.bodyMuted.copyWith(fontSize: 11.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
