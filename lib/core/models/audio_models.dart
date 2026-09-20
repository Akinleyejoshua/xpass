import 'dart:typed_data';

/// Which capture path a chunk of audio came from.
enum AudioSource {
  /// The local microphone — i.e. the user speaking.
  mic,

  /// System-audio loopback — i.e. the interviewer coming out of the speakers.
  system;

  String get label => switch (this) {
    AudioSource.mic => 'You',
    AudioSource.system => 'Them',
  };

  static AudioSource fromName(String name) =>
      name == 'mic' ? AudioSource.mic : AudioSource.system;
}

/// One ~100 ms chunk of 16 kHz mono Int16 PCM delivered by the native bridge.
class AudioFrame {
  const AudioFrame({
    required this.source,
    required this.pcm,
    required this.rms,
    required this.sampleRate,
  });

  final AudioSource source;
  final Uint8List pcm;

  /// Normalised 0...1 loudness, precomputed natively for the VAD.
  final double rms;
  final int sampleRate;

  Duration get duration => Duration(
    microseconds:
        (pcm.lengthInBytes / 2 / sampleRate * Duration.microsecondsPerSecond)
            .round(),
  );

  factory AudioFrame.fromEvent(Map<Object?, Object?> event) {
    return AudioFrame(
      source: AudioSource.fromName(event['source'] as String? ?? 'system'),
      pcm: event['pcm'] as Uint8List? ?? Uint8List(0),
      rms: (event['rms'] as num?)?.toDouble() ?? 0,
      sampleRate: (event['sampleRate'] as num?)?.toInt() ?? 16000,
    );
  }
}

/// A contiguous run of speech isolated by the VAD, ready to transcribe.
class SpeechSegment {
  const SpeechSegment({
    required this.source,
    required this.pcm,
    required this.sampleRate,
    required this.startedAt,
    required this.duration,
  });

  final AudioSource source;
  final Uint8List pcm;
  final int sampleRate;
  final DateTime startedAt;
  final Duration duration;
}

/// A line of transcript surfaced in the HUD footer.
class TranscriptSegment {
  const TranscriptSegment({
    required this.source,
    required this.text,
    required this.isFinal,
    required this.at,
  });

  final AudioSource source;
  final String text;

  /// `false` while a streaming backend is still revising this utterance.
  final bool isFinal;
  final DateTime at;

  TranscriptSegment copyWith({String? text, bool? isFinal}) =>
      TranscriptSegment(
        source: source,
        text: text ?? this.text,
        isFinal: isFinal ?? this.isFinal,
        at: at,
      );
}
