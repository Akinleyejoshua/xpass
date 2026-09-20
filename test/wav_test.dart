import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/utils/wav.dart';

void main() {
  group('pcm16ToWav', () {
    test('writes a canonical 44-byte RIFF header', () {
      final Uint8List pcm = Uint8List(1600);
      final Uint8List wav = pcm16ToWav(pcm, sampleRate: 16000);

      expect(wav.lengthInBytes, 44 + pcm.lengthInBytes);

      String ascii(int start, int length) =>
          String.fromCharCodes(wav.sublist(start, start + length));
      expect(ascii(0, 4), 'RIFF');
      expect(ascii(8, 4), 'WAVE');
      expect(ascii(12, 4), 'fmt ');
      expect(ascii(36, 4), 'data');

      final ByteData view = ByteData.view(wav.buffer);
      expect(view.getUint32(4, Endian.little), 36 + pcm.lengthInBytes);
      expect(view.getUint16(20, Endian.little), 1, reason: 'PCM format tag');
      expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint32(28, Endian.little), 32000, reason: 'byte rate');
      expect(view.getUint16(32, Endian.little), 2, reason: 'block align');
      expect(view.getUint16(34, Endian.little), 16, reason: 'bits per sample');
      expect(view.getUint32(40, Endian.little), pcm.lengthInBytes);
    });

    test('copies the samples through unchanged', () {
      final Uint8List pcm = Uint8List.fromList(<int>[1, 2, 3, 4, 250, 251]);
      final Uint8List wav = pcm16ToWav(pcm);

      expect(wav.sublist(44), pcm);
    });

    test('handles an empty buffer', () {
      final Uint8List wav = pcm16ToWav(Uint8List(0));
      expect(wav.lengthInBytes, 44);
      expect(ByteData.view(wav.buffer).getUint32(40, Endian.little), 0);
    });
  });
}
