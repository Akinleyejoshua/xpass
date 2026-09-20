import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hotkey_binding.dart';

/// Which engine turns speech segments into text.
enum TranscriptionBackend {
  /// One Gemini call per utterance the VAD isolates. Default: no extra
  /// connection to keep alive, and it degrades gracefully on a flaky network.
  geminiBatch('Gemini (per utterance)'),

  /// Gemini Live bidirectional WebSocket — continuous partial transcripts.
  geminiLive('Gemini Live (streaming)'),

  /// A self-hosted NVIDIA Riva ASR NIM container.
  rivaNim('NVIDIA Riva NIM');

  const TranscriptionBackend(this.label);
  final String label;

  static TranscriptionBackend fromName(String? name) =>
      TranscriptionBackend.values.firstWhere(
        (TranscriptionBackend b) => b.name == name,
        orElse: () => TranscriptionBackend.geminiBatch,
      );
}

/// How much of the screen a solve captures.
enum CaptureMode {
  /// The whole display under the cursor.
  display('Full display'),

  /// Just the frontmost window — tighter context, fewer tokens, faster.
  activeWindow('Active window');

  const CaptureMode(this.label);
  final String label;

  static CaptureMode fromName(String? name) => CaptureMode.values.firstWhere(
    (CaptureMode m) => m.name == name,
    orElse: () => CaptureMode.display,
  );
}

/// Immutable snapshot of every user-tunable value.
@immutable
class XpSettings {
  const XpSettings({
    this.nvidiaApiKey = '',
    this.geminiApiKey = '',
    this.nimModel = defaultNimModel,
    this.geminiFastModel = defaultGeminiFastModel,
    this.geminiDeepModel = defaultGeminiDeepModel,
    this.geminiTranscribeModel = defaultGeminiTranscribeModel,
    this.useDeepReasoning = false,
    this.codeLanguage = 'Python',
    this.opacity = 0.96,
    this.captureMode = CaptureMode.display,
    this.captureMaxWidth = 1600,
    this.captureQuality = 0.72,
    this.micEnabled = true,
    this.systemAudioEnabled = true,
    this.autoAnswer = true,
    this.transcriptionBackend = TranscriptionBackend.geminiBatch,
    this.rivaBaseUrl = 'http://localhost:9000/v1',
    this.fastPromptOverride = '',
    this.deepPromptOverride = '',
    this.groundInProfile = true,
    this.portfolioUrl = defaultPortfolioUrl,
    this.hotkeys = MacKeyCodes.defaults,
  });

  static const String defaultNimModel = 'nvidia/nemotron-3.5-lightning-30b-a3b';

  // Offline fallbacks only — the pickers fetch the live catalogue from each
  // provider. Kept current because a stale default is a dead request: the
  // gemini-2.0 line has already been shut down, and the 2.5 line is on its way
  // out.
  static const String defaultGeminiFastModel = 'gemini-3.5-flash';
  static const String defaultGeminiDeepModel = 'gemini-3.1-pro-preview';
  static const String defaultGeminiTranscribeModel = 'gemini-3.5-transcribe';
  static const String defaultPortfolioUrl = 'https://joshuapro.netlify.app';

  /// Offline fallback only. The picker lists the provider's live catalogue,
  /// which is the single source of truth — model ids are retired regularly.
  static const List<String> nimModelChoices = <String>[
    'nvidia/nemotron-3.5-lightning-30b-a3b',
    'nvidia/nemotron-nano-3-30b-a3b',
    'deepseek-ai/deepseek-v4-flash-0731',
    'z-ai/glm-5.3-flash',
    'z-ai/glm-5.3',
    'moonshotai/kimi-k3',
    'nvidia/nemotron-3-super-120b-a12b',
    'google/gemma-4-31b-it',
    'mistralai/mistral-large-2-instruct',
  ];

  static const List<String> geminiModelChoices = <String>[
    'gemini-3.8-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-pro-preview',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
  ];

