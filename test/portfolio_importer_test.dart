import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xpass/core/models/assist_models.dart';
import 'package:xpass/core/models/profile_models.dart';
import 'package:xpass/core/services/portfolio_importer.dart';

const String kBio =
    '<div><span>I’m <b>Joshua</b>, a multidisciplinary '
    'technologist &amp; builder.</span></div>';

final List<Map<String, Object?>> kExperience = <Map<String, Object?>>[
  <String, Object?>{
    '_id': 'x1',
    'role': 'Full Stack Developer',
    'company': 'Corvendra',
    'startDate': '2026-01-07T00:00:00.000Z',
    'endDate': null,
    'isCurrent': true,
    'description': <String>['Front-End Engineering', 'Back-End Development'],
  },
  <String, Object?>{
    '_id': 'x2',
    'role': 'Web Developer',
    'company': 'C.A.C',
    'startDate': '2020-01-01T00:00:00.000Z',
    'endDate': '2021-12-31T00:00:00.000Z',
    'isCurrent': false,
    'description': <String>['Designed responsive web applications'],
  },
];

final List<Map<String, Object?>> kProjects = <Map<String, Object?>>[
  <String, Object?>{
    '_id': 'p1',
    'title': 'xMachine',
    'description': '<p>Browser-based deep learning platform.</p>',
    'category': 'ml',
    'technologies': <String>['TensorFlow.js', 'Next.js', 'React'],
    'githubUrl': 'https://github.com/x/xmachine',
    'liveUrl': 'https://xmachinepro.netlify.app/',
    'featured': true,
    'isVisible': true,
  },
  <String, Object?>{
    '_id': 'p2',
    'title': 'Hidden project',
    'description': 'Should not be imported.',
    'technologies': <String>['Nextjs'],
    'isVisible': false,
  },
  <String, Object?>{
    '_id': 'p3',
    'title': 'Ultra Share Pro',
    'description': 'WebRTC file sharing.',
    'category': 'web',
    'technologies': <String>['nextjs', 'WebRTC'],
  },
];

PortfolioImporter importerServing(Map<String, Object?> routes) {
  return PortfolioImporter(
    clientFactory: () => MockClient((http.Request request) async {
      final String path = request.url.path;
      for (final MapEntry<String, Object?> route in routes.entries) {
        if (path.endsWith(route.key)) {
          return http.Response(
            jsonEncode(route.value),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
      }
      // A Next.js site answers an unknown /api route with its 404 HTML page.
      return http.Response('<!DOCTYPE html><html>404</html>', 404);
    }),
  );
}

void main() {
  group('stripHtml', () {
    test('removes tags and decodes entities', () {
      expect(
        PortfolioImporter.stripHtml(kBio),
        'I’m Joshua, a multidisciplinary technologist & builder.',
      );
    });

    test('turns block tags into line breaks', () {
      expect(PortfolioImporter.stripHtml('<p>one</p><p>two</p>'), 'one\ntwo');
    });

    test('decodes numeric entities', () {
      expect(PortfolioImporter.stripHtml('caf&#233;'), 'café');
    });
  });

  group('importFrom', () {
    late PortfolioImporter importer;

    setUp(() {
      importer = importerServing(<String, Object?>{
        '/api/about': <String, Object?>{
          'bio': kBio,
          'socialLinks': <Object?>[
            <String, Object?>{
              'platform': 'github',
              'url': 'http://github.com/Akinleyejoshua',
            },
          ],
        },
        '/api/experience': kExperience,
        '/api/projects': kProjects,
      });
    });

    test('imports experience with a readable period', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test',
      );

      final ProfileEntry current = profile.entries.firstWhere(
        (ProfileEntry e) => e.organization == 'Corvendra',
      );
      expect(current.kind, ProfileEntryKind.experience);
      expect(current.period, '2026 – present');
      expect(current.bullets, hasLength(2));

      final ProfileEntry past = profile.entries.firstWhere(
        (ProfileEntry e) => e.organization == 'C.A.C',
      );
      expect(past.period, '2020 – 2021');
    });

    test('derives years of experience from the earliest role', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test',
      );
      expect(profile.yearsExperience, contains('since 2020'));
    });

    test('strips HTML from the bio into the summary', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test',
      );
      expect(profile.summary, startsWith('I’m Joshua'));
      expect(profile.summary, isNot(contains('<')));
    });

    test('skips projects marked not visible', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test',
      );

      expect(
        profile.entries.any((ProfileEntry e) => e.title == 'Hidden project'),
        isFalse,
      );
      expect(
        profile.entries.any((ProfileEntry e) => e.title == 'xMachine'),
        isTrue,
      );
    });

    test('records project links and stack as talking points', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test',
      );

      final ProfileEntry project = profile.entries.firstWhere(
        (ProfileEntry e) => e.title == 'xMachine',
      );
      expect(project.bullets.first, startsWith('Stack:'));
      expect(
        project.bullets.any((String b) => b.startsWith('Source:')),
        isTrue,
      );
      expect(project.bullets.any((String b) => b.startsWith('Live:')), isTrue);
      expect(project.tags, contains('ml'));
    });

    test('folds tech spelling variants when ranking skills', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test',
      );

      final ProfileEntry skills = profile.entries.firstWhere(
        (ProfileEntry e) => e.kind == ProfileEntryKind.skill,
      );

      // "Next.js" and "nextjs" are the same skill across two projects.
      expect(
        skills.bullets.any((String b) => b.startsWith('Next.js — 2 projects')),
        isTrue,
        reason: skills.bullets.join(' | '),
      );
    });

    test('never overwrites prepared recruiter answers', () async {
      const UserProfile existing = UserProfile(
        entries: <ProfileEntry>[
          ProfileEntry(
            id: 'recruiter-0',
            kind: ProfileEntryKind.question,
            title: 'Tell me about yourself',
            summary: 'My own carefully written answer.',
          ),
        ],
      );

      final UserProfile profile = await importer.importFrom(
        'https://example.test',
        existing: existing,
      );

      expect(
        profile.entries.any(
          (ProfileEntry e) => e.summary == 'My own carefully written answer.',
        ),
        isTrue,
      );
    });

    test('imports whatever responds when an endpoint is missing', () async {
      final PortfolioImporter partial = importerServing(<String, Object?>{
        '/api/experience': kExperience,
      });

      final UserProfile profile = await partial.importFrom(
        'https://example.test',
      );

      expect(
        profile.entries.any((ProfileEntry e) => e.organization == 'Corvendra'),
        isTrue,
      );
      expect(profile.summary, isEmpty, reason: '/api/about returned 404 HTML');
    });

    test('throws when nothing responds at all', () async {
      final PortfolioImporter dead = importerServing(<String, Object?>{});

      expect(
        () => dead.importFrom('https://example.test'),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('rejects an empty URL without making a request', () {
      expect(
        () => importer.importFrom('   '),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('tolerates a trailing slash on the base URL', () async {
      final UserProfile profile = await importer.importFrom(
        'https://example.test/',
      );
      expect(profile.entries, isNotEmpty);
    });
  });
}
