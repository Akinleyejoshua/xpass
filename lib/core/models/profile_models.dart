/// What kind of thing a profile entry describes.
enum ProfileEntryKind {
  experience('Experience', 'Roles and positions'),
  project('Project', 'Things you built'),
  skill('Skill', 'Technologies and depth'),
  achievement('Achievement', 'Measurable wins'),
  education('Education', 'Degrees and certifications'),
  question('Prepared answer', 'Your answer to a recruiter question'),
  note('Note', 'Anything else worth remembering');

  const ProfileEntryKind(this.label, this.hint);

  final String label;
  final String hint;

  static ProfileEntryKind fromName(String? name) =>
      ProfileEntryKind.values.firstWhere(
        (ProfileEntryKind k) => k.name == name,
        orElse: () => ProfileEntryKind.note,
      );
}

/// One retrievable fact about the user.
class ProfileEntry {
  const ProfileEntry({
    required this.id,
    required this.kind,
    required this.title,
    this.organization = '',
    this.period = '',
    this.summary = '',
    this.bullets = const <String>[],
    this.tags = const <String>[],
  });

  final String id;
  final ProfileEntryKind kind;

  /// Role title, project name, skill name, or the recruiter question itself.
  final String title;
  final String organization;

  /// e.g. "2022 – present".
  final String period;
  final String summary;

  /// Impact bullets — what the user actually says out loud.
  final List<String> bullets;

  /// Retrieval hints: 'kubernetes', 'leadership', 'conflict', 'weakness'.
  final List<String> tags;

  bool get isEmpty =>
      title.trim().isEmpty &&
      summary.trim().isEmpty &&
      bullets.every((String b) => b.trim().isEmpty);

  /// Everything retrieval scores against, lowercased once at construction time
  /// by the caller that needs it.
  String get searchText => <String>[
    title,
    organization,
    summary,
    ...bullets,
    ...tags,
  ].join(' ').toLowerCase();

  /// Rendered for injection into a prompt.
  String toPromptBlock() {
    final StringBuffer buffer = StringBuffer();
    final String heading = <String>[
      title.trim(),
      if (organization.trim().isNotEmpty) '@ ${organization.trim()}',
      if (period.trim().isNotEmpty) '(${period.trim()})',
    ].where((String s) => s.isNotEmpty).join(' ');

    buffer.writeln('[${kind.label}] $heading');
    if (summary.trim().isNotEmpty) buffer.writeln(summary.trim());
    for (final String bullet in bullets) {
      if (bullet.trim().isNotEmpty) buffer.writeln('- ${bullet.trim()}');
    }
    return buffer.toString().trimRight();
  }

  ProfileEntry copyWith({
    ProfileEntryKind? kind,
    String? title,
    String? organization,
    String? period,
    String? summary,
    List<String>? bullets,
    List<String>? tags,
  }) => ProfileEntry(
    id: id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    organization: organization ?? this.organization,
    period: period ?? this.period,
    summary: summary ?? this.summary,
    bullets: bullets ?? this.bullets,
    tags: tags ?? this.tags,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'title': title,
    'organization': organization,
    'period': period,
    'summary': summary,
    'bullets': bullets,
    'tags': tags,
  };

  static ProfileEntry fromJson(Map<String, Object?> json) => ProfileEntry(
    id:
        json['id'] as String? ??
        'entry-${DateTime.now().microsecondsSinceEpoch}',
    kind: ProfileEntryKind.fromName(json['kind'] as String?),
    title: json['title'] as String? ?? '',
    organization: json['organization'] as String? ?? '',
    period: json['period'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    bullets: _stringList(json['bullets']),
    tags: _stringList(json['tags']),
  );

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList();
  }
}

/// The user's whole background, as xpass knows it.
class UserProfile {
  const UserProfile({
    this.name = '',
    this.headline = '',
    this.summary = '',
    this.location = '',
    this.yearsExperience = '',
    this.entries = const <ProfileEntry>[],
  });

  final String name;

  /// e.g. "Senior Backend Engineer · Distributed systems".
  final String headline;

  /// The 30-second "tell me about yourself" answer, in the user's own words.
  final String summary;
  final String location;
  final String yearsExperience;
  final List<ProfileEntry> entries;

  bool get isEmpty =>
      name.trim().isEmpty &&
      headline.trim().isEmpty &&
      summary.trim().isEmpty &&
      entries.where((ProfileEntry e) => !e.isEmpty).isEmpty;

  bool get isConfigured => !isEmpty;

