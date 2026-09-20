import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/utils/reasoning_filter.dart';

/// Streams text through the filter one character at a time — the worst case a
/// real SSE stream can produce.
String runCharwise(String input) {
  final ReasoningFilter filter = ReasoningFilter();
  final StringBuffer out = StringBuffer();
  for (final int unit in input.runes) {
    out.write(filter.add(String.fromCharCode(unit)));
  }
  out.write(filter.flush());
  return out.toString();
}

String runChunked(String input, int size) {
  final ReasoningFilter filter = ReasoningFilter();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < input.length; i += size) {
    out.write(
      filter.add(input.substring(i, (i + size).clamp(0, input.length))),
    );
  }
  out.write(filter.flush());
  return out.toString();
}

void main() {
  group('tagged reasoning', () {
    test('removes a think block and keeps the answer', () {
      const String input =
          '<think>The user wants X. Let me consider.</think>'
          'Use a min-heap; O(n log k).';
      expect(runCharwise(input), 'Use a min-heap; O(n log k).');
    });

    test('handles tags split across deltas', () {
      const String input = '<thinking>noise</thinking>Real answer.';
      for (final int size in <int>[1, 2, 3, 5, 7, 11]) {
        expect(runChunked(input, size), 'Real answer.', reason: 'chunk $size');
      }
    });

    test('removes a tag with attributes', () {
      expect(
        runCharwise('<reasoning effort="high">hidden</reasoning>Shown.'),
        'Shown.',
      );
    });

    test('drops an unterminated think block entirely', () {
      final ReasoningFilter filter = ReasoningFilter();
      final StringBuffer out = StringBuffer()
        ..write(filter.add('<think>still thinking when the budget ran out'))
        ..write(filter.flush());

      expect(out.toString(), isEmpty);
      expect(filter.suppressedEverything, isTrue);
    });

    test('leaves ordinary angle brackets alone', () {
      const String input = 'Use List<int> and a < b comparisons.';
      expect(runCharwise(input), input);
    });

    test('passes a clean answer through untouched', () {
      const String input =
          '## Verbal Summary\nUse a sliding window.\n\n'
          '## Production Code\n```python\nx = 1\n```';
      expect(runCharwise(input), input);
      expect(ReasoningFilter().removedReasoning, isFalse);
    });
  });

  group('untagged preamble', () {
    test('discards the monologue this actually produced in the field', () {
      const String input =
          "Here's a thinking process:\n\n"
          '1. Analyze User Input\n'
          '   - User is roleplaying a candidate.\n'
          '2. Check Facts for Relevant Information\n';
      final ReasoningFilter filter = ReasoningFilter();
      final StringBuffer out = StringBuffer()
        ..write(filter.add(input))
        ..write(filter.flush());

      expect(out.toString(), isEmpty);
      expect(filter.suppressedEverything, isTrue);
    });

    test('catches the common openers', () {
      for (final String opener in <String>[
        'Let me think through this.',
        'Thought process: first I should',
        'The user is asking about migrations',
        'Okay, let me look at the facts',
      ]) {
        final ReasoningFilter filter = ReasoningFilter();
        final String out = filter.add(opener) + filter.flush();
        expect(out, isEmpty, reason: opener);
      }
    });

    test('never eats a real answer that merely starts with "Here"', () {
      const String input = 'Here is the tradeoff: batching cuts p99 latency.';
      expect(runCharwise(input), input);
    });

    test('never eats an answer starting with "I"', () {
      const String input = 'I led the Postgres migration at Corvendra.';
      expect(runCharwise(input), input);
    });

    test('a first-person STAR answer survives intact', () {
      const String input =
          'I owned the move from MongoDB to Postgres. '
          'I mapped the schema, then cut over behind a flag. '
          'Query p99 dropped from 900ms to 120ms.';
      expect(runCharwise(input), input);
      expect(runChunked(input, 4), input);
    });

    test('stops discarding rather than swallowing an endless response', () {
      final ReasoningFilter filter = ReasoningFilter();
      final StringBuffer out = StringBuffer()..write(filter.add('Reasoning: '));
      for (int i = 0; i < 200; i++) {
        out.write(filter.add('padding padding padding padding padding '));
      }
      out.write(filter.flush());

      expect(
        out.toString(),
        isNotEmpty,
        reason: 'a blank panel is worse than showing something',
      );
    });
  });

  group('combined', () {
    test('tag then preamble then answer', () {
      const String input =
          '<think>internal</think>'
          "Here's a thinking process: 1. consider";
      final ReasoningFilter filter = ReasoningFilter();
      final String out = filter.add(input) + filter.flush();

      expect(out, isEmpty);
      expect(filter.removedReasoning, isTrue);
      expect(filter.suppressedEverything, isTrue);
    });

    test('empty input is inert', () {
      final ReasoningFilter filter = ReasoningFilter();
      expect(filter.add(''), isEmpty);
      expect(filter.flush(), isEmpty);
      expect(filter.removedReasoning, isFalse);
      expect(filter.suppressedEverything, isFalse);
    });
  });
}
