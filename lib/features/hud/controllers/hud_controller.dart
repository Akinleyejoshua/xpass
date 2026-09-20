import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_prompts.dart';
import '../../../core/models/assist_models.dart';
import '../../../core/models/audio_models.dart';
import '../../../core/models/hotkey_binding.dart';
import '../../../core/services/audio_capture_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/nvidia_nim_service.dart';
import '../../../core/services/portfolio_importer.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/screen_capture_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/transcription_service.dart';
import '../../../core/services/window_service.dart';
import '../../../core/shortcuts/hotkey_service.dart';
import '../../../core/utils/vad.dart';

/// Orchestrates everything the HUD does: capture, transcribe, decide, stream.
///
/// Structural changes go through [notifyListeners]; streamed answer text goes
/// through each turn's own [AssistTurn.body] notifier, so tokens arriving at
/// 60/second repaint only the markdown view rather than the whole tree.
class HudController extends ChangeNotifier {
  HudController({
    required this.settings,
    required this.window,
    required this.screen,
    required this.audio,
    required this.hotkeys,
    required this.gemini,
    required this.nim,
    required this.profile,
    required this.portfolio,
  });

  final SettingsController settings;
  final WindowService window;
  final ScreenCaptureService screen;
  final AudioCaptureService audio;
  final HotkeyService hotkeys;
  final GeminiService gemini;
  final NvidiaNimService nim;
  final ProfileService profile;
  final PortfolioImporter portfolio;

  // ----------------------------------------------------------------- state
  HudStatus _status = HudStatus.idle;
  HudStatus get status => _status;

  final List<TranscriptSegment> _transcript = <TranscriptSegment>[];
  List<TranscriptSegment> get transcript =>
      List<TranscriptSegment>.unmodifiable(_transcript);

  AssistTurn? _current;
  AssistTurn? get current => _current;

  final List<AssistTurn> _history = <AssistTurn>[];
  List<AssistTurn> get history => List<AssistTurn>.unmodifiable(_history);

  bool _listening = false;
  bool get isListening => _listening;

  bool _clickThrough = false;
  bool get isClickThrough => _clickThrough;

  bool _visible = true;
  bool get isVisible => _visible;

  bool _micActive = false;
  bool get micActive => _micActive;

  bool _systemActive = false;
  bool get systemAudioActive => _systemActive;

  String? _banner;
  String? get banner => _banner;

  bool _bannerIsError = false;
  bool get bannerIsError => _bannerIsError;

  double _micLevel = 0;
  double _systemLevel = 0;
  double get micLevel => _micLevel;
  double get systemLevel => _systemLevel;

  bool _screenPermission = false;
  bool get hasScreenPermission => _screenPermission;

  HudPane _pane = HudPane.answer;
  HudPane get pane => _pane;
  bool get isSettingsOpen => _pane == HudPane.settings;
  bool get isNotesOpen => _pane == HudPane.notes;

  /// Last frame sent to Gemini, shown as a thumbnail on the active turn.
  Uint8List? _lastFrame;
  Uint8List? get lastFrame => _lastFrame;

  // --------------------------------------------------------------- internals
  final VoiceActivityDetector _micVad = VoiceActivityDetector(
    source: AudioSource.mic,
  );
  final VoiceActivityDetector _systemVad = VoiceActivityDetector(
    source: AudioSource.system,
  );

  Transcriber? _transcriber;
  StreamSubscription<AudioFrame>? _frameSub;
  StreamSubscription<String>? _audioErrorSub;
  StreamSubscription<TranscriptEvent>? _transcriptSub;
  StreamSubscription<String>? _transcriberErrorSub;
  StreamSubscription<String>? _deltaSub;

  Completer<void>? _turnCompleter;
  Timer? _flushTimer;
  Timer? _bannerTimer;
  final StringBuffer _pendingText = StringBuffer();
  int _turnCounter = 0;
  bool _disposed = false;

  /// Coalesce token deltas to one repaint per frame.
  static const Duration _flushInterval = Duration(milliseconds: 16);

  /// How much conversation is fed back into each prompt.
  static const int _contextSegments = 6;

  // ---------------------------------------------------------------- lifecycle