  int get answeredQuestionCount => entries
      .where(
        (ProfileEntry e) => e.kind == ProfileEntryKind.question && !e.isEmpty,
      )
      .length;

  /// The always-included header: who this person is.
  String get identityBlock {
    final StringBuffer buffer = StringBuffer();
    if (name.trim().isNotEmpty) buffer.writeln('Name: ${name.trim()}');
    if (headline.trim().isNotEmpty) {
      buffer.writeln('Current focus: ${headline.trim()}');
    }
    if (yearsExperience.trim().isNotEmpty) {
      buffer.writeln('Experience: ${yearsExperience.trim()}');
    }
    if (location.trim().isNotEmpty) {
      buffer.writeln('Based in: ${location.trim()}');
    }
    if (summary.trim().isNotEmpty) {
      buffer.writeln('Positioning: ${summary.trim()}');
    }
    return buffer.toString().trimRight();
  }

  UserProfile copyWith({
    String? name,
    String? headline,
    String? summary,
    String? location,
    String? yearsExperience,
    List<ProfileEntry>? entries,
  }) => UserProfile(
    name: name ?? this.name,
    headline: headline ?? this.headline,
    summary: summary ?? this.summary,
    location: location ?? this.location,
    yearsExperience: yearsExperience ?? this.yearsExperience,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'name': name,
    'headline': headline,
    'summary': summary,
    'location': location,
    'yearsExperience': yearsExperience,
    'entries': entries.map((ProfileEntry e) => e.toJson()).toList(),
  };

  static UserProfile fromJson(Map<String, Object?> json) => UserProfile(
    name: json['name'] as String? ?? '',
    headline: json['headline'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    location: json['location'] as String? ?? '',
    yearsExperience: json['yearsExperience'] as String? ?? '',
    entries: (json['entries'] as List<Object?>? ?? <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> e) =>
              ProfileEntry.fromJson(e.cast<String, Object?>()),
        )
        .toList(),
  );
}

/// The questions recruiters ask in nearly every screen.
///
/// Seeded as empty [ProfileEntryKind.question] entries so the user can pre-write
/// answers in their own voice. An answered one is retrieved verbatim and beats
/// anything the model would improvise.
abstract final class RecruiterQuestions {
  static const List<({String question, List<String> tags})>
  common = <({String question, List<String> tags})>[
    (
      question: 'Tell me about yourself',
      tags: <String>['intro', 'background', 'yourself', 'walk me through'],
    ),
    (
      question: 'Why are you looking to leave your current role?',
      tags: <String>['leave', 'why', 'motivation', 'current role'],
    ),
    (
      question: 'Why this company?',
      tags: <String>['why us', 'company', 'motivation', 'interest'],
    ),
    (
      question: 'What is the project you are proudest of?',
      tags: <String>['proud', 'project', 'favourite', 'best work'],
    ),
    (
      question: 'Tell me about a difficult technical problem you solved',
      tags: <String>['difficult', 'challenge', 'hardest', 'problem', 'debug'],
    ),
    (
      question: 'Tell me about a conflict with a teammate',
      tags: <String>[
        'conflict',
        'disagreement',
        'teammate',
        'difficult person',
      ],
    ),
    (
      question: 'What is your biggest weakness?',
      tags: <String>['weakness', 'improve', 'development area', 'feedback'],
    ),
    (
      question: 'Describe a time you failed',
      tags: <String>['failure', 'mistake', 'went wrong', 'learned'],
    ),
    (
      question: 'Tell me about a time you led without authority',
      tags: <String>['leadership', 'led', 'influence', 'ownership'],
    ),
    (
      question: 'How do you handle competing priorities?',
      tags: <String>['priorities', 'deadline', 'time management', 'pressure'],
    ),
    (
      question: 'What are your salary expectations?',
      tags: <String>['salary', 'compensation', 'expectations', 'pay', 'range'],
    ),
    (
      question: 'Where do you see yourself in a few years?',
      tags: <String>['future', 'goals', 'career', 'growth', 'five years'],
    ),
    (
      question: 'Do you have any questions for us?',
      tags: <String>['questions for us', 'anything to ask'],
    ),
  ];

  /// Blank prepared-answer entries for a fresh profile.
  static List<ProfileEntry> seedEntries() => <ProfileEntry>[
    for (int i = 0; i < common.length; i++)
      ProfileEntry(
        id: 'recruiter-$i',
        kind: ProfileEntryKind.question,
        title: common[i].question,
        tags: common[i].tags,
      ),
  ];
}
