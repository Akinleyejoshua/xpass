import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/utils/rate_limiter.dart';

void main() {
  group('RateLimiter', () {
    test('lets the first request through immediately', () async {
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 60);
      expect(limiter.currentDelay, Duration.zero);

      final Stopwatch watch = Stopwatch()..start();
      await limiter.acquire();
      expect(watch.elapsedMilliseconds, lessThan(50));
    });

    test('spaces consecutive requests evenly', () async {
      // 600/min == one every 100ms.
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 600);

      await limiter.acquire();
      final Stopwatch watch = Stopwatch()..start();
      await limiter.acquire();
      watch.stop();

      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(80));
    });

    test('never hands two concurrent callers the same slot', () async {
      // 600/min == one every 100ms.
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 600);
      final Stopwatch watch = Stopwatch()..start();
      final List<int> completions = <int>[];

      // Fire three at once, the way a burst of short utterances would.
      await Future.wait<void>(<Future<void>>[
        for (int i = 0; i < 3; i++)
          limiter.acquire().then(
            (_) => completions.add(watch.elapsedMilliseconds),
          ),
      ]);

      completions.sort();
      expect(completions[0], lessThan(50));
      expect(completions[1], greaterThanOrEqualTo(80));
      expect(completions[2], greaterThanOrEqualTo(180));
    });

    test('a penalty pushes the queue back', () {
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 600);

      expect(limiter.isPenalised, isFalse);
      limiter.penalise(const Duration(seconds: 30));

      expect(limiter.isPenalised, isTrue);
      expect(limiter.currentDelay, greaterThan(const Duration(seconds: 25)));
    });

    test('keeps the longest penalty, not the latest', () {
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 60);

      limiter.penalise(const Duration(seconds: 60));
      limiter.penalise(const Duration(seconds: 5));

      expect(limiter.currentDelay, greaterThan(const Duration(seconds: 50)));
    });

    test('recover clears the penalty', () {
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 600);
      limiter.penalise(const Duration(seconds: 30));
      limiter.recover();

      expect(limiter.isPenalised, isFalse);
    });

    test('treats a nonsense rate as one per minute', () {
      expect(RateLimiter(permitsPerMinute: 0).permitsPerMinute, 1);
      expect(RateLimiter(permitsPerMinute: -5).permitsPerMinute, 1);
    });

    test('rate can be changed at runtime', () {
      final RateLimiter limiter = RateLimiter(permitsPerMinute: 10);
      limiter.permitsPerMinute = 30;
      expect(limiter.permitsPerMinute, 30);
    });
  });
}
