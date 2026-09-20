import 'dart:math' as math;
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
    this.noiseWindowFrames = 300,
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

  /// Frames of history the noise floor is estimated over (~30 s at 100 ms
  /// frames). Long enough to span a monologue, short enough to follow a room.
  final int noiseWindowFrames;

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

  /// Rolling history of frame loudness, used for minimum-statistics noise
  /// estimation.
  final List<double> _levelWindow = <double>[];

  double _noiseFloor = 0.004;
  int _loudRun = 0;
  int _quietRun = 0;
  bool _open = false;
  DateTime? _openedAt;
  int _sampleRate = 16000;

  bool get isSpeaking => _open;

  /// Current gate threshold, exposed so the UI can draw a meaningful meter.
  double get threshold =>
      math.max(_noiseFloor * config.noiseMultiplier, config.absoluteFloor);

  /// Feed one frame; returns an event when the speech state changes.
  VadEvent? process(AudioFrame frame) {
    _sampleRate = frame.sampleRate;
    // Decide against the floor as it stood *before* this frame, so the first
    // word of an utterance cannot raise the bar against itself.
    final bool loud = frame.rms > threshold;
    _updateNoiseFloor(frame.rms);

    if (!_open) {
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

  /// Estimates room tone as the quietest frame in the recent past.
  ///
  /// Deliberately independent of the gate. An earlier version only learned
  /// while the gate was closed, which meant a steady noise source above the
  /// threshold — a fan, a noisy line, background music — latched the gate open
  /// and the floor never caught up. Taking the minimum over a rolling window
  /// works in both cases: continuous speech still contains brief low-energy
  /// frames between words, while a quiet room with a hiss has a minimum equal
  /// to the hiss itself.
  void _updateNoiseFloor(double rms) {
    _levelWindow.add(rms);
    if (_levelWindow.length > config.noiseWindowFrames) {
      _levelWindow.removeAt(0);
    }

    double minimum = double.infinity;
    for (final double level in _levelWindow) {
      if (level < minimum) minimum = level;
    }
    if (!minimum.isFinite) return;

    // Asymmetric easing. A drop in the minimum means the room really is that
    // quiet, so trust it quickly. A rise means either genuine new noise or a
    // long stretch of speech, so adopt it slowly — that way a monologue cannot
    // deafen the detector before the speaker finishes.
    _noiseFloor = minimum < _noiseFloor
        ? _noiseFloor * 0.6 + minimum * 0.4
        : _noiseFloor * 0.98 + minimum * 0.02;
  }

  void reset() {
    _preroll.clear();
    _active.clear();
    _levelWindow.clear();
    _open = false;
    _openedAt = null;
    _loudRun = 0;
    _quietRun = 0;
    _noiseFloor = 0.004;
  }
}
