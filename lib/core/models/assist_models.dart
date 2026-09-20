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