  /// Speech-to-text models. Purpose-built ASR beats a general model on both
  /// latency and word error rate.
  static const List<String> geminiTranscribeChoices = <String>[
    'gemini-3.5-transcribe',
    'gemini-3.5-flash',
    'gemini-3.8-flash',
  ];

  static const List<String> languageChoices = <String>[
    'Python',
    'TypeScript',
    'JavaScript',
    'Java',
    'Go',
    'C++',
    'Rust',
    'C#',
    'Kotlin',
    'Swift',
    'Ruby',
    'SQL',
  ];

  final String nvidiaApiKey;
  final String geminiApiKey;
  final String nimModel;
  final String geminiFastModel;
  final String geminiDeepModel;

  /// Model used for speech-to-text on the batch transcription path.
  final String geminiTranscribeModel;

  /// Route deep solves to [geminiDeepModel] instead of [geminiFastModel].
  final bool useDeepReasoning;
  final String codeLanguage;
  final double opacity;
  final CaptureMode captureMode;
  final int captureMaxWidth;
  final double captureQuality;
  final bool micEnabled;
  final bool systemAudioEnabled;

  /// Fire a tier-1 answer automatically when the interviewer stops talking.
  final bool autoAnswer;
  final TranscriptionBackend transcriptionBackend;
  final String rivaBaseUrl;
  final String fastPromptOverride;
  final String deepPromptOverride;

  /// Answer questions about the user from their stored profile instead of
  /// improvising a generic response.
  final bool groundInProfile;

  /// Portfolio site the profile importer reads from.
  final String portfolioUrl;
  final Map<HotkeyAction, HotkeyBinding> hotkeys;

  /// The Gemini model a solve actually uses, given the reasoning toggle.
  String get activeSolveModel =>
      useDeepReasoning ? geminiDeepModel : geminiFastModel;

  bool get hasNvidiaKey => nvidiaApiKey.trim().isNotEmpty;
  bool get hasGeminiKey => geminiApiKey.trim().isNotEmpty;
  bool get isConfigured => hasNvidiaKey || hasGeminiKey;

  XpSettings copyWith({
    String? nvidiaApiKey,
    String? geminiApiKey,
    String? nimModel,
    String? geminiFastModel,
    String? geminiDeepModel,
    String? geminiTranscribeModel,
    bool? useDeepReasoning,
    String? codeLanguage,
    double? opacity,
    CaptureMode? captureMode,
    int? captureMaxWidth,
    double? captureQuality,
    bool? micEnabled,
    bool? systemAudioEnabled,
    bool? autoAnswer,
    TranscriptionBackend? transcriptionBackend,
    String? rivaBaseUrl,
    String? fastPromptOverride,
    String? deepPromptOverride,
    bool? groundInProfile,
    String? portfolioUrl,
    Map<HotkeyAction, HotkeyBinding>? hotkeys,
  }) {
    return XpSettings(
      nvidiaApiKey: nvidiaApiKey ?? this.nvidiaApiKey,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      nimModel: nimModel ?? this.nimModel,
      geminiFastModel: geminiFastModel ?? this.geminiFastModel,
      geminiDeepModel: geminiDeepModel ?? this.geminiDeepModel,
      geminiTranscribeModel:
          geminiTranscribeModel ?? this.geminiTranscribeModel,
      useDeepReasoning: useDeepReasoning ?? this.useDeepReasoning,
      codeLanguage: codeLanguage ?? this.codeLanguage,
      opacity: opacity ?? this.opacity,
      captureMode: captureMode ?? this.captureMode,
      captureMaxWidth: captureMaxWidth ?? this.captureMaxWidth,
      captureQuality: captureQuality ?? this.captureQuality,
      micEnabled: micEnabled ?? this.micEnabled,
      systemAudioEnabled: systemAudioEnabled ?? this.systemAudioEnabled,
      autoAnswer: autoAnswer ?? this.autoAnswer,
      transcriptionBackend: transcriptionBackend ?? this.transcriptionBackend,
      rivaBaseUrl: rivaBaseUrl ?? this.rivaBaseUrl,
      fastPromptOverride: fastPromptOverride ?? this.fastPromptOverride,
      deepPromptOverride: deepPromptOverride ?? this.deepPromptOverride,
      groundInProfile: groundInProfile ?? this.groundInProfile,
      portfolioUrl: portfolioUrl ?? this.portfolioUrl,
      hotkeys: hotkeys ?? this.hotkeys,
    );
  }
}

