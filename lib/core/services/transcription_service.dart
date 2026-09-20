import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_prompts.dart';
import '../models/assist_models.dart';
import '../models/audio_models.dart';
import '../utils/wav.dart';
import 'gemini_service.dart';
import 'settings_service.dart';

/// A transcript update from any backend.
class TranscriptEvent {
  const TranscriptEvent({
    required this.source,
    required this.text,
    required this.isFinal,
  });

  final AudioSource source;
  final String text;

  /// Streaming backends emit `false` while still revising the utterance.
  final bool isFinal;
}

/// Common shape for every speech-to-text backend.
abstract class Transcriber {
  Stream<TranscriptEvent> get events;

  /// Errors worth telling the user about (auth, quota, socket death).
  Stream<String> get errors;

  Future<void> start();

  /// Continuous backends consume raw frames as they arrive.
  void pushFrame(AudioFrame frame) {}

  /// Segment backends consume complete utterances isolated by the VAD.
  void pushSegment(SpeechSegment segment) {}

  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// Gemini, one request per utterance (default)
// ---------------------------------------------------------------------------

/// Transcribes each VAD-isolated utterance with a single Gemini call.
///
/// The default backend: nothing to keep alive between questions, so a dropped
/// Wi-Fi packet costs one utterance rather than the whole session. At most
/// [_maxConcurrent] requests are in flight so a fast back-and-forth cannot
/// stampede the API.
class GeminiBatchTranscriber extends Transcriber {
  GeminiBatchTranscriber({
    required this.gemini,
    required this.apiKey,
    required this.model,
  });

  final GeminiService gemini;
  final String apiKey;
  final String model;

  static const int _maxConcurrent = 2;

  final StreamController<TranscriptEvent> _events =
      StreamController<TranscriptEvent>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final List<SpeechSegment> _queue = <SpeechSegment>[];

  int _inFlight = 0;
  bool _disposed = false;

  @override
  Stream<TranscriptEvent> get events => _events.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> start() async {}

  @override
  void pushSegment(SpeechSegment segment) {
    if (_disposed) return;
    _queue.add(segment);
    _drain();
  }

  void _drain() {
    while (_inFlight < _maxConcurrent && _queue.isNotEmpty) {
      final SpeechSegment segment = _queue.removeAt(0);
      _inFlight++;
      unawaited(_transcribe(segment));
    }
  }

  Future<void> _transcribe(SpeechSegment segment) async {
    try {
      final Uint8List wav = pcm16ToWav(
        segment.pcm,
        sampleRate: segment.sampleRate,
      );
      final String text = await gemini.transcribe(
        apiKey: apiKey,
        wav: wav,
        model: model,
      );
      if (_disposed || _events.isClosed) return;
      if (text.trim().isEmpty) return;
      _events.add(
        TranscriptEvent(
          source: segment.source,
          text: text.trim(),
          isFinal: true,
        ),
      );
    } on AiServiceException catch (error) {
      if (!_disposed && !_errors.isClosed) _errors.add(error.message);
    } catch (error) {
      if (!_disposed && !_errors.isClosed) _errors.add(error.toString());
    } finally {
      _inFlight--;
      if (!_disposed) _drain();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _queue.clear();
    await _events.close();
    await _errors.close();
  }
}

// ---------------------------------------------------------------------------
// NVIDIA Riva ASR NIM
// ---------------------------------------------------------------------------

/// Transcribes utterances with a Riva ASR NIM container.
///
/// NIM ASR exposes an OpenAI-compatible `POST /audio/transcriptions` multipart
/// endpoint, so this works against a locally hosted container
/// (`http://localhost:9000/v1` by default) with no gRPC stack in Dart. Pointing
/// [baseUrl] at a hosted deployment works identically.
class RivaNimTranscriber extends Transcriber {
  RivaNimTranscriber({
    required this.baseUrl,
    this.apiKey = '',
    this.model = 'nvidia/parakeet-ctc-1.1b-asr',
    this.language = 'en-US',
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String language;

  static const int _maxConcurrent = 2;

  final StreamController<TranscriptEvent> _events =
      StreamController<TranscriptEvent>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final List<SpeechSegment> _queue = <SpeechSegment>[];
  final http.Client _client = http.Client();

  int _inFlight = 0;
  bool _disposed = false;

  @override
  Stream<TranscriptEvent> get events => _events.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> start() async {}

  @override
  void pushSegment(SpeechSegment segment) {
    if (_disposed) return;
    _queue.add(segment);
    _drain();
  }

  void _drain() {
    while (_inFlight < _maxConcurrent && _queue.isNotEmpty) {
      final SpeechSegment segment = _queue.removeAt(0);
      _inFlight++;
      unawaited(_transcribe(segment));
    }
  }

  Future<void> _transcribe(SpeechSegment segment) async {
    try {
      final Uri uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/audio/transcriptions',
      );
      final http.MultipartRequest request = http.MultipartRequest('POST', uri)
        ..fields['model'] = model
        ..fields['language'] = language
        ..fields['response_format'] = 'json'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            pcm16ToWav(segment.pcm, sampleRate: segment.sampleRate),
            filename: 'utterance.wav',
          ),
        );
      if (apiKey.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }

      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final String body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw AiServiceException(
          body.trim().isEmpty
              ? 'Riva NIM returned HTTP ${streamed.statusCode}.'
              : body.trim(),
          statusCode: streamed.statusCode,
          provider: 'Riva NIM',
        );
      }

