import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../constants/app_prompts.dart';
import '../models/assist_models.dart';
import '../utils/sse.dart';

/// Tier 2 — Google Gemini, multimodal screen reasoning.
///
/// Uses `:streamGenerateContent?alt=sse` so partial text lands on the HUD while
/// the model is still writing. The key travels in the `x-goog-api-key` header
/// rather than a query parameter, which keeps it out of URLs, proxy logs and
/// crash reports.
class GeminiService {
  GeminiService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const String base = 'https://generativelanguage.googleapis.com/v1beta';

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration idleTimeout = Duration(seconds: 45);

  /// Streams a multimodal generation: optional screenshot plus a text query.
  Stream<String> streamGenerate({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required String userText,
    Uint8List? imageJpeg,
    double temperature = 0.3,
    int maxOutputTokens = 4096,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException(
        'No API key configured. Add one in Settings or export GEMINI_API_KEY.',
        provider: 'Gemini',
      );
    }

    final Uri uri = Uri.parse(
      '$base/models/$model:streamGenerateContent',
    ).replace(queryParameters: <String, String>{'alt': 'sse'});

    // Image first: Gemini attends to a single image more reliably when it
    // precedes the instruction text.
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[
      if (imageJpeg != null && imageJpeg.isNotEmpty)
        <String, Object?>{
          'inlineData': <String, Object?>{
            'mimeType': 'image/jpeg',
            'data': base64Encode(imageJpeg),
          },
        },
      <String, Object?>{'text': userText},
    ];

    final Map<String, Object?> payload = <String, Object?>{
      'systemInstruction': <String, Object?>{
        'parts': <Map<String, Object?>>[
          <String, Object?>{'text': systemInstruction},
        ],
      },
      'contents': <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'parts': parts},
      ],
      'generationConfig': <String, Object?>{
        'temperature': temperature,
        'topP': 0.95,
        'maxOutputTokens': maxOutputTokens,
      },
    };

    final http.Client client = _clientFactory();
    try {
      final http.Request request = http.Request('POST', uri)
        ..headers.addAll(<String, String>{
          'x-goog-api-key': apiKey.trim(),
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..bodyBytes = utf8.encode(jsonEncode(payload));

      final http.StreamedResponse response = await client
          .send(request)
          .timeout(connectTimeout);

      if (response.statusCode != 200) {
        final String body = await response.stream.bytesToString();
        throw AiServiceException(
          _describeError(body, response.statusCode),
          statusCode: response.statusCode,
          provider: 'Gemini',
        );
      }

      final Stream<String> events = decodeSseData(response.stream).timeout(
        idleTimeout,
        onTimeout: (EventSink<String> sink) => sink.addError(
          const AiServiceException(
            'Stream stalled — no tokens received.',
            provider: 'Gemini',
          ),
        ),
      );

      await for (final String payload in events) {
        final String? text = _extractText(payload);
        if (text != null && text.isNotEmpty) yield text;
      }
    } on TimeoutException {
      throw const AiServiceException('Request timed out.', provider: 'Gemini');
    } on http.ClientException catch (error) {
      throw AiServiceException(error.message, provider: 'Gemini');
    } finally {
      client.close();
    }
  }

  /// Single-shot verbatim transcription of one WAV-wrapped speech segment.
  ///
  /// This is the default ASR path: one request per utterance the VAD isolates,
  /// with no long-lived socket to nurse through a flaky conference-hotel
  /// network.
  Future<String> transcribe({
    required String apiKey,
    required Uint8List wav,
    String model = 'gemini-3.5-transcribe',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException(
        'No API key configured.',
        provider: 'Gemini',
      );
    }

    final Uri uri = Uri.parse('$base/models/$model:generateContent');
    final http.Client client = _clientFactory();
    try {
      final http.Response response = await client
          .post(
            uri,
            headers: <String, String>{
              'x-goog-api-key': apiKey.trim(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'systemInstruction': <String, Object?>{
                'parts': <Map<String, Object?>>[
                  <String, Object?>{'text': XpPrompts.transcribe},
                ],
              },
              'contents': <Map<String, Object?>>[
                <String, Object?>{
                  'role': 'user',
                  'parts': <Map<String, Object?>>[
                    <String, Object?>{
                      'inlineData': <String, Object?>{
                        'mimeType': 'audio/wav',
                        'data': base64Encode(wav),
                      },
                    },
                  ],
                },
              ],
              // Deterministic, and short enough that a hallucinated monologue
              // cannot run away with the latency budget.
              'generationConfig': <String, Object?>{
                'temperature': 0.0,
                'maxOutputTokens': 512,
              },
            }),
          )
          .timeout(connectTimeout);

      if (response.statusCode != 200) {
        throw AiServiceException(
          _describeError(response.body, response.statusCode),
          statusCode: response.statusCode,
          provider: 'Gemini',
        );
      }

      return _extractText(response.body)?.trim() ?? '';
    } on TimeoutException {
      throw const AiServiceException(
        'Transcription timed out.',
        provider: 'Gemini',
      );
    } on http.ClientException catch (error) {
      throw AiServiceException(error.message, provider: 'Gemini');
    } finally {
      client.close();
    }
  }

  /// Concatenates every text part of one `GenerateContentResponse`.
  String? _extractText(String payload) {
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) return null;

      if (decoded['error'] != null) {
        throw AiServiceException(
          _stringifyError(decoded['error']),
          provider: 'Gemini',
        );
      }

      // A safety block arrives with no candidates at all.
      final Object? feedback = decoded['promptFeedback'];
      if (feedback is Map<String, Object?> && feedback['blockReason'] != null) {
        throw AiServiceException(
          'Blocked by safety filter (${feedback['blockReason']}).',
          provider: 'Gemini',
        );
      }

      final Object? candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;

      final Object? first = candidates.first;
      if (first is! Map<String, Object?>) return null;

      final Object? finishReason = first['finishReason'];
      if (finishReason is String &&
          finishReason != 'STOP' &&
          finishReason != 'MAX_TOKENS' &&
          finishReason.isNotEmpty) {
        throw AiServiceException(
          'Generation stopped early ($finishReason).',
          provider: 'Gemini',
        );
      }

      final Object? content = first['content'];
      if (content is! Map<String, Object?>) return null;

      final Object? parts = content['parts'];
      if (parts is! List) return null;

      final StringBuffer buffer = StringBuffer();
      for (final Object? part in parts) {
        if (part is Map<String, Object?> && part['text'] is String) {
          buffer.write(part['text']! as String);
        }
      }
      return buffer.toString();
    } on FormatException {
      return null;
    }
  }

  String _describeError(String body, int statusCode) {
    if (statusCode == 400 && body.contains('API_KEY_INVALID')) {
      return 'API key rejected. Check your Gemini key in Settings.';
    }
    if (statusCode == 401 || statusCode == 403) {
      return 'API key rejected or lacks access to this model.';
    }
    if (statusCode == 404) {
      return 'Model not found. Pick a different Gemini model in Settings.';
    }
    if (statusCode == 429) {
      return 'Rate limited by Google. Wait a moment and retry.';
    }
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?> && decoded['error'] != null) {
        return _stringifyError(decoded['error']);
      }
    } on FormatException {
      // Fall through.
    }
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return 'Request failed with HTTP $statusCode.';
    return trimmed.length > 220 ? '${trimmed.substring(0, 220)}…' : trimmed;
  }

  String _stringifyError(Object? error) {
    if (error is String) return error;
    if (error is Map<String, Object?>) {
      final Object? message = error['message'];
      if (message is String) return message;
    }
    return error.toString();
  }
}
