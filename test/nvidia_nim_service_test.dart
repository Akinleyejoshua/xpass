import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/core/services/nvidia_nim_service.dart';

/// Wraps SSE text in a streaming mock client and captures the request.
NvidiaNimService serviceReturning(
  String sse, {
  int status = 200,
  void Function(http.BaseRequest)? onRequest,
}) {
  return NvidiaNimService(
    clientFactory: () => MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream body,
    ) async {
      onRequest?.call(request);
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(sse)),
        status,
        request: request,
      );
    }),
  );
}

String delta(String content) => 'data: ${jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'delta': <String, Object?>{'content': content},
        },
      ],
    })}\n\n';

void main() {
  group('NvidiaNimService.streamChat', () {
    test('yields the content deltas in order', () async {
      final NvidiaNimService service = serviceReturning(
        '${delta("Use a ")}${delta("min-heap")}data: [DONE]\n\n',
      );

      final List<String> chunks = await service
          .streamChat(
            apiKey: 'nvapi-test',
            model: 'meta/llama-3.3-70b-instruct',
            messages: <ChatMessage>[const ChatMessage.user('hi')],
          )
          .toList();

      expect(chunks.join(), 'Use a min-heap');
    });

    test('sends a well-formed streaming request', () async {
      http.BaseRequest? captured;
      final NvidiaNimService service = serviceReturning(
        'data: [DONE]\n\n',
        onRequest: (http.BaseRequest r) => captured = r,
      );

      await service
          .streamChat(
            apiKey: 'nvapi-test',
            model: 'deepseek-ai/deepseek-v3',
            messages: <ChatMessage>[const ChatMessage.system('persona')],
          )
          .drain<void>();

      expect(captured, isNotNull);
      expect(captured!.url.toString(), NvidiaNimService.endpoint);
      expect(captured!.headers['Authorization'], 'Bearer nvapi-test');
      expect(captured!.headers['Accept'], 'text/event-stream');

      final Map<String, Object?> body =
          jsonDecode((captured! as http.Request).body) as Map<String, Object?>;
      expect(body['stream'], isTrue);
      expect(body['model'], 'deepseek-ai/deepseek-v3');
      expect((body['messages']! as List<Object?>).length, 1);
    });

    test('drops reasoning_content and keeps only the answer', () async {
      const String reasoning = 'data: {"choices":[{"delta":'
          '{"reasoning_content":"thinking out loud"}}]}\n\n';
      final NvidiaNimService service =
          serviceReturning('$reasoning${delta("Answer")}');

      final List<String> chunks = await service
          .streamChat(
            apiKey: 'k',
            model: 'm',
            messages: <ChatMessage>[const ChatMessage.user('q')],
          )
          .toList();

      expect(chunks.join(), 'Answer');
    });

    test('survives a malformed frame mid-stream', () async {
      final NvidiaNimService service = serviceReturning(
        '${delta("good ")}data: {not json}\n\n${delta("still good")}',
      );

      final List<String> chunks = await service
          .streamChat(
            apiKey: 'k',
            model: 'm',
            messages: <ChatMessage>[const ChatMessage.user('q')],
          )
          .toList();

      expect(chunks.join(), 'good still good');
    });

    test('explains a rejected key rather than leaking the raw body', () async {
      final NvidiaNimService service = serviceReturning(
        '{"error":{"message":"invalid api key"}}',
        status: 401,
      );

      expect(
        () => service
            .streamChat(
              apiKey: 'bad',
              model: 'm',
              messages: <ChatMessage>[const ChatMessage.user('q')],
            )
            .toList(),
        throwsA(
          isA<AiServiceException>()
              .having((AiServiceException e) => e.message, 'message',
                  contains('key'))
              .having((AiServiceException e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('names rate limiting explicitly', () async {
      final NvidiaNimService service = serviceReturning('', status: 429);

      expect(
        () => service
            .streamChat(
              apiKey: 'k',
              model: 'm',
              messages: <ChatMessage>[const ChatMessage.user('q')],
            )
            .toList(),
        throwsA(
          isA<AiServiceException>().having(
            (AiServiceException e) => e.message,
            'message',
            contains('Rate limited'),
          ),
        ),
      );
    });

    test('fails fast with no key instead of making a request', () async {
      bool called = false;
      final NvidiaNimService service = serviceReturning(
        '',
        onRequest: (_) => called = true,
      );

      await expectLater(
        service
            .streamChat(
              apiKey: '   ',
              model: 'm',
              messages: <ChatMessage>[const ChatMessage.user('q')],
            )
            .toList(),
        throwsA(isA<AiServiceException>()),
      );
      expect(called, isFalse);
    });
  });
}
