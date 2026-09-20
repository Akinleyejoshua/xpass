import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/features/hud/controllers/hud_controller.dart';

AssistTurn turnWith(String body) {
  final AssistTurn turn = AssistTurn(
    id: 't',
    tier: AssistTier.deep,
    query: 'q',
    startedAt: DateTime.now(),
  );
  turn.body.value = body;
  return turn;
}

void main() {
  group('extractLastCodeBlock', () {
    test('pulls the body of a complete fenced block', () {
      const String markdown = '''
## Production Code
```python
def solve(nums):
    return sorted(nums)
```
**Time:** O(n log n)
''';
      expect(
        HudController.extractLastCodeBlock(markdown),
        'def solve(nums):\n    return sorted(nums)\n',
      );
    });

    test('takes the last block when there are several', () {
      const String markdown = '```py\nfirst()\n```\ntext\n```py\nsecond()\n```';
      expect(HudController.extractLastCodeBlock(markdown), 'second()\n');
    });

    test('returns what has arrived so far inside an unterminated fence', () {
      const String markdown =
          '## Production Code\n```typescript\nconst a = 1;\nconst b';
      expect(
        HudController.extractLastCodeBlock(markdown),
        'const a = 1;\nconst b',
      );
    });

    test('returns null when there is no code at all', () {
      expect(
        HudController.extractLastCodeBlock(
          'Just talking points.\n- one\n- two',
        ),
        isNull,
      );
    });

    test('returns null for a fence that has only just opened', () {
      expect(HudController.extractLastCodeBlock('text\n```'), isNull);
    });

    test('handles a block with no language tag', () {
      expect(HudController.extractLastCodeBlock('```\nplain\n```'), 'plain\n');
    });
  });

  group('AssistTurn.gist', () {
    test('takes the first real sentence, skipping headings', () {
      final AssistTurn turn = turnWith(
        '## Verbal Summary\nUse a sliding window; it is O(n) time.\n\n'
        '## Algorithm\n- Track the window bounds',
      );
      expect(turn.gist, 'Use a sliding window; it is O(n) time.');
    });

    test('strips bullet markers and inline emphasis', () {
      final AssistTurn turn = turnWith('- **Kafka** handles the `fan-out`');
      expect(turn.gist, 'Kafka handles the fan-out');
    });

    test('stops before a code block rather than quoting code', () {
      final AssistTurn turn = turnWith(
        '## Production Code\n```python\nx = 1\n```',
      );
      expect(turn.gist, isEmpty);
    });

    test('is empty before any tokens arrive', () {
      expect(turnWith('').gist, isEmpty);
    });
  });
}
