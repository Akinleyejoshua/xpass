import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/core/services/model_catalog_service.dart';

ModelCatalogService serviceServing(
  Map<String, Object?> byPage, {
  int status = 200,
  void Function(http.Request)? onRequest,
}) {
  return ModelCatalogService(
    clientFactory: () => MockClient((http.Request request) async {
      onRequest?.call(request);
      final String token = request.url.queryParameters['pageToken'] ?? '';
      final Object? payload = byPage[token] ?? byPage[''];
      return http.Response(
        jsonEncode(payload),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

Map<String, Object?> geminiModel(
  String id, {
  List<String> methods = const <String>[
    'generateContent',
    'streamGenerateContent',
  ],
}) => <String, Object?>{
  'name': 'models/$id',
  'displayName': id.toUpperCase(),
  'supportedGenerationMethods': methods,
  'inputTokenLimit': 1048576,
};

void main() {
  group('fetchGeminiModels', () {
    test('strips the models/ prefix and keeps generation models', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{
          'models': <Object?>[
            geminiModel('gemini-3.5-flash'),
            geminiModel(
              'gemini-embedding-001',
              methods: <String>['embedContent'],
            ),
          ],
        },
      });

      final List<ModelInfo> models = await service.fetchGeminiModels(
        apiKey: 'k',
      );

      expect(models.map((ModelInfo m) => m.id), <String>['gemini-3.5-flash']);
    });

    test('follows pagination', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{
          'models': <Object?>[geminiModel('gemini-3.5-flash')],
          'nextPageToken': 'page2',
        },
        'page2': <String, Object?>{
          'models': <Object?>[geminiModel('gemini-3.8-flash')],
        },
      });

      final List<ModelInfo> models = await service.fetchGeminiModels(
        apiKey: 'k',
      );

      expect(models.map((ModelInfo m) => m.id).toSet(), <String>{
        'gemini-3.5-flash',
        'gemini-3.8-flash',
      });
    });

    test('sorts the newest version first', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{
          'models': <Object?>[
            geminiModel('gemini-2.5-pro'),
            geminiModel('gemini-3.8-flash'),
            geminiModel('gemini-3.5-flash'),
          ],
        },
      });

      final List<ModelInfo> models = await service.fetchGeminiModels(
        apiKey: 'k',
      );

      expect(models.first.id, 'gemini-3.8-flash');
      expect(models.last.id, 'gemini-2.5-pro');
    });

    test('marks non-chat endpoints as unsuitable for screen reading', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{
          'models': <Object?>[
            geminiModel('gemini-3.5-flash'),
            geminiModel('gemini-3.1-flash-image'),
            geminiModel('gemini-2.5-flash-preview-tts'),
            geminiModel('gemini-3.5-transcribe'),
          ],
        },
      });

      final List<ModelInfo> models = await service.fetchGeminiModels(
        apiKey: 'k',
      );

      ModelInfo find(String id) =>
          models.firstWhere((ModelInfo m) => m.id == id);

      expect(find('gemini-3.5-flash').supportsVision, isTrue);
      expect(find('gemini-3.1-flash-image').supportsVision, isFalse);
      expect(find('gemini-2.5-flash-preview-tts').supportsVision, isFalse);
      expect(find('gemini-3.5-transcribe').supportsVision, isFalse);
      // Still listed, just not recommended for the solver.
      expect(models.length, 4);
    });

    test('sends the key as a header, never in the URL', () async {
      http.Request? captured;
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{'models': <Object?>[]},
      }, onRequest: (http.Request r) => captured = r);

      await service.fetchGeminiModels(apiKey: 'AIza-secret');

      expect(captured!.headers['x-goog-api-key'], 'AIza-secret');
      expect(captured!.url.toString(), isNot(contains('AIza-secret')));
    });

    test('requires a key', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{},
      });

      expect(
        () => service.fetchGeminiModels(apiKey: ''),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('explains a rejected key', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{},
      }, status: 403);

      expect(
        () => service.fetchGeminiModels(apiKey: 'bad'),
        throwsA(
          isA<AiServiceException>().having(
            (AiServiceException e) => e.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
    });
  });

  group('fetchNimModels', () {
    test('reads the OpenAI-style list without needing a key', () async {
      http.Request? captured;
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{
          'object': 'list',
          'data': <Object?>[
            <String, Object?>{
              'id': 'nvidia/nemotron-3.5-lightning-30b-a3b',
              'owned_by': 'nvidia',
            },
            <String, Object?>{
              'id': 'meta/llama-3.2-90b-vision-instruct',
              'owned_by': 'meta',
            },
          ],
        },
      }, onRequest: (http.Request r) => captured = r);

      final List<ModelInfo> models = await service.fetchNimModels();

      expect(models, hasLength(2));
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('flags vision-language models', () async {
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'meta/llama-3.2-90b-vision-instruct'},
            <String, Object?>{'id': 'nvidia/nemotron-3.5-lightning-30b-a3b'},
          ],
        },
      });

      final List<ModelInfo> models = await service.fetchNimModels();

      expect(
        models
            .firstWhere((ModelInfo m) => m.id.contains('vision'))
            .supportsVision,
        isTrue,
      );
      expect(
        models
            .firstWhere((ModelInfo m) => m.id.contains('lightning'))
            .supportsVision,
        isFalse,
      );
    });

    test('attaches the key when one is available', () async {
      http.Request? captured;
      final ModelCatalogService service = serviceServing(<String, Object?>{
        '': <String, Object?>{'data': <Object?>[]},
      }, onRequest: (http.Request r) => captured = r);

      await service.fetchNimModels(apiKey: 'nvapi-1');
      expect(captured!.headers['Authorization'], 'Bearer nvapi-1');
    });
  });
}
