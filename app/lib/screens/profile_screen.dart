// lib/screens/profile_screen.dart
// v1.1 Profile screen (Design System §6). Pushed page, no bottom nav.
import 'package:flutter/material.dart';

import '../analytics.dart';
import '../profile_store.dart';
import '../theme/concierge_theme.dart';

/// Country dropdown sentinel: let device location decide.
const _kAuto = 'Auto-detect (location)';

/// Markets we search offers/rates for. UAE-first, then the wider GCC + common
/// expat home countries.
const kCountries = <String>[
  'United Arab Emirates', 'Saudi Arabia', 'Qatar', 'Kuwait', 'Bahrain', 'Oman',
  'India', 'Pakistan', 'United Kingdom', 'United States', 'Singapore',
];

const kCurrencies = <String>[
  'AED', 'SAR', 'QAR', 'KWD', 'BHD', 'OMR', 'INR', 'PKR', 'GBP', 'USD', 'SGD',
];

const kEmploymentOptions = <String>[
  'Employed', 'Self-employed', 'Unemployed', 'Student', 'Retired',
];

const kIssueCategories = <String>[
  'Wallet', 'Card data', 'Offers', 'App issue', 'Suggestion', 'Other',
];

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
  late final _name = TextEditingController(text: widget.profile.name);
  late String _birthYear = widget.profile.birthYear;
  late String _employment = widget.profile.employment;
  bool _refreshing = false;

  // 18–90 year-olds; newest first.
  static final List<String> _birthYears = [
    for (var y = DateTime.now().year - 18; y >= DateTime.now().year - 90; y--)
      '$y'
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveDetails() async {
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty ||
        _birthYear.isEmpty ||
        _employment.isEmpty) {
      _snack('Please fill name, year of birth and employment.');
      return;
    }
    await widget.profile.saveDetails(
      name: _name.text,
      birthYear: _birthYear,
      employment: _employment,
    );
    if (!mounted) return;
    _snack('Saved');
  }

  Future<void> _openWriteToUs() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _WriteToUsSheet(),
    );
    if (sent == true && mounted) {
      _snack("Query submitted. We'll get in touch with you soon.",
          duration: const Duration(seconds: 5));
    }
  }

  void _snack(String msg, {Duration duration = const Duration(seconds: 2)}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ));
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
              _BackChip(
                  key: const Key('profile_back'),
                  onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              Text('Profile', style: t.textTheme.displaySmall),
            ],
          ),

          // PERSONAL DETAILS — stored locally only, deliberately non-PII.
          const _Eyebrow('PERSONAL DETAILS'),
          _SurfaceCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LabeledField(
                      label: 'Name',
                      child: TextField(
                        key: const Key('profile_name_field'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        style: t.textTheme.bodyMedium,
                        decoration:
                            const InputDecoration(hintText: 'e.g. Prasad'),
                      ),
                    ),
                    _LabeledField(
                      label: 'Year of birth',
                      child: _FieldDropdown(
                        key: const Key('profile_birthyear_field'),
                        hint: 'Select year',
                        value: _birthYear.isEmpty ? null : _birthYear,
                        options: _birthYears,
                        onChanged: (v) => setState(() => _birthYear = v),
                      ),
                    ),
                    _LabeledField(
                      label: 'Employment',
                      child: _FieldDropdown(
                        key: const Key('profile_employment_field'),
                        hint: 'Select status',
                        value: _employment.isEmpty ? null : _employment,
                        options: kEmploymentOptions,
                        onChanged: (v) => setState(() => _employment = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // REGION — sharpens offer/rate searches to your market.
          const _Eyebrow('REGION'),
          AnimatedBuilder(
            animation: widget.profile,
            builder: (context, _) {
              final country = widget.profile.country;
              // 'Auto-detect' == let location decide; include any detected
              // country not already in the fixed list so it still displays.
              final countryOptions = <String>[
                _kAuto,
                if (country.isNotEmpty && !kCountries.contains(country)) country,
                ...kCountries,
              ];
              return _SurfaceCard(
                children: [
                  _DropdownRow(
                    title: 'Country',
                    value: country.isEmpty ? _kAuto : country,
                    options: countryOptions,
                    onChanged: (v) => v == _kAuto
                        ? widget.profile.clearCountry()
                        : widget.profile.setCountry(v),
                  ),
                  const _InsetDivider(),
                  _DropdownRow(
                    title: 'Primary currency',
                    value: widget.profile.currency,
                    options: kCurrencies,
                    onChanged: (v) => widget.profile.setCurrency(v),
                  ),
                ],
              );
            },
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
                  title: 'Opt out of search history',
                  description:
                      'Recent searches appear under the search bar for quick '
                      'access, stored on this device only.',
                  value: !widget.profile.searchHistoryEnabled,
                  onChanged: (v) => widget.profile.setSearchHistoryEnabled(!v),
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

          // PRIVACY — opt-out framing; spell out exactly what's collected.
          const _Eyebrow('PRIVACY'),
          _SurfaceCard(
            children: [
              AnimatedBuilder(
                animation: widget.analytics,
                builder: (context, _) => _SwitchRow(
                  switchKey: const Key('analytics_toggle'),
                  title: 'Opt out of usage insights',
                  description:
                      'We use app usage insights to improve your experience. '
                      'Strictly no personal information is collected.',
                  value: !widget.analytics.enabled,
                  onChanged: (v) => widget.analytics.setEnabled(!v),
                ),
              ),
            ],
          ),

          // SUPPORT
          const _Eyebrow('SUPPORT'),
          _SurfaceCard(
            children: [
              _ActionRow(
                title: 'Write to us',
                subtitle: 'Report an issue or send a suggestion',
                onTap: _openWriteToUs,
              ),
            ],
          ),

          // Save (applies to Personal details).
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('save_profile'),
              onPressed: _saveDetails,
              child: const Text('Save'),
            ),
          ),

          // Footer
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Text('ToroKard 1.0.0',
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
  const _BackChip({super.key, required this.onTap});

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

/// A small caption label above a form field.
class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 2),
            child: Text(label,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          child,
        ],
      ),
    );
  }
}

