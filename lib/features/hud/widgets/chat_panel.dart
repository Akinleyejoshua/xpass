import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/assist_models.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers.dart';
import '../../../core/services/conversation_store.dart';
import '../controllers/hud_controller.dart';
import 'hud_controls.dart';
import 'streaming_markdown.dart';

/// The conversation, as a chat.
///
/// Everything heard and everything answered, in order and persisted, so a long
/// call can be reviewed afterwards and an answer from twenty minutes ago is
/// still reachable.
class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _followTail(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ConversationStore store = ref.watch(conversationProvider);
    final HudController hud = ref.watch(hudControllerProvider);
    final List<ChatEntry> entries = store.entries;
    _followTail(entries.length);

    if (entries.isEmpty) return const _EmptyChat();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: XpColors.border)),
          ),
          child: Row(
            children: <Widget>[
              Text(
                '${entries.length} in this conversation',
                style: XpType.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text('Saved automatically', style: XpType.metric),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int index) {
              final ChatEntry entry = entries[index];
              // While an answer is still streaming its text lives on the turn,
              // not the stored entry, so render from the live turn when it is
              // the one in flight.
              final AssistTurn? live =
                  entry.turnId != null && hud.current?.id == entry.turnId
                  ? hud.current
                  : null;
              return _Bubble(entry: entry, live: live);
            },
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, this.live});

  final ChatEntry entry;
  final AssistTurn? live;

  @override
  Widget build(BuildContext context) {
    final bool mine = entry.role == ChatRole.you;
    final bool answer = entry.isAnswer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  answer ? (entry.tier?.label ?? 'XPASS') : entry.role.label,
                  style: XpType.label.copyWith(
                    fontSize: 9,
                    color: _tone(entry),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _clock(entry.at),
                  style: XpType.metric.copyWith(fontSize: 9),
                ),
                if (entry.latencyMs != null) ...<Widget>[
                  const SizedBox(width: 5),
                  Text(
                    '${entry.latencyMs}ms',
                    style: XpType.metric.copyWith(fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: EdgeInsets.fromLTRB(
              11,
              answer ? 9 : 8,
              11,
              answer ? 10 : 8,
            ),
            decoration: BoxDecoration(
              color: answer
                  ? XpColors.panel
                  : mine
                  ? XpColors.accentSoft
                  : XpColors.panelRaised,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(9),
                topRight: const Radius.circular(9),
                bottomLeft: Radius.circular(mine ? 9 : 2),
                bottomRight: Radius.circular(mine ? 2 : 9),
              ),
              border: Border.all(
                color: answer
                    ? _tone(entry).withValues(alpha: 0.35)
                    : XpColors.border,
              ),
            ),
            child: answer
                ? _AnswerBody(entry: entry, live: live)
                : Text(
                    entry.text,
                    style: XpType.body.copyWith(fontSize: 13, height: 1.45),
                  ),
          ),
        ],
      ),
    );
  }

  static Color _tone(ChatEntry entry) {
    if (!entry.isAnswer) {
      return entry.role == ChatRole.them
          ? XpColors.accentHover
          : XpColors.textTertiary;
    }
    return switch (entry.tier) {
      AssistTier.profile => XpColors.statusLive,
      AssistTier.deep => XpColors.statusThinking,
      _ => XpColors.accentHover,
    };
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _AnswerBody extends StatelessWidget {
  const _AnswerBody({required this.entry, this.live});

  final ChatEntry entry;
  final AssistTurn? live;

  @override
  Widget build(BuildContext context) {
    final AssistTurn? turn = live;
    if (turn != null) {
      return StreamingMarkdown(text: turn.body, isStreaming: !turn.isDone);
    }
    if (entry.text.trim().isEmpty) {
      return Text('No answer returned.', style: XpType.bodyMuted);
    }
    return StreamingMarkdown(text: ValueNotifier<String>(entry.text));
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.forum_outlined,
              size: 22,
              color: XpColors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text('Nothing yet.', style: XpType.body.copyWith(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'Everything the other side says, and every answer xpass gives, '
              'lands here in order — and is saved, so a long call can be read '
              'back afterwards.',
              textAlign: TextAlign.center,
              style: XpType.bodyMuted.copyWith(fontSize: 11.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            const XpChip(
              label: 'SYSTEM AUDIO ONLY',
              icon: Icons.speaker_outlined,
              color: XpColors.accentHover,
            ),
          ],
        ),
      ),
    );
  }
}
