import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/providers.dart';
import '../../../core/services/settings_service.dart';
import '../../hud/controllers/hud_controller.dart';
import 'model_picker.dart';
import 'settings_atoms.dart';

/// Audio sources, transcription backend, screenshot quality, permissions.
class CaptureTab extends ConsumerWidget {
  const CaptureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsController controller = ref.watch(settingsProvider);
    final HudController hud = ref.watch(hudControllerProvider);
    final XpSettings config = controller.value;

    void update(XpSettings Function(XpSettings) transform) =>
        controller.mutate(transform);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: <Widget>[
        if (!hud.hasScreenPermission) const _PermissionCard(),

        SettingsSection(
          title: 'AUDIO SOURCES',
          subtitle: 'Restart listening after changing these.',
          children: <Widget>[
            SettingsRow(
              label: 'Microphone',
              hint: 'What you say — used for context',
              controlWidth: 60,
              child: XpSwitch(
                value: config.micEnabled,
                onChanged: (bool v) =>
                    update((XpSettings s) => s.copyWith(micEnabled: v)),
              ),
            ),
            SettingsRow(
              label: 'System audio',
              hint: 'What the interviewer says — needs Screen Recording',
              controlWidth: 60,
              child: XpSwitch(
                value: config.systemAudioEnabled,
                onChanged: (bool v) =>
                    update((XpSettings s) => s.copyWith(systemAudioEnabled: v)),
              ),
            ),
            SettingsRow(
              label: 'Capture',
              hint: hud.isListening ? 'Running' : 'Paused',
              controlWidth: 110,
              child: XpButton(
                label: hud.isListening ? 'Restart' : 'Start',
                icon: Icons.refresh_rounded,
                onTap: () async {
                  await hud.stopListening();
                  await hud.startListening();
                },
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'TRANSCRIPTION',
          children: <Widget>[
            SettingsRow(
              label: 'Backend',
              hint: config.transcriptionBackend.name == 'geminiBatch'
                  ? 'One request per utterance — most reliable'
                  : 'Streaming',
              child: XpDropdown<TranscriptionBackend>(
                value: config.transcriptionBackend,
                items: TranscriptionBackend.values,
                labelOf: (TranscriptionBackend b) => b.label,
                onChanged: (TranscriptionBackend v) => update(
                  (XpSettings s) => s.copyWith(transcriptionBackend: v),
                ),
              ),
            ),
            SettingsRow(
              label: 'Transcribe my microphone too',
              hint: 'Doubles the request rate — leave off if you hit quota',
              controlWidth: 60,
              child: XpSwitch(
                value: config.transcribeMic,
                onChanged: (bool v) =>
                    update((XpSettings s) => s.copyWith(transcribeMic: v)),
              ),
            ),
            SettingsRow(
              label: 'Requests per minute',
              hint: 'Keep below your plan\'s limit so screen solves still fit',
              child: XpSlider(
                value: config.transcriptionRpm.toDouble(),
                min: 2,
                max: 60,
                divisions: 29,
                format: (double v) => '${v.round()}/min',
                onChanged: (double v) => update(
                  (XpSettings s) => s.copyWith(transcriptionRpm: v.round()),
                ),
              ),
            ),
            if (config.transcriptionBackend == TranscriptionBackend.geminiBatch)
              SettingsRow(
                label: 'Speech-to-text model',
                hint: 'A dedicated ASR model beats a general one on latency',
                controlWidth: 250,
                child: ModelPicker(
                  provider: ModelProvider.gemini,
                  value: config.geminiTranscribeModel,
                  apiKey: config.geminiApiKey,
                  fallback: XpSettings.geminiTranscribeChoices,
                  onChanged: (String v) => update(
                    (XpSettings s) => s.copyWith(geminiTranscribeModel: v),
                  ),
                ),
              ),
            if (config.transcriptionBackend == TranscriptionBackend.rivaNim)
              SettingsStack(
                label: 'Riva NIM base URL',
                hint: 'OpenAI-compatible /audio/transcriptions endpoint',
                child: XpTextField(
                  value: config.rivaBaseUrl,
                  monospace: true,
                  hintText: 'http://localhost:9000/v1',
                  onChanged: (String v) =>
                      update((XpSettings s) => s.copyWith(rivaBaseUrl: v)),
                ),
              ),
          ],
        ),

        SettingsSection(
          title: 'SCREEN CAPTURE',
          children: <Widget>[
            SettingsRow(
              label: 'What to capture',
              hint: 'Active window sends fewer tokens and answers faster',
              child: XpDropdown<CaptureMode>(
                value: config.captureMode,
                items: CaptureMode.values,
                labelOf: (CaptureMode m) => m.label,
                onChanged: (CaptureMode v) =>
                    update((XpSettings s) => s.copyWith(captureMode: v)),
              ),
            ),
            SettingsRow(
              label: 'Max width',
              hint: 'Smaller uploads faster; 1600px reads most code',
              child: XpSlider(
                value: config.captureMaxWidth.toDouble(),
                min: 800,
                max: 2560,
                divisions: 22,
                format: (double v) => '${v.round()}px',
                onChanged: (double v) => update(
                  (XpSettings s) => s.copyWith(captureMaxWidth: v.round()),
                ),
              ),
            ),
            SettingsRow(
              label: 'JPEG quality',
              child: XpSlider(
                value: config.captureQuality,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                format: (double v) => '${(v * 100).round()}%',
                onChanged: (double v) =>
                    update((XpSettings s) => s.copyWith(captureQuality: v)),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'HUD',
          children: <Widget>[
            SettingsRow(
              label: 'Opacity',
              hint: 'Lower blends the HUD into the desktop behind it',
              child: XpSlider(
                value: config.opacity,
                min: 0.2,
                max: 1.0,
                divisions: 16,
                format: (double v) => '${(v * 100).round()}%',
                onChanged: hud.setOpacity,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Screen Recording is the one permission that cannot be recovered without a
/// relaunch, so it gets a loud card rather than a toast.
class _PermissionCard extends ConsumerWidget {
  const _PermissionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: XpColors.statusThinking.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: XpColors.statusThinking.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.screen_share_outlined,
                size: 14,
                color: XpColors.statusThinking,
              ),
              const SizedBox(width: 7),
              Text(
                'Screen Recording permission required',
                style: XpType.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Both screen solving and system-audio capture need it. Enable xpass '
            'under Privacy & Security › Screen Recording, then relaunch — macOS '
            'only applies the grant on a fresh launch.',
            style: XpType.bodyMuted.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              XpButton(
                label: 'Request',
                icon: Icons.lock_open_rounded,
                onTap: () =>
                    ref.read(screenCaptureServiceProvider).requestPermission(),
              ),
              const SizedBox(width: 8),
              XpButton(
                label: 'Open Settings',
                icon: Icons.settings_outlined,
                tone: XpColors.panelRaised,
                onTap: () =>
                    ref.read(screenCaptureServiceProvider).openSystemSettings(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