/// Dropdown styled like the text fields (uses the input decoration theme).
class _FieldDropdown extends StatelessWidget {
  final String hint;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _FieldDropdown({
    super.key,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      hint: Text(hint, style: t.textTheme.bodyMedium),
      style: t.textTheme.bodyMedium,
      items: [
        for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
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

class _DropdownRow extends StatelessWidget {
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _DropdownRow({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(title, style: t.textTheme.titleSmall)),
            const SizedBox(width: 12),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.contains(value) ? value : null,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(Icons.expand_more,
                    size: 18, color: scheme.onSurfaceVariant),
                style: t.textTheme.titleSmall?.copyWith(color: scheme.primary),
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o, child: Text(o)),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// "Write to us" form: category + message (<=512) + email. Submit is a
/// placeholder for now — nothing is sent; we just confirm receipt.
class _WriteToUsSheet extends StatefulWidget {
  const _WriteToUsSheet();

  @override
  State<_WriteToUsSheet> createState() => _WriteToUsSheetState();
}

class _WriteToUsSheetState extends State<_WriteToUsSheet> {
  String? _category;
  final _message = TextEditingController();
  final _email = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _validEmail {
    final e = _email.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);
  }

  Future<void> _submit() async {
    if (_category == null ||
        _message.text.trim().isEmpty ||
        !_validEmail) {
      setState(() => _error = 'Pick a category, write a message, and add a '
          'valid email.');
      return;
    }
    setState(() => _sending = true);
    // TODO: wire to the backend / email. Placeholder for now.
    await _submitFeedback(
        category: _category!,
        message: _message.text.trim(),
        email: _email.text.trim());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _submitFeedback({
    required String category,
    required String message,
    required String email,
  }) async {
    // Intentionally does nothing yet — a real endpoint slots in here later.
    return;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.outline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Write to us', style: GoogleFontsSafeTitle.of(t)),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Category',
              child: _FieldDropdown(
                hint: 'Select a category',
                value: _category,
                options: kIssueCategories,
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
            _LabeledField(
              label: 'Message',
              child: TextField(
                controller: _message,
                maxLength: 512,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: t.textTheme.bodyMedium,
                decoration:
                    const InputDecoration(hintText: 'How can we help?'),
              ),
            ),
            _LabeledField(
              label: 'Email',
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: t.textTheme.bodyMedium,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: t.textTheme.bodySmall?.copyWith(color: scheme.error)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('submit_feedback'),
              onPressed: _sending ? null : _submit,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Serif title style helper for sheets.
class GoogleFontsSafeTitle {
  static TextStyle of(ThemeData t) =>
      (t.textTheme.displaySmall ?? const TextStyle())
          .copyWith(fontSize: 20, fontWeight: FontWeight.w500);
}
