import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/features/hud/controllers/hud_controller.dart';

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
      const String markdown = '## Production Code\n```typescript\nconst a = 1;\nconst b';
      expect(
        HudController.extractLastCodeBlock(markdown),
        'const a = 1;\nconst b',
      );
    });

    test('returns null when there is no code at all', () {
      expect(
        HudController.extractLastCodeBlock('Just talking points.\n- one\n- two'),
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
}
