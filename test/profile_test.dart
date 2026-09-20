import 'package:flutter_test/flutter_test.dart';
import 'package:xpass/core/models/profile_models.dart';
import 'package:xpass/core/services/profile_service.dart';

UserProfile buildProfile() => const UserProfile(
  name: 'Joshua Akinleye',
  headline: 'Full Stack Developer · AI/ML',
  summary: 'I build data-heavy products end to end.',
  yearsExperience: '6+ years',
  entries: <ProfileEntry>[
    ProfileEntry(
      id: 'e1',
      kind: ProfileEntryKind.experience,
      title: 'Conversational A.I Scientist',
      organization: 'Smartecniqs',
      period: '2022 – 2023',
      bullets: <String>[
        'Built and trained machine learning models',
        'Implemented NLP solutions for business applications',
      ],
      tags: <String>['nlp', 'machine', 'learning'],
    ),
    ProfileEntry(
      id: 'e2',
      kind: ProfileEntryKind.project,
      title: 'xMachine',
      summary: 'Browser-based deep learning and inference platform.',
      bullets: <String>['Stack: TensorFlow.js, WebGPU, Next.js'],
      tags: <String>['tensorflow.js', 'webgpu', 'next.js', 'ml'],
    ),
    ProfileEntry(
      id: 'e3',
      kind: ProfileEntryKind.project,
      title: 'Ultra Share Pro',
      summary: 'Peer-to-peer file sharing over WebRTC.',
      tags: <String>['webrtc', 'socket.io', 'web'],
    ),
    ProfileEntry(
      id: 'q1',
      kind: ProfileEntryKind.question,
      title: 'What is your biggest weakness?',
      summary: 'I over-invest in tooling early. I now timebox it.',
      tags: <String>['weakness', 'improve'],
    ),
  ],
);

void main() {
  group('retrieval', () {
    final ProfileService service = ProfileService.inMemory(buildProfile());

    test('ranks the entry that actually matches first', () {
      final List<ScoredEntry> hits = service.retrieve('tell me about webrtc');

      expect(hits, isNotEmpty);
      expect(hits.first.entry.title, 'Ultra Share Pro');
    });

    test('matches on tags as well as titles', () {
      final List<ScoredEntry> hits = service.retrieve('do you know webgpu?');
      expect(hits.first.entry.title, 'xMachine');
    });

    test('prefers a prepared answer for the question it answers', () {
      final List<ScoredEntry> hits = service.retrieve(
        'what is your biggest weakness?',
      );
      expect(hits.first.entry.kind, ProfileEntryKind.question);
    });

    test('returns nothing for a query with no overlap', () {
      expect(service.retrieve('kubernetes helm istio'), isEmpty);
    });

    test('respects the result limit', () {
      final List<ScoredEntry> hits = service.retrieve(
        'machine learning webrtc platform',
        limit: 2,
      );
      expect(hits.length, lessThanOrEqualTo(2));
    });
  });

  group('contextFor', () {
    final ProfileService service = ProfileService.inMemory(buildProfile());

    test('always leads with identity', () {
      final String context = service.contextFor('tell me about webrtc');
      expect(context, contains('Joshua Akinleye'));
      expect(context, contains('6+ years'));
      expect(context, contains('Ultra Share Pro'));
    });

    test('falls back to strongest material when nothing matches', () {
      final String context = service.contextFor('so, tell me more');
      expect(context, contains('Joshua Akinleye'));
      // Experience and project entries are the fallback.
      expect(
        context.contains('Smartecniqs') || context.contains('xMachine'),
        isTrue,
      );
    });

    test('is empty for an empty profile', () {
      final ProfileService empty = ProfileService.inMemory(const UserProfile());
      expect(empty.contextFor('anything'), isEmpty);
    });
  });

  group('looksLikeProfileQuestion', () {
    test('recognises classic recruiter openers', () {
      for (final String question in <String>[
        'Tell me about yourself',
        'Walk me through your experience',
        'Describe a time you failed',
        'What are your salary expectations?',
        'Why are you leaving your current role?',
        'Where do you see yourself in five years?',
        'Have you ever shipped something at scale?',
      ]) {
        expect(
          ProfileService.looksLikeProfileQuestion(question),
          isTrue,
          reason: question,
        );
      }
    });

    test('recognises second-person questions about past work', () {
      expect(
        ProfileService.looksLikeProfileQuestion(
          'What was your role on that project?',
        ),
        isTrue,
      );
    });

    test('leaves pure computer-science questions alone', () {
      for (final String question in <String>[
        'How does a red-black tree stay balanced?',
        'Invert a binary tree',
        'What is the time complexity of quicksort?',
        'Explain CAP theorem',
      ]) {
        expect(
          ProfileService.looksLikeProfileQuestion(question),
          isFalse,
          reason: question,
        );
      }
    });

    test('ignores empty input', () {
      expect(ProfileService.looksLikeProfileQuestion('   '), isFalse);
    });
  });

  group('parseMarkdownResume', () {
    test('turns headings into entries and bullets into talking points', () {
      const String resume = '''
## Experience
### Senior Engineer, Acme
- Cut p99 latency from 900ms to 120ms
- Led the migration to Postgres

## Projects
Built an internal analytics platform.
''';
      final UserProfile parsed = ProfileService.parseMarkdownResume(resume);

      final ProfileEntry experience = parsed.entries.firstWhere(
        (ProfileEntry e) => e.title.contains('Senior Engineer'),
      );
      expect(experience.kind, ProfileEntryKind.experience);
      expect(experience.bullets, hasLength(2));
      expect(experience.bullets.first, contains('p99'));

      expect(
        parsed.entries.any(
          (ProfileEntry e) => e.kind == ProfileEntryKind.project,
        ),
        isTrue,
      );
    });

    test('preserves prepared answers already written', () {
      final UserProfile base = buildProfile();
      final UserProfile merged = ProfileService.parseMarkdownResume(
        '## Skills\n- Dart',
        base: base,
      );

      expect(
        merged.entries.any(
          (ProfileEntry e) =>
              e.kind == ProfileEntryKind.question &&
              e.summary.contains('over-invest in tooling'),
        ),
        isTrue,
      );
    });
  });
}
