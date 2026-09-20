import 'package:flutter/foundation.dart';

/// Which reasoning tier produced an answer.
enum AssistTier {
  /// NVIDIA NIM — sub-second conversational talking points.
  fast,

  /// Google Gemini — screenshot + deep algorithmic solve.
  deep,

  /// NVIDIA NIM grounded in the user's own profile.
  profile;

  String get label => switch (this) {
    AssistTier.fast => 'WINGMAN',
    AssistTier.deep => 'DEEP SOLVE',
    AssistTier.profile => 'YOUR STORY',
  };
}

/// Which tier a heard question is routed to.
enum AssistRoute {
  /// Conceptual question — fast talking points.
  wingman,

  /// A question about the user — answered from their profile.
  profile,

  /// A question about something on screen — capture, then solve.
  screen,
}

/// Which surface the HUD body is showing.
enum HudPane {
  /// The current answer.
  answer,

  /// The running record of what has been asked and what was said back.
  notes,

  /// Configuration.
  settings,
}

/// Coarse HUD state, drives the status dot and header copy.
enum HudStatus {
  idle,
  listening,
  capturing,
  thinking,
  streaming,
  error,
  muted;

  String get label => switch (this) {
    HudStatus.idle => 'Idle',
    HudStatus.listening => 'Listening',
    HudStatus.capturing => 'Capturing',
    HudStatus.thinking => 'Analyzing',
    HudStatus.streaming => 'Answering',
    HudStatus.error => 'Error',
    HudStatus.muted => 'Muted',
  };
}

/// One request/response cycle.
///
/// The streamed body lives in a [ValueNotifier] rather than in the turn's
/// identity so that token arrival repaints only the markdown view — at 60+
/// tokens/second a full-tree rebuild per delta is visibly janky.
class AssistTurn {
  AssistTurn({
    required this.id,
    required this.tier,
    required this.query,
    required this.startedAt,
    this.thumbnail,
  }) : body = ValueNotifier<String>('');

  final String id;
  final AssistTier tier;

  /// The prompt or transcript line that triggered this turn.
  final String query;
  final DateTime startedAt;

  /// JPEG bytes of the frame sent with a deep solve, for the header preview.
  final Uint8List? thumbnail;

  final ValueNotifier<String> body;

  /// Time to first token — the number that actually matters live.
  Duration? firstTokenLatency;
  Duration? totalLatency;
  String? error;
  bool isDone = false;
  bool wasCancelled = false;

  bool get hasContent => body.value.isNotEmpty;

  /// True when the question arrived from the call rather than the ask box.
  bool wasHeard = false;

  /// The one line worth remembering, for the notes list.
  ///
  /// Takes the first real sentence of the answer, skipping headings and
  /// stopping before any code — a fenced block is useless as a reminder of
  /// what was said out loud.
  String get gist {
    final String text = body.value;
    if (text.isEmpty) return '';

    for (final String rawLine in text.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('```')) break;

      final String cleaned = line
          .replaceFirst(RegExp(r'^[-*+]\s*'), '')
          .replaceAll(RegExp(r'[*_`]'), '')
          .trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }

  void dispose() => body.dispose();
}

/// Thrown by both model services so the HUD can render one consistent error.
class AiServiceException implements Exception {
  const AiServiceException(this.message, {this.statusCode, this.provider});

  final String message;
  final int? statusCode;
  final String? provider;

  @override
  String toString() {
    final String prefix = provider == null ? '' : '$provider: ';
    final String code = statusCode == null ? '' : ' (HTTP $statusCode)';
    return '$prefix$message$code';
  }
}
