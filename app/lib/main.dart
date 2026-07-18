import 'dart:ui' as ui;

import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app_db.dart';
import 'dao.dart';
import 'ingest_service.dart';
import 'profile_store.dart';
import 'theme/concierge_theme.dart';
import 'venue.dart';

/// Returns current position as (lat, lng).
typedef LocationFn = Future<(double, double)> Function();

Future<(double, double)> _deviceLocation() async {
  await Geolocator.requestPermission();
  final pos = await Geolocator.getCurrentPosition();
  return (pos.latitude, pos.longitude);
}

/// Simulation shortcuts: venue kind -> (icon, canonical category).
const simulations = <String, (IconData, String)>{
  'Restaurant': (Icons.restaurant_outlined, 'dining'),
  'Supermarket': (Icons.local_grocery_store_outlined, 'grocery'),
  'Fuel': (Icons.local_gas_station_outlined, 'fuel'),
  'Cinema': (Icons.movie_outlined, 'entertainment'),
  'Online': (Icons.shopping_bag_outlined, 'online'),
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const apiKey = String.fromEnvironment('PLACES_API_KEY');

  final DatabaseFactory factory;
  if (kIsWeb) {
    factory = databaseFactoryFfiWeb;
  } else {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  }
  final db = await openAppDb(factory);
  final dao = CardDao(db);
  final poiMap = await dao.loadPoiMap();
  final venue = VenueCategoryService(
    lookup: GooglePlacesLookup(apiKey: apiKey),
    poiMap: poiMap,
  );
  final ingest = IngestService(
    endpoint: Uri.parse(const String.fromEnvironment(
      'INGEST_URL',
      defaultValue: 'http://127.0.0.1:8765/ingest',
    )),
  );
  final profile = await ProfileStore.load();

  runApp(BestCardApp(
    dao: dao,
    venue: venue,
    locationFn: _deviceLocation,
    ingest: ingest,
    profile: profile,
  ));
}

class BestCardApp extends StatelessWidget {
  final CardDao dao;
  final VenueCategoryService venue;
  final LocationFn locationFn;
  final IngestService? ingest;
  final ProfileStore profile;

  const BestCardApp({
    super.key,
    required this.dao,
    required this.venue,
    required this.locationFn,
    required this.profile,
    this.ingest,
  });

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp when the theme preference changes.
    return AnimatedBuilder(
      animation: profile,
      builder: (context, _) => MaterialApp(
        title: 'Best Card',
        debugShowCheckedModeBanner: false,
        theme: conciergeTheme(Brightness.light),
        darkTheme: conciergeTheme(Brightness.dark),
        themeMode: profile.themeMode,
        home: RootScreen(
            dao: dao,
            venue: venue,
            locationFn: locationFn,
            ingest: ingest,
            profile: profile),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  final CardDao dao;
  final VenueCategoryService venue;
  final LocationFn locationFn;
  final IngestService? ingest;
  final ProfileStore profile;

  const RootScreen({
    super.key,
    required this.dao,
    required this.venue,
    required this.locationFn,
    required this.profile,
    this.ingest,
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tab = 0;
  final _recommendKey = GlobalKey<_RecommendTabState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: ConciergeMotion.rerank,
          switchInCurve: Curves.easeOutQuart,
          switchOutCurve: Curves.easeOutQuart,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _tab == 0
              ? RecommendTab(
                  key: _recommendKey,
                  dao: widget.dao,
                  venue: widget.venue,
                  locationFn: widget.locationFn,
                  profile: widget.profile,
                )
              : WalletTab(
                  dao: widget.dao,
                  ingest: widget.ingest,
                  onWalletChanged: () =>
                      _recommendKey.currentState?.refreshAfterWalletChange(),
                ),
        ),
      ),
      bottomNavigationBar:
          _BlurNav(tab: _tab, onSelect: (i) => setState(() => _tab = i)),
    );
  }
}