      final Object? decoded = jsonDecode(body);
      final String text = decoded is Map<String, Object?>
          ? (decoded['text'] as String? ?? '')
          : '';

      if (_disposed || _events.isClosed || text.trim().isEmpty) return;
      _events.add(
        TranscriptEvent(
          source: segment.source,
          text: text.trim(),
          isFinal: true,
        ),
      );
    } on AiServiceException catch (error) {
      if (!_disposed && !_errors.isClosed) _errors.add(error.message);
    } catch (error) {
      if (!_disposed && !_errors.isClosed) {
        _errors.add('Riva NIM unreachable at $baseUrl — $error');
      }
    } finally {
      _inFlight--;
      if (!_disposed) _drain();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _queue.clear();
    _client.close();
    await _events.close();
    await _errors.close();
  }
}

// ---------------------------------------------------------------------------
// Gemini Live (bidirectional WebSocket)
// ---------------------------------------------------------------------------

/// Continuous transcription over the Gemini Live bidirectional socket.
///
/// One socket per audio source, because a Live session transcribes a single
/// input stream and we need to know whether a sentence came from the user or
/// from the interviewer.
class GeminiLiveTranscriber extends Transcriber {
  GeminiLiveTranscriber({
    required this.apiKey,
    required this.sources,
    this.model = 'gemini-3.8-live',
  });

  final String apiKey;
  final String model;

  /// Which capture paths get their own session.
  final List<AudioSource> sources;

  final StreamController<TranscriptEvent> _events =
      StreamController<TranscriptEvent>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final Map<AudioSource, _LiveSession> _sessions =
      <AudioSource, _LiveSession>{};

  bool _disposed = false;

  @override
  Stream<TranscriptEvent> get events => _events.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> start() async {
    for (final AudioSource source in sources) {
      final _LiveSession session = _LiveSession(
        apiKey: apiKey,
        model: model,
        source: source,
        onEvent: (TranscriptEvent event) {
          if (!_disposed && !_events.isClosed) _events.add(event);
        },
        onError: (String message) {
          if (!_disposed && !_errors.isClosed) _errors.add(message);
        },
      );
      _sessions[source] = session;
      await session.connect();
    }
  }

  @override
  void pushFrame(AudioFrame frame) {
    if (_disposed) return;
    _sessions[frame.source]?.sendAudio(frame.pcm);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final _LiveSession session in _sessions.values) {
      await session.close();
    }
    _sessions.clear();
    await _events.close();
    await _errors.close();
  }
}

/// One Live socket, with bounded reconnect.
class _LiveSession {
  _LiveSession({
    required this.apiKey,
    required this.model,
    required this.source,
    required this.onEvent,
    required this.onError,
  });

  final String apiKey;
  final String model;
  final AudioSource source;
  final void Function(TranscriptEvent) onEvent;
  final void Function(String) onError;

  static const String _host = 'generativelanguage.googleapis.com';
  static const String _path =
      '/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
  static const int _maxReconnects = 3;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  final StringBuffer _partial = StringBuffer();
  bool _ready = false;
  bool _closed = false;
  int _reconnects = 0;

