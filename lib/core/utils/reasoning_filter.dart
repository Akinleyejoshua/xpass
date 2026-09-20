/// Strips a model's internal monologue out of a stream before it reaches the
/// HUD.
///
/// Hybrid reasoning models think out loud. Some wrap it in `<think>` tags,
/// some emit it as ordinary prose ("Here's a thinking process: 1. Analyze the
/// user input…"), and some then run out of token budget before writing the
/// actual answer. None of that is readable mid-interview.
///
/// Two stages, both streaming — no buffering of the whole response, because
/// time-to-first-token is the entire point of the fast tier:
///
///  1. **Tagged reasoning** is removed outright. Tags split across deltas are
///     handled by holding back a short tail.
///  2. **Untagged preamble** is detected from the first few characters. Only an
///     unambiguous opener triggers it, and the probe is abandoned the moment
///     the text cannot match one, so a normal answer is never delayed by more
///     than a handful of characters.
///
/// If the whole response turns out to be reasoning, [suppressedEverything]
/// tells the caller to say so plainly rather than show a blank panel.
class ReasoningFilter {
  static const List<String> _tagNames = <String>[
    'think',
    'thinking',
    'reason',
    'reasoning',
    'reflection',
    'scratchpad',
    'analysis',
  ];

  /// Openers that are never the start of a real answer.
  static const List<String> _preambleMarkers = <String>[
    "here's a thinking process",
    'here is a thinking process',
    "here's my thinking",
    'here is my thinking',
    "here's my thought process",
    'here is my thought process',
    'thinking process:',
    'thought process:',
    'reasoning:',
    'analysis:',
    'let me think through',
    'let me think about',
    'let me analyze',
    'let me analyse',
    'let me break this down',
    'first, i need to analyze',
    'first, i need to understand',
    'i need to analyze the',
    'okay, let me',
    'okay, so the user',
    'the user is asking',
    'the user wants',
  ];

  /// Longest marker, so we know when to stop probing.
  static final int _probeLimit = _preambleMarkers.fold(
    0,
    (int a, String m) => m.length > a ? m.length : a,
  );

  /// Beyond this, stop discarding and show what is left — a wrong answer the
  /// user can see beats a blank panel they cannot debug.
  static const int _discardLimit = 4000;

  String _pending = '';
  String _probe = '';

  bool _inTag = false;
  String _openTag = '';
  bool _discarding = false;
  int _discarded = 0;
  bool _emitted = false;
  bool _sawReasoning = false;

  /// True when reasoning was found and removed.
  bool get removedReasoning => _sawReasoning;

  /// True when reasoning was removed and nothing else ever arrived.
  bool get suppressedEverything => _sawReasoning && !_emitted;

  /// Feed one delta; returns the text that should actually be shown.
  String add(String delta) {
    if (delta.isEmpty) return '';
    final String visible = _stripTags(delta);
    if (visible.isEmpty) return '';
    return _stripPreamble(visible);
  }

  /// Release anything held back when the stream ends.
  String flush() {
    final String tail = _pending + _probe;
    _pending = '';
    _probe = '';
    if (tail.isEmpty || _inTag || _discarding) return '';
    if (tail.trim().isNotEmpty) _emitted = true;
    return tail;
  }

  // ------------------------------------------------------------------ stage 1

  String _stripTags(String delta) {
    _pending += delta;
    final StringBuffer out = StringBuffer();

    while (_pending.isNotEmpty) {
      if (_inTag) {
        final String close = '</$_openTag>';
        final int index = _pending.indexOf(close);
        if (index < 0) {
          // Hold back just enough to catch a closing tag split across deltas.
          _pending = _tail(_pending, close.length - 1);
          break;
        }
        _pending = _pending.substring(index + close.length);
        _inTag = false;
        _sawReasoning = true;
        continue;
      }

      final _TagMatch? open = _findOpenTag(_pending);
      if (open != null) {
        out.write(_pending.substring(0, open.start));
        _openTag = open.name;
        _inTag = true;
        _sawReasoning = true;
        _pending = _pending.substring(open.end);
        continue;
      }

      // No complete tag yet. Hold back a trailing '<…' only while it could
      // still become one — a fixed-length window is not enough, because
      // `<reasoning effort="high">` is longer than any sensible window and
      // `List<int>` must not be held at all.
      final int bracket = _pending.lastIndexOf('<');
      if (bracket >= 0 &&
          !_pending.substring(bracket).contains('>') &&
          _couldBeTagStart(_pending.substring(bracket))) {
        out.write(_pending.substring(0, bracket));
        _pending = _pending.substring(bracket);
      } else {
        out.write(_pending);
        _pending = '';
      }
      break;
    }

    return out.toString();
  }

  static String _tail(String value, int keep) =>
      value.length <= keep ? value : value.substring(value.length - keep);

  /// Whether a trailing `<…` fragment could still turn into a reasoning tag.
  static bool _couldBeTagStart(String fragment) {
    final String body = fragment.substring(1).toLowerCase();
    if (body.isEmpty) return true; // just '<' so far
    if (body.length > 200) return false; // runaway, not a tag
    if (body.startsWith(' ')) return false; // '< b' is a comparison

    final String name = body.split(RegExp(r'[\s>]')).first;
    if (name.isEmpty) return false;
    return _tagNames.any((String tag) => tag.startsWith(name));
  }

  static _TagMatch? _findOpenTag(String value) {
    for (final String name in _tagNames) {
      for (final String form in <String>['<$name>', '<$name ']) {
        final int start = value.indexOf(form);
        if (start < 0) continue;
        final int end = form.endsWith(' ')
            ? value.indexOf('>', start) + 1
            : start + form.length;
        if (end <= start) continue; // '>' not arrived yet
        return _TagMatch(name, start, end);
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ stage 2

  String _stripPreamble(String visible) {
    if (_discarding) {
      _discarded += visible.length;
      if (_discarded < _discardLimit) return '';
      _discarding = false;
      _emitted = true;
      return visible;
    }

    if (_emitted) return visible;

    _probe += visible;
    final String lower = _probe.trimLeft().toLowerCase();
    if (lower.isEmpty) return '';

    for (final String marker in _preambleMarkers) {
      if (lower.startsWith(marker)) {
        _discarding = true;
        _sawReasoning = true;
        _discarded = _probe.length;
        _probe = '';
        return '';
      }
    }

    // Could this still become a marker? Keep probing only while it might.
    final bool couldMatch =
        lower.length < _probeLimit &&
        _preambleMarkers.any((String m) => m.startsWith(lower));
    if (couldMatch) return '';

    final String flushed = _probe;
    _probe = '';
    if (flushed.trim().isNotEmpty) _emitted = true;
    return flushed;
  }
}

class _TagMatch {
  const _TagMatch(this.name, this.start, this.end);
  final String name;
  final int start;
  final int end;
}
