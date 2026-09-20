import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/utils/sse.dart';

Stream<List<int>> chunks(List<String> parts) =>
    Stream<List<int>>.fromIterable(parts.map(utf8.encode));

void main() {
  group('decodeSseData', () {
    test('yields one payload per event', () async {
      final List<String> events = await decodeSseData(
        chunks(<String>['data: one\n\n', 'data: two\n\n']),
      ).toList();

      expect(events, <String>['one', 'two']);
    });

    test('stops at the [DONE] sentinel', () async {
      final List<String> events = await decodeSseData(
        chunks(<String>['data: a\n\n', 'data: [DONE]\n\n', 'data: b\n\n']),
      ).toList();

      expect(events, <String>['a']);
    });

    test('joins multi-line data fields with newlines', () async {
      final List<String> events = await decodeSseData(
        chunks(<String>['data: line1\ndata: line2\n\n']),
      ).toList();

      expect(events, <String>['line1\nline2']);
    });

    test('ignores comments, CRLF and other fields', () async {
      final List<String> events = await decodeSseData(
        chunks(<String>[': keep-alive\r\n', 'event: msg\r\n', 'data: hi\r\n\r\n']),
      ).toList();

      expect(events, <String>['hi']);
    });

    test('strips exactly one leading space from the value', () async {
      final List<String> events = await decodeSseData(
        chunks(<String>['data:  padded\n\n']),
      ).toList();

      // One space is field syntax; the second belongs to the payload.
      expect(events, <String>[' padded']);
    });

    test('reassembles a multi-byte character split across TCP chunks',
        () async {
      // "é" is 0xC3 0xA9 — arriving in two separate network reads.
      final List<int> encoded = utf8.encode('data: café\n\n');
      final int split = encoded.indexOf(0xC3) + 1;

      final List<String> events = await decodeSseData(
        Stream<List<int>>.fromIterable(<List<int>>[
          encoded.sublist(0, split),
          encoded.sublist(split),
        ]),
      ).toList();

      expect(events, <String>['café']);
    });

    test('emits a trailing event when the server closes without a blank line',
        () async {
      final List<String> events =
          await decodeSseData(chunks(<String>['data: last\n'])).toList();

      expect(events, <String>['last']);
    });

    test('skips empty keep-alive blocks', () async {
      final List<String> events = await decodeSseData(
        chunks(<String>['\n\n', 'data: real\n\n']),
      ).toList();

      expect(events, <String>['real']);
    });
  });
}