  Future<void> initialize() async {
    settings.addListener(_onSettingsChanged);

    _screenPermission = await screen.hasPermission();
    await window.setOpacity(settings.value.opacity);

    _registerHotkeys();
    await hotkeys.applyBindings(settings.value.hotkeys);
    _reportHotkeyFailures();

    if (!settings.value.isConfigured) {
      _setBanner(
        'Add an API key in Settings to start. ⌘⌥H hides xpass instantly.',
        isError: false,
      );
      _pane = HudPane.settings;
    } else {
      await startListening();
    }
    notifyListeners();
  }

  void _registerHotkeys() {
    hotkeys
      ..on(HotkeyAction.panic, () => unawaited(togglePanic()))
      ..on(HotkeyAction.solve, () => unawaited(captureAndSolve()))
      ..on(HotkeyAction.clickThrough, () => unawaited(toggleClickThrough()))
      ..on(HotkeyAction.clear, clearSession);
  }

  void _reportHotkeyFailures() {
    if (hotkeys.failures.isEmpty) return;
    final String names = hotkeys.failures.keys
        .map((HotkeyAction a) => a.label)
        .join(', ');
    _setBanner(
      'Could not bind: $names. Rebind them in Settings.',
      isError: true,
    );
  }

  void _onSettingsChanged() {
    unawaited(window.setOpacity(settings.value.opacity));
    unawaited(hotkeys.applyBindings(settings.value.hotkeys));
    notifyListeners();
  }

  // ------------------------------------------------------------------- audio

  Future<void> startListening() async {
    if (_listening) return;
    final XpSettings config = settings.value;

    if (!config.micEnabled && !config.systemAudioEnabled) {
      _setStatus(HudStatus.muted);
      return;
    }

    if (config.micEnabled && !await audio.hasMicPermission()) {
      final bool granted = await audio.requestMicPermission();
      if (!granted) {
        _setBanner(
          'Microphone access denied. xpass will only hear system audio.',
          isError: true,
        );
      }
    }

    final AudioStartResult result = await audio.start(
      mic: config.micEnabled,
      system: config.systemAudioEnabled,
    );

    _micActive = result.micStarted;
    _systemActive = result.systemStarted;

    if (!result.anyStarted) {
      _setBanner(
        result.firstError ??
            'Could not start audio capture. Grant Screen Recording in '
                'System Settings › Privacy & Security, then relaunch.',
        isError: true,
      );
      _setStatus(HudStatus.error);
      return;
    }

    if (result.systemError != null && config.systemAudioEnabled) {
      _setBanner(
        'System audio unavailable: ${result.systemError}. '
        'Grant Screen Recording, then relaunch.',
        isError: true,
      );
    }

    await _startTranscriber();

    _frameSub = audio.frames.listen(_onAudioFrame);
    _audioErrorSub = audio.errors.listen((String message) {
      _micActive = false;
      _systemActive = false;
      _listening = false;
      _setBanner(message, isError: true);
      _setStatus(HudStatus.error);
    });

    _listening = true;
    _setStatus(HudStatus.listening);
  }

  Future<void> stopListening() async {
    _listening = false;
    _micActive = false;
    _systemActive = false;

    await _frameSub?.cancel();
    _frameSub = null;
    await _audioErrorSub?.cancel();
    _audioErrorSub = null;

    await audio.stop();
    await _disposeTranscriber();

    _micVad.reset();
    _systemVad.reset();

    _setStatus(HudStatus.muted);
  }

  Future<void> toggleListening() =>
      _listening ? stopListening() : startListening();

  Future<void> _startTranscriber() async {
    await _disposeTranscriber();

    final Transcriber transcriber = buildTranscriber(
      backend: settings.value.transcriptionBackend,
      settings: settings.value,
      gemini: gemini,
    );

    _transcriptSub = transcriber.events.listen(_onTranscript);
    _transcriberErrorSub = transcriber.errors.listen(
      (String message) => _setBanner(message, isError: true),
    );

    await transcriber.start();
    _transcriber = transcriber;
  }

  Future<void> _disposeTranscriber() async {
    await _transcriptSub?.cancel();
    _transcriptSub = null;
    await _transcriberErrorSub?.cancel();
    _transcriberErrorSub = null;
    await _transcriber?.dispose();
    _transcriber = null;
  }

