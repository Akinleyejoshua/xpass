import 'dart:typed_data';

/// Wraps raw 16-bit little-endian PCM in a 44-byte canonical WAV header.
///
/// The batch transcription backends take a file rather than a raw stream, and
/// both are far happier with a real RIFF container than with headerless PCM.
Uint8List pcm16ToWav(
  Uint8List pcm, {
  int sampleRate = 16000,
  int channels = 1,
}) {
  const int headerSize = 44;
  const int bitsPerSample = 16;
  final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final int blockAlign = channels * bitsPerSample ~/ 8;
  final int dataSize = pcm.lengthInBytes;

  final Uint8List out = Uint8List(headerSize + dataSize);
  final ByteData view = ByteData.view(out.buffer);

  void writeAscii(int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      out[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');

  writeAscii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // PCM chunk size
  view.setUint16(20, 1, Endian.little); // audio format = PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);

  writeAscii(36, 'data');
  view.setUint32(40, dataSize, Endian.little);

  out.setRange(headerSize, headerSize + dataSize, pcm);
  return out;
}
