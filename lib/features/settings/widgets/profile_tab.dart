import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/profile_models.dart';
import '../../../core/providers.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/settings_service.dart';
import 'settings_atoms.dart';

/// The user's own background — what "You" mode answers from.
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  bool _importing = false;
  String _resumeDraft = '';

  @override
  Widget build(BuildContext context) {
    final ProfileService service = ref.watch(profileProvider);
    final SettingsController settings = ref.watch(settingsProvider);
    final UserProfile profile = service.profile;

    void updateProfile(UserProfile Function(UserProfile) transform) =>
        service.mutate(transform);

    final Map<ProfileEntryKind, int> counts = <ProfileEntryKind, int>{};
    for (final ProfileEntry entry in profile.entries) {
      if (entry.isEmpty) continue;
      counts[entry.kind] = (counts[entry.kind] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: <Widget>[
        _ProfileSummaryCard(counts: counts, profile: profile),

        SettingsSection(
          title: 'IMPORT',
          subtitle:
              'Pulls /api/about, /api/experience and /api/projects from '
              'your portfolio. Your written answers below are never overwritten.',
          children: <Widget>[
            SettingsStack(
              label: 'Portfolio URL',
              child: XpTextField(
                value: settings.value.portfolioUrl,
                monospace: true,
                hintText: 'https://your-portfolio.example',
                onChanged: (String v) => settings.mutate(
                  (XpSettings s) => s.copyWith(portfolioUrl: v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: <Widget>[
                  XpButton(
                    label: _importing ? 'Importing…' : 'Import now',
                    icon: Icons.cloud_download_outlined,
                    busy: _importing,
                    onTap: () async {
                      setState(() => _importing = true);
                      await ref
                          .read(hudControllerProvider)
                          .importProfile(settings.value.portfolioUrl);
                      if (mounted) setState(() => _importing = false);
                    },
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      service.storagePath,
                      style: XpType.metric.copyWith(fontSize: 9),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'IDENTITY',
          children: <Widget>[
            SettingsRow(
              label: 'Name',
              child: XpTextField(
                value: profile.name,
                hintText: 'Your name',
                onChanged: (String v) =>
                    updateProfile((UserProfile p) => p.copyWith(name: v)),
              ),
            ),
            SettingsRow(
              label: 'Headline',
              hint: 'Role and focus, one line',
              child: XpTextField(
                value: profile.headline,
                hintText: 'Senior Backend Engineer · Distributed systems',
                onChanged: (String v) =>
                    updateProfile((UserProfile p) => p.copyWith(headline: v)),
              ),
            ),
            SettingsRow(
              label: 'Years of experience',
              child: XpTextField(
                value: profile.yearsExperience,
                hintText: '6+ years',
                onChanged: (String v) => updateProfile(
                  (UserProfile p) => p.copyWith(yearsExperience: v),
                ),
              ),
            ),
            SettingsRow(
              label: 'Location',
              child: XpTextField(
                value: profile.location,
                hintText: 'Remote',
                onChanged: (String v) =>
                    updateProfile((UserProfile p) => p.copyWith(location: v)),
              ),
            ),
            SettingsStack(
              label: 'Positioning',
              hint: 'Your "tell me about yourself" in your own words.',
              child: XpTextField(
                value: profile.summary,
                maxLines: 6,
                hintText: 'I build…',
                onChanged: (String v) =>
                    updateProfile((UserProfile p) => p.copyWith(summary: v)),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'PREPARED ANSWERS',
          subtitle:
              'An answer you write here is used verbatim as the basis for '
              'that question. Blank ones fall back to your experience entries.',
          children: <Widget>[
            for (final ProfileEntry entry in profile.entries.where(
              (ProfileEntry e) => e.kind == ProfileEntryKind.question,
            ))
              _PreparedAnswerRow(
                entry: entry,
                onChanged: (String answer) => updateProfile(
                  (UserProfile p) => p.copyWith(
                    entries: p.entries
                        .map(
                          (ProfileEntry e) => e.id == entry.id
                              ? e.copyWith(summary: answer)
                              : e,
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        ),

        SettingsSection(
          title: 'PASTE A RÉSUMÉ',
          subtitle:
              'Markdown headings become entries; bullets become talking '
              'points. Merged with what you already have.',
          children: <Widget>[
            SettingsStack(
              label: 'Résumé text',
              child: XpTextField(
                value: _resumeDraft,
                maxLines: 8,
                monospace: true,
                hintText:
                    '## Experience\n### Senior Engineer, Acme (2022–now)\n'
                    '- Cut p99 latency from 900ms to 120ms',
                onChanged: (String v) => _resumeDraft = v,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Align(
                alignment: Alignment.centerLeft,
                child: XpButton(
                  label: 'Parse and merge',
                  icon: Icons.playlist_add_rounded,
                  onTap: () {
                    if (_resumeDraft.trim().isEmpty) return;
                    service.save(
                      ProfileService.parseMarkdownResume(
                        _resumeDraft,
                        base: profile,
                      ),
                    );
                    setState(() => _resumeDraft = '');
                  },
                ),
              ),
            ),
          ],
        ),

        SettingsSection(
          title: 'STORED FACTS',
          subtitle: 'Everything xpass can retrieve when answering about you.',
          children: <Widget>[
            for (final ProfileEntry entry in profile.entries.where(
              (ProfileEntry e) =>
                  e.kind != ProfileEntryKind.question && !e.isEmpty,
            ))
              _FactRow(
                entry: entry,
                onDelete: () => updateProfile(
                  (UserProfile p) => p.copyWith(
                    entries: p.entries
                        .where((ProfileEntry e) => e.id != entry.id)
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({required this.counts, required this.profile});

  final Map<ProfileEntryKind, int> counts;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final int total = counts.values.fold(0, (int a, int b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: XpColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: XpColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            profile.name.isEmpty ? 'Your profile' : profile.name,
            style: XpType.verbal.copyWith(fontSize: 14),
          ),
          if (profile.headline.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              profile.headline,
              style: XpType.bodyMuted.copyWith(fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _CountChip(
                label: 'FACTS',
                value: total,
                tone: XpColors.accentHover,
              ),
              for (final MapEntry<ProfileEntryKind, int> entry
                  in counts.entries)
                _CountChip(
                  label: entry.key.label.toUpperCase(),
                  value: entry.value,
                  tone: XpColors.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Ask anything in "You" mode, or let xpass answer behavioural '
            'questions automatically when it hears one.',
            style: XpType.bodyMuted.copyWith(
              fontSize: 11,
              color: XpColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final int value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: XpColors.panel,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: XpColors.border),
      ),
      child: Text('$value $label', style: XpType.label.copyWith(color: tone)),
    );
  }
}

class _PreparedAnswerRow extends StatelessWidget {
  const _PreparedAnswerRow({required this.entry, required this.onChanged});

  final ProfileEntry entry;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool answered = entry.summary.trim().isNotEmpty;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 11),
        childrenPadding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
        dense: true,
        visualDensity: VisualDensity.compact,
        iconColor: XpColors.textSecondary,
        collapsedIconColor: XpColors.textTertiary,
        title: Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: answered ? XpColors.statusLive : XpColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.title,
                style: XpType.body.copyWith(fontSize: 12.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: <Widget>[
          XpTextField(
            value: entry.summary,
            maxLines: 5,
            hintText: 'Your answer, in your own voice…',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.entry, required this.onDelete});

  final ProfileEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String subtitle = <String>[
      entry.organization,
      entry.period,
    ].where((String s) => s.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: XpColors.panelRaised,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: XpColors.border),
            ),
            child: Text(
              entry.kind.label.toUpperCase(),
              style: XpType.label.copyWith(fontSize: 8),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.title,
                  style: XpType.body.copyWith(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: XpType.bodyMuted.copyWith(
                      fontSize: 10.5,
                      color: XpColors.textTertiary,
                    ),
                  ),
                if (entry.bullets.isNotEmpty)
                  Text(
                    '${entry.bullets.length} talking point'
                    '${entry.bullets.length == 1 ? '' : 's'}',
                    style: XpType.metric.copyWith(fontSize: 9),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 13),
            color: XpColors.textTertiary,
            splashRadius: 12,
            tooltip: 'Remove',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
