import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/providers.dart';
import 'widgets/capture_tab.dart';
import 'widgets/models_tab.dart';
import 'widgets/profile_tab.dart';
import 'widgets/shortcuts_tab.dart';

enum _Tab {
  models('Models', Icons.hub_outlined),
  capture('Capture', Icons.graphic_eq_rounded),
  profile('You', Icons.person_outline_rounded),
  shortcuts('Keys', Icons.keyboard_outlined);

  const _Tab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Settings, rendered inside the HUD rather than in a separate window — a
/// second window would be visible to screen sharing.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  _Tab _tab = _Tab.models;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: XpColors.border)),
          ),
          child: Row(
            children: <Widget>[
              for (final _Tab tab in _Tab.values)
                _TabButton(
                  tab: tab,
                  selected: tab == _tab,
                  onTap: () => setState(() => _tab = tab),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: ref.read(hudControllerProvider).closeSettings,
                icon: const Icon(Icons.check_rounded, size: 13),
                label: Text('Done', style: XpType.label),
                style: TextButton.styleFrom(
                  foregroundColor: XpColors.accentHover,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 26),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            _Tab.models => const ModelsTab(),
            _Tab.capture => const CaptureTab(),
            _Tab.profile => const ProfileTab(),
            _Tab.shortcuts => const ShortcutsTab(),
          },
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? XpColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              tab.icon,
              size: 12,
              color: selected ? XpColors.accentHover : XpColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              tab.label,
              style: XpType.label.copyWith(
                color: selected ? XpColors.textPrimary : XpColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
