import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/providers.dart';
import '../../../core/services/settings_service.dart';
import 'model_picker.dart';
import 'settings_atoms.dart';

/// API keys, model selection and answer style.
class ModelsTab extends ConsumerWidget {
  const ModelsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsController controller = ref.watch(settingsProvider);
    final XpSettings config = controller.value;

    void update(XpSettings Function(XpSettings) transform) =>
        controller.mutate(transform);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: <Widget>[
        SettingsSection(
          title: 'API KEYS',
          subtitle:
              'Stored locally. A key exported in your environment or '
              'written to .env is picked up automatically.',
          children: <Widget>[
            SettingsStack(
              label: 'NVIDIA NIM key',
              hint: controller.nvidiaKeyFromEnv
                  ? 'Currently inherited from NVIDIA_API_KEY.'
                  : 'Used for the fast wingman and your profile answers.',
              child: XpTextField(
                value: config.nvidiaApiKey,
                obscure: true,
                hintText: 'nvapi-…',
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(nvidiaApiKey: v)),
              ),
            ),
            SettingsStack(
              label: 'Google Gemini key',
              hint: controller.geminiKeyFromEnv
                  ? 'Currently inherited from GEMINI_API_KEY.'
                  : 'Used for screen solving and transcription.',
              child: XpTextField(
                value: config.geminiApiKey,
                obscure: true,
                hintText: 'AIza…',
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(geminiApiKey: v)),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'MODELS',
          children: <Widget>[
            SettingsRow(
              label: 'Fast wingman',
              hint: 'Spoken questions, sub-second answers',
              controlWidth: 250,
              child: ModelPicker(
                provider: ModelProvider.nvidia,
                value: config.nimModel,
                apiKey: config.nvidiaApiKey,
                fallback: XpSettings.nimModelChoices,
                preferVision: false,
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(nimModel: v)),
              ),
            ),
            SettingsRow(
              label: 'Screen solver',
              hint: 'Multimodal reasoning over a screenshot',
              controlWidth: 250,
              child: ModelPicker(
                provider: ModelProvider.gemini,
                value: config.geminiFastModel,
                apiKey: config.geminiApiKey,
                fallback: XpSettings.geminiModelChoices,
                preferVision: true,
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(geminiFastModel: v)),
              ),
            ),
            SettingsRow(
              label: 'Deep reasoning model',
              hint: 'Used when Deep mode is on',
              controlWidth: 250,
              child: ModelPicker(
                provider: ModelProvider.gemini,
                value: config.geminiDeepModel,
                apiKey: config.geminiApiKey,
                fallback: XpSettings.geminiModelChoices,
                preferVision: true,
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(geminiDeepModel: v)),
              ),
            ),
            SettingsRow(
              label: 'Deep mode',
              hint: 'Slower and stronger. Leave off for timed rounds.',
              controlWidth: 60,
              child: XpSwitch(
                value: config.useDeepReasoning,
                onChanged: (bool v) =>
                    update((XpSettings s) => s.copyWith(useDeepReasoning: v)),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'ANSWER STYLE',
          children: <Widget>[
            SettingsRow(
              label: 'Code language',
              hint: 'What solutions are written in',
              child: XpDropdown<String>(
                value: config.codeLanguage,
                items: XpSettings.languageChoices,
                labelOf: (String l) => l,
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(codeLanguage: v)),
              ),
            ),
            SettingsRow(
              label: 'Answer questions about you from your profile',
              hint: 'Routes behavioural questions to your stored background',
              controlWidth: 60,
              child: XpSwitch(
                value: config.groundInProfile,
                onChanged: (bool v) =>
                    update((XpSettings s) => s.copyWith(groundInProfile: v)),
              ),
            ),
            SettingsRow(
              label: 'Answer automatically',
              hint: 'Reply as soon as the interviewer finishes a question',
              controlWidth: 60,
              child: XpSwitch(
                value: config.autoAnswer,
                onChanged: (bool v) =>
                    update((XpSettings s) => s.copyWith(autoAnswer: v)),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'PROMPT OVERRIDES',
          subtitle: 'Leave empty to use the tuned defaults.',
          children: <Widget>[
            SettingsStack(
              label: 'Wingman persona',
              child: XpTextField(
                value: config.fastPromptOverride,
                maxLines: 5,
                monospace: true,
                hintText: 'Custom system prompt for spoken questions…',
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(fastPromptOverride: v)),
              ),
            ),
            SettingsStack(
              label: 'Screen solver persona',
              child: XpTextField(
                value: config.deepPromptOverride,
                maxLines: 5,
                monospace: true,
                hintText: 'Custom system prompt for screen solves…',
                onChanged: (String v) =>
                    update((XpSettings s) => s.copyWith(deepPromptOverride: v)),
              ),
            ),
          ],
        ),

        Text(
          'xpass never uploads your keys, transcript or profile anywhere except '
          'directly to the model provider you configured.',
          style: XpType.bodyMuted.copyWith(
            fontSize: 11,
            color: XpColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
