import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/providers.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/settings_service.dart';
import '../../hud/controllers/hud_controller.dart';

/// How to drive xpass, available without leaving the HUD.
class GuideTab extends ConsumerWidget {
  const GuideTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final XpSettings config = ref.watch(settingsProvider).value;
    final HudController hud = ref.watch(hudControllerProvider);
    final ProfileService profile = ref.watch(profileProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        _Checklist(
          items: <({String label, bool done, String detail})>[
            (
              label: 'NVIDIA key added',
              done: config.hasNvidiaKey,
              detail: 'Powers spoken answers and your profile answers.',
            ),
            (
              label: 'Gemini key added',
              done: config.hasGeminiKey,
              detail: 'Powers screen solving and transcription.',
            ),
            (
              label: 'Screen Recording granted',
              done: hud.hasScreenPermission,
              detail:
                  'Needed for screen solves and interviewer audio. '
                  'Relaunch after granting.',
            ),
            (
              label: 'Profile loaded',
              done: profile.profile.isConfigured,
              detail: '${profile.factCount} facts available for "You" mode.',
            ),
          ],
        ),

        const _GuideSection(
          title: 'THE FOUR SHORTCUTS',
          body:
              'These work anywhere in macOS, even while xpass is hidden and '
              'another app has focus.',
          rows: <({String left, String right})>[
            (
              left: '⌘⌥C',
              right: 'Screenshot what you are looking at and solve it',
            ),
            (left: '⌘⌥H', right: 'Hide or show the HUD instantly'),
            (
              left: '⌘⌥T',
              right:
                  'Click-through: the HUD stops catching clicks so you can '
                  'type into the editor underneath while still reading it',
            ),
            (left: '⌘⌥⌫', right: 'Wipe the transcript and the current answer'),
          ],
        ),

        const _GuideSection(
          title: 'THE THREE ASK MODES',
          body:
              'The switch to the left of the ask box picks which engine '
              'answers. Press Return to send.',
          rows: <({String left, String right})>[
            (
              left: 'Wingman',
              right:
                  'Fast conceptual answers — 2-3 talking points you can say '
                  'out loud. Use for "what is X", "how would you scale Y".',
            ),
            (
              left: 'You',
              right:
                  'Answered only from your stored profile, in first person. '
                  'Use for "tell me about a time…", "what did you build at…".',
            ),
            (
              left: 'Screen',
              right:
                  'Captures the screen and returns a verbal summary, the '
                  'approach, and runnable code with complexity.',
            ),
          ],
        ),

        const _GuideSection(
          title: 'WHAT HAPPENS ON ITS OWN',
          body:
              'While listening, xpass transcribes the other side of the call '
              'and answers questions as they land, so you can read while they '
              'are still finishing the sentence. It picks the engine from the '
              'question itself — you never have to choose:',
          rows: <({String left, String right})>[
            (
              left: 'Screen',
              right:
                  '"What is wrong with this function?" — a demonstrative '
                  'pointing at something visible grabs a frame first',
            ),
            (
              left: 'You',
              right: '"Tell me about a time you…" — answered from your profile',
            ),
            (
              left: 'Wingman',
              right: 'everything else — "how would you scale this service?"',
            ),
          ],
        ),

        const _GuideSection(
          title: 'NOTES',
          body:
              'The notes icon in the header keeps every question of the '
              'session — heard or typed — with the engine that answered, the '
              'first line of what it said, and how fast it arrived. Click any '
              'entry to bring that answer back.\n\n'
              'This is what makes a long call workable: an answer that '
              'scrolled away is still reachable, and "do you have questions '
              'for us?" is easier when you can see what ground was covered.',
          rows: <({String left, String right})>[],
        ),

        const _GuideSection(
          title: 'HEARING THE CALL',
          body:
              'The footer shows two level meters: MIC is you, SYS is them. '
              'xpass tells you apart by capture path, not by voice — SYS is '
              'the system-audio loopback, so anything your speakers play is '
              '"them". If SYS never moves, xpass cannot hear the call: check '
              'Screen Recording and relaunch.\n\n'
              'Use headphones. On speakers their voice re-enters your '
              'microphone and registers on both meters.\n\n'
              'Turn all of this off with "Answer automatically" under Models '
              'if you would rather drive everything by hand.',
          rows: <({String left, String right})>[],
        ),

        const _GuideSection(
          title: 'YOUR PROFILE',
          body:
              'Under the "You" tab, import straight from your portfolio, '
              'paste a résumé, or type entries by hand. Write your own answers '
              'to the common recruiter questions — a prepared answer is used '
              'as the basis for that question instead of anything improvised.\n\n'
              'xpass only ever uses facts you stored. It will say what is '
              'adjacent rather than invent an employer, a date or a metric you '
              'would then have to defend out loud.',
          rows: <({String left, String right})>[],
        ),

        const _GuideSection(
          title: 'STAYING INVISIBLE',
          body:
              'The window sets NSWindowSharingNone, so the macOS compositor '
              'never hands it to a capturing client. It is absent from the '
              'frames themselves — not painted over — in Zoom, Meet, Teams, '
              'Slack, QuickTime and browser screen shares alike. Screenshots '
              'xpass takes exclude the HUD, so a solve never captures its own '
              'answer.\n\n'
              'What this does not cover: a second camera pointed at your '
              'screen, a proctoring tool that inspects running processes, or '
              'anyone watching your eyes. Lower the opacity and use '
              'click-through if you want it less conspicuous to you as well.',
          rows: <({String left, String right})>[],
        ),

        const _GuideSection(
          title: 'IF YOU GET RATE LIMITED',
          body:
              'Each thing the other person says becomes one transcription '
              'request, so a fast exchange can outrun a free-tier quota. xpass '
              'paces requests, backs off when the provider says no, and drops '
              'a stale backlog rather than queueing it.\n\n'
              'If you still hit the limit: lower "Requests per minute" under '
              'Capture, leave "Transcribe my microphone too" off, or move to a '
              'paid key.',
          rows: <({String left, String right})>[],
        ),

        const _GuideSection(
          title: 'MOVING AND SIZING',
          body:
              'Drag the header to move it. Double-click the header to snap '
              'back to the top centre. The move icon in the toolbar parks it '
              'in any corner. Drag the window edges to resize. The droplet '
              'icon cycles opacity, and ⎋ closes Settings or hides the HUD.',
          rows: <({String left, String right})>[],
        ),
      ],
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.items});

  final List<({String label, bool done, String detail})> items;

  @override
  Widget build(BuildContext context) {
    final int done = items
        .where((({bool done, String detail, String label}) i) => i.done)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done == items.length
            ? XpColors.statusLive.withValues(alpha: 0.07)
            : XpColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (done == items.length ? XpColors.statusLive : XpColors.accent)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            done == items.length
                ? 'Setup complete.'
                : 'Setup — $done of ${items.length} done',
            style: XpType.verbal.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 10),
          for (final ({String label, bool done, String detail}) item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    item.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 13,
                    color: item.done
                        ? XpColors.statusLive
                        : XpColors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.label,
                          style: XpType.body.copyWith(
                            fontSize: 12.5,
                            color: item.done
                                ? XpColors.textPrimary
                                : XpColors.textSecondary,
                          ),
                        ),
                        Text(
                          item.detail,
                          style: XpType.bodyMuted.copyWith(
                            fontSize: 11,
                            color: XpColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.title,
    required this.body,
    required this.rows,
  });

  final String title;
  final String body;
  final List<({String left, String right})> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: XpType.sectionHeading),
          const SizedBox(height: 6),
          Text(
            body,
            style: XpType.bodyMuted.copyWith(fontSize: 12, height: 1.55),
          ),
          if (rows.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            for (final ({String left, String right}) row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 66,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: XpColors.panelRaised,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: XpColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        row.left,
                        style: XpType.code.copyWith(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          row.right,
                          style: XpType.bodyMuted.copyWith(
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