  void _onAudioFrame(AudioFrame frame) {
    if (_disposed) return;

    // Continuous backends want every frame; segment backends want utterances.
    _transcriber?.pushFrame(frame);

    final VoiceActivityDetector detector = frame.source == AudioSource.mic
        ? _micVad
        : _systemVad;
    final VadEvent? event = detector.process(frame);

    // Cheap level meter: decay fast enough to look live, slow enough to read.
    if (frame.source == AudioSource.mic) {
      _micLevel = _decay(_micLevel, frame.rms);
    } else {
      _systemLevel = _decay(_systemLevel, frame.rms);
    }

    switch (event) {
      case VadSpeechStart():
        if (_status == HudStatus.listening || _status == HudStatus.idle) {
          _setStatus(HudStatus.listening);
        }
      case VadSpeechEnd(segment: final SpeechSegment segment):
        // Every segment is one API request. The user's own speech is optional
        // context; the interviewer's is what actually drives an answer.
        if (segment.source == AudioSource.system ||
            settings.value.transcribeMic) {
          _transcriber?.pushSegment(segment);
        }
      case null:
        break;
    }
  }

  static double _decay(double current, double sample) =>
      sample > current ? sample : current * 0.82 + sample * 0.18;

  void _onTranscript(TranscriptEvent event) {
    if (_disposed) return;

    if (!event.isFinal) {
      // Replace the trailing non-final line from the same source.
      final int index = _transcript.lastIndexWhere(
        (TranscriptSegment s) => s.source == event.source && !s.isFinal,
      );
      if (index >= 0) {
        _transcript[index] = _transcript[index].copyWith(text: event.text);
      } else {
        _transcript.add(
          TranscriptSegment(
            source: event.source,
            text: event.text,
            isFinal: false,
            at: DateTime.now(),
          ),
        );
      }
      notifyListeners();
      return;
    }

    final int pendingIndex = _transcript.lastIndexWhere(
      (TranscriptSegment s) => s.source == event.source && !s.isFinal,
    );
    final TranscriptSegment finalised = TranscriptSegment(
      source: event.source,
      text: event.text,
      isFinal: true,
      at: DateTime.now(),
    );
    if (pendingIndex >= 0) {
      _transcript[pendingIndex] = finalised;
    } else {
      _transcript.add(finalised);
    }

    // Keep the ticker bounded; the prompt only ever reads the tail.
    if (_transcript.length > 40) {
      _transcript.removeRange(0, _transcript.length - 40);
    }
    notifyListeners();

    // Only the interviewer's questions trigger an automatic answer — answering
    // the user's own sentences would flood the HUD.
    if (settings.value.autoAnswer &&
        event.source == AudioSource.system &&
        _looksLikeQuestion(event.text)) {
      unawaited(answerHeardQuestion(event.text));
    }
  }

  /// Answers a question picked up from the call, choosing the tier for it.
  ///
  /// This is the whole point of listening: by the time the interviewer stops
  /// talking, the right engine is already streaming. Routing happens locally
  /// on the transcript, so it costs nothing and adds no latency.
  Future<void> answerHeardQuestion(String question) {
    final AssistRoute route = routeFor(
      question,
      profileReady:
          settings.value.groundInProfile && profile.profile.isConfigured,
      screenEnabled: settings.value.autoScreenSolve,
    );

    return switch (route) {
      AssistRoute.screen => captureAndSolve(question: question, heard: true),
      AssistRoute.profile => askAboutMe(question, heard: true),
      AssistRoute.wingman => askFast(question, heard: true),
    };
  }

  /// Picks the tier for a question heard on the call.
  ///
  /// Screen is tested first: a demonstrative reference ("this function", "the
  /// error here") is the strongest signal in the sentence, and it names the one
  /// resource the other two tiers cannot see. Profile comes next because it is
  /// specific about past experience. Everything else is conceptual.
  static AssistRoute routeFor(
    String question, {
    required bool profileReady,
    required bool screenEnabled,
  }) {
    if (screenEnabled && looksLikeScreenQuestion(question)) {
      return AssistRoute.screen;
    }
    if (profileReady && ProfileService.looksLikeProfileQuestion(question)) {
      return AssistRoute.profile;
    }
    return AssistRoute.wingman;
  }

