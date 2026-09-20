import 'dart:typed_data';

import '../models/audio_models.dart';

/// Tunables for [VoiceActivityDetector].
class VadConfig {
  const VadConfig({
    this.absoluteFloor = 0.012,
    this.noiseMultiplier = 3.2,
    this.framesToOpen = 2,
    this.framesToClose = 6,
    this.prerollFrames = 3,
    this.minSegment = const Duration(milliseconds: 320),
    this.maxSegment = const Duration(seconds: 22),
  });

  /// Never treat anything below this RMS as speech, however quiet the room.
  final double absoluteFloor;

  /// Speech must exceed `noiseFloor * noiseMultiplier` to open the gate.
  final double noiseMultiplier;

  /// Consecutive loud frames (~100 ms each) required to open.
  final int framesToOpen;

  /// Consecutive quiet frames required to close — the hangover that stops a
  /// natural pause mid-sentence from splitting one question into two.
  final int framesToClose;

  /// Frames retained before the gate opens, so the first syllable is not clipped.
  final int prerollFrames;

  /// Drop anything shorter than this — keyboard clicks, chair creaks.
  final Duration minSegment;

  /// Force-flush a monologue this long so the pipeline never stalls.
  final Duration maxSegment;
}

/// What the detector decided about the frame it was just handed.
sealed class VadEvent {
  const VadEvent();
}

/// The gate just opened — the HUD can show "listening" immediately.
class VadSpeechStart extends VadEvent {
  const VadSpeechStart(this.source);
  final AudioSource source;
}

/// A complete utterance is ready to transcribe.
class VadSpeechEnd extends VadEvent {
  const VadSpeechEnd(this.segment);
  final SpeechSegment segment;
}

/// Energy-gated voice activity detection with an adaptive noise floor.
///
/// One detector per audio source: the microphone and the system-audio loopback
/// have completely different noise characteristics and must not share a floor.
///
/// Frames arrive already RMS-tagged by the native layer, so this stays O(1) per
/// frame and adds no measurable latency to the capture path.
class VoiceActivityDetector {
  VoiceActivityDetector({
    required this.source,
    this.config = const VadConfig(),
  });

  final AudioSource source;
  final VadConfig config;

  final List<Uint8List> _preroll = <Uint8List>[];
  final BytesBuilder _active = BytesBuilder(copy: false);

  double _noiseFloor = 0.004;
  int _loudRun = 0;
  int _quietRun = 0;
  bool _open = false;
  DateTime? _openedAt;
  int _sampleRate = 16000;

  bool get isSpeaking => _open;

  /// Current gate threshold, exposed so the UI can draw a meaningful meter.
  double get threshold =>
      (_noiseFloor * config.noiseMultiplier).clamp(config.absoluteFloor, 1.0);

  /// Feed one frame; returns an event when the speech state changes.
  VadEvent? process(AudioFrame frame) {
    _sampleRate = frame.sampleRate;
    final bool loud = frame.rms > threshold;

    if (!_open) {
      // Track the room tone only while nobody is talking.
      _noiseFloor = _noiseFloor * 0.95 + frame.rms * 0.05;

      _preroll.add(frame.pcm);
      if (_preroll.length > config.prerollFrames) _preroll.removeAt(0);

      _loudRun = loud ? _loudRun + 1 : 0;
      if (_loudRun < config.framesToOpen) return null;

      _open = true;
      _openedAt = DateTime.now();
      _quietRun = 0;
      _active.clear();
      for (final Uint8List chunk in _preroll) {
        _active.add(chunk);
      }
      _preroll.clear();
      return VadSpeechStart(source);
    }

    _active.add(frame.pcm);
    _quietRun = loud ? 0 : _quietRun + 1;

    final Duration held = _heldDuration();
    if (_quietRun >= config.framesToClose || held >= config.maxSegment) {
      return _close();
    }
    return null;
  }

  /// Force the current utterance closed — used when the user hits a hotkey and
  /// we want whatever they just said, immediately.
  VadEvent? flush() => _open ? _close() : null;

  VadEvent? _close() {
    final Duration held = _heldDuration();
    final Uint8List pcm = _active.takeBytes();
    final DateTime startedAt = _openedAt ?? DateTime.now();

    _open = false;
    _openedAt = null;
    _loudRun = 0;
    _quietRun = 0;

    if (held < config.minSegment) return null;

    return VadSpeechEnd(
      SpeechSegment(
        source: source,
        pcm: pcm,
        sampleRate: _sampleRate,
        startedAt: startedAt,
        duration: held,
      ),
    );
  }

  Duration _heldDuration() {
    final int bytes = _active.length;
    return Duration(
      microseconds: (bytes / 2 / _sampleRate * Duration.microsecondsPerSecond)
          .round(),
    );
  }

  void reset() {
    _preroll.clear();
    _active.clear();
    _open = false;
    _openedAt = null;
    _loudRun = 0;
    _quietRun = 0;
    _noiseFloor = 0.004;
  }
}
