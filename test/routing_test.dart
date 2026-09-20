import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/features/hud/controllers/hud_controller.dart';

AssistRoute route(
  String question, {
  bool profileReady = true,
  bool screenEnabled = true,
}) => HudController.routeFor(
  question,
  profileReady: profileReady,
  screenEnabled: screenEnabled,
);

void main() {
  group('looksLikeScreenQuestion', () {
    test('catches explicit references to the screen', () {
      for (final String q in <String>[
        'What do you see on the screen?',
        'Can you walk me through what is on your screen?',
        'Look at the code in the editor and tell me what it does',
      ]) {
        expect(HudController.looksLikeScreenQuestion(q), isTrue, reason: q);
      }
    });

    test('catches a demonstrative attached to something technical', () {
      for (final String q in <String>[
        'What is wrong with this function?',
        'Can you optimise this query?',
        'Why does this test fail?',
        'Talk me through the stack trace',
        'What would you change about this implementation?',
        'Explain this algorithm to me',
      ]) {
        expect(HudController.looksLikeScreenQuestion(q), isTrue, reason: q);
      }
    });

    test('catches imperatives aimed at existing code', () {
      for (final String q in <String>[
        'Fix this for me',
        'Go ahead and refactor that',
        'Debug the issue please',
        "What's wrong with it?",
      ]) {
        expect(HudController.looksLikeScreenQuestion(q), isTrue, reason: q);
      }
    });

    test('leaves self-contained questions alone', () {
      // These are answerable from the words alone. Capturing a frame would
      // spend a request and a second of latency for nothing.
      for (final String q in <String>[
        'Implement a queue using two stacks',
        'What is the time complexity of quicksort?',
        'How would you scale a chat service to ten million users?',
        'Explain the CAP theorem',
        'Tell me about yourself',
        'What is your biggest weakness?',
      ]) {
        expect(HudController.looksLikeScreenQuestion(q), isFalse, reason: q);
      }
    });

    test('ignores empty input', () {
      expect(HudController.looksLikeScreenQuestion('   '), isFalse);
    });
  });

  group('routeFor', () {
    test('sends screen-referential questions to the solver', () {
      expect(route('What is wrong with this function?'), AssistRoute.screen);
      expect(route('Why does this test fail?'), AssistRoute.screen);
    });

    test('sends questions about the candidate to their profile', () {
      expect(route('Tell me about yourself'), AssistRoute.profile);
      expect(route('Describe a time you failed'), AssistRoute.profile);
      expect(route('What are your salary expectations?'), AssistRoute.profile);
    });

    test('sends everything else to the wingman', () {
      expect(route('What is the CAP theorem?'), AssistRoute.wingman);
      expect(
        route('How would you design a rate limiter?'),
        AssistRoute.wingman,
      );
    });

    test('screen beats profile when the question points at the screen', () {
      // "you" plus "built" would otherwise read as a profile question, but the
      // demonstrative names a resource only the solver can see.
      expect(
        route('Can you explain this code you built here?'),
        AssistRoute.screen,
      );
    });

    test('falls back to the wingman when the profile is empty', () {
      expect(
        route('Tell me about yourself', profileReady: false),
        AssistRoute.wingman,
      );
    });

    test('falls back to the wingman when auto-capture is off', () {
      expect(
        route('What is wrong with this function?', screenEnabled: false),
        AssistRoute.wingman,
      );
    });

    test('a screen question with auto-capture off still reaches the profile '
        'if it is really about the candidate', () {
      expect(
        route(
          'Describe a time you fixed this kind of bug',
          screenEnabled: false,
        ),
        AssistRoute.profile,
      );
    });
  });
}
