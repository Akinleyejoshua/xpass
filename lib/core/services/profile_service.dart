import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/profile_models.dart';

/// One entry plus how well it matched a query.
typedef ScoredEntry = ({ProfileEntry entry, double score});

/// Pre-tokenised entry, so retrieval never re-splits the whole profile.
class _IndexedEntry {
  _IndexedEntry(this.entry)
    : titleTokens = _tokenize(entry.title),
      tagTokens = _tokenize(entry.tags.join(' ')),
      summaryTokens = _tokenize(entry.summary),
      bulletTokens = _tokenize(entry.bullets.join(' ')),
      orgTokens = _tokenize(entry.organization) {
    allTokens = <String>{
      ...titleTokens,
      ...tagTokens,
      ...summaryTokens,
      ...bulletTokens,
      ...orgTokens,
    };
  }

  final ProfileEntry entry;
  final Set<String> titleTokens;
  final Set<String> tagTokens;
  final Set<String> summaryTokens;
  final Set<String> bulletTokens;
  final Set<String> orgTokens;
  late final Set<String> allTokens;
}

/// Loads, stores and searches the user's own background.
///
/// Retrieval is a small local BM25-flavoured scorer rather than embeddings: a
/// profile is tens of entries, not millions, and a keyword pass costs
/// microseconds with no extra API round trip in the latency budget.
class ProfileService extends ChangeNotifier {
  ProfileService._(this._file, UserProfile profile) {
    _setProfile(profile);
  }

  /// A service backed by a scratch file, for tests and previews.
  ///
  /// Retrieval and classification are pure functions of the profile, so this
  /// exercises them without touching the user's real Application Support data.
  @visibleForTesting
  factory ProfileService.inMemory(UserProfile profile) => ProfileService._(
    File(
      '${Directory.systemTemp.path}/xpass-profile-'
      '${DateTime.now().microsecondsSinceEpoch}.json',
    ),
    profile,
  );

  final File _file;

  UserProfile _profile = const UserProfile();
  List<_IndexedEntry> _index = <_IndexedEntry>[];

  UserProfile get profile => _profile;

  String get storagePath => _file.path;

  /// How many non-empty entries back the assistant's answers.
  int get factCount =>
      _profile.entries.where((ProfileEntry e) => !e.isEmpty).length;

  // --------------------------------------------------------------- load/save

  static Future<ProfileService> load() async {
    final File file = File(_defaultPath());
    UserProfile profile = const UserProfile();

    try {
      if (file.existsSync()) {
        final Object? decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) {
          profile = UserProfile.fromJson(decoded);
        }
      }
    } on IOException {
      // Unreadable profile: start empty rather than blocking launch.
    } on FormatException {
      // Corrupt profile: same.
    }

    // Nothing on disk: fall back to the profile bundled with the build, so a
    // fresh install can answer questions about the user immediately.
    if (profile.isEmpty) {
      profile = await _loadSeed() ?? profile;
    }

    // A brand-new profile still gets the recruiter question prompts so the
    // Settings screen has something to fill in.
    if (profile.entries.isEmpty) {
      profile = profile.copyWith(entries: RecruiterQuestions.seedEntries());
    }

