import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/assist_models.dart';
import '../utils/sse.dart';

/// One turn in a chat completion request.
class ChatMessage {
  const ChatMessage.system(this.content) : role = 'system';
  const ChatMessage.user(this.content) : role = 'user';
  const ChatMessage.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'content': content,
  };
}

/// Tier 1 — NVIDIA NIM, the sub-second verbal wingman.
///
/// Streams OpenAI-compatible SSE from `integrate.api.nvidia.com`. Everything
/// here is tuned for time-to-first-token rather than throughput: a short max
/// token budget, low temperature, and no retry (a retry would land well after
/// the moment has passed — better to surface the failure and let the user hit
/// the hotkey again).
class NvidiaNimService {
  NvidiaNimService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const String endpoint =
      'https://integrate.api.nvidia.com/v1/chat/completions';

  /// Time allowed for headers to come back before we give up.
  static const Duration connectTimeout = Duration(seconds: 12);

  /// Maximum gap between tokens before the stream is considered dead.
  static const Duration idleTimeout = Duration(seconds: 20);

  /// Streams assistant text deltas.
  ///
  /// Cancelling the subscription closes the underlying socket, which aborts the
  /// generation server-side — used when the user fires a new query before the
  /// previous one finished.
  Stream<String> streamChat({
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    double temperature = 0.2,
    double topP = 0.9,
    int maxTokens = 420,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException(
        'No API key configured. Add one in Settings or export NVIDIA_API_KEY.',
        provider: 'NVIDIA NIM',
      );
    }

    final http.Client client = _clientFactory();
    try {
      final http.Request request = http.Request('POST', Uri.parse(endpoint))
        ..headers.addAll(<String, String>{
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(<String, Object?>{
          'model': model,
          'messages': messages.map((ChatMessage m) => m.toJson()).toList(),
          'temperature': temperature,
          'top_p': topP,
          'max_tokens': maxTokens,
          'stream': true,
        });

      final http.StreamedResponse response = await client
          .send(request)
          .timeout(connectTimeout);

      if (response.statusCode != 200) {
        final String body = await response.stream.bytesToString();
        throw AiServiceException(
          _describeError(body, response.statusCode),
          statusCode: response.statusCode,
          provider: 'NVIDIA NIM',
        );
      }

      final Stream<String> events = decodeSseData(response.stream).timeout(
        idleTimeout,
        onTimeout: (EventSink<String> sink) => sink.addError(
          const AiServiceException(
            'Stream stalled — no tokens received.',
            provider: 'NVIDIA NIM',
          ),
        ),
      );

      await for (final String payload in events) {
        final String? delta = _extractDelta(payload);
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    } on TimeoutException {
      throw const AiServiceException(
        'Request timed out.',
        provider: 'NVIDIA NIM',
      );
    } on http.ClientException catch (error) {
      throw AiServiceException(error.message, provider: 'NVIDIA NIM');
    } finally {
      client.close();
    }
  }

  /// Pulls `choices[0].delta.content` out of one SSE payload.
  ///
  /// Reasoning models on NIM also emit `reasoning_content`; that is deliberately
  /// dropped — the user wants the answer, not the chain of thought.
  String? _extractDelta(String payload) {
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) return null;

      if (decoded['error'] != null) {
        throw AiServiceException(
          _stringifyError(decoded['error']),
          provider: 'NVIDIA NIM',
        );
      }

      final Object? choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;

      final Object? first = choices.first;
      if (first is! Map<String, Object?>) return null;

      final Object? delta = first['delta'];
      if (delta is Map<String, Object?>) {
        final Object? content = delta['content'];
        if (content is String) return content;
      }

      // Some deployments emit a final non-delta message.
      final Object? message = first['message'];
      if (message is Map<String, Object?>) {
        final Object? content = message['content'];
        if (content is String) return content;
      }
      return null;
    } on FormatException {
      // A partial or malformed frame is not worth killing the stream over.
      return null;
    }
  }

  String _describeError(String body, int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'API key rejected. Check your NVIDIA key in Settings.';
    }
    if (statusCode == 429) {
      return 'Rate limited by NVIDIA. Wait a moment and retry.';
    }
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        if (decoded['error'] != null) return _stringifyError(decoded['error']);
        if (decoded['detail'] != null) {
          return _stringifyError(decoded['detail']);
        }
        if (decoded['message'] is String) return decoded['message']! as String;
      }
    } on FormatException {
      // Fall through to the raw body.
    }
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return 'Request failed with HTTP $statusCode.';
    return trimmed.length > 220 ? '${trimmed.substring(0, 220)}…' : trimmed;
  }

  String _stringifyError(Object? error) {
    if (error is String) return error;
    if (error is Map<String, Object?>) {
      final Object? message = error['message'] ?? error['detail'];
      if (message is String) return message;
    }
    if (error is List && error.isNotEmpty) return _stringifyError(error.first);
    return error.toString();
  }
}