  /// True when the question refers to something the user is looking at.
  ///
  /// Requires a demonstrative ("this", "that", "here", "on the screen") tied to
  /// something technical, or an imperative aimed at existing code. A bare
  /// "implement a queue" is deliberately *not* a screen question — it is
  /// answerable from the words alone, and capturing a frame for it would spend
  /// a request and a second of latency for nothing.
  static bool looksLikeScreenQuestion(String text) {
    final String lower = text.toLowerCase().trim();
    if (lower.isEmpty) return false;

    const List<String> explicit = <String>[
      'on the screen',
      'on your screen',
      'what you see',
      'what do you see',
      'in the editor',
      'in your editor',
      'share your screen',
    ];
    if (explicit.any(lower.contains)) return true;

    // "fix this", "debug that", "what is wrong with this"
    final bool imperativeOnExisting = RegExp(
      r'\b(fix|debug|refactor|optimi[sz]e|improve|review|trace|profile|'
      r'rewrite|simplify)\s+(this|that|it|the)\b',
    ).hasMatch(lower);
    if (imperativeOnExisting) return true;

    if (RegExp(r"what'?s wrong with (this|that|it|the)\b").hasMatch(lower)) {
      return true;
    }

    // A demonstrative attached to something technical and visible.
    final bool demonstrative = RegExp(
      r'\b(this|that|these|those|the)\s+'
      r'(code|function|method|class|snippet|query|schema|diagram|'
      r'error|exception|stack\s?trace|bug|test|failure|output|log|'
      r'problem|question|implementation|solution|algorithm|signature)\b',
    ).hasMatch(lower);
    if (demonstrative) return true;

    // "walk me through this", "explain what is happening here"
    return RegExp(
      r'\b(walk me through|explain|talk me through|step through)\b'
      r'.*\b(this|that|here)\b',
    ).hasMatch(lower);
  }

  /// Heuristic for "the interviewer just asked me something".
  ///
  /// Deliberately permissive on interrogative openers, because interviewers
  /// phrase most questions as imperatives ("walk me through...", "tell me
  /// about...") that never end in a question mark.
  static bool _looksLikeQuestion(String text) {
    final String trimmed = text.trim();
    if (trimmed.length < 12) return false;
    if (trimmed.endsWith('?')) return true;

    final int words = trimmed.split(RegExp(r'\s+')).length;
    if (words < 4) return false;

    final String lower = trimmed.toLowerCase();
    const List<String> cues = <String>[
      'what',
      'why',
      'how',
      'when',
      'where',
      'which',
      'who',
      'can you',
      'could you',
      'would you',
      'do you',
      'did you',
      'have you',
      'are you',
      'is there',
      'tell me',
      'walk me',
      'explain',
      'describe',
      'give me',
      'talk me',
      'suppose',
      'imagine',
      'design a',
      'design an',
      "let's",
      'lets say',
      'write a',
      'write an',
      'implement',
    ];
    return cues.any(lower.startsWith);
  }

  // ------------------------------------------------------------ tier 1: fast

