import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/models/audio_models.dart';
import 'package:xpass/core/utils/vad.dart';

/// One 100 ms frame of 16 kHz mono Int16 at the given loudness.
AudioFrame frame(double rms) => AudioFrame(
      source: AudioSource.system,
      pcm: Uint8List(3200),
      rms: rms,
      sampleRate: 16000,
    );

const double quiet = 0.001;
const double loud = 0.2;

void main() {
  group('VoiceActivityDetector', () {
    test('opens only after enough consecutive loud frames', () {
      final VoiceActivityDetector vad =
          VoiceActivityDetector(source: AudioSource.system);

      expect(vad.process(frame(loud)), isNull, reason: 'one frame is not speech');
      expect(vad.process(frame(loud)), isA<VadSpeechStart>());
      expect(vad.isSpeaking, isTrue);
    });

    test('emits a segment after the hangover expires', () {
      final VoiceActivityDetector vad =
          VoiceActivityDetector(source: AudioSource.system);

      for (int i = 0; i < 3; i++) {
        vad.process(frame(quiet));
      }
      vad.process(frame(loud));
      vad.process(frame(loud));
      for (int i = 0; i < 5; i++) {
        vad.process(frame(loud));
      }

      VadEvent? closing;
      for (int i = 0; i < 6; i++) {
        closing = vad.process(frame(quiet)) ?? closing;
      }

      expect(closing, isA<VadSpeechEnd>());
      final SpeechSegment segment = (closing! as VadSpeechEnd).segment;
      expect(segment.source, AudioSource.system);
      expect(segment.pcm.lengthInBytes, greaterThan(0));
      expect(vad.isSpeaking, isFalse);
    });

    test('keeps preroll so the first syllable is not clipped', () {
      final VoiceActivityDetector vad =
          VoiceActivityDetector(source: AudioSource.mic);

      // Three quiet frames, then speech: the segment should contain more audio
      // than just the frames that arrived after the gate opened.
      for (int i = 0; i < 3; i++) {
        vad.process(frame(quiet));
      }
      vad.process(frame(loud));
      vad.process(frame(loud));
      vad.process(frame(loud));

      final VadEvent? event = vad.flush();
      expect(event, isA<VadSpeechEnd>());

      // 3 preroll frames captured before the gate opened, plus the one frame
      // that arrived after it — the quiet lead-in is what proves preroll works.
      final SpeechSegment segment = (event! as VadSpeechEnd).segment;
      expect(segment.pcm.lengthInBytes, 4 * 3200);
    });

    test('drops segments shorter than the minimum', () {
      final VoiceActivityDetector vad = VoiceActivityDetector(
        source: AudioSource.mic,
        config: const VadConfig(
          framesToOpen: 1,
          prerollFrames: 0,
          minSegment: Duration(seconds: 5),
        ),
      );

      expect(vad.process(frame(loud)), isA<VadSpeechStart>());
      expect(vad.flush(), isNull, reason: 'too short to be speech');
    });

    test('force-flushes a monologue at the maximum length', () {
      final VoiceActivityDetector vad = VoiceActivityDetector(
        source: AudioSource.system,
        config: const VadConfig(
          framesToOpen: 1,
          prerollFrames: 0,
          // Must stay above minSegment, or the forced segment is correctly
          // discarded as too short to be speech.
          maxSegment: Duration(milliseconds: 400),
        ),
      );

      VadEvent? event;
      for (int i = 0; i < 10 && event is! VadSpeechEnd; i++) {
        event = vad.process(frame(loud)) ?? event;
      }

      expect(event, isA<VadSpeechEnd>(), reason: 'must not stall the pipeline');
      expect(
        (event! as VadSpeechEnd).segment.duration,
        greaterThanOrEqualTo(const Duration(milliseconds: 400)),
      );
    });

    test('adapts to a noisy room instead of latching open', () {
      final VoiceActivityDetector vad =
          VoiceActivityDetector(source: AudioSource.system);

      // Steady background hiss well above the absolute floor.
      for (int i = 0; i < 200; i++) {
        vad.process(frame(0.05));
      }

      expect(
        vad.threshold,
        greaterThan(0.05),
        reason: 'the gate must rise above steady room noise',
      );
      expect(
        vad.process(frame(0.05)),
        isNull,
        reason: 'hiss alone must not register as speech',
      );
      // Real speech still has to get through.
      vad.process(frame(loud));
      expect(vad.process(frame(loud)), isA<VadSpeechStart>());
    });

    test('reset clears all state', () {
      final VoiceActivityDetector vad =
          VoiceActivityDetector(source: AudioSource.mic);
      vad.process(frame(loud));
      vad.process(frame(loud));
      expect(vad.isSpeaking, isTrue);

      vad.reset();
      expect(vad.isSpeaking, isFalse);
      expect(vad.flush(), isNull);
    });
  });
}
