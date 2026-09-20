import 'dart:convert';

/// Decodes a `text/event-stream` byte stream into its `data:` payloads.
///
/// Handles the parts of the SSE grammar the model providers actually use:
/// multi-line `data:` fields joined with newlines, `:` comment/keep-alive
/// lines, CRLF endings, and the `[DONE]` sentinel that terminates the stream.
///
/// The UTF-8 decoder is stateful, so multi-byte characters split across TCP
/// chunks are reassembled correctly rather than emitting replacement chars
/// mid-token.
Stream<String> decodeSseData(Stream<List<int>> bytes) async* {
  final List<String> dataLines = <String>[];

  Stream<String> lines = bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  await for (final String rawLine in lines) {
    final String line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;

    // Blank line terminates an event.
    if (line.isEmpty) {
      if (dataLines.isEmpty) continue;
      final String payload = dataLines.join('\n');
      dataLines.clear();
      if (payload == '[DONE]') return;
      yield payload;
      continue;
    }

    // Comment / keep-alive.
    if (line.startsWith(':')) continue;

    if (line.startsWith('data:')) {
      // Exactly one optional leading space is part of the field value syntax.
      String value = line.substring(5);
      if (value.startsWith(' ')) value = value.substring(1);
      if (value == '[DONE]') return;
      dataLines.add(value);
    }
    // `event:`, `id:` and `retry:` carry nothing we need.
  }

  // Some servers close without a trailing blank line.
  if (dataLines.isNotEmpty) {
    final String payload = dataLines.join('\n');
    if (payload != '[DONE]') yield payload;
  }
}
