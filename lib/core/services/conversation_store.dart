import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/assist_models.dart';
import '../models/audio_models.dart';
import '../models/conversation.dart';

/// Holds the running conversation and writes it to disk.
///
/// Everything said and everything answered lands here in one chronological
/// list, so a call can be reviewed afterwards and an answer from twenty
/// minutes ago is still reachable. Saves are debounced — a live transcript
/// changes several times a second and there is no reason to hit the disk for
/// each revision.
class ConversationStore extends ChangeNotifier {
  ConversationStore._(this._directory, this._conversation);

  final Directory _directory;
  Conversation _conversation;

  Timer? _saveTimer;
  bool _disposed = false;

  static const Duration _saveDebounce = Duration(seconds: 2);

  /// Keeps a long call from growing without bound in memory.
  static const int _maxEntries = 500;

  List<ChatEntry> get entries =>
      List<ChatEntry>.unmodifiable(_conversation.entries);

  Conversation get conversation => _conversation;

  bool get isEmpty => _conversation.entries.isEmpty;

  String get storagePath => '${_directory.path}/${_conversation.id}.json';

  // ------------------------------------------------------------------ load

  static Future<ConversationStore> open() async {
    final String home = Platform.environment['HOME'] ?? '.';
    final Directory directory = Directory(
      '$home/Library/Application Support/com.xpass.app/conversations',
    );
    try {
      await directory.create(recursive: true);
    } on IOException {
      // A read-only home is not worth failing launch over; saves will no-op.
    }

    final DateTime now = DateTime.now();
    final String id = 'session-${now.toIso8601String().replaceAll(':', '-')}';
    return ConversationStore._(
      directory,
      Conversation(id: id, startedAt: now, entries: <ChatEntry>[]),
    );
  }

  /// Past conversations, newest first.
  Future<List<Conversation>> history({int limit = 20}) async {
    try {
      if (!_directory.existsSync()) return const <Conversation>[];
      final List<File> files =
          _directory
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.endsWith('.json'))
              .toList()
            ..sort((File a, File b) => b.path.compareTo(a.path));

      final List<Conversation> loaded = <Conversation>[];
      for (final File file in files.take(limit)) {
        try {
          final Object? decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, Object?>) {
            loaded.add(Conversation.fromJson(decoded));
          }
        } on FormatException {
          continue;
        }
      }
      return loaded;
    } on IOException {
      return const <Conversation>[];
    }
  }

  // ------------------------------------------------------------------ write

  /// Records something said. A non-final line replaces the previous non-final
  /// line from the same speaker rather than stacking up revisions.
  void recordSpeech({
    required AudioSource source,
    required String text,
    required bool isFinal,
  }) {
    if (_disposed || text.trim().isEmpty) return;
    final ChatRole role = ChatRole.fromSource(source);

    final int pending = _conversation.entries.lastIndexWhere(
      (ChatEntry e) => e.role == role && e.id.startsWith('live-'),
    );

    final ChatEntry entry = ChatEntry(
      id: isFinal
          ? 'said-${DateTime.now().microsecondsSinceEpoch}'
          : 'live-${role.name}',
      role: role,
      text: text.trim(),
      at: DateTime.now(),
    );

    if (pending >= 0) {
      _conversation.entries[pending] = entry;
    } else {
      _conversation.entries.add(entry);
    }
    _trim();
    _scheduleSave();
    notifyListeners();
  }

  /// Records an answer as it begins, so it appears in the chat immediately.
  void beginAnswer(AssistTurn turn) {
    if (_disposed) return;
    _conversation.entries.add(
      ChatEntry(
        id: 'answer-${turn.id}',
        role: ChatRole.assistant,
        text: '',
        at: turn.startedAt,
        tier: turn.tier,
        turnId: turn.id,
      ),
    );
    _trim();
    notifyListeners();
  }

  /// Fills in the answer once it has finished streaming.
  void completeAnswer(AssistTurn turn) {
    if (_disposed) return;
    final int index = _conversation.entries.indexWhere(
      (ChatEntry e) => e.turnId == turn.id,
    );
    final String body = turn.error ?? turn.body.value;
    if (index < 0) return;

    _conversation.entries[index] = _conversation.entries[index].copyWith(
      text: body,
      latencyMs: turn.firstTokenLatency?.inMilliseconds,
    );
    _scheduleSave();
    notifyListeners();
  }

  void clear() {
    _conversation = Conversation(
      id: _conversation.id,
      startedAt: _conversation.startedAt,
      entries: <ChatEntry>[],
    );
    _scheduleSave();
    notifyListeners();
  }

  void _trim() {
    final int excess = _conversation.entries.length - _maxEntries;
    if (excess > 0) _conversation.entries.removeRange(0, excess);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(save()));
  }

  Future<void> save() async {
    if (_disposed || _conversation.entries.isEmpty) return;
    try {
      await File(storagePath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(_conversation.toJson()),
      );
    } on IOException catch (error) {
      debugPrint('xpass: could not save conversation — $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    super.dispose();
  }
}
