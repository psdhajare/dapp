// lib/screens/profile_screen.dart
// v1.1 Profile screen (Design System §6). Pushed page, no bottom nav.
import 'package:flutter/material.dart';

import '../analytics.dart';
import '../profile_store.dart';
import '../theme/concierge_theme.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileStore profile;
  final Analytics analytics;
  final Future<void> Function() onRefreshCardData;
  final Future<void> Function() onRemoveAllCards;
  final String? lastUpdatedLabel;

  const ProfileScreen({
    super.key,
    required this.profile,
    required this.analytics,
    required this.onRefreshCardData,
    required this.onRemoveAllCards,
    this.lastUpdatedLabel,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.name);
  final _nameFocus = FocusNode();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Auto-save on blur (in addition to onChanged).
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) widget.profile.setName(_name.text);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefreshCardData();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _confirmRemoveAll() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => const _RemoveAllSheet(),
    );
    if (confirmed == true) await widget.onRemoveAllCards();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          // Header row: 36px tonal back chip + serif title inline, gap 12.
          Row(
            children: [
              _BackChip(onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              Text('Profile', style: t.textTheme.displaySmall),
            ],
          ),

          // YOUR NAME
          const _Eyebrow('YOUR NAME'),
          TextField(
            key: const Key('profile_name_field'),
            controller: _name,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.done,
            style: t.textTheme.bodyMedium,
            decoration: const InputDecoration(hintText: 'e.g. Prasad'),
            onChanged: widget.profile.setName,
            onSubmitted: widget.profile.setName,
          ),

          // APPEARANCE
          const _Eyebrow('APPEARANCE'),
          AnimatedBuilder(
            animation: widget.profile,
            builder: (context, _) => _SegmentedTheme(
              value: widget.profile.themeMode,
              onChanged: widget.profile.setThemeMode,
            ),
          ),

          // SEARCH
          const _Eyebrow('SEARCH'),
          _SurfaceCard(
            children: [
              AnimatedBuilder(
                animation: widget.profile,
                builder: (context, _) => _SwitchRow(
                  title: 'Save recent searches',
                  description:
                      'Show your last 10 searches under the search bar.',
                  value: widget.profile.searchHistoryEnabled,
                  onChanged: widget.profile.setSearchHistoryEnabled,
                ),
              ),
              const _InsetDivider(),
              _ActionRow(
                title: 'Clear search history',
                titleColor: scheme.primary,
                onTap: widget.profile.clearSearchHistory,
              ),
            ],
          ),

          // PRIVACY
          const _Eyebrow('PRIVACY'),
          _SurfaceCard(
            children: [
              AnimatedBuilder(
                animation: widget.analytics,
                builder: (context, _) => _SwitchRow(
                  switchKey: const Key('analytics_toggle'),
                  title: 'Share anonymous usage',
                  description:
                      'Anonymous counts only — no names, cards, or amounts. '
                      'Helps improve the app.',
                  value: widget.analytics.enabled,
                  onChanged: widget.analytics.setEnabled,
                ),
              ),
            ],
          ),

          // DATA
          const _Eyebrow('DATA'),
          _SurfaceCard(
            children: [
              _ActionRow(
                title: 'Refresh card data',
                subtitle: widget.lastUpdatedLabel,
                trailing: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _refreshing ? null : _refresh,
              ),
              const _InsetDivider(),
              _ActionRow(
                title: 'Remove all cards',
                titleColor: scheme.error,
                onTap: _confirmRemoveAll,
              ),
            ],
          ),

          // Footer
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Text('Best Card 1.0.0',
                    style: t.textTheme.labelSmall?.copyWith(letterSpacing: 0)),
                const SizedBox(height: 4),
                Text('All data stays on this device.',
                    style: t.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header back chip
// ---------------------------------------------------------------------------

class _BackChip extends StatelessWidget {
  final VoidCallback onTap;
  const _BackChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Back',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.chevron_left,
              size: 22, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Eyebrow (labelSmall caps, margin 22/0/8)
// ---------------------------------------------------------------------------

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance segmented control (radius 12 inside 16, padding 4)
// ---------------------------------------------------------------------------

class _SegmentedTheme extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;
  const _SegmentedTheme({required this.value, required this.onChanged});

  static const _segments = <(ThemeMode, String, IconData)>[
    (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (i, seg) in _segments.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                label: seg.$2,
                icon: seg.$3,
                selected: value == seg.$1,
                onTap: () => onChanged(seg.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: ConciergeMotion.chip, // 180ms
            curve: Curves.easeOut,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: ConciergeMotion.chip,
                  style: t.textTheme.labelMedium!
                      .copyWith(fontSize: 11.5, color: fg),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Surface card (radius 16, soft tile shadow) holding stacked rows
// ---------------------------------------------------------------------------

class _SurfaceCard extends StatelessWidget {
  final List<Widget> children;
  const _SurfaceCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : const Color(0xFF272219))
                .withValues(alpha: dark ? 0.8 : 0.5),
            blurRadius: 18,
            spreadRadius: -14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Inset 1px hairline, 16px side margins.
class _InsetDivider extends StatelessWidget {
  const _InsetDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

// ---------------------------------------------------------------------------
// Rows (all ≥48px)
// ---------------------------------------------------------------------------

class _SwitchRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;
  const _SwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.switchKey = const Key('search_history_toggle'),
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _ActionRow({
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title,
                          style: t.textTheme.titleSmall
                              ?.copyWith(color: titleColor)),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: t.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing ??
                    Icon(Icons.chevron_right,
                        size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Destructive confirmation sheet (iOS-style)
// ---------------------------------------------------------------------------

class _RemoveAllSheet extends StatelessWidget {
  const _RemoveAllSheet();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('CARDS', style: t.textTheme.labelSmall),
            const SizedBox(height: 12),
            Text(
              'This removes every card from your wallet. You can add them again anytime.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('confirm_remove_all'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove all cards'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel',
                    style: t.textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurface)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