/// Loads, holds and persists [XpSettings].
///
/// API keys resolve in this order: what the user typed in Settings, then a
/// `.env` file, then the process environment. That way a developer can export
/// `GEMINI_API_KEY` and never type a key into the UI, while a normal user never
/// has to touch a terminal.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this._env, this._value);

  final SharedPreferences _prefs;
  final Map<String, String> _env;
  XpSettings _value;

  XpSettings get value => _value;

  /// True when the key came from the environment rather than the UI, so the
  /// settings screen can show it as inherited instead of blank.
  bool get nvidiaKeyFromEnv =>
      (_prefs.getString(_kNvidiaKey) ?? '').isEmpty && _envNvidiaKey.isNotEmpty;

  bool get geminiKeyFromEnv =>
      (_prefs.getString(_kGeminiKey) ?? '').isEmpty && _envGeminiKey.isNotEmpty;

  static const String _kNvidiaKey = 'nvidiaApiKey';
  static const String _kGeminiKey = 'geminiApiKey';

  String get _envNvidiaKey =>
      _env['NVIDIA_API_KEY'] ?? _env['NVIDIA_NIM_API_KEY'] ?? '';

  String get _envGeminiKey =>
      _env['GEMINI_API_KEY'] ?? _env['GOOGLE_API_KEY'] ?? '';

  static Future<SettingsController> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, String> env = await _readEnvironment();

    final Map<HotkeyAction, HotkeyBinding> hotkeys =
        <HotkeyAction, HotkeyBinding>{};
    for (final HotkeyAction action in HotkeyAction.values) {
      final String? raw = prefs.getString('hotkey.${action.id}');
      hotkeys[action] =
          (raw == null ? null : HotkeyBinding.decode(raw)) ??
          MacKeyCodes.defaults[action]!;
    }

    final XpSettings settings = XpSettings(
      nvidiaApiKey:
          _nonEmpty(prefs.getString(_kNvidiaKey)) ??
          (env['NVIDIA_API_KEY'] ?? env['NVIDIA_NIM_API_KEY'] ?? ''),
      geminiApiKey:
          _nonEmpty(prefs.getString(_kGeminiKey)) ??
          (env['GEMINI_API_KEY'] ?? env['GOOGLE_API_KEY'] ?? ''),
      nimModel: prefs.getString('nimModel') ?? XpSettings.defaultNimModel,
      geminiFastModel:
          prefs.getString('geminiFastModel') ??
          XpSettings.defaultGeminiFastModel,
      geminiDeepModel:
          prefs.getString('geminiDeepModel') ??
          XpSettings.defaultGeminiDeepModel,
      useDeepReasoning: prefs.getBool('useDeepReasoning') ?? false,
      codeLanguage: prefs.getString('codeLanguage') ?? 'Python',
      opacity: prefs.getDouble('opacity') ?? 0.96,
      captureMode: CaptureMode.fromName(prefs.getString('captureMode')),
      captureMaxWidth: prefs.getInt('captureMaxWidth') ?? 1600,
      captureQuality: prefs.getDouble('captureQuality') ?? 0.72,
      micEnabled: prefs.getBool('micEnabled') ?? true,
      systemAudioEnabled: prefs.getBool('systemAudioEnabled') ?? true,
      autoAnswer: prefs.getBool('autoAnswer') ?? true,
      transcriptionBackend: TranscriptionBackend.fromName(
        prefs.getString('transcriptionBackend'),
      ),
      rivaBaseUrl: prefs.getString('rivaBaseUrl') ?? 'http://localhost:9000/v1',
      fastPromptOverride: prefs.getString('fastPromptOverride') ?? '',
      deepPromptOverride: prefs.getString('deepPromptOverride') ?? '',
      groundInProfile: prefs.getBool('groundInProfile') ?? true,
      portfolioUrl:
          prefs.getString('portfolioUrl') ?? XpSettings.defaultPortfolioUrl,
      hotkeys: hotkeys,
    );

    return SettingsController._(prefs, env, settings);
  }

  static String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  Future<void> update(XpSettings next) async {
    _value = next;
    notifyListeners();

    await Future.wait(<Future<Object?>>[
      _prefs.setString(
        _kNvidiaKey,
        next.nvidiaApiKey == _envNvidiaKey ? '' : next.nvidiaApiKey,
      ),
      _prefs.setString(
        _kGeminiKey,
        next.geminiApiKey == _envGeminiKey ? '' : next.geminiApiKey,
      ),
      _prefs.setString('nimModel', next.nimModel),
      _prefs.setString('geminiFastModel', next.geminiFastModel),
      _prefs.setString('geminiDeepModel', next.geminiDeepModel),
      _prefs.setString('geminiTranscribeModel', next.geminiTranscribeModel),
      _prefs.setBool('useDeepReasoning', next.useDeepReasoning),
      _prefs.setString('codeLanguage', next.codeLanguage),
      _prefs.setDouble('opacity', next.opacity),
      _prefs.setString('captureMode', next.captureMode.name),
      _prefs.setInt('captureMaxWidth', next.captureMaxWidth),
      _prefs.setDouble('captureQuality', next.captureQuality),
      _prefs.setBool('micEnabled', next.micEnabled),
      _prefs.setBool('systemAudioEnabled', next.systemAudioEnabled),
      _prefs.setBool('autoAnswer', next.autoAnswer),
      _prefs.setString('transcriptionBackend', next.transcriptionBackend.name),
      _prefs.setString('rivaBaseUrl', next.rivaBaseUrl),
      _prefs.setString('fastPromptOverride', next.fastPromptOverride),
      _prefs.setString('deepPromptOverride', next.deepPromptOverride),
      _prefs.setBool('groundInProfile', next.groundInProfile),
      _prefs.setString('portfolioUrl', next.portfolioUrl),
      for (final MapEntry<HotkeyAction, HotkeyBinding> entry
          in next.hotkeys.entries)
        _prefs.setString('hotkey.${entry.key.id}', entry.value.encode()),
    ]);
  }

  /// Convenience for single-field edits from the HUD chrome.
  Future<void> mutate(XpSettings Function(XpSettings current) transform) =>
      update(transform(_value));

  // ------------------------------------------------------------------- env

  /// Reads `.env` from the working directory, the app bundle's parent, and
  /// `~/.xpass/.env`, then layers the real process environment on top.
  static Future<Map<String, String>> _readEnvironment() async {
    final Map<String, String> merged = <String, String>{};

    final List<String> candidates = <String>[
      '${Directory.current.path}/.env',
      '${File(Platform.resolvedExecutable).parent.parent.parent.parent.path}/.env',
      '${Platform.environment['HOME'] ?? ''}/.xpass/.env',
    ];

    for (final String path in candidates) {
      try {
        final File file = File(path);
        if (!file.existsSync()) continue;
        merged.addAll(_parseEnv(await file.readAsString()));
      } on IOException {
        // An unreadable .env is not worth failing startup over.
        continue;
      }
    }

    // Real exported variables win over any file.
    for (final String key in const <String>[
      'NVIDIA_API_KEY',
      'NVIDIA_NIM_API_KEY',
      'GEMINI_API_KEY',
      'GOOGLE_API_KEY',
    ]) {
      final String? value = Platform.environment[key];
      if (value != null && value.isNotEmpty) merged[key] = value;
    }

    return merged;
  }

  static Map<String, String> _parseEnv(String contents) {
    final Map<String, String> result = <String, String>{};
    for (final String rawLine in contents.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final int equals = line.indexOf('=');
      if (equals <= 0) continue;

      final String key = line
          .substring(0, equals)
          .trim()
          .replaceFirst(RegExp(r'^export\s+'), '');
      String value = line.substring(equals + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
  }
}