  Future<void> connect() async {
    if (_closed) return;
    try {
      final Uri uri = Uri.https(_host, _path, <String, String>{'key': apiKey});
      final WebSocketChannel channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 12));

      channel.sink.add(
        jsonEncode(<String, Object?>{
          'setup': <String, Object?>{
            'model': 'models/$model',
            'generationConfig': <String, Object?>{
              'responseModalities': <String>['TEXT'],
            },
            // Ask the server to transcribe what we send it; we never want the
            // model's own replies on this socket, only the transcript.
            'inputAudioTranscription': <String, Object?>{},
            'systemInstruction': <String, Object?>{
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': XpPrompts.transcribe},
              ],
            },
          },
        }),
      );

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error) => _handleDisconnect(error.toString()),
        onDone: () => _handleDisconnect('Live socket closed.'),
        cancelOnError: false,
      );
      _ready = true;
      _reconnects = 0;
    } on TimeoutException {
      _handleDisconnect('Gemini Live connection timed out.');
    } catch (error) {
      _handleDisconnect('Gemini Live connection failed: $error');
    }
  }

  void sendAudio(Uint8List pcm) {
    if (!_ready || _closed || _channel == null || pcm.isEmpty) return;
    try {
      _channel!.sink.add(
        jsonEncode(<String, Object?>{
          'realtimeInput': <String, Object?>{
            'mediaChunks': <Map<String, Object?>>[
              <String, Object?>{
                'mimeType': 'audio/pcm;rate=16000',
                'data': base64Encode(pcm),
              },
            ],
          },
        }),
      );
    } catch (error) {
      _handleDisconnect('Gemini Live send failed: $error');
    }
  }

  void _handleMessage(Object? raw) {
    final String text = switch (raw) {
      String value => value,
      List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => '',
    };
    if (text.isEmpty) return;

    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return;

      if (decoded['setupComplete'] != null) {
        _ready = true;
        return;
      }

      final Object? serverContent = decoded['serverContent'];
      if (serverContent is! Map<String, Object?>) return;

      final Object? transcription = serverContent['inputTranscription'];
      if (transcription is Map<String, Object?>) {
        final Object? chunk = transcription['text'];
        if (chunk is String && chunk.isNotEmpty) {
          _partial.write(chunk);
          onEvent(
            TranscriptEvent(
              source: source,
              text: _partial.toString().trim(),
              isFinal: false,
            ),
          );
        }
      }

      final bool turnComplete = serverContent['turnComplete'] == true;
      if (turnComplete && _partial.isNotEmpty) {
        onEvent(
          TranscriptEvent(
            source: source,
            text: _partial.toString().trim(),
            isFinal: true,
          ),
        );
        _partial.clear();
      }
    } on FormatException {
      // Ignore frames we cannot parse rather than tearing down the session.
    }
  }

  void _handleDisconnect(String reason) {
    _ready = false;
    if (_closed) return;

    if (_reconnects >= _maxReconnects) {
      onError('$reason Falling back is recommended — check Settings.');
      return;
    }
    _reconnects++;
    final Duration backoff = Duration(milliseconds: 400 * _reconnects);
    Timer(backoff, () {
      if (!_closed) unawaited(connect());
    });
  }

  Future<void> close() async {
    _closed = true;
    _ready = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// Builds the transcriber the user selected in Settings.
Transcriber buildTranscriber({
  required TranscriptionBackend backend,
  required XpSettings settings,
  required GeminiService gemini,
}) {
  switch (backend) {
    case TranscriptionBackend.geminiLive:
      return GeminiLiveTranscriber(
        apiKey: settings.geminiApiKey,
        sources: <AudioSource>[
          if (settings.micEnabled) AudioSource.mic,
          if (settings.systemAudioEnabled) AudioSource.system,
        ],
      );
    case TranscriptionBackend.rivaNim:
      return RivaNimTranscriber(
        baseUrl: settings.rivaBaseUrl,
        apiKey: settings.nvidiaApiKey,
      );
    case TranscriptionBackend.geminiBatch:
      return GeminiBatchTranscriber(
        gemini: gemini,
        apiKey: settings.geminiApiKey,
        // A dedicated speech-to-text model, never the reasoning model — the
        // deep tier would add seconds per utterance for no accuracy gain.
        model: settings.geminiTranscribeModel,
      );
  }
}
