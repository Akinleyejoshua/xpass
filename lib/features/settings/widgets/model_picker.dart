import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/assist_models.dart';
import '../../../core/services/model_catalog_service.dart';
import 'settings_atoms.dart';

/// Which provider a picker lists.
enum ModelProvider { nvidia, gemini }

/// Live model catalogue, fetched once per provider per session.
///
/// Hardcoding model ids goes stale fast, so the pickers read the provider's own
/// list. Until it loads — or if it fails — the static fallback keeps the picker
/// usable instead of leaving the user with an empty dropdown.
class ModelCatalogNotifier extends ChangeNotifier {
  ModelCatalogNotifier(this._service);

  final ModelCatalogService _service;

  final Map<ModelProvider, List<ModelInfo>> _models =
      <ModelProvider, List<ModelInfo>>{};
  final Map<ModelProvider, String> _errors = <ModelProvider, String>{};
  final Set<ModelProvider> _loading = <ModelProvider>{};

  List<ModelInfo> modelsFor(ModelProvider provider) =>
      _models[provider] ?? const <ModelInfo>[];

  String? errorFor(ModelProvider provider) => _errors[provider];

  bool isLoading(ModelProvider provider) => _loading.contains(provider);

  bool hasLoaded(ModelProvider provider) => _models.containsKey(provider);

  Future<void> load(
    ModelProvider provider, {
    required String apiKey,
    bool force = false,
  }) async {
    if (_loading.contains(provider)) return;
    if (!force && _models.containsKey(provider)) return;

    _loading.add(provider);
    _errors.remove(provider);
    notifyListeners();

    try {
      _models[provider] = switch (provider) {
        ModelProvider.gemini => await _service.fetchGeminiModels(
          apiKey: apiKey,
        ),
        ModelProvider.nvidia => await _service.fetchNimModels(apiKey: apiKey),
      };
    } on AiServiceException catch (error) {
      _errors[provider] = error.message;
    } catch (error) {
      _errors[provider] = error.toString();
    } finally {
      _loading.remove(provider);
      notifyListeners();
    }
  }
}

final Provider<ModelCatalogService> modelCatalogServiceProvider =
    Provider<ModelCatalogService>((Ref ref) => ModelCatalogService());

final ChangeNotifierProvider<ModelCatalogNotifier> modelCatalogProvider =
    ChangeNotifierProvider<ModelCatalogNotifier>(
      (Ref ref) => ModelCatalogNotifier(ref.watch(modelCatalogServiceProvider)),
    );

/// A model dropdown backed by the provider's live catalogue.
class ModelPicker extends ConsumerStatefulWidget {
  const ModelPicker({
    super.key,
    required this.provider,
    required this.value,
    required this.onChanged,
    required this.fallback,
    this.apiKey = '',
    this.preferVision = false,
  });

  final ModelProvider provider;
  final String value;
  final ValueChanged<String> onChanged;

  /// Used before the catalogue loads, and if the request fails.
  final List<String> fallback;
  final String apiKey;

  /// Sorts image-capable models first, for the screen solver. Nothing is
  /// hidden — the provider's full catalogue stays selectable.
  final bool preferVision;

  @override
  ConsumerState<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends ConsumerState<ModelPicker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfPossible());
  }

  void _loadIfPossible({bool force = false}) {
    if (widget.apiKey.trim().isEmpty) return;
    ref
        .read(modelCatalogProvider)
        .load(widget.provider, apiKey: widget.apiKey, force: force);
  }

  @override
  Widget build(BuildContext context) {
    final ModelCatalogNotifier catalog = ref.watch(modelCatalogProvider);
    final List<ModelInfo> fetched = catalog.modelsFor(widget.provider);

    // Everything the provider returns stays selectable; nothing is hidden.
    List<ModelInfo> available = fetched.isEmpty
        ? widget.fallback
              .map((String id) => ModelInfo(id: id, displayName: ''))
              .toList()
        : List<ModelInfo>.from(fetched);

    if (widget.preferVision && fetched.isNotEmpty) {
      // Float the models that can actually read a screenshot to the top,
      // rather than removing the rest from the list.
      available = <ModelInfo>[
        ...available.where((ModelInfo m) => m.supportsVision),
        ...available.where((ModelInfo m) => !m.supportsVision),
      ];
    }

    // The saved model must always remain selectable, even if the provider has
    // since retired it — otherwise opening Settings would silently change it.
    final List<ModelInfo> items = <ModelInfo>[
      if (!available.any((ModelInfo m) => m.id == widget.value))
        ModelInfo(id: widget.value, displayName: ''),
      ...available,
    ];

    final bool loading = catalog.isLoading(widget.provider);
    final String? error = catalog.errorFor(widget.provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: XpDropdown<ModelInfo>(
                value: items.firstWhere(
                  (ModelInfo m) => m.id == widget.value,
                  orElse: () => items.first,
                ),
                items: items,
                labelOf: (ModelInfo m) => m.label,
                onChanged: (ModelInfo m) => widget.onChanged(m.id),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  widget.provider == ModelProvider.gemini &&
                      widget.apiKey.trim().isEmpty
                  ? 'Add a Gemini API key to load the live model list'
                  : 'Reload the model list',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _loadIfPossible(force: true),
                child: SizedBox(
                  width: 26,
                  height: 30,
                  child: loading
                      ? const Center(
                          child: SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: XpColors.accentHover,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: XpColors.textSecondary,
                        ),
                ),
              ),
            ),
          ],
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            error,
            style: XpType.metric.copyWith(
              fontSize: 9,
              color: XpColors.statusMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ] else if (fetched.isNotEmpty) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            '${available.length} live from the API',
            style: XpType.metric.copyWith(fontSize: 9),
          ),
        ],
      ],
    );
  }
}