    return ProfileService._(file, profile);
  }

  /// Reads `assets/profile/seed_profile.json`, if the build ships one.
  static Future<UserProfile?> _loadSeed() async {
    try {
      final String raw = await rootBundle.loadString(
        'assets/profile/seed_profile.json',
      );
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return UserProfile.fromJson(decoded);
    } catch (_) {
      // No seed bundled, or it is malformed — neither is fatal.
    }
    return null;
  }

  static String _defaultPath() {
    final String home = Platform.environment['HOME'] ?? '.';
    return '$home/Library/Application Support/com.xpass.app/profile.json';
  }

  Future<void> save(UserProfile profile) async {
    _setProfile(profile);
    notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(profile.toJson()),
      );
    } on IOException catch (error) {
      debugPrint('xpass: could not persist profile — $error');
    }
  }

  Future<void> mutate(UserProfile Function(UserProfile current) transform) =>
      save(transform(_profile));

  void _setProfile(UserProfile profile) {
    _profile = profile;
    _index = profile.entries
        .where((ProfileEntry e) => !e.isEmpty)
        .map(_IndexedEntry.new)
        .toList();
  }

  // --------------------------------------------------------------- retrieval

  /// Best-matching entries for a question, most relevant first.
  List<ScoredEntry> retrieve(String query, {int limit = 4}) {
    final Set<String> tokens = _tokenize(query);
    if (tokens.isEmpty || _index.isEmpty) return const <ScoredEntry>[];

    final bool behavioural = looksLikeProfileQuestion(query);
    final int total = _index.length;

    // Document frequency over the whole profile, for IDF.
    final Map<String, int> documentFrequency = <String, int>{};
    for (final _IndexedEntry indexed in _index) {
      for (final String token in tokens) {
        if (indexed.allTokens.contains(token)) {
          documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
        }
      }
    }

    final List<ScoredEntry> scored = <ScoredEntry>[];
    for (final _IndexedEntry indexed in _index) {
      double score = 0;
      for (final String token in tokens) {
        final int df = documentFrequency[token] ?? 0;
        if (df == 0) continue;
        // Rare terms carry the signal; "engineer" in every entry carries none.
        final double idf = math.log(1 + total / df);

        if (indexed.titleTokens.contains(token)) score += 3.0 * idf;
        if (indexed.tagTokens.contains(token)) score += 2.6 * idf;
        if (indexed.summaryTokens.contains(token)) score += 1.4 * idf;
        if (indexed.bulletTokens.contains(token)) score += 1.0 * idf;
        if (indexed.orgTokens.contains(token)) score += 1.2 * idf;
      }

      if (score <= 0) continue;

      // A pre-written answer to this exact question should win outright.
      if (behavioural && indexed.entry.kind == ProfileEntryKind.question) {
        score *= 1.8;
      }
      scored.add((entry: indexed.entry, score: score));
    }

    scored.sort((ScoredEntry a, ScoredEntry b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  /// The profile context block injected into a prompt.
  ///
  /// Always leads with identity so the model knows whose voice to write in,
  /// then adds the highest-scoring facts. Returns an empty string when the user
  /// has not filled anything in, so callers can skip grounding entirely.
  String contextFor(String query, {int limit = 4}) {
    if (_profile.isEmpty) return '';

    final StringBuffer buffer = StringBuffer();
    final String identity = _profile.identityBlock;
    if (identity.isNotEmpty) {
      buffer
        ..writeln(identity)
        ..writeln();
    }

    final List<ScoredEntry> hits = retrieve(query, limit: limit);
    if (hits.isEmpty) {
      // No keyword overlap — fall back to the user's strongest material so a
      // vague question like "so, tell me more" still gets grounded.
      final List<ProfileEntry> fallback = _index
          .map((_IndexedEntry i) => i.entry)
          .where(
            (ProfileEntry e) =>
                e.kind == ProfileEntryKind.experience ||
                e.kind == ProfileEntryKind.project,
          )
          .take(2)
          .toList();
      for (final ProfileEntry entry in fallback) {
        buffer
          ..writeln(entry.toPromptBlock())
          ..writeln();
      }
      return buffer.toString().trimRight();
    }

    for (final ScoredEntry hit in hits) {
      buffer
        ..writeln(hit.entry.toPromptBlock())
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  // ------------------------------------------------------------- classification

  /// True when a question is about the user rather than about computer science.
  ///
  /// Kept deliberately broad on second-person phrasing: a false positive just
  /// adds the user's background to the prompt, while a false negative loses the
  /// grounding that makes the answer theirs.
  static bool looksLikeProfileQuestion(String text) {
    final String lower = text.toLowerCase().trim();
    if (lower.isEmpty) return false;

    const List<String> strongCues = <String>[
      'tell me about yourself',
      'walk me through your',
      'walk us through your',
      'about your background',
      'your experience',
      'your background',
      'your resume',
      'your cv',
      'your current role',
      'your last role',
      'your previous',
      'your strengths',
      'your weakness',
      'biggest weakness',
      'proudest',
      'describe a time',
      'tell me about a time',
      'give me an example of a time',
      'have you ever',
      'why are you leaving',
      'why do you want',
      'why this company',
      'why should we hire',
      'salary expectation',
      'compensation expectation',
      'notice period',
      'where do you see yourself',
      'your goals',
      'your career',
      'worked with',
      'have you used',
      'are you familiar with',
      'rate yourself',
      'years of experience',
      'do you have experience',
    ];

    if (strongCues.any(lower.contains)) return true;

    // "What did you do at <company>", "how did you handle ..."
    final bool secondPerson = RegExp(r'\b(you|your|yours)\b').hasMatch(lower);
    final bool pastExperienceNoun = RegExp(
      r'\b(project|role|job|team|company|stack|responsib|achiev|built|shipped|led|managed|handled)\w*\b',
    ).hasMatch(lower);

    return secondPerson && pastExperienceNoun;
  }

  // ------------------------------------------------------------------ import

  /// Parses a pasted résumé written in markdown into entries.
  ///
  /// Headings become entries, bullets beneath them become impact bullets. This
  /// is the offline path; [structuredImportPrompt] hands the same text to a
  /// model when the user wants a better job of it.
  static UserProfile parseMarkdownResume(String markdown, {UserProfile? base}) {
    final List<ProfileEntry> entries = <ProfileEntry>[];
    final List<String> lines = markdown.split('\n');

    String currentHeading = '';
    ProfileEntryKind currentKind = ProfileEntryKind.note;
    // Résumés are written as "## Experience" followed by "### Role, Company".
    // The subheadings inherit their section's kind, since only the section
    // heading names it.
    ProfileEntryKind sectionKind = ProfileEntryKind.note;
    int sectionLevel = 0;
    final List<String> bullets = <String>[];
    final StringBuffer prose = StringBuffer();
    int counter = 0;

    void flush() {
      if (currentHeading.trim().isEmpty &&
          bullets.isEmpty &&
          prose.toString().trim().isEmpty) {
        return;
      }
      entries.add(
        ProfileEntry(
          id: 'import-${DateTime.now().microsecondsSinceEpoch}-${counter++}',
          kind: currentKind,
          title: currentHeading.trim().isEmpty
              ? 'Background'
              : currentHeading.trim(),
          summary: prose.toString().trim(),
          bullets: List<String>.from(bullets),
        ),
      );
      bullets.clear();
      prose.clear();
    }

    for (final String raw in lines) {
      final String line = raw.trimRight();
      final String trimmed = line.trim();

      if (trimmed.startsWith('#')) {
        flush();
        final int level = RegExp(r'^#+').firstMatch(trimmed)!.group(0)!.length;
        currentHeading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');

        final ProfileEntryKind? named = _kindForHeading(currentHeading);
        if (named != null) {
          currentKind = named;
          sectionKind = named;
          sectionLevel = level;
        } else {
          currentKind = level > sectionLevel
              ? sectionKind
              : ProfileEntryKind.note;
        }
        continue;
      }

      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('• ')) {
        bullets.add(trimmed.substring(2).trim());
        continue;
      }

      if (trimmed.isNotEmpty) prose.writeln(trimmed);
    }
    flush();

    final UserProfile start = base ?? const UserProfile();
    return start.copyWith(
      entries: <ProfileEntry>[
        ...entries.where((ProfileEntry e) => !e.isEmpty),
        // Keep any recruiter answers the user already wrote.
        ...start.entries.where(
          (ProfileEntry e) => e.kind == ProfileEntryKind.question,
        ),
      ],
    );
  }

  /// Returns null when the heading does not name a section kind, so the caller
  /// can fall back to the enclosing section.
  static ProfileEntryKind? _kindForHeading(String heading) {
    final String lower = heading.toLowerCase();
    if (lower.contains('experience') ||
        lower.contains('employment') ||
        lower.contains('work history')) {
      return ProfileEntryKind.experience;
    }
    if (lower.contains('project')) return ProfileEntryKind.project;
    if (lower.contains('skill') ||
        lower.contains('technolog') ||
        lower.contains('stack')) {
      return ProfileEntryKind.skill;
    }
    if (lower.contains('education') ||
        lower.contains('degree') ||
        lower.contains('certif')) {
      return ProfileEntryKind.education;
    }
    if (lower.contains('achievement') ||
        lower.contains('award') ||
        lower.contains('impact')) {
      return ProfileEntryKind.achievement;
    }
    return null;
  }

  /// Instruction used when the user asks a model to structure their résumé.
  static String structuredImportPrompt(String rawText) =>
      '''
Convert the résumé below into JSON matching exactly this shape:

{
  "name": "", "headline": "", "summary": "", "location": "", "yearsExperience": "",
  "entries": [
    {"kind": "experience|project|skill|achievement|education|note",
     "title": "", "organization": "", "period": "", "summary": "",
     "bullets": ["..."], "tags": ["..."]}
  ]
}

Rules:
- Copy facts verbatim where possible. Never invent a role, date, metric or
  employer that is not in the text.
- "summary" at the top level is a 2-3 sentence first-person positioning
  statement suitable as an answer to "tell me about yourself".
- "tags" are lowercase retrieval keywords: technologies, domains and themes
  ("kubernetes", "leadership", "migration", "latency").
- Output JSON only. No markdown fence, no commentary.

RÉSUMÉ:
$rawText
''';
}

// ---------------------------------------------------------------------------
// Tokenisation
// ---------------------------------------------------------------------------

const Set<String> _stopWords = <String>{
  'the',
  'and',
  'for',
  'you',
  'your',
  'are',
  'was',
  'were',
  'with',
  'that',
  'this',
  'have',
  'has',
  'had',
  'but',
  'not',
  'can',
  'could',
  'would',
  'should',
  'about',
  'from',
  'into',
  'over',
  'under',
  'what',
  'when',
  'where',
  'which',
  'who',
  'how',
  'why',
  'did',
  'does',
  'do',
  'been',
  'being',
  'they',
  'them',
  'their',
  'our',
  'ours',
  'his',
  'her',
  'its',
  'use',
  'used',
  'using',
  'any',
  'all',
  'some',
  'more',
  'most',
  'much',
  'very',
  'just',
  'like',
  'get',
  'got',
  'tell',
  'give',
  'say',
  'said',
  'one',
  'two',
  'also',
  'than',
  'then',
  'there',
  'here',
  'out',
  'off',
  'onto',
  'per',
  'via',
  'within',
  'without',
  'me',
  'my',
};

Set<String> _tokenize(String text) {
  final Iterable<String> raw = text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9+#.]+'))
      .map((String token) => token.replaceAll(RegExp(r'^[.]+|[.]+$'), ''));

  return raw
      .where(
        (String token) =>
            token.length > 2 && !_stopWords.contains(token) ||
            // Keep short but meaningful tech tokens.
            const <String>{
              'go',
              'c',
              'c#',
              'c++',
              'js',
              'ts',
              'ai',
              'ml',
              'qa',
            }.contains(token),
      )
      .toSet();
}
