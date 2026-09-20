import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/audio_models.dart';
import '../../../core/providers.dart';
import '../controllers/hud_controller.dart';
import 'hud_controls.dart';

/// Live transcription footer.
///
/// Shows the last couple of utterances with who said them, plus a level meter
/// per capture path so the user can tell at a glance whether xpass is actually
/// hearing the call — the single most common failure to diagnose mid-interview.
class TranscriptionTicker extends ConsumerWidget {
  const TranscriptionTicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudController hud = ref.watch(hudControllerProvider);
    final List<TranscriptSegment> segments = hud.transcript;
    final TranscriptSegment? latest = segments.isEmpty ? null : segments.last;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: XpColors.border)),
      ),
      child: Row(
        children: <Widget>[
          // ------------------------------------------------ level meters
          _SourceIndicator(
            label: 'MIC',
            level: hud.micLevel,
            active: hud.micActive,
          ),
          const SizedBox(width: 10),
          _SourceIndicator(
            label: 'SYS',
            level: hud.systemLevel,
            active: hud.systemAudioActive,
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 12, color: XpColors.border),
          const SizedBox(width: 10),

          // -------------------------------------------------- transcript
          Expanded(
            child: latest == null
                ? Text(
                    hud.isListening
                        ? 'Listening for the conversation…'
                        : 'Capture paused — press the mic to resume.',
                    style: XpType.metric.copyWith(
                      fontFamily: XpType.displayFamily,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : _TranscriptLine(segment: latest),
          ),

          if (segments.length > 1) ...<Widget>[
            const SizedBox(width: 8),
            Text('${segments.length} lines', style: XpType.metric),
          ],
        ],
      ),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({required this.segment});

  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    final bool fromInterviewer = segment.source == AudioSource.system;

    return Row(
      children: <Widget>[
        Text(
          segment.source.label.toUpperCase(),
          style: XpType.label.copyWith(
            color: fromInterviewer
                ? XpColors.accentHover
                : XpColors.textTertiary,
            fontSize: 9,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: XpType.bodyMuted.copyWith(
              fontSize: 11.5,
              height: 1.2,
              // A still-streaming line reads dimmer so a half-heard question
              // is never mistaken for a settled one.
              color: segment.isFinal
                  ? XpColors.textSecondary
                  : XpColors.textTertiary,
              fontStyle: segment.isFinal ? FontStyle.normal : FontStyle.italic,
            ),
            child: Text(
              segment.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceIndicator extends StatelessWidget {
  const _SourceIndicator({
    required this.label,
    required this.level,
    required this.active,
  });

  final String label;
  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active
          ? '$label capture live'
          : '$label capture off — check Settings and permissions',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: XpType.label.copyWith(
              fontSize: 9,
              color: active ? XpColors.statusLive : XpColors.textTertiary,
            ),
          ),
          const SizedBox(width: 5),
          LevelMeter(level: level, active: active),
        ],
      ),
    );
  }
}
