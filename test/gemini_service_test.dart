import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/core/services/gemini_service.dart';

GeminiService serviceReturning(
  String body, {
  int status = 200,
  void Function(http.BaseRequest)? onRequest,
}) {
  return GeminiService(
    clientFactory: () => MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream requestBody,
    ) async {
      onRequest?.call(request);
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        status,
        request: request,
      );
    }),
  );
}

String textEvent(String text) =>
    'data: ${jsonEncode(<String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': text},
            ],
          },
        },
      ],
    })}\n\n';

void main() {
  group('GeminiService.streamGenerate', () {
    test('concatenates streamed text parts', () async {
      final GeminiService service = serviceReturning(
        '${textEvent("## Verbal Summary\\n")}${textEvent("Use a sliding window.")}',
      );

      final List<String> chunks = await service
          .streamGenerate(
            apiKey: 'AIza-test',
            model: 'gemini-2.0-flash',
            systemInstruction: 'persona',
            userText: 'solve it',
          )
          .toList();

      expect(chunks.join(), contains('sliding window'));
    });

    test(
      'sends the image before the text and keeps the key in a header',
      () async {
        http.BaseRequest? captured;
        final GeminiService service = serviceReturning(
          textEvent('ok'),
          onRequest: (http.BaseRequest r) => captured = r,
        );

        await service
            .streamGenerate(
              apiKey: 'AIza-secret',
              model: 'gemini-2.5-pro',
              systemInstruction: 'persona',
              userText: 'solve',
              imageJpeg: Uint8List.fromList(<int>[1, 2, 3]),
            )
            .drain<void>();

        expect(captured!.headers['x-goog-api-key'], 'AIza-secret');
        expect(
          captured!.url.toString(),
          isNot(contains('AIza-secret')),
          reason: 'the key must never appear in a URL',
        );
        expect(captured!.url.queryParameters['alt'], 'sse');

        final Map<String, Object?> body =
            jsonDecode((captured! as http.Request).body)
                as Map<String, Object?>;
        final List<Object?> parts =
            ((body['contents']! as List<Object?>).first
                    as Map<String, Object?>)['parts']!
                as List<Object?>;
        expect((parts.first as Map<String, Object?>)['inlineData'], isNotNull);
        expect((parts.last as Map<String, Object?>)['text'], 'solve');
      },
    );

    test('reports a safety block as an error, not silence', () async {
      final GeminiService service = serviceReturning(
        'data: {"promptFeedback":{"blockReason":"SAFETY"}}\n\n',
      );

      expect(
        () => service
            .streamGenerate(
              apiKey: 'k',
              model: 'm',
              systemInstruction: 's',
              userText: 'u',
            )
            .toList(),
        throwsA(
          isA<AiServiceException>().having(
            (AiServiceException e) => e.message,
            'message',
            contains('SAFETY'),
          ),
        ),
      );
    });

    test('suggests picking another model on 404', () async {
      final GeminiService service = serviceReturning('{}', status: 404);

      expect(
        () => service
            .streamGenerate(
              apiKey: 'k',
              model: 'gemini-does-not-exist',
              systemInstruction: 's',
              userText: 'u',
            )
            .toList(),
        throwsA(
          isA<AiServiceException>().having(
            (AiServiceException e) => e.message,
            'message',
            contains('Model not found'),
          ),
        ),
      );
    });

    test('MAX_TOKENS is a normal finish, not a failure', () async {
      final GeminiService service = serviceReturning(
        'data: {"candidates":[{"finishReason":"MAX_TOKENS","content":'
        '{"parts":[{"text":"partial"}]}}]}\n\n',
      );

      final List<String> chunks = await service
          .streamGenerate(
            apiKey: 'k',
            model: 'm',
            systemInstruction: 's',
            userText: 'u',
          )
          .toList();

      expect(chunks.join(), 'partial');
    });
  });

  group('GeminiService.transcribe', () {
    test('returns the trimmed transcript', () async {
      final GeminiService service = serviceReturning(
        jsonEncode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{
                    'text': '  So walk me through your stack. ',
                  },
                ],
              },
            },
          ],
        }),
      );

      final String text = await service.transcribe(
        apiKey: 'k',
        wav: Uint8List(64),
      );

      expect(text, 'So walk me through your stack.');
    });

    test('returns empty when the model heard nothing', () async {
      final GeminiService service = serviceReturning(
        jsonEncode(<String, Object?>{'candidates': <Object?>[]}),
      );

      expect(await service.transcribe(apiKey: 'k', wav: Uint8List(8)), isEmpty);
    });
  });
}