/// Bottom nav on a blur with a hairline top edge (no M3 indicator pill).
class _BlurNav extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onSelect;
  const _BlurNav({required this.tab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final x = Theme.of(context).extension<ConciergeColors>()!;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: x.navFill,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: onSelect,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.style_outlined),
                selectedIcon: Icon(Icons.style),
                label: 'Best card',
              ),
              NavigationDestination(
                key: Key('wallet_button'),
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Wallet',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Best card tab
// ===========================================================================

class _Ranked {
  final CardInfo card;
  final Recommendation rec;
  _Ranked(this.card, this.rec);
}

class _Result {
  final String category;
  final List<_Ranked> ranked; // best first, up to 3
  final List<(String label, MinSpendHint hint)> hints;
  final List<OfferInfo> offers;
  _Result(this.category, this.ranked, this.hints, this.offers);

  _Ranked get winner => ranked.first;
}

class RecommendTab extends StatefulWidget {
  final CardDao dao;
  final VenueCategoryService venue;
  final LocationFn locationFn;
  final ProfileStore profile;

  const RecommendTab({
    super.key,
    required this.dao,
    required this.venue,
    required this.locationFn,
    required this.profile,
  });

  @override
  State<RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends State<RecommendTab> {
  String? _selected; // simulation label or 'location'; null = everyday spend
  String? _status;
  _Result? _result;
  bool _loading = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recommend('general'));
  }

  Future<void> refreshAfterWalletChange() async {
    await _recommend(_result?.category ?? 'general');
  }

  Future<void> _useLocation() async {
    setState(() {
      _selected = 'location';
      _loading = true;
      _locating = true;
      _status = 'Finding where you are…';
      _result = null;
    });
    try {
      final (lat, lng) = await widget.locationFn();
      final category = await widget.venue.categoryAt(lat, lng) ?? 'general';
      await _recommend(category);
    } catch (e) {
      setState(() => _status = 'Location unavailable. Pick a place above.');
    } finally {
      setState(() {
        _loading = false;
        _locating = false;
      });
    }
  }

  Future<void> _simulate(String label, String category) async {
    setState(() {
      _selected = label;
      _loading = true;
      _result = null;
    });
    try {
      await _recommend(category);
    } catch (e) {
      setState(() => _status = 'Something went wrong. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _recommend(String category) async {
    final cards = await widget.dao.loadUserCards();
    final recs = rankCards(category, cards);
    if (recs.isEmpty) {
      setState(() {
        _status = 'No card in your wallet covers $category yet.';
        _result = null;
      });
      return;
    }
    final all = await widget.dao.allCards();
    final ranked = [
      for (final rec in recs.take(3))
        _Ranked(all.firstWhere((c) => c.id == rec.cardId), rec),
    ];
    final hints = <(String, MinSpendHint)>[];
    for (final h in recs.first.hints) {
      hints.add((await widget.dao.cardLabel(h.cardId), h));
    }
    final offers = await widget.dao.offersForCategory(category);
    setState(() {
      _status = null;
      _result = _Result(category, ranked, hints, offers);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final r = _result;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            AnimatedBuilder(
              animation: widget.profile,
              builder: (context, _) => Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Best card', style: t.textTheme.displaySmall),
                        const SizedBox(height: 2),
                        Text(
                            widget.profile.name.isEmpty
                                ? 'Where are you paying?'
                                : 'Where are you paying, ${widget.profile.name}?',
                            style: t.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  _ProfileButton(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(profile: widget.profile))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _VenueChips(
              selected: _selected,
              enabled: !_loading,
              onSelect: _simulate,
            ),
            const SizedBox(height: 22),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2.4),
                      if (_status != null) ...[
                        const SizedBox(height: 16),
                        Text(_status!,
                            style: t.textTheme.titleMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              )
            else if (r == null)
              _EmptyCategory(
                  category: _labelFor(_selected, 'general'), status: _status)
            else ...[
              _Reveal(
                order: 0,
                child: Text(
                  _selected == null
                      ? 'Best for everyday spend'
                      : 'Best for ${r.category}',
                  style: t.textTheme.titleMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 14),
              _Reveal(
                order: 1,
                child: _RankedDeck(ranked: r.ranked, category: r.category),
              ),
              if (r.winner.rec.hasCap)
                _Reveal(
                  order: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _InfoPill(
                      key: const Key('cap_flag'),
                      kind: _PillKind.cap,
                      text:
                          'Rewards cap: ${_fmtAmount(r.winner.rec.capAmount!)} per ${_period(r.winner.rec.capPeriod)}',
                    ),
                  ),
                ),
              for (final (label, hint) in r.hints)
                _Reveal(
                  order: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _InfoPill(
                      key: const Key('min_spend_hint'),
                      kind: _PillKind.hint,
                      text:
                          '$label hits ${(hint.effectiveRate * 100).toStringAsFixed(2)}% on ${r.category} once monthly spend reaches ${_fmtAmount(hint.minSpend)}',
                    ),
                  ),
                ),
              if (r.offers.isNotEmpty) ...[
                const SizedBox(height: 30),
                _Reveal(
                  order: 4,
                  child: Text('PERKS FOR ${r.category.toUpperCase()}',
                      style: t.textTheme.labelSmall),
                ),
                const SizedBox(height: 12),
                for (final (i, o) in r.offers.indexed)
                  _Reveal(
                    order: 5 + i,
                    child: _OfferTile(offer: o, category: r.category),
                  ),
              ],
            ],
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: _LocationFab(
            active: _selected == 'location',
            locating: _locating,
            onTap: _loading ? null : _useLocation,
          ),
        ),
      ],
    );
  }
}

String _labelFor(String? selected, String fallback) {
  if (selected == null || selected == 'location') return fallback;
  return simulations[selected]?.$2 ?? fallback;
}

String _fmtAmount(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _period(String p) => switch (p) {
      'monthly' => 'month',
      'quarterly' => 'quarter',
      'yearly' => 'year',
      _ => p,
    };

// ---------------------------------------------------------------------------
// Venue chips — five equal icon-only stadium chips across the gutter
// ---------------------------------------------------------------------------

class _VenueChips extends StatelessWidget {
  final String? selected;
  final bool enabled;
  final void Function(String label, String category) onSelect;
  const _VenueChips(
      {required this.selected, required this.enabled, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tonal = scheme.onSurface.withValues(alpha: 0.06);
    return Row(
      children: [
        for (final entry in simulations.entries) ...[
          Expanded(
            child: Tooltip(
              message: entry.key,
              child: _AnimatedChip(
                key: Key('sim_${entry.value.$2}'),
                icon: entry.value.$1,
                selected: selected == entry.key,
                tonal: tonal,
                accent: scheme.primary,
                onAccent: scheme.onPrimary,
                muted: scheme.onSurfaceVariant,
                onTap:
                    enabled ? () => onSelect(entry.key, entry.value.$2) : null,
              ),
            ),
          ),
          if (entry.key != simulations.keys.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _AnimatedChip extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color tonal, accent, onAccent, muted;
  final VoidCallback? onTap;
  const _AnimatedChip({
    super.key,
    required this.icon,
    required this.selected,
    required this.tonal,
    required this.accent,
    required this.onAccent,
    required this.muted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: ConciergeMotion.chip,
            curve: Curves.easeOut,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? accent : tonal,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, size: 20, color: selected ? onAccent : muted),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location FAB
// ---------------------------------------------------------------------------

class _LocationFab extends StatelessWidget {
  final bool active;
  final bool locating;
  final VoidCallback? onTap;
  const _LocationFab(
      {required this.active, required this.locating, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Use my location',
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: scheme.primary.withValues(alpha: 0.5),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 56,
            child: locating
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: scheme.onPrimary),
                  )
                : Icon(Icons.near_me, color: scheme.onPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Profile',
      child: InkResponse(
        key: const Key('profile_button'),
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_outline,
              size: 20, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ===========================================================================
// Profile screen
// ===========================================================================

class ProfileScreen extends StatefulWidget {
  final ProfileStore profile;
  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Profile', style: t.textTheme.displaySmall),
          const SizedBox(height: 20),
          Text('YOUR NAME', style: t.textTheme.labelSmall),
          const SizedBox(height: 8),
          TextField(
            key: const Key('profile_name_field'),
            controller: _name,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'e.g. Prasad'),
            onChanged: widget.profile.setName,
          ),
          const SizedBox(height: 28),
          Text('APPEARANCE', style: t.textTheme.labelSmall),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: widget.profile,
            builder: (context, _) => Container(
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  for (final (mode, label, icon) in const [
                    (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
                    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                  ])
                    Expanded(
                      child: _ThemeOption(
                        label: label,
                        icon: icon,
                        selected: widget.profile.themeMode == mode,
                        onTap: () => widget.profile.setThemeMode(mode),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: ConciergeMotion.chip,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label,
                  style: t.textTheme.labelMedium?.copyWith(
                      color:
                          selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staggered entrance (fade + rise); collapses to a fade under reduce-motion
// ---------------------------------------------------------------------------

class _Reveal extends StatefulWidget {
  final int order;
  final Widget child;
  const _Reveal({required this.order, required this.child});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: ConciergeMotion.entrance);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: ConciergeMotion.enter);

  @override
  void initState() {
    super.initState();
    Future.delayed(
        ConciergeMotion.stagger * widget.order, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
            offset: Offset(0, ConciergeMotion.riseOffset * (1 - _t.value)),
            child: child),
      ),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// The ranked deck — winner full, ranks 2-3 stacked behind, bottom strip shown
// ---------------------------------------------------------------------------

class _RankedDeck extends StatelessWidget {
  final List<_Ranked> ranked;
  final String category;
  const _RankedDeck({required this.ranked, required this.category});

  static const double _strip = 52;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final winnerH = width / kCardAspect;
      final extra = (ranked.length - 1) * _strip;
      return SizedBox(
        height: winnerH + extra,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Back cards first (rank 3 furthest back).
            for (int i = ranked.length - 1; i >= 1; i--)
              Positioned(
                top: _strip * i,
                left: 8.0 * i,
                right: 8.0 * i,
                height: winnerH,
                child: _BackCard(
                  rank: i + 1,
                  ranked: ranked[i],
                  stripHeight: _strip,
                ),
              ),
            // Winner on top, rendered in full.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _CardVisual(
                card: ranked.first.card,
                headline:
                    '${(ranked.first.rec.effectiveRate * 100).toStringAsFixed(2)}%',
                caption: 'back on $category',
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// A runner-up: full card face behind the winner, only its bottom strip
/// (rank badge, name, issuer, rate) exposed over a scrim that keeps white ink
/// readable on any face color.
class _BackCard extends StatelessWidget {
  final int rank;
  final _Ranked ranked;
  final double stripHeight;
  const _BackCard(
      {required this.rank, required this.ranked, required this.stripHeight});

  @override
  Widget build(BuildContext context) {
    final x = Theme.of(context).extension<ConciergeColors>()!;
    final (a, b) = _faceColors(ranked.card);
    return ClipRRect(
      key: Key('rank_$rank'),
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: cardFace(a, b)),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: stripHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(gradient: deckScrim(x)),
            child: Row(
              children: [
                Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Text('$rank',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ranked.card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      Text(ranked.card.issuer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.white.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(ranked.rec.effectiveRate * 100).toStringAsFixed(2)}%',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFeatures: [ui.FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info pills
// ---------------------------------------------------------------------------

enum _PillKind { cap, hint }

class _InfoPill extends StatelessWidget {
  final _PillKind kind;
  final String text;
  const _InfoPill({super.key, required this.kind, required this.text});

  @override
  Widget build(BuildContext context) {
    final x = Theme.of(context).extension<ConciergeColors>()!;
    final (bg, ink, icon) = switch (kind) {
      _PillKind.cap => (x.capBg, x.capInk, Icons.error_outline),
      _PillKind.hint => (x.hintBg, x.hintInk, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: ink),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: ink)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Perk tiles
// ---------------------------------------------------------------------------

const _categoryIcons = <String, IconData>{
  'dining': Icons.restaurant_outlined,
  'grocery': Icons.local_grocery_store_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'entertainment': Icons.movie_outlined,
  'online': Icons.shopping_bag_outlined,
  'travel': Icons.flight_outlined,
  'transit': Icons.train_outlined,
  'utilities': Icons.bolt_outlined,
  'general': Icons.card_giftcard_outlined,
};

class _OfferTile extends StatelessWidget {
  final OfferInfo offer;
  final String category;
  const _OfferTile({required this.offer, required this.category});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final swatch = _parseHex(offer.colorPrimary);
    return Container(
      key: const Key('offer'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (t.brightness == Brightness.dark
                    ? Colors.black
                    : const Color(0xFF272219))
                .withValues(alpha: t.brightness == Brightness.dark ? 0.8 : 0.5),
            blurRadius: 18,
            spreadRadius: -14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(_categoryIcons[category] ?? Icons.card_giftcard_outlined,
                size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall),
                if (offer.description != null &&
                    offer.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(offer.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          height: 1.35,
                          color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 9,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: swatch ?? scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        offer.cardName.isEmpty
                            ? offer.cardLabel
                            : offer.cardName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelSmall?.copyWith(
                            letterSpacing: 0, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty states
// ---------------------------------------------------------------------------

class _EmptyCategory extends StatelessWidget {
  final String category;
  final String? status;
  const _EmptyCategory({required this.category, this.status});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          _GhostCard(),
          const SizedBox(height: 20),
          Text(status ?? 'No card in your wallet covers $category yet.',
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Add one in the Wallet tab →',
              style: t.textTheme.labelLarge
                  ?.copyWith(color: t.colorScheme.primary)),
        ],
      ),
    );
  }
}

class _GhostCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return AspectRatio(
      aspectRatio: kCardAspect,
      child: DottedBorder(
        color: outline,
        radius: kCardRadius,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Minimal dashed rounded-rect border (avoids a package dependency).
class DottedBorder extends StatelessWidget {
  final Color color;
  final double radius;
  final Widget child;
  const DottedBorder(
      {super.key,
      required this.color,
      required this.radius,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 7.0, gap = 6.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) =>
      old.color != color || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Card face colors
// ---------------------------------------------------------------------------

const _fallbackFaces = [
  (Color(0xFF16161F), Color(0xFF2E2E48)), // midnight
  (Color(0xFF0C312D), Color(0xFF1E5F55)), // deep teal
  (Color(0xFF2E1622), Color(0xFF61344A)), // wine
  (Color(0xFF1F2A34), Color(0xFF3F5666)), // slate
];

Color? _parseHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Two face hexes from ingestion, else a stable issuer-hashed fallback pair.
(Color, Color) _faceColors(CardInfo card) {
  final a = _parseHex(card.colorPrimary);
  if (a == null) {
    return _fallbackFaces[card.issuer.hashCode.abs() % _fallbackFaces.length];
  }
  final b = _parseHex(card.colorSecondary) ??
      HSLColor.fromColor(a)
          .withLightness(
              (HSLColor.fromColor(a).lightness * 1.35).clamp(0.0, 1.0))
          .toColor();
  return (a, b);
}

// ---------------------------------------------------------------------------
// The card visual (hero)
// ---------------------------------------------------------------------------

class _CardVisual extends StatelessWidget {
  final CardInfo card;
  final String? headline; // e.g. "5.00%"
  final String? caption; // e.g. "back on dining"
  final VoidCallback? onRemove;

  const _CardVisual({
    required this.card,
    this.headline,
    this.caption,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (a, b) = _faceColors(card);
    final ink = cardInk(a, b);
    final inkSoft = ink.withValues(alpha: 0.72);
    final inkFaint = ink.withValues(alpha: 0.5);
    final lightFace = ink != Colors.white;

    final semantics = headline != null
        ? 'Best card for ${caption?.replaceFirst('back on ', '') ?? ''}: '
            '${card.issuer} ${card.name}, $headline back'
        : '${card.issuer} ${card.name}';

    return Semantics(
      label: semantics,
      child: AspectRatio(
        aspectRatio: kCardAspect,
        child: Container(
          key: headline != null ? const Key('best_card') : null,
          padding: const EdgeInsets.fromLTRB(18, 15, 15, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kCardRadius),
            gradient: cardFace(a, b),
            // Light faces get a hairline so they don't dissolve into surfaces.
            border: lightFace
                ? Border.all(color: t.colorScheme.outline)
                : null,
            boxShadow: [
              BoxShadow(
                color: (t.brightness == Brightness.dark
                        ? Colors.black
                        : const Color(0xFF272219))
                    .withValues(
                        alpha: t.brightness == Brightness.dark ? 0.75 : 0.45),
                blurRadius: 40,
                spreadRadius: -18,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(card.issuer.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 1.84,
                            fontWeight: FontWeight.w600,
                            color: inkSoft)),
                  ),
                  _Contactless(color: inkFaint),
                  if (onRemove != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      key: Key('remove_${card.id}'),
                      onTap: onRemove,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, size: 15, color: ink),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _EmvChip(),
              const Spacer(),
              if (headline != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(headline!,
                        style: t.textTheme.headlineLarge?.copyWith(color: ink)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(caption ?? '',
                          style: TextStyle(
                              fontSize: 13,
                              color: ink.withValues(alpha: 0.88))),
                    ),
                  ],
                )
              else
                Text('••••  ••••  ••••  ••••',
                    style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 2.1,
                        fontWeight: FontWeight.w600,
                        color: ink.withValues(alpha: 0.62))),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: ink)),
                  ),
                  const SizedBox(width: 8),
                  _NetworkMark(network: card.network, ink: ink),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contactless: three nested arcs.
class _Contactless extends StatelessWidget {
  final Color color;
  const _Contactless({required this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(18, 18), painter: _ContactlessPainter(color));
}

class _ContactlessPainter extends CustomPainter {
  final Color color;
  _ContactlessPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width * 0.1, size.height / 2);
    for (int i = 1; i <= 3; i++) {
      final r = size.width * 0.28 * i;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: r), -0.7, 1.4, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ContactlessPainter old) => old.color != color;
}

/// EMV chip: gold rounded rectangle with contact lines.
class _EmvChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 27,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8CE8F), Color(0xFFC79E52)],
        ),
      ),
      child: CustomPaint(painter: _ChipLines()),
    );
  }
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55432F00)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 2),
        Offset(size.width, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _NetworkMark extends StatelessWidget {
  final String network;
  final Color ink;
  const _NetworkMark({required this.network, this.ink = Colors.white});

  @override
  Widget build(BuildContext context) {
    switch (network) {
      case 'mastercard':
        return SizedBox(
          width: 38,
          height: 24,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEB001B).withValues(alpha: 0.9),
                        shape: BoxShape.circle)),
              ),
              Positioned(
                right: 0,
                child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                        color: const Color(0xFFF79E1B).withValues(alpha: 0.85),
                        shape: BoxShape.circle)),
              ),
            ],
          ),
        );
      case 'visa':
        return Text('VISA',
            style: TextStyle(
                fontSize: 16,
                color: ink,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5));
      case 'amex':
        return Text('AMEX',
            style: TextStyle(
                fontSize: 14,
                color: ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 1));
      default:
        return const SizedBox.shrink();
    }
  }
}

// ===========================================================================
// Wallet tab
// ===========================================================================

class WalletTab extends StatefulWidget {
  final CardDao dao;
  final IngestService? ingest;
  final VoidCallback? onWalletChanged;

  const WalletTab({
    super.key,
    required this.dao,
    this.ingest,
    this.onWalletChanged,
  });

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> {
  List<CardInfo>? _held;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await widget.dao.allCards();
    setState(() => _held = cards.where((c) => c.held).toList());
  }

  Future<void> _remove(CardInfo card) async {
    await widget.dao.setHeld(card.id, false);
    await _load();
    widget.onWalletChanged?.call();
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text('Removed ${card.name}'),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.dao.setHeld(card.id, true);
            await _load();
            widget.onWalletChanged?.call();
          },
        ),
      ));
    }
  }

  Future<void> _confirmRemove(CardInfo card) async {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: scheme.outline,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(card.label.toUpperCase(),
                  textAlign: TextAlign.center, style: t.textTheme.labelSmall),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('confirm_remove'),
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Remove from wallet',
                  style: t.textTheme.titleSmall?.copyWith(color: scheme.error)),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            ListTile(
              leading: Icon(Icons.close, color: scheme.onSurfaceVariant),
              title: Text('Cancel', style: t.textTheme.titleSmall),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (confirmed == true) await _remove(card);
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddCardSheet(dao: widget.dao, ingest: widget.ingest),
    );
    if (added == true) {
      await _load();
      widget.onWalletChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final held = _held;
    return Stack(
      children: [
        held == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : held.isEmpty
                ? _EmptyWallet(onAdd: _openAddSheet)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
                    children: [
                      Text('Wallet', style: t.textTheme.displaySmall),
                      const SizedBox(height: 2),
                      Text('Tap ✕ on a card to remove it.',
                          style: t.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 18),
                      for (final c in held)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _CardVisual(
                              card: c, onRemove: () => _confirmRemove(c)),
                        ),
                    ],
                  ),
        // "Add a card" pinned over a background fade.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              height: 190,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    t.scaffoldBackgroundColor.withValues(alpha: 0),
                    t.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: FilledButton(
            key: const Key('add_card_button'),
            onPressed: _openAddSheet,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 8),
                Text('Add a card'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyWallet extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyWallet({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 220, child: _GhostCard()),
            const SizedBox(height: 22),
            Text('Your wallet is empty.',
                style: t.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Add your first card to start getting picks.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 22),
            FilledButton(
              key: const Key('add_card_button'),
              onPressed: onAdd,
              child: const Text('Add a card'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCardSheet extends StatefulWidget {
  final CardDao dao;
  final IngestService? ingest;
  const _AddCardSheet({required this.dao, this.ingest});

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final ingest = widget.ingest;
    if (name.isEmpty) return;
    if (ingest == null) {
      setState(() => _error = 'Ingestion service not configured.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ingest.ingest(name);
      await widget.dao.insertExtraction(data);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Padding(
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
          const SizedBox(height: 18),
          Text('Add a card',
              style: GoogleFontsSafe.title(t)),
          const SizedBox(height: 4),
          Text('Type the card name — its rewards are found and added for you.',
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('new_card_field'),
            controller: _name,
            enabled: !_busy,
            autofocus: true,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: 'e.g. Emirates NBD Titanium',
              errorText: null,
              enabledBorder: _busy
                  ? null
                  : OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: _error != null
                          ? BorderSide(color: scheme.error)
                          : BorderSide.none),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                key: const Key('add_card_error'),
                style: t.textTheme.bodySmall?.copyWith(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          if (_busy)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      minHeight: 4, color: scheme.primary),
                ),
                const SizedBox(height: 10),
                Text('Reading the fine print…',
                    style: t.textTheme.titleMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            )
          else
            FilledButton(
              key: const Key('confirm_add_card'),
              onPressed: _submit,
              child: const Text('Add card'),
            ),
        ],
      ),
    );
  }
}

/// Small helper so the sheet title uses the serif display face at 20/w500.
class GoogleFontsSafe {
  static TextStyle title(ThemeData t) =>
      (t.textTheme.displaySmall ?? const TextStyle())
          .copyWith(fontSize: 20, fontWeight: FontWeight.w500);
}