  /// Ultra-low-latency talking points via NVIDIA NIM.
  ///
  /// Questions about the user go to the profile-grounded persona instead, so
  /// "tell me about a time you led a migration" is answered from their real
  /// history rather than improvised.
  Future<void> askFast(String question, {bool heard = false}) async {
    final XpSettings config = settings.value;
    if (!config.hasNvidiaKey) {
      _setBanner(
        'Add an NVIDIA API key in Settings to use the fast wingman.',
        isError: true,
      );
      return;
    }

    if (settings.value.groundInProfile &&
        profile.profile.isConfigured &&
        ProfileService.looksLikeProfileQuestion(question)) {
      return askAboutMe(question, heard: heard);
    }

    final AssistTurn turn = _beginTurn(AssistTier.fast, question, heard: heard);
    final String persona = config.fastPromptOverride.trim().isEmpty
        ? XpPrompts.fastWingman
        : config.fastPromptOverride;

    await _consume(
      turn,
      nim.streamChat(
        apiKey: config.nvidiaApiKey,
        model: config.nimModel,
        messages: <ChatMessage>[
          ChatMessage.system(persona),
          ChatMessage.user(
            XpPrompts.fastUserTurn(
              question: question,
              recentContext: _recentContext(excludeLast: true),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- profile answers

  /// Answers a question about the user from their own profile.
  ///
  /// Retrieval runs locally over the profile entries and only the top matches
  /// are sent, which keeps the prompt small enough to stay inside the
  /// sub-second budget even with a large background.
  Future<void> askAboutMe(String question, {bool heard = false}) async {
    final XpSettings config = settings.value;
    if (!config.hasNvidiaKey) {
      _setBanner(
        'Add an NVIDIA API key in Settings to answer from your profile.',
        isError: true,
      );
      return;
    }
    if (!profile.profile.isConfigured) {
      _setBanner(
        'Your profile is empty — import it or fill it in under Settings › Profile.',
        isError: true,
      );
      return;
    }

    final String context = profile.contextFor(question, limit: 5);
    final AssistTurn turn = _beginTurn(
      AssistTier.profile,
      question,
      heard: heard,
    );

    await _consume(
      turn,
      nim.streamChat(
        apiKey: config.nvidiaApiKey,
        model: config.nimModel,
        messages: <ChatMessage>[
          ChatMessage.system(XpPrompts.profileWingman(context)),
          ChatMessage.user(
            XpPrompts.profileUserTurn(
              question: question,
              recentContext: _recentContext(excludeLast: true),
            ),
          ),
        ],
        // Profile answers need room for a full STAR story, and a little more
        // variation than a factual lookup so they do not sound recited.
        maxTokens: 520,
        temperature: 0.35,
      ),
    );
  }

  /// Pulls the user's profile from their portfolio site.
  Future<bool> importProfile(String baseUrl) async {
    try {
      final profileResult = await portfolio.importFrom(
        baseUrl,
        existing: profile.profile,
      );
      await profile.save(profileResult);
      _setBanner(
        'Profile imported — ${profile.factCount} facts available.',
        isError: false,
      );
      return true;
    } on AiServiceException catch (error) {
      _setBanner(error.message, isError: true);
      return false;
    } catch (error) {
      _setBanner('Import failed: $error', isError: true);
      return false;
    }
  }

  // ------------------------------------------------------------ tier 2: deep

  /// Screenshot the active region and stream a full solve from Gemini.
  Future<void> captureAndSolve({String? question, bool heard = false}) async {
    final XpSettings config = settings.value;
    if (!config.hasGeminiKey) {
      _setBanner(
        'Add a Gemini API key in Settings to use screen solving.',
        isError: true,
      );
      return;
    }

    _cancelActiveTurn();
    _setStatus(HudStatus.capturing);

    final CapturedFrame frame;
    try {
      frame = await screen.capture(
        mode: config.captureMode,
        maxWidth: config.captureMaxWidth,
        quality: config.captureQuality,
      );
    } on AiServiceException catch (error) {
      _screenPermission = await screen.hasPermission();
      _setBanner(error.message, isError: true);
      _setStatus(HudStatus.error);
      return;
    }

    _lastFrame = frame.jpeg;
    _screenPermission = true;

    final AssistTurn turn = _beginTurn(
      AssistTier.deep,
      question ?? 'Screen solve · ${frame.width}×${frame.height}',
      thumbnail: frame.jpeg,
      heard: heard,
    );

    final String persona = config.deepPromptOverride.trim().isEmpty
        ? XpPrompts.deepSolve(config.codeLanguage)
        : config.deepPromptOverride;

    await _consume(
      turn,
      gemini.streamGenerate(
        apiKey: config.geminiApiKey,
        model: config.activeSolveModel,
        systemInstruction: persona,
        userText: XpPrompts.deepUserTurn(
          recentContext: _recentContext(),
          explicitQuestion: question,
        ),
        imageJpeg: frame.jpeg,
      ),
    );
  }

  /// Typed question from the ask box. Routes by intent: anything that needs the
  /// screen goes to Gemini, anything conversational goes to NIM.
  Future<void> ask(
    String text, {
    bool withScreen = false,
    bool aboutMe = false,
  }) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    if (withScreen) return captureAndSolve(question: trimmed);
    if (aboutMe) return askAboutMe(trimmed);
    return askFast(trimmed);
  }

  // -------------------------------------------------------------- turn plumbing

  AssistTurn _beginTurn(
    AssistTier tier,
    String query, {
    Uint8List? thumbnail,
    bool heard = false,
  }) {
    _cancelActiveTurn();

    final AssistTurn turn = AssistTurn(
      id: 'turn-${DateTime.now().microsecondsSinceEpoch}-${_turnCounter++}',
      tier: tier,
      query: query,
      startedAt: DateTime.now(),
      thumbnail: thumbnail,
    );

    if (_current != null) _history.insert(0, _current!);
    if (_history.length > 12) {
      _history.removeLast().dispose();
    }

    turn.wasHeard = heard;
    _current = turn;
    _pendingText.clear();
    _setStatus(HudStatus.thinking);
    return turn;
  }

  Future<void> _consume(AssistTurn turn, Stream<String> deltas) {
    final Completer<void> completer = Completer<void>();
    _turnCompleter = completer;
    final Stopwatch stopwatch = Stopwatch()..start();

    void finish() {
      _flushTimer?.cancel();
      _flushTimer = null;
      _flushPending(turn);
      stopwatch.stop();
      turn.totalLatency = stopwatch.elapsed;
      turn.isDone = true;
      if (!completer.isCompleted) completer.complete();
      if (_current == turn) {
        _setStatus(
          turn.error != null
              ? HudStatus.error
              : (_listening ? HudStatus.listening : HudStatus.idle),
        );
      }
      notifyListeners();
    }

    _deltaSub = deltas.listen(
      (String delta) {
        if (turn.firstTokenLatency == null) {
          turn.firstTokenLatency = stopwatch.elapsed;
          _setStatus(HudStatus.streaming);
        }
        _pendingText.write(delta);
        _scheduleFlush(turn);
      },
      onError: (Object error) {
        turn.error = error is AiServiceException
            ? error.message
            : error.toString();
        _setBanner(turn.error!, isError: true);
        finish();
      },
      onDone: finish,
      cancelOnError: true,
    );

    return completer.future;
  }

  void _scheduleFlush(AssistTurn turn) {
    _flushTimer ??= Timer(_flushInterval, () {
      _flushTimer = null;
      _flushPending(turn);
    });
  }

  void _flushPending(AssistTurn turn) {
    if (_pendingText.isEmpty) return;
    turn.body.value = turn.body.value + _pendingText.toString();
    _pendingText.clear();
  }

  void _cancelActiveTurn() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingText.clear();

    final AssistTurn? turn = _current;
    unawaited(_deltaSub?.cancel());
    _deltaSub = null;

    if (turn != null && !turn.isDone) {
      turn.wasCancelled = true;
      turn.isDone = true;
    }
    if (_turnCompleter != null && !_turnCompleter!.isCompleted) {
      _turnCompleter!.complete();
    }
    _turnCompleter = null;
  }

  /// The tail of the conversation, formatted for a prompt.
  String _recentContext({bool excludeLast = false}) {
    final List<TranscriptSegment> finals = _transcript
        .where((TranscriptSegment s) => s.isFinal)
        .toList();
    if (excludeLast && finals.isNotEmpty) finals.removeLast();
    if (finals.isEmpty) return '';

    final Iterable<TranscriptSegment> tail = finals.length > _contextSegments
        ? finals.skip(finals.length - _contextSegments)
        : finals;

    return tail
        .map((TranscriptSegment s) => '${s.source.label}: ${s.text}')
        .join('\n');
  }

  // ------------------------------------------------------------ window control

  /// Panic toggle — instant show/hide, bound to ⌘⌥H.
  Future<void> togglePanic() async {
    _visible = await window.toggleVisibility();
    notifyListeners();
  }

  Future<void> hide() async {
    _visible = await window.hide();
    notifyListeners();
  }

  Future<void> toggleClickThrough() async {
    _clickThrough = await window.toggleClickThrough();
    // A click-through HUD cannot receive the clicks Settings needs.
    if (_clickThrough && _pane == HudPane.settings) _pane = HudPane.answer;
    _setBanner(
      _clickThrough
          ? 'Click-through on — typing goes to the app underneath.'
          : 'Click-through off.',
      isError: false,
    );
    notifyListeners();
  }

  Future<void> setOpacity(double opacity) async {
    await settings.mutate((XpSettings s) => s.copyWith(opacity: opacity));
    await window.setOpacity(opacity);
  }

  Future<void> snap(HudAnchor anchor) => window.snapTo(anchor);

  void toggleSettings() =>
      showPane(_pane == HudPane.settings ? HudPane.answer : HudPane.settings);

  void toggleNotes() =>
      showPane(_pane == HudPane.notes ? HudPane.answer : HudPane.notes);

  void closeSettings() => showPane(HudPane.answer);

  void showPane(HudPane next) {
    if (_pane == next) return;
    _pane = next;
    // Settings has text fields, so it needs the keyboard; the other panes must
    // hand focus straight back to whatever the user was really working in.
    if (next == HudPane.settings) {
      unawaited(window.focus());
    } else {
      unawaited(window.releaseFocus());
    }
    notifyListeners();
  }

  /// Bring a past answer back into the answer pane.
  void restoreTurn(String id) {
    final int index = _history.indexWhere((AssistTurn t) => t.id == id);
    if (index < 0) return;

    final AssistTurn turn = _history.removeAt(index);
    if (_current != null) _history.insert(0, _current!);
    _current = turn;
    showPane(HudPane.answer);
    notifyListeners();
  }

  /// Everything asked this session, newest first — the running notes.
  List<AssistTurn> get notes => <AssistTurn>[?_current, ..._history];

  // -------------------------------------------------------------------- reset

  /// Wipe transcript, answers and streams — bound to ⌘⌥⌫.
  void clearSession() {
    _cancelActiveTurn();

    _current?.dispose();
    _current = null;
    for (final AssistTurn turn in _history) {
      turn.dispose();
    }
    _history.clear();
    _transcript.clear();
    _lastFrame = null;

    _micVad.reset();
    _systemVad.reset();

    _setBanner('Context cleared.', isError: false);
    _setStatus(_listening ? HudStatus.listening : HudStatus.idle);
  }

  // ------------------------------------------------------------------ clipboard

  /// Copies the last fenced code block of the active answer, or the whole
  /// answer if it contains none.
  Future<bool> copyCode() async {
    final AssistTurn? turn = _current;
    if (turn == null || turn.body.value.isEmpty) return false;

    final String code =
        extractLastCodeBlock(turn.body.value) ?? turn.body.value;
    await Clipboard.setData(ClipboardData(text: code.trim()));
    _setBanner('Copied to clipboard.', isError: false);
    return true;
  }

  Future<bool> copyAnswer() async {
    final AssistTurn? turn = _current;
    if (turn == null || turn.body.value.isEmpty) return false;
    await Clipboard.setData(ClipboardData(text: turn.body.value.trim()));
    _setBanner('Answer copied.', isError: false);
    return true;
  }

  /// Returns the contents of the last complete ``` fenced block.
  static String? extractLastCodeBlock(String markdown) {
    final RegExp fence = RegExp(r'```[^\n]*\n([\s\S]*?)```', multiLine: true);
    final Iterable<RegExpMatch> matches = fence.allMatches(markdown);
    if (matches.isEmpty) {
      // Still streaming: take everything after the last opening fence.
      final int open = markdown.lastIndexOf('```');
      if (open < 0) return null;
      final int newline = markdown.indexOf('\n', open);
      if (newline < 0) return null;
      final String tail = markdown.substring(newline + 1);
      return tail.trim().isEmpty ? null : tail;
    }
    return matches.last.group(1);
  }

  // -------------------------------------------------------------------- utils

  void _setStatus(HudStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  void _setBanner(String message, {required bool isError}) {
    _banner = message;
    _bannerIsError = isError;
    notifyListeners();

    _bannerTimer?.cancel();
    _bannerTimer = Timer(Duration(seconds: isError ? 8 : 3), () {
      if (_disposed) return;
      _banner = null;
      notifyListeners();
    });
  }

  void dismissBanner() {
    _bannerTimer?.cancel();
    _banner = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
    _bannerTimer?.cancel();
    _flushTimer?.cancel();
    _cancelActiveTurn();
    unawaited(_frameSub?.cancel());
    unawaited(_audioErrorSub?.cancel());
    unawaited(_disposeTranscriber());
    unawaited(audio.dispose());
    unawaited(hotkeys.unregisterAll());
    hotkeys.dispose();
    _current?.dispose();
    for (final AssistTurn turn in _history) {
      turn.dispose();
    }
    super.dispose();
  }
}
