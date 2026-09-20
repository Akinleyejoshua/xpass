import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/assist_models.dart';

/// One model offered by a provider.
class ModelInfo implements Comparable<ModelInfo> {
  const ModelInfo({
    required this.id,
    required this.displayName,
    this.supportsStreaming = true,
    this.supportsVision = false,
    this.inputTokenLimit,
  });

  /// The identifier sent in an API request, e.g. `gemini-2.5-flash`.
  final String id;

  /// What the provider calls it, for the dropdown.
  final String displayName;
  final bool supportsStreaming;

  /// True when the model accepts image input — required for screen solving.
  final bool supportsVision;
  final int? inputTokenLimit;

  String get label =>
      displayName.isEmpty || displayName == id ? id : '$id  ·  $displayName';

  /// Newest-looking first, then alphabetically. Providers return an arbitrary
  /// order and the user almost always wants the latest model.
  @override
  int compareTo(ModelInfo other) {
    final double a = _versionScore(id);
    final double b = _versionScore(other.id);
    if (a != b) return b.compareTo(a);
    return id.compareTo(other.id);
  }

  static double _versionScore(String id) {
    final RegExpMatch? match = RegExp(r'(\d+)\.(\d+)').firstMatch(id);
    if (match == null) {
      final RegExpMatch? single = RegExp(r'(\d+)b?').firstMatch(id);
      return single == null ? 0 : double.parse(single.group(1)!);
    }
    return double.parse(match.group(1)!) + double.parse(match.group(2)!) / 100;
  }

  @override
  bool operator ==(Object other) => other is ModelInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Fetches the live model lists from NVIDIA NIM and Google Gemini.
///
/// Both catalogues change often — new Gemini flash revisions, new NIM-hosted
/// open models — so a hardcoded list goes stale within weeks. The static lists
/// in [XpSettings] remain only as an offline fallback.
class ModelCatalogService {
  ModelCatalogService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const Duration _timeout = Duration(seconds: 15);

  static const String geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const String nimEndpoint =
      'https://integrate.api.nvidia.com/v1/models';

  // ------------------------------------------------------------------ Gemini

  /// Lists Gemini models, following pagination.
  ///
  /// Only models that can actually run a streamed generation are returned; the
  /// catalogue also contains embedding and token-counting endpoints that would
  /// fail the moment the user picked one.
  Future<List<ModelInfo>> fetchGeminiModels({required String apiKey}) async {
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException(
        'Add a Gemini API key to load the model list.',
        provider: 'Gemini',
      );
    }

    final http.Client client = _clientFactory();
    final List<ModelInfo> models = <ModelInfo>[];
    String? pageToken;

    try {
      // Bounded, so a malformed nextPageToken cannot loop forever.
      for (int page = 0; page < 10; page++) {
        final Uri uri = Uri.parse(geminiEndpoint).replace(
          queryParameters: <String, String>{
            'pageSize': '200',
            'pageToken': ?pageToken,
          },
        );

        final http.Response response = await client
            .get(
              uri,
              headers: <String, String>{'x-goog-api-key': apiKey.trim()},
            )
            .timeout(_timeout);

        if (response.statusCode != 200) {
          throw AiServiceException(
            _describe(response.body, response.statusCode),
            statusCode: response.statusCode,
            provider: 'Gemini',
          );
        }

        final Object? decoded = jsonDecode(response.body);
        if (decoded is! Map<String, Object?>) break;

        for (final Object? raw
            in decoded['models'] as List<Object?>? ?? const <Object?>[]) {
          if (raw is! Map<String, Object?>) continue;

          final String name = raw['name'] as String? ?? '';
          if (name.isEmpty) continue;

          final List<String> methods =
              (raw['supportedGenerationMethods'] as List<Object?>? ??
                      const <Object?>[])
                  .whereType<String>()
                  .toList();
          if (!methods.contains('streamGenerateContent') &&
              !methods.contains('generateContent')) {
            continue;
          }

          final String id = name.startsWith('models/')
              ? name.substring('models/'.length)
              : name;

          models.add(
            ModelInfo(
              id: id,
              displayName: raw['displayName'] as String? ?? '',
              supportsStreaming: methods.contains('streamGenerateContent'),
              // The catalogue mixes in image generation, TTS, video and
              // embedding endpoints that would fail the moment they were used
              // to read a screenshot.
              supportsVision: isTextGenerationModel(id),
              inputTokenLimit: (raw['inputTokenLimit'] as num?)?.toInt(),
            ),
          );
        }

        pageToken = decoded['nextPageToken'] as String?;
        if (pageToken == null || pageToken.isEmpty) break;
      }
    } on TimeoutException {
      throw const AiServiceException(
        'Timed out loading the model list.',
        provider: 'Gemini',
      );
    } on http.ClientException catch (error) {
      throw AiServiceException(error.message, provider: 'Gemini');
    } finally {
      client.close();
    }

    models.sort();
    return models;
  }

  // -------------------------------------------------------------------- NIM

  /// Lists the models the NVIDIA NIM gateway is serving.
  /// The NIM catalogue is served without authentication, so the picker is
  /// populated even before the user has pasted a key.
  Future<List<ModelInfo>> fetchNimModels({String apiKey = ''}) async {
    final http.Client client = _clientFactory();
    try {
      final http.Response response = await client
          .get(
            Uri.parse(nimEndpoint),
            headers: <String, String>{
              if (apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${apiKey.trim()}',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw AiServiceException(
          _describe(response.body, response.statusCode),
          statusCode: response.statusCode,
          provider: 'NVIDIA NIM',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return const <ModelInfo>[];

      final List<ModelInfo> models = <ModelInfo>[];
      for (final Object? raw
          in decoded['data'] as List<Object?>? ?? const <Object?>[]) {
        if (raw is! Map<String, Object?>) continue;
        final String id = raw['id'] as String? ?? '';
        if (id.isEmpty) continue;

        models.add(
          ModelInfo(
            id: id,
            displayName: raw['owned_by'] as String? ?? '',
            supportsVision: _looksMultimodal(id),
          ),
        );
      }

      models.sort();
      return models;
    } on TimeoutException {
      throw const AiServiceException(
        'Timed out loading the model list.',
        provider: 'NVIDIA NIM',
      );
    } on http.ClientException catch (error) {
      throw AiServiceException(error.message, provider: 'NVIDIA NIM');
    } finally {
      client.close();
    }
  }

  /// False for endpoints that exist in the catalogue but cannot answer a
  /// question about a screenshot: image generation, TTS, video, embeddings.
  static bool isTextGenerationModel(String id) {
    final String lower = id.toLowerCase();
    const List<String> excluded = <String>[
      'embedding',
      'tts',
      '-image',
      'veo-',
      'lyria',
      'robotics',
      'transcribe',
      'aqa',
    ];
    return !excluded.any(lower.contains);
  }

  static bool _looksMultimodal(String id) {
    final String lower = id.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('vlm') ||
        lower.contains('vila') ||
        lower.contains('llava') ||
        lower.contains('nemotron-nano-vl');
  }

  static String _describe(String body, int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'API key rejected — cannot list models.';
    }
    if (statusCode == 429) return 'Rate limited while listing models.';
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final Object? error = decoded['error'];
        if (error is Map<String, Object?> && error['message'] is String) {
          return error['message']! as String;
        }
        if (error is String) return error;
      }
    } on FormatException {
      // Fall through.
    }
    return 'Could not list models (HTTP $statusCode).';
  }
}
