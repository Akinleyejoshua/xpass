import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/assist_models.dart';
import '../models/profile_models.dart';

/// Pulls a profile straight from a portfolio site's JSON API.
///
/// Built against the shape joshuapro.netlify.app serves:
///   GET /api/about       -> `{ bio: "<html>", socialLinks: [...] }`
///   GET /api/experience  -> [ { role, company, startDate, endDate, isCurrent,
///                               description: [...] } ]
///   GET /api/projects    -> [ { title, description, category, technologies,
///                               githubUrl, liveUrl, blogUrl, featured } ]
///
/// Every endpoint is optional: whatever responds gets imported, and the rest is
/// skipped, so a partially-available site still refreshes what it can.
class PortfolioImporter {
  PortfolioImporter({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const String defaultBaseUrl = 'https://joshuapro.netlify.app';
  static const Duration _timeout = Duration(seconds: 20);

  /// Fetches and merges into [existing], preserving the user's hand-written
  /// recruiter answers and identity fields.
  Future<UserProfile> importFrom(
    String baseUrl, {
    UserProfile existing = const UserProfile(),
  }) async {
    final String root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) {
      throw const AiServiceException(
        'Set a portfolio URL first.',
        provider: 'Portfolio import',
      );
    }

    final http.Client client = _clientFactory();
    try {
      final List<Object?> results = await Future.wait(<Future<Object?>>[
        _getJson(client, '$root/api/about'),
        _getJson(client, '$root/api/experience'),
        _getJson(client, '$root/api/projects'),
      ]);

      final Object? about = results[0];
      final Object? experience = results[1];
      final Object? projects = results[2];

      if (about == null && experience == null && projects == null) {
        throw AiServiceException(
          'No profile endpoints responded at $root/api/…',
          provider: 'Portfolio import',
        );
      }

      final List<ProfileEntry> entries = <ProfileEntry>[
        ..._experienceEntries(experience),
        ..._projectEntries(projects),
        ..._skillEntries(projects),
        ..._linkEntry(about),
      ];

      return existing.copyWith(
        summary: _bioSummary(about) ?? existing.summary,
        yearsExperience:
            _yearsExperience(experience) ?? existing.yearsExperience,
        entries: <ProfileEntry>[
          ...entries,
          // Hand-written recruiter answers are the user's own voice; an import
          // must never clobber them.
          ...existing.entries.where(
            (ProfileEntry e) => e.kind == ProfileEntryKind.question,
          ),
        ],
      );
    } finally {
      client.close();
    }
  }

  Future<Object?> _getJson(http.Client client, String url) async {
    try {
      final http.Response response = await client
          .get(Uri.parse(url))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      // A Next.js site answers an unknown /api route with its 404 HTML page.
      final String body = response.body.trimLeft();
      if (!body.startsWith('{') && !body.startsWith('[')) return null;

      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------- about

  String? _bioSummary(Object? about) {
    if (about is! Map<String, Object?>) return null;
    final Object? bio = about['bio'];
    if (bio is! String) return null;
    final String text = stripHtml(bio);
    return text.isEmpty ? null : text;
  }

  List<ProfileEntry> _linkEntry(Object? about) {
    if (about is! Map<String, Object?>) return const <ProfileEntry>[];
    final Object? links = about['socialLinks'];
    if (links is! List) return const <ProfileEntry>[];

    final List<String> bullets = <String>[];
    for (final Object? link in links) {
      if (link is! Map<String, Object?>) continue;
      final String platform = (link['platform'] as String? ?? '').trim();
      final String url = (link['url'] as String? ?? '').trim();
      if (url.isEmpty) continue;
      bullets.add(platform.isEmpty ? url : '$platform: $url');
    }
    if (bullets.isEmpty) return const <ProfileEntry>[];

    return <ProfileEntry>[
      ProfileEntry(
        id: 'imported-links',
        kind: ProfileEntryKind.note,
        title: 'Profiles and links',
        bullets: bullets,
        tags: const <String>['github', 'linkedin', 'portfolio', 'contact'],
      ),
    ];
  }

  // -------------------------------------------------------------- experience

  List<ProfileEntry> _experienceEntries(Object? experience) {
    if (experience is! List) return const <ProfileEntry>[];

    final List<ProfileEntry> entries = <ProfileEntry>[];
    for (final Object? raw in experience) {
      if (raw is! Map<String, Object?>) continue;

      final String role = (raw['role'] as String? ?? '').trim();
      final String company = (raw['company'] as String? ?? '').trim();
      if (role.isEmpty && company.isEmpty) continue;

      final List<String> bullets =
          (raw['description'] as List<Object?>? ?? <Object?>[])
              .whereType<String>()
              .map((String b) => stripHtml(b))
              .where((String b) => b.isNotEmpty)
              .toList();

      entries.add(
        ProfileEntry(
          id: 'exp-${raw['_id'] ?? entries.length}',
          kind: ProfileEntryKind.experience,
          title: role.isEmpty ? company : role,
          organization: company,
          period: _formatPeriod(
            raw['startDate'],
            raw['endDate'],
            raw['isCurrent'] == true,
          ),
          bullets: bullets,
          tags: _tagsFrom('$role $company ${bullets.join(' ')}'),
        ),
      );
    }

    // Most recent first: that is the order an interviewer asks about.
    entries.sort(
      (ProfileEntry a, ProfileEntry b) => b.period.compareTo(a.period),
    );
    return entries;
  }

  String _formatPeriod(Object? start, Object? end, bool isCurrent) {
    final String? from = _year(start);
    final String? to = isCurrent ? 'present' : _year(end);
    if (from == null && to == null) return '';
    if (from == null) return to!;
    if (to == null) return from;
    return '$from – $to';
  }

  String? _year(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed?.year.toString();
  }

  String? _yearsExperience(Object? experience) {
    if (experience is! List || experience.isEmpty) return null;

    int? earliest;
    for (final Object? raw in experience) {
      if (raw is! Map<String, Object?>) continue;
      final DateTime? start = DateTime.tryParse(
        raw['startDate'] as String? ?? '',
      );
      if (start == null) continue;
      if (earliest == null || start.year < earliest) earliest = start.year;
    }
    if (earliest == null) return null;

    final int years = DateTime.now().year - earliest;
    if (years <= 0) return null;
    return '$years+ years (since $earliest)';
  }

  // ----------------------------------------------------------------- projects

  List<ProfileEntry> _projectEntries(Object? projects) {
    if (projects is! List) return const <ProfileEntry>[];

    final List<ProfileEntry> entries = <ProfileEntry>[];
    for (final Object? raw in projects) {
      if (raw is! Map<String, Object?>) continue;
      if (raw['isVisible'] == false) continue;

      final String title = (raw['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;

      final List<String> technologies =
          (raw['technologies'] as List<Object?>? ?? <Object?>[])
              .whereType<String>()
              .map((String t) => t.trim())
              .where((String t) => t.isNotEmpty)
              .toList();

      final List<String> links = <String>[
        for (final String key in <String>['githubUrl', 'liveUrl', 'blogUrl'])
          if ((raw[key] as String? ?? '').trim().isNotEmpty)
            '${_linkLabel(key)}: ${(raw[key]! as String).trim()}',
      ];

      entries.add(
        ProfileEntry(
          id: 'proj-${raw['_id'] ?? entries.length}',
          kind: ProfileEntryKind.project,
          title: title,
          organization: raw['featured'] == true ? 'Featured project' : '',
          summary: stripHtml(raw['description'] as String? ?? ''),
          bullets: <String>[
            if (technologies.isNotEmpty) 'Stack: ${technologies.join(', ')}',
            ...links,
          ],
          tags: <String>[
            ...technologies.map((String t) => t.toLowerCase()),
            if ((raw['category'] as String? ?? '').isNotEmpty)
              (raw['category']! as String).toLowerCase(),
          ],
        ),
      );
    }
    return entries;
  }

  String _linkLabel(String key) => switch (key) {
    'githubUrl' => 'Source',
    'liveUrl' => 'Live',
    _ => 'Write-up',
  };

  /// Rolls every project's tech list into one skills entry, ordered by how
  /// often the technology actually appears in shipped work — which is the
  /// honest answer to "what are you strongest in".
  List<ProfileEntry> _skillEntries(Object? projects) {
    if (projects is! List) return const <ProfileEntry>[];

    final Map<String, int> counts = <String, int>{};
    for (final Object? raw in projects) {
      if (raw is! Map<String, Object?>) continue;
      // Hidden projects are excluded from the project list, so they must not
      // inflate the skill ranking either.
      if (raw['isVisible'] == false) continue;
      for (final Object? tech
          in raw['technologies'] as List<Object?>? ?? <Object?>[]) {
        if (tech is! String) continue;
        final String name = tech.trim();
        if (name.isEmpty) continue;
        final String canonical = _canonicalTech(name);
        counts[canonical] = (counts[canonical] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const <ProfileEntry>[];

    final List<MapEntry<String, int>> ranked = counts.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    return <ProfileEntry>[
      ProfileEntry(
        id: 'imported-skills',
        kind: ProfileEntryKind.skill,
        title: 'Technical skills',
        summary: 'Ranked by how many shipped projects each one appears in.',
        bullets: ranked
            .take(24)
            .map(
              (MapEntry<String, int> e) =>
                  '${e.key} — ${e.value} project${e.value == 1 ? '' : 's'}',
            )
            .toList(),
        tags: ranked
            .map((MapEntry<String, int> e) => e.key.toLowerCase())
            .toList(),
      ),
    ];
  }

  /// Folds the spelling variants a portfolio accumulates over the years.
  static String _canonicalTech(String raw) {
    final String lower = raw.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');
    return switch (lower) {
      'nextjs' || 'next' => 'Next.js',
      'nodejs' || 'node' => 'Node.js',
      'reactjs' || 'react' => 'React',
      'typescript' || 'ts' => 'TypeScript',
      'javascript' || 'js' => 'JavaScript',
      'tensorflowjs' => 'TensorFlow.js',
      'tensorflow' => 'TensorFlow',
      'pytorch' => 'PyTorch',
      'mongodb' || 'mongo' => 'MongoDB',
      'powerbi' => 'Power BI',
      'css' || 'css3' => 'CSS',
      'html' || 'html5' => 'HTML',
      'socketio' => 'Socket.io',
      'ethersjs' => 'ethers.js',
      'hardhartjs' || 'hardhatjs' || 'hardhat' => 'Hardhat',
      _ => raw.trim(),
    };
  }

  static List<String> _tagsFrom(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9+#.]+'))
        .where((String t) => t.length > 3)
        .toSet()
        .take(12)
        .toList();
  }

  /// Strips the rich-text HTML a CMS bio field carries.
  static String stripHtml(String html) {
    // Block-level tags end a line; inline tags (<b>, <span>, <a>) are removed
    // outright, because they do not create a word boundary — replacing them
    // with a space yields "Joshua , a developer".
    String text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|h[1-6]|tr|blockquote)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');

    const Map<String, String> entities = <String, String>{
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&mdash;': '—',
      '&ndash;': '–',
      '&rsquo;': '’',
      '&lsquo;': '‘',
      '&hellip;': '…',
    };
    entities.forEach((String from, String to) {
      text = text.replaceAll(from, to);
    });
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (Match m) => String.fromCharCode(int.parse(m.group(1)!)),
    );

    // Normalise per line so a stripped block tag cannot leave the next line
    // indented by the space its opening tag used to occupy.
    return text
        .split('\n')
        .map((String line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((String line) => line.isNotEmpty)
        .join('\n');
  }
}
