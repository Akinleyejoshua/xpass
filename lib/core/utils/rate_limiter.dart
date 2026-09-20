import 'dart:async';

/// Paces outbound requests so a busy conversation cannot exhaust an API quota.
///
/// This is a leaky bucket, not a token bucket: requests are spaced evenly at
/// `permitsPerMinute` rather than allowed to burst. Bursting is exactly what
/// gets a key throttled — a fast back-and-forth produces a cluster of short
/// utterances, and firing all of them at once trips the per-minute limit even
/// when the average rate is well under it.
///
/// `_nextAvailable` is advanced synchronously before any `await`, so two
/// concurrent callers can never be handed the same slot.
class RateLimiter {
  RateLimiter({required int permitsPerMinute})
    : _permitsPerMinute = permitsPerMinute < 1 ? 1 : permitsPerMinute;

  int _permitsPerMinute;
  DateTime _nextAvailable = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _blockedUntil;

  int get permitsPerMinute => _permitsPerMinute;

  set permitsPerMinute(int value) {
    _permitsPerMinute = value < 1 ? 1 : value;
  }

  Duration get _interval =>
      Duration(microseconds: (60 * 1000000 / _permitsPerMinute).round());

  /// How long the next [acquire] would wait, without reserving a slot.
  Duration get currentDelay {
    final DateTime now = DateTime.now();
    final DateTime start = _startFor(now);
    final Duration delay = start.difference(now);
    return delay.isNegative ? Duration.zero : delay;
  }

  /// True while a provider-imposed penalty is still in effect.
  bool get isPenalised =>
      _blockedUntil != null && _blockedUntil!.isAfter(DateTime.now());

  DateTime _startFor(DateTime now) {
    DateTime start = _nextAvailable.isAfter(now) ? _nextAvailable : now;
    final DateTime? blocked = _blockedUntil;
    if (blocked != null && blocked.isAfter(start)) start = blocked;
    return start;
  }

  /// Reserves the next slot, waiting for it if necessary.
  Future<void> acquire() async {
    final DateTime now = DateTime.now();
    final DateTime start = _startFor(now);

    // Reserve before awaiting, so concurrent callers queue behind each other.
    _nextAvailable = start.add(_interval);

    final Duration delay = start.difference(now);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  /// Back off after the provider said no — e.g. an HTTP 429.
  ///
  /// Everything already queued slides behind the penalty too, which is the
  /// point: continuing to fire during a throttle just extends it.
  void penalise(Duration duration) {
    final DateTime until = DateTime.now().add(duration);
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
      _blockedUntil = until;
    }
  }

  /// Clears any penalty, after a request succeeds again.
  void recover() => _blockedUntil = null;

  void reset() {
    _nextAvailable = DateTime.fromMillisecondsSinceEpoch(0);
    _blockedUntil = null;
  }
}
