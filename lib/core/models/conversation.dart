import '../models/assist_models.dart';
import '../models/audio_models.dart';

/// Who produced a line of the conversation.
enum ChatRole {
  /// The other side of the call.
  them('Them'),

  /// The user.
  you('You'),

  /// xpass's answer.
  assistant('xpass');

  const ChatRole(this.label);
  final String label;

  static ChatRole fromName(String? name) => ChatRole.values.firstWhere(
    (ChatRole r) => r.name == name,
    orElse: () => ChatRole.them,
  );

  static ChatRole fromSource(AudioSource source) =>
      source == AudioSource.system ? ChatRole.them : ChatRole.you;
}

/// One line of the conversation — something said, or something answered.
class ChatEntry {
  ChatEntry({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.tier,
    this.turnId,
    this.latencyMs,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime at;

  /// Which engine answered, for assistant entries.
  final AssistTier? tier;

  /// Links back to the live [AssistTurn] while it is still streaming.
  final String? turnId;
  final int? latencyMs;

  bool get isAnswer => role == ChatRole.assistant;

  ChatEntry copyWith({String? text, int? latencyMs}) => ChatEntry(
    id: id,
    role: role,
    text: text ?? this.text,
    at: at,
    tier: tier,
    turnId: turnId,
    latencyMs: latencyMs ?? this.latencyMs,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'role': role.name,
    'text': text,
    'at': at.toIso8601String(),
    if (tier != null) 'tier': tier!.name,
    if (turnId != null) 'turnId': turnId,
    if (latencyMs != null) 'latencyMs': latencyMs,
  };

  static ChatEntry fromJson(Map<String, Object?> json) => ChatEntry(
    id:
        json['id'] as String? ??
        'entry-${DateTime.now().microsecondsSinceEpoch}',
    role: ChatRole.fromName(json['role'] as String?),
    text: json['text'] as String? ?? '',
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    tier: json['tier'] == null
        ? null
        : AssistTier.values.firstWhere(
            (AssistTier t) => t.name == json['tier'],
            orElse: () => AssistTier.fast,
          ),
    turnId: json['turnId'] as String?,
    latencyMs: (json['latencyMs'] as num?)?.toInt(),
  );
}

/// A whole conversation, as saved to disk.
class Conversation {
  const Conversation({
    required this.id,
    required this.startedAt,
    required this.entries,
  });

  final String id;
  final DateTime startedAt;
  final List<ChatEntry> entries;

  /// Everything said out loud, oldest first — what a prompt's context is
  /// built from.
  Iterable<ChatEntry> get spoken => entries.where((ChatEntry e) => !e.isAnswer);

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'entries': entries.map((ChatEntry e) => e.toJson()).toList(),
  };

  static Conversation fromJson(Map<String, Object?> json) => Conversation(
    id: json['id'] as String? ?? 'session',
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now(),
    entries: (json['entries'] as List<Object?>? ?? <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> e) =>
              ChatEntry.fromJson(e.cast<String, Object?>()),
        )
        .toList(),
  );
}
