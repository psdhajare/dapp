import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:geolocator/geolocator.dart';

import 'analytics.dart';
import 'app_db.dart';
import 'dao.dart';
import 'db_factory.dart';
import 'home_widget_service.dart';
import 'ingest_service.dart';
import 'input_guard.dart';
import 'merchant_category.dart';
import 'profile_store.dart';
import 'rate_limiter.dart';
import 'screens/profile_screen.dart';
import 'share_service.dart';
import 'theme/concierge_theme.dart';
import 'util/card_match.dart';
import 'util/formatting.dart';
import 'util/gradients.dart';
import 'util/offer_dedupe.dart';
import 'venue.dart';
import 'widgets/card_visual.dart';

/// Shown for any server/network failure — the real cause is in the server logs.
const kFriendlyError = 'Oops, something went wrong. Try again later.';

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

  final db = await openAppDb(resolveDbFactory());
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
  final analytics = await Analytics.load();

  runApp(BestCardApp(
    dao: dao,
    venue: venue,
    locationFn: _deviceLocation,
    ingest: ingest,
    profile: profile,
    analytics: analytics,
  ));
}

class BestCardApp extends StatelessWidget {
  final CardDao dao;
  final VenueCategoryService venue;
  final LocationFn locationFn;
  final IngestService? ingest;
  final ProfileStore profile;
  final Analytics analytics;

  const BestCardApp({
    super.key,
    required this.dao,
    required this.venue,
    required this.locationFn,
    required this.profile,
    required this.analytics,
    this.ingest,
  });

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp when the theme preference changes.
    return AnimatedBuilder(
      animation: profile,
      builder: (context, _) => MaterialApp(
        title: 'ToroKard',
        debugShowCheckedModeBanner: false,
        theme: conciergeTheme(Brightness.light),
        darkTheme: conciergeTheme(Brightness.dark),
        themeMode: profile.themeMode,
        home: RootScreen(
            dao: dao,
            venue: venue,
            locationFn: locationFn,
            ingest: ingest,
            profile: profile,
            analytics: analytics),
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
  final Analytics analytics;

  const RootScreen({
    super.key,
    required this.dao,
    required this.venue,
    required this.locationFn,
    required this.profile,
    required this.analytics,
    this.ingest,
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tab = 0;
  final _recommendKey = GlobalKey<_RecommendTabState>();
  final _pager = PageController();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    _pager.animateToPage(i,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutQuart);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageView(
          controller: _pager,
          onPageChanged: (i) {
            setState(() => _tab = i);
            if (i == 0) {
              _recommendKey.currentState?.refreshAfterWalletChange();
            }
          },
          children: [
            RecommendTab(
              key: _recommendKey,
              dao: widget.dao,
              venue: widget.venue,
              locationFn: widget.locationFn,
              profile: widget.profile,
              analytics: widget.analytics,
              ingest: widget.ingest,
            ),
            WalletTab(
              dao: widget.dao,
              ingest: widget.ingest,
              analytics: widget.analytics,
              profile: widget.profile,
              onWalletChanged: () =>
                  _recommendKey.currentState?.refreshAfterWalletChange(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BlurNav(tab: _tab, onSelect: _goTo),
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
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: x.navFill,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          // Symmetric 10px above/below the icon+label; home indicator sits below.
          padding: EdgeInsets.only(top: 10, bottom: 10 + bottom),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  _NavItem(
                    icon: Icons.style_outlined,
                    selectedIcon: Icons.style,
                    label: 'Best card',
                    selected: tab == 0,
                    onTap: () => onSelect(0),
                  ),
                  _NavItem(
                    buttonKey: const Key('wallet_button'),
                    icon: Icons.account_balance_wallet_outlined,
                    selectedIcon: Icons.account_balance_wallet,
                    label: 'Wallet',
                    selected: tab == 1,
                    onTap: () => onSelect(1),
                  ),
                ],
              ),
              // Accent segment on the top boundary above the ACTIVE tab.
              Positioned(
                top: -10, // sit on the panel's top edge (cancels the 10 padding)
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    for (var i = 0; i < 2; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: ConciergeMotion.chip,
                          height: 2.5,
                          color: tab == i
                              ? scheme.primary
                              : Colors.transparent,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Key? buttonKey;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkResponse(
        key: buttonKey,
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? selectedIcon : icon, size: 26, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: color)),
          ],
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
  final Analytics analytics;
  final IngestService? ingest;

  const RecommendTab({
    super.key,
    required this.dao,
    required this.venue,
    required this.locationFn,
    required this.profile,
    required this.analytics,
    this.ingest,
  });

  @override
  State<RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends State<RecommendTab>
    with WidgetsBindingObserver {
  String? _selected; // simulation label or 'location'; null = everyday spend
  String? _status;
  _Result? _result;
  bool _loading = false;
  bool _locating = false;

  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchLink = LayerLink();
  final _historyOverlay = OverlayPortalController();
  String? _searchMerchant; // the queried merchant, when in search mode
  bool _searchLoading = false;
  List<MerchantOfferView>? _merchantOffers; // offers on the user's held cards
  List<MerchantOfferView> _otherOffers = const []; // non-held (secondary)
  // Deck re-ranked for a merchant search: each held card boosted to its best
  // offer value, so every card (not just the top) reflects its real benefit.
  List<_Ranked>? _searchDeck;
  // cardId -> (headline, caption) for cards whose offer beats their base rate.
  Map<String, (String, String)> _deckDisplay = {};
  int _celebrateToken = 0; // bumped to fire the on-card celebration
  bool _celebrateBig = false; // big crackers vs a light sparkle
  final Set<int> _revealed = {}; // reveal ids already animated this result

  @override
  void initState() {
    super.initState();
    // Show the recent-searches dropdown (a floating overlay) while focused.
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) {
        _historyOverlay.show();
      } else {
        _historyOverlay.hide();
      }
      setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Honor a Siri request ("best card for groceries"), else default view.
      if (!await _handleSiriRequest()) await _recommend('general');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _handleSiriRequest();
  }

  /// If Siri queued a category, show it. Returns true if one was handled.
  Future<bool> _handleSiriRequest() async {
    final cat = await consumeSiriCategory();
    if (cat == null || !mounted) return false;
    setState(() => _selected = cat == 'general' ? null : cat);
    await _recommend(cat);
    return true;
  }

  Future<void> refreshAfterWalletChange() async {
    await _recommend(_result?.category ?? 'general');
  }

  /// Profile → "Remove all cards": empties the wallet, then re-ranks.
  Future<void> _removeAllCards() async {
    final held = (await widget.dao.allCards()).where((c) => c.held);
    for (final c in held) {
      await widget.dao.setHeld(c.id, false);
    }
    await refreshAfterWalletChange();
  }

  /// Profile → "Refresh card data": re-ingest each held card's rules from the
  /// bank's official page (best-effort; skips any that fail), then re-ranks.
  Future<void> _refreshCardData() async {
    final ingest = widget.ingest;
    if (ingest == null) return;
    final all = await widget.dao.allCards();
    final held = all.where((c) => c.held).toList();
    // Keep each card's user-picked face color across a refresh.
    final colors = {for (final c in all) c.id: (c.colorPrimary, c.colorSecondary)};
    for (final c in held) {
      try {
        final cards = await ingest.ingest(c.name, country: widget.profile.country);
        for (final data in cards) {
          final id = (data['card'] as Map)['id'];
          final existing = colors[id];
          await widget.dao.insertExtraction(
            data,
            colorPrimary: existing?.$1,
            colorSecondary: existing?.$2,
          );
        }
      } catch (_) {
        // leave this card as-is on failure
      }
    }
    await refreshAfterWalletChange();
  }

  /// Search a specific merchant: instant best card from the offline keyword
  /// category, then live offer discovery + refined category from the backend.
  Future<void> _search(String raw) async {
    FocusScope.of(context).unfocus();
    // 1) Validate/sanitize before anything leaves the device.
    final String merchant;
    try {
      merchant = sanitizeQuery(raw);
    } on InputGuardException catch (e) {
      _toast(e.message);
      return;
    }
    widget.profile.addSearch(merchant); // record (no-op if history disabled)
    widget.analytics
        .log(Analytics.searchPerformed, label: categoryForMerchant(merchant));
    setState(() {
      _selected = 'search';
      _searchMerchant = merchant;
      _merchantOffers = null;
      _otherOffers = const [];
      _loading = true;
    });
    // Instant best-card from the offline keyword category.
    await _recommend(categoryForMerchant(merchant));
    setState(() => _loading = false);
    _celebrate(_result?.winner.rec.effectiveRate ?? 0, live: false);

    final key = merchant.toLowerCase();

    // 2) Cache-aside: a fresh local hit is instant + offline, no rate-limit cost.
    final cached = await widget.dao.cachedSearch(key);
    if (cached != null) {
      await _applySearchPayload(cached);
      return;
    }

    // 3) Client rate limit (10/min, shared with add-card) — only on real calls.
    if (!queryRateLimiter.tryAcquire()) {
      final secs = queryRateLimiter.retryAfter().inSeconds;
      _toast('Too many searches — try again in ${secs}s.');
      return;
    }
    final ingest = widget.ingest;
    if (ingest == null) return;
    setState(() => _searchLoading = true);
    try {
      // Send held card names so the backend can target loyalty-program offers
      // (e.g. Wio → Entertainer). Not persisted server-side.
      final held = (await widget.dao.allCards())
          .where((c) => c.held)
          .map((c) => '${displayIssuer(c.issuer)} ${c.name}'.trim())
          .toList();
      final data = await ingest.search(merchant,
          cards: held, country: widget.profile.country);
      // Cache a real hit for a day; a miss only briefly so it retries soon and
      // a genuine offer is never hidden for long.
      final hasOffers = (data['offers'] as List?)?.isNotEmpty ?? false;
      await widget.dao.cacheSearch(key, data,
          ttl: hasOffers ? const Duration(hours: 24) : const Duration(minutes: 30));
      await _applySearchPayload(data);
    } catch (_) {
      // Server/network failure — friendly message, real cause is in server logs.
      if (mounted) {
        setState(() => _merchantOffers = const []);
        _toast(kFriendlyError);
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  /// Turns a /search payload (from cache or network) into UI state: refined
  /// category re-rank, offer list, and the featured %-offer deck winner. Held
  /// highlights are recomputed from the current wallet, so cache stays
  /// wallet-independent.
  Future<void> _applySearchPayload(Map<String, dynamic> data) async {
    final refined = data['category'] as String?;
    if (refined != null && refined != _result?.category) {
      await _recommend(refined);
    }
    final held = (await widget.dao.allCards()).where((c) => c.held).toList();
    final heldNames =
        held.map((c) => '${c.issuer} ${c.name}'.toLowerCase()).toList();
    final rawOffers = (data['offers'] as List? ?? []);
    final offers = <MerchantOfferView>[
      for (final o in rawOffers)
        MerchantOfferView.fromJson((o as Map).cast<String, dynamic>(), heldNames),
    ];
    // Drop near-duplicate offers (same deal, different merchant phrasing).
    final deduped =
        dedupeByText(offers, (o) => '${o.title} ${o.description ?? ''}');
    // Wallet-first: an offer only matters if it's on a card the user holds.
    // Non-held offers are kept separately and shown as muted secondary info.
    final walletOffers = deduped.where((o) => o.held).toList();
    final otherOffers = deduped.where((o) => !o.held).toList();

    // Re-rank the WHOLE deck by each card's best value here: a card's merchant
    // offer boosts THAT card, so every position reflects real benefit — e.g.
    // Wio 1+1 (50%) > ENBD 20% > Mashreq 5%, not just the single top winner.
    final byId = <String, _Ranked>{};
    final display = <String, (String, String)>{};
    for (final rr in _result?.ranked ?? const <_Ranked>[]) {
      byId[rr.card.id] = rr; // category baseline (headline stays the rate)
    }
    for (final o in walletOffers) {
      final value = (o.valuePct ?? 0) / 100;
      if (value <= 0) continue;
      final card = _matchHeldCard(o.cardHint ?? '', held);
      if (card == null) continue;
      final baseRate = byId[card.id]?.rec.effectiveRate ?? 0.0;
      if (value <= baseRate) continue; // offer must beat this card's own rate
      byId[card.id] = _Ranked(
        card,
        Recommendation(
          cardId: card.id, categoryUsed: 'offer',
          effectiveRate: value, hasCap: false,
        ),
      );
      display[card.id] = (
        o.shortLabel ?? '${(o.valuePct ?? 0).round()}%',
        o.via != null ? 'via ${o.via}' : 'at $_searchMerchant',
      );
    }
    final deck = byId.values.toList()
      ..sort((a, b) => b.rec.effectiveRate.compareTo(a.rec.effectiveRate));

    if (mounted) {
      setState(() {
        _merchantOffers = walletOffers;
        _otherOffers = otherOffers;
        _searchDeck = deck.isEmpty ? null : deck;
        _deckDisplay = display;
      });
      // Celebrate ONLY when the user's own card has an offer here — big.
      if (walletOffers.isNotEmpty) {
        _celebrate(deck.isNotEmpty ? deck.first.rec.effectiveRate : 0.10,
            live: true);
        widget.analytics.log(Analytics.liveOfferViewed);
      }
    }
  }

  CardInfo? _matchHeldCard(String hint, List<CardInfo> held) {
    for (final c in held) {
      if (offerHintMatchesCardText(hint, '${c.issuer} ${c.name}')) return c;
    }
    return null;
  }

  /// Floating recent-searches dropdown, anchored under the search field via a
  /// LayerLink so it overlays content (chips/deck) instead of pushing it down.
  Widget _buildHistoryOverlay(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final gutter = 20.0;
    final width = MediaQuery.of(context).size.width - gutter * 2;
    return AnimatedBuilder(
      animation: widget.profile,
      builder: (context, _) {
        final items = widget.profile.searchHistory;
        if (!widget.profile.searchHistoryEnabled || items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            // Scrim from the field's bottom edge downward (title stays clear);
            // tap it to dismiss.
            CompositedTransformFollower(
              link: _searchLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: Offset(-gutter, 6),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  child: ColoredBox(
                      color: scheme.onSurface.withValues(alpha: 0.18)),
                ),
              ),
            ),
            CompositedTransformFollower(
              link: _searchLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  shadowColor: Colors.black.withValues(alpha: 0.4),
                  color: Color.alphaBlend(
                      scheme.onSurface.withValues(alpha: 0.06), scheme.surface),
                  child: Container(
                    width: width,
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.outline),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 6, 10, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('RECENT', style: t.textTheme.labelSmall),
                              GestureDetector(
                                onTap: widget.profile.clearSearchHistory,
                                child: Text('Clear',
                                    style: t.textTheme.labelMedium
                                        ?.copyWith(color: scheme.primary)),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: [
                              for (final term in items)
                                InkWell(
                                  onTap: () {
                                    _searchCtl.text = term;
                                    _search(term);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 11),
                                    child: Row(
                                      children: [
                                        Icon(Icons.history,
                                            size: 18,
                                            color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(term,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: t.textTheme.bodyMedium),
                                        ),
                                        Icon(Icons.north_west,
                                            size: 15,
                                            color: scheme.onSurfaceVariant),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    ));
    Future.delayed(const Duration(seconds: 3), m.hideCurrentSnackBar);
  }

  Future<void> _useLocation() async {
    setState(() {
      _selected = 'location';
      _loading = true;
      _locating = true;
      _status = 'Finding where you are…';
      _result = null;
      _searchMerchant = null;
      _merchantOffers = null;
      _otherOffers = const [];
      _searchDeck = null;
      _deckDisplay = {};
    });
    try {
      final (lat, lng) = await widget.locationFn();
      final category = await widget.venue.categoryAt(lat, lng) ?? 'general';
      await _recommend(category);
      _celebrate(_result?.winner.rec.effectiveRate ?? 0, live: false);
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
      _searchMerchant = null;
      _merchantOffers = null;
      _otherOffers = const [];
      _searchDeck = null;
      _deckDisplay = {};
    });
    try {
      await _recommend(category);
      _celebrate(_result?.winner.rec.effectiveRate ?? 0, live: false);
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
        _status = 'No card in your wallet covers ${prettyCategory(category)} yet.';
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
      _revealed.clear(); // new result -> entrances play once, then stay put
      _result = _Result(category, ranked, hints, offers);
    });
    widget.analytics.log(Analytics.recommendationShown, label: category);
    // Keep the home-screen widget in sync with the current best card.
    final winner = ranked.first;
    updateBestCardWidget(
      card: winner.card,
      category: prettyCategory(category),
      headline: '${(winner.rec.effectiveRate * 100).toStringAsFixed(2)}%',
      caption: 'back on ${prettyCategory(category)}',
    );
  }

  /// Share the current best-card pick as a branded image.
  Future<void> _sharePick(_Result r) async {
    final w = _deckRanked(r).first;
    final pretty = prettyCategory(r.category);
    final disp = _deckDisplay[w.card.id];
    widget.analytics.log(Analytics.proFeatureTapped, label: 'share');
    await shareBestCard(
      context,
      card: w.card,
      category: pretty,
      headline:
          disp?.$1 ?? '${(w.rec.effectiveRate * 100).toStringAsFixed(2)}%',
      caption: disp?.$2 ?? 'back on $pretty',
    );
  }

  /// Fire the on-card celebration for the current top card only.
  /// Big (crackers) for a live offer or savings >= 10%; light (sparkle) for
  /// >= 2%; nothing below that. Promoting a runner-up never calls this.
  void _celebrate(double rate, {required bool live}) {
    final big = live || rate >= 0.10;
    if (!big && rate < 0.02) return;
    if (big) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick(); // softer kick for a light one
    }
    setState(() {
      _celebrateBig = big;
      _celebrateToken++;
    });
  }

  /// Deck cards: during a merchant search, the offer-boosted re-rank; otherwise
  /// the plain category ranking.
  List<_Ranked> _deckRanked(_Result r) => (_searchDeck ?? r.ranked).take(3).toList();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final r = _result;
    return GestureDetector(
      // Tap empty space to dismiss the keyboard (standard mobile behavior).
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
      children: [
        ListView(
          // Dragging the list also dismisses the keyboard.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                        builder: (_) => ProfileScreen(
                              profile: widget.profile,
                              analytics: widget.analytics,
                              onRefreshCardData: _refreshCardData,
                              onRemoveAllCards: _removeAllCards,
                            ))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OverlayPortal(
              controller: _historyOverlay,
              overlayChildBuilder: _buildHistoryOverlay,
              child: CompositedTransformTarget(
                link: _searchLink,
                child: TextField(
                  key: const Key('merchant_search'),
                  controller: _searchCtl,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Search a shop, place, or website',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : _searchCtl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchCtl.clear();
                                  FocusScope.of(context).unfocus();
                                  setState(() {});
                                },
                              )
                            : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _VenueChips(
              selected: _selected,
              enabled: !_loading,
              locating: _locating,
              onSelect: _simulate,
              onLocation: _useLocation,
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
                revealed: _revealed,
                child: Text(
                  _searchMerchant != null
                      ? 'Best at $_searchMerchant'
                      : _selected == null
                          ? 'Best for everyday spend'
                          : 'Best for ${prettyCategory(r.category)}',
                  style: t.textTheme.titleMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 14),
              _Reveal(
                order: 1,
                revealed: _revealed,
                child: _RankedDeck(
                  ranked: _deckRanked(r),
                  category: r.category,
                  displays: _deckDisplay,
                  celebrateToken: _celebrateToken,
                  celebrateBig: _celebrateBig,
                ),
              ),
              _Reveal(
                order: 2,
                revealed: _revealed,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('share_pick'),
                    onPressed: () => _sharePick(r),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ),
              if (r.winner.rec.hasCap)
                _Reveal(
                  order: 2,
                revealed: _revealed,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: _InfoPill(
                      key: const Key('cap_flag'),
                      kind: _PillKind.cap,
                      text:
                          '${displayIssuer(r.winner.card.issuer)} ${r.winner.card.name} · rewards cap ${_fmtAmount(r.winner.rec.capAmount!)} per ${_period(r.winner.rec.capPeriod)}',
                    ),
                  ),
                ),
              for (final (label, hint) in r.hints)
                _Reveal(
                  order: 3,
                revealed: _revealed,
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
              // Live merchant offers come BEFORE static perks — they're the
              // reason the user searched, and their arrival is celebrated.
              if (_searchMerchant != null) ...[
                const SizedBox(height: 16),
                Text('OFFERS ON YOUR CARDS AT ${_searchMerchant!.toUpperCase()}',
                    style: t.textTheme.labelSmall),
                const SizedBox(height: 12),
                if (_searchLoading && _merchantOffers == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('Checking for current offers…',
                          style: t.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  )
                else if (_merchantOffers != null) ...[
                  if (_merchantOffers!.isNotEmpty)
                    for (final o in _merchantOffers!)
                      _MerchantOfferTile(offer: o)
                  else
                    Text('None of your cards has an offer here right now.',
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  // Non-held offers: muted, collapsed, never celebrated.
                  if (_otherOffers.isNotEmpty)
                    _OtherCardsOffers(offers: _otherOffers),
                ],
              ],
              if (r.offers.isNotEmpty) ...[
                const SizedBox(height: 30),
                _Reveal(
                  order: 4,
                revealed: _revealed,
                  child: Text('PERKS FOR ${prettyCategory(r.category).toUpperCase()}',
                      style: t.textTheme.labelSmall),
                ),
                const SizedBox(height: 12),
                for (final (i, o) in r.offers.indexed)
                  _Reveal(
                    order: 5 + i,
                revealed: _revealed,
                    child: _OfferTile(offer: o, category: r.category),
                  ),
              ],
            ],
          ],
        ),
      ],
      ),
    );
  }
}

/// Wraps the winning card and overlays a Diwali-style crackers burst — rockets
/// rise from the base and explode into sparks — strictly clipped to the card.
class _CelebratableCard extends StatelessWidget {
  final AnimationController controller;
  final bool big;
  final Widget child;
  const _CelebratableCard(
      {required this.controller, required this.big, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, __) {
                  if (controller.value == 0 || controller.value == 1) {
                    return const SizedBox.shrink();
                  }
                  return CustomPaint(
                      painter: _CrackersPainter(controller.value, big));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diwali crackers: a few rockets shoot up, then burst into radiating sparks.
/// All coordinates are within the card's box (painter is clipped to it).
class _CrackersPainter extends CustomPainter {
  final double t; // 0..1
  final bool big; // big = full crackers; light = a few gentle sparks
  _CrackersPainter(this.t, this.big);

  static const _colors = [
    Color(0xFFE8CE8F), // gold
    Color(0xFFE08A2E), // amber
    Color(0xFF8CBEA3), // mint
    Color(0xFFEB6F92), // rose
    Color(0xFFFFFFFF), // white spark
  ];

  // Rockets spread across the whole timeline so bursts keep popping ~3s.
  // Each: horizontal position, launch delay (0..1), burst height, spark count.
  static const _launches = [
    (x: 0.30, delay: 0.00, burstY: 0.34, sparks: 12),
    (x: 0.66, delay: 0.08, burstY: 0.24, sparks: 14),
    (x: 0.82, delay: 0.16, burstY: 0.44, sparks: 10),
    (x: 0.16, delay: 0.26, burstY: 0.40, sparks: 12),
    (x: 0.50, delay: 0.36, burstY: 0.20, sparks: 16),
    (x: 0.74, delay: 0.46, burstY: 0.36, sparks: 12),
    (x: 0.24, delay: 0.56, burstY: 0.28, sparks: 12),
    (x: 0.58, delay: 0.66, burstY: 0.46, sparks: 14),
    (x: 0.88, delay: 0.74, burstY: 0.30, sparks: 10),
  ];

  static const _window = 0.26; // each rocket's rise+burst lifespan (of total)

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // Light celebration: a few rockets spread across the timeline. Big: all.
    final active = big
        ? _launches
        : [_launches[0], _launches[4], _launches[7]];

    for (var r = 0; r < active.length; r++) {
      final l = active[r];
      final lt = ((t - l.delay) / _window).clamp(0.0, 1.0);
      if (lt <= 0 || lt >= 1) continue;
      final bx = size.width * l.x;
      final burstY = size.height * l.burstY;

      if (lt < 0.4) {
        // Rocket rising: a bright streak from the base to the burst point.
        final p = lt / 0.4;
        final y =
            size.height - (size.height - burstY) * Curves.easeOut.transform(p);
        paint.color = _colors[r % _colors.length].withValues(alpha: 0.9);
        canvas.drawCircle(Offset(bx, y), 2.2, paint);
        paint.color = _colors[r % _colors.length].withValues(alpha: 0.25);
        canvas.drawRect(
            Rect.fromLTWH(bx - 1, y, 2, (size.height - y) * 0.4), paint);
      } else {
        // Burst: sparks radiate outward, fade + fall.
        final bp = (lt - 0.4) / 0.6; // 0..1 within the burst
        final radius = 46 * Curves.easeOut.transform(bp);
        for (var s = 0; s < l.sparks; s++) {
          final a = (s / l.sparks) * 2 * math.pi;
          final gravity = 26 * bp * bp;
          final dx = bx + radius * math.cos(a);
          final dy = burstY + radius * math.sin(a) + gravity;
          paint.color =
              _colors[(r + s) % _colors.length].withValues(alpha: 1 - bp);
          canvas.drawCircle(Offset(dx, dy), 2.0 * (1 - bp * 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CrackersPainter old) =>
      old.t != t || old.big != big;
}

/// Offers for cards the user does NOT hold — shown muted, collapsed by default,
/// and never celebrated. Honest ("not in your wallet") without distracting from
/// the cards the user can actually use.
class _OtherCardsOffers extends StatefulWidget {
  final List<MerchantOfferView> offers;
  const _OtherCardsOffers({required this.offers});

  @override
  State<_OtherCardsOffers> createState() => _OtherCardsOffersState();
}

class _OtherCardsOffersState extends State<_OtherCardsOffers> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final n = widget.offers.length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'OFFERS ON OTHER CARDS · NOT IN YOUR WALLET ($n)',
                    style: t.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            // Muted so they read as informational, not actionable.
            Opacity(
              opacity: 0.6,
              child: Column(
                children: [
                  for (final o in widget.offers) _MerchantOfferTile(offer: o),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card info sheet: network, annual fee, and the reward rules.
class _CardInfoSheet extends StatelessWidget {
  final CardInfo card;
  final CardDetails details;
  const _CardInfoSheet({required this.card, required this.details});

  String _network(String n) => switch (n) {
        'mastercard' => 'Mastercard',
        'visa' => 'Visa',
        'amex' => 'American Express',
        'rupay' => 'RuPay',
        'diners' => 'Diners Club',
        'discover' => 'Discover',
        'unionpay' => 'UnionPay',
        'jcb' => 'JCB',
        _ => 'Card',
      };

  /// APR risk bands: <15 purple, 15–20 green, 20–25 orange, >25 red.
  Color? _aprColor(double? apr) {
    if (apr == null) return null;
    if (apr < 15) return const Color(0xFF7E57C2); // purple
    if (apr < 20) return const Color(0xFF2E9E5B); // green
    if (apr < 25) return const Color(0xFFE08A2E); // orange
    return const Color(0xFFD64545); // red
  }

  String _rateLabel(RuleInfo r) => r.unit == 'points_per_unit'
      ? '${r.rate.toStringAsFixed(r.rate == r.rate.roundToDouble() ? 0 : 2)} pts / ${details.currency}'
      : '${r.rate.toStringAsFixed(r.rate == r.rate.roundToDouble() ? 0 : 2)}%';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final cur = details.currency;
    final facts = <(String, String)>[
      (
        'APR (interest)',
        details.apr != null ? '${details.apr!.toStringAsFixed(2)}% / year' : '—',
      ),
      (
        'Annual fee',
        details.annualFee <= 0
            ? 'None'
            : '$cur ${details.annualFee.toStringAsFixed(0)}',
      ),
      if (details.foreignTxFee != null)
        ('Foreign spend fee', '${details.foreignTxFee!.toStringAsFixed(2)}%'),
      if (details.minSalary != null)
        ('Min. monthly salary', '$cur ${details.minSalary!.toStringAsFixed(0)}'),
      if (details.interestFreeDays != null)
        ('Interest-free days', '${details.interestFreeDays} days'),
      ('Network', _network(details.network)),
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Cap height so the sheet never reaches the status bar — otherwise a
        // swipe-down opens iOS Notification Center instead of closing it.
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
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
            // Everything below scrolls WITHIN the sheet.
            Flexible(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
                children: [
                  Text(displayIssuer(card.issuer).toUpperCase(),
                      style: t.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(card.name, style: t.textTheme.displaySmall),
                  const SizedBox(height: 20),
                  Text('KEY FACTS', style: t.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  for (final (label, value) in facts)
                    _FactRow(
                        label: label,
                        value: value,
                        valueColor: label.startsWith('APR')
                            ? _aprColor(details.apr)
                            : null),
                  const SizedBox(height: 20),
                  Text('REWARDS', style: t.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  if (details.rules.isEmpty)
                    Text('No reward rules on record for this card.',
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant))
                  else
                    for (final r in details.rules)
                      _RuleRow(rate: _rateLabel(r), rule: r),
                  const SizedBox(height: 16),
                  Text(
                    'APR and full terms are in your card agreement.',
                    style: t.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor; // band colour for APR; null = default ink
  const _FactRow(
      {required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          Text(value,
              style: t.textTheme.titleSmall?.copyWith(
                  color: valueColor ?? scheme.onSurface,
                  fontWeight: FontWeight.w700)), // just bold
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final String rate;
  final RuleInfo rule;
  const _RuleRow({required this.rate, required this.rule});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final subs = <String>[
      if (rule.capAmount != null)
        'up to ${rule.capAmount!.toStringAsFixed(0)} / ${rule.capPeriod}',
      if (rule.minSpend != null)
        'min spend ${rule.minSpend!.toStringAsFixed(0)}',
      if (rule.conditions != null && rule.conditions!.isNotEmpty) rule.conditions!,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prettyCategory(rule.category),
                    style: t.textTheme.titleSmall),
                if (subs.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subs.join(' · '),
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(rate,
              style: t.textTheme.titleSmall?.copyWith(color: scheme.primary)),
        ],
      ),
    );
  }
}

/// Never show the internal token "general" — say "everyday spend" (v1.1 copy).
String prettyCategory(String c) => c == 'general' ? 'everyday spend' : c;

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
  final bool locating;
  final void Function(String label, String category) onSelect;
  final VoidCallback? onLocation;
  const _VenueChips({
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.locating,
    this.onLocation,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tonal = scheme.onSurface.withValues(alpha: 0.06);
    return Row(
      children: [
        // Current-location chip, first in the row.
        Expanded(
          child: Tooltip(
            message: 'My location',
            child: _AnimatedChip(
              key: const Key('chip_location'),
              icon: Icons.my_location,
              selected: selected == 'location',
              busy: locating,
              tonal: tonal,
              accent: scheme.primary,
              onAccent: scheme.onPrimary,
              muted: scheme.onSurfaceVariant,
              onTap: enabled ? onLocation : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
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
  final bool busy;
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
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? onAccent : muted;
    return Opacity(
      opacity: onTap == null && !busy ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: busy ? null : onTap,
          child: AnimatedContainer(
            duration: ConciergeMotion.chip,
            curve: Curves.easeOut,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? accent : tonal,
              borderRadius: BorderRadius.circular(999),
            ),
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Icon(icon, size: 20, color: fg),
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
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_outline,
              size: 24, color: scheme.onSurfaceVariant),
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

  /// Set of reveal ids already played this result-generation. Once an item has
  /// animated, scrolling it off and back shows it instantly instead of
  /// re-running the entrance. Cleared by the parent when a new result loads.
  final Set<int>? revealed;

  const _Reveal({required this.order, required this.child, this.revealed});

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
    final seen = widget.revealed;
    if (seen != null && seen.contains(widget.order)) {
      _c.value = 1.0; // already revealed once — show instantly on re-scroll
      return;
    }
    seen?.add(widget.order); // mark so it won't re-animate later
    Future.delayed(ConciergeMotion.stagger * widget.order, () {
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

class _RankedDeck extends StatefulWidget {
  final List<_Ranked> ranked;
  final String category;
  // cardId -> (headline, caption) for cards showing an offer instead of a rate.
  final Map<String, (String, String)> displays;
  final int celebrateToken; // bump to fire the on-card celebration once
  final bool celebrateBig; // big crackers vs a light sparkle
  const _RankedDeck(
      {required this.ranked,
      required this.category,
      this.displays = const {},
      this.celebrateToken = 0,
      this.celebrateBig = false});

  @override
  State<_RankedDeck> createState() => _RankedDeckState();
}

class _RankedDeckState extends State<_RankedDeck>
    with SingleTickerProviderStateMixin {
  static const double _strip = 52;
  late List<_Ranked> _order = List.of(widget.ranked);

  // Celebration on the winning card. Duration is set per fire (big vs light).
  late final AnimationController _celebrate =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

  @override
  void dispose() {
    _celebrate.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_RankedDeck old) {
    super.didUpdateWidget(old);
    // Reset the user's promotion only when the underlying set of cards changes
    // (a new search/category), not on incidental parent rebuilds.
    final incoming = widget.ranked.map((r) => r.card.id).toSet();
    final current = _order.map((r) => r.card.id).toSet();
    if (incoming.length != current.length ||
        !incoming.containsAll(current)) {
      _order = List.of(widget.ranked);
    }
    if (widget.celebrateToken != old.celebrateToken &&
        widget.celebrateToken > 0) {
      _celebrate.duration = Duration(
          milliseconds: widget.celebrateBig ? 3000 : 1400);
      _celebrate.forward(from: 0);
    }
  }

  void _promote(int index) {
    if (index == 0) return;
    setState(() {
      final picked = _order.removeAt(index);
      _order.insert(0, picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final winnerH = width / kCardAspect;
      final height = winnerH + (_order.length - 1) * _strip;
      return SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Paint back-to-front so the winner (index 0) is on top; keyed by
            // card id so AnimatedPositioned slides each card on reorder.
            for (int i = _order.length - 1; i >= 0; i--)
              AnimatedPositioned(
                key: ValueKey(_order[i].card.id),
                duration: ConciergeMotion.rerank,
                curve: Curves.easeInOutCubic,
                top: _strip * i,
                left: 8.0 * i,
                right: 8.0 * i,
                height: winnerH,
                child: i == 0
                    ? _CelebratableCard(
                        controller: _celebrate,
                        big: widget.celebrateBig,
                        child: Builder(builder: (_) {
                          final top = _order.first;
                          // Offer cards show their badge ("1+1"/"20%") + caption;
                          // plain cards show the category rate.
                          final disp = widget.displays[top.card.id];
                          return CardVisual(
                            card: top.card,
                            headline: disp?.$1 ??
                                '${(top.rec.effectiveRate * 100).toStringAsFixed(2)}%',
                            caption: disp?.$2 ??
                                'back on ${prettyCategory(widget.category)}',
                          );
                        }),
                      )
                    : GestureDetector(
                        onTap: () => _promote(i),
                        child: _BackCard(
                          rank: i + 1,
                          ranked: _order[i],
                          stripHeight: _strip,
                        ),
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
    final (a, b) = faceColors(ranked.card);
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
                      Text(displayIssuer(ranked.card.issuer),
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

class _OfferTile extends StatefulWidget {
  final OfferInfo offer;
  final String category;
  const _OfferTile({required this.offer, required this.category});

  @override
  State<_OfferTile> createState() => _OfferTileState();
}

class _OfferTileState extends State<_OfferTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final swatch = parseHex(offer.colorPrimary);
    final hasDesc =
        offer.description != null && offer.description!.isNotEmpty;
    return GestureDetector(
      onTap: hasDesc ? () => setState(() => _expanded = !_expanded) : null,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Container(
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
                    .withValues(
                        alpha: t.brightness == Brightness.dark ? 0.8 : 0.5),
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
                child: Icon(
                    _categoryIcons[widget.category] ??
                        Icons.card_giftcard_outlined,
                    size: 17,
                    color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(offer.title,
                              maxLines: _expanded ? null : 1,
                              overflow:
                                  _expanded ? null : TextOverflow.ellipsis,
                              style: t.textTheme.titleSmall),
                        ),
                        if (hasDesc)
                          Icon(
                              _expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: scheme.onSurfaceVariant),
                      ],
                    ),
                    if (hasDesc) ...[
                      const SizedBox(height: 2),
                      Text(offer.description!,
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
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
                                letterSpacing: 0,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live merchant offers (from /search)
// ---------------------------------------------------------------------------

class MerchantOfferView {
  final String title;
  final String? description;
  final String? cardHint;
  final String? validUntil;
  final String? via; // delivering program, e.g. "The Entertainer"
  final double? valuePct; // LLM-estimated effective saving %
  final String? shortLabel; // deck badge, e.g. "1+1", "30%"
  final bool held; // the offer's card is in the user's wallet

  const MerchantOfferView({
    required this.title,
    this.description,
    this.cardHint,
    this.validUntil,
    this.via,
    this.valuePct,
    this.shortLabel,
    this.held = false,
  });

  factory MerchantOfferView.fromJson(
      Map<String, dynamic> json, List<String> heldNames) {
    final hint = (json['card_hint'] as String?)?.trim();
    final held = hint != null && hint.isNotEmpty && _matchesHeld(hint, heldNames);
    final via = (json['via'] as String?)?.trim();
    final vp = json['value_pct'];
    final label = (json['short_label'] as String?)?.trim();
    return MerchantOfferView(
      title: (json['title'] as String?)?.trim() ?? '',
      description: json['description'] as String?,
      cardHint: (hint != null && hint.isEmpty) ? null : hint,
      validUntil: json['valid_until'] as String?,
      via: (via != null && via.isEmpty) ? null : via,
      valuePct: vp is num ? vp.toDouble() : null,
      shortLabel: (label != null && label.isNotEmpty) ? label : null,
      held: held,
    );
  }

  static bool _matchesHeld(String hint, List<String> heldNames) =>
      offerHintMatchesAny(hint, heldNames);
}

class _MerchantOfferTile extends StatefulWidget {
  final MerchantOfferView offer;
  const _MerchantOfferTile({required this.offer});

  @override
  State<_MerchantOfferTile> createState() => _MerchantOfferTileState();
}

class _MerchantOfferTileState extends State<_MerchantOfferTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final hasDesc = offer.description != null && offer.description!.isNotEmpty;
    return GestureDetector(
      onTap: hasDesc ? () => setState(() => _expanded = !_expanded) : null,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Container(
          key: const Key('merchant_offer'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: offer.held
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: (t.brightness == Brightness.dark
                        ? Colors.black
                        : const Color(0xFF272219))
                    .withValues(
                        alpha: t.brightness == Brightness.dark ? 0.8 : 0.5),
                blurRadius: 18,
                spreadRadius: -14,
                offset: const Offset(0, 6),
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
                    child: Text(offer.title,
                        style: t.textTheme.titleSmall,
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded ? null : TextOverflow.ellipsis),
                  ),
                  if (hasDesc)
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              if (hasDesc) ...[
                const SizedBox(height: 3),
                Text(offer.description!,
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: t.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        height: 1.35,
                        color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 8),
              Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (offer.cardHint != null)
                _Badge(
                  text: offer.cardHint!,
                  color: scheme.onSurfaceVariant,
                  background: scheme.onSurface.withValues(alpha: 0.06),
                ),
              if (offer.held)
                _Badge(
                  text: 'In your wallet',
                  color: scheme.onPrimary,
                  background: scheme.primary,
                ),
              if (offer.via != null)
                _Badge(
                  text: 'via ${offer.via}',
                  color: scheme.onSurfaceVariant,
                  background: scheme.onSurface.withValues(alpha: 0.06),
                  icon: Icons.card_membership,
                ),
              if (offer.validUntil != null && offer.validUntil!.isNotEmpty)
                _Badge(
                  text: 'Until ${offer.validUntil}',
                  color: t.extension<ConciergeColors>()!.capInk,
                  background: t.extension<ConciergeColors>()!.capBg,
                  icon: Icons.schedule,
                ),
            ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final IconData? icon;
  const _Badge({
    required this.text,
    required this.color,
    required this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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
          Text(status ?? 'No card in your wallet covers ${prettyCategory(category)} yet.',
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


// ===========================================================================
// Wallet tab
// ===========================================================================

class WalletTab extends StatefulWidget {
  final CardDao dao;
  final IngestService? ingest;
  final Analytics analytics;
  final ProfileStore profile;
  final VoidCallback? onWalletChanged;

  const WalletTab({
    super.key,
    required this.dao,
    required this.analytics,
    required this.profile,
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
    // Drop from the visible list first so a swipe-dismissed card isn't rebuilt.
    setState(() => _held = [...?_held]..removeWhere((x) => x.id == card.id));
    await widget.dao.setHeld(card.id, false);
    widget.onWalletChanged?.call();
    if (mounted) {
      // Same top banner as "Added", with an Undo action.
      _walletToast('Removed ${card.name}',
          icon: Icons.delete_outline,
          actionLabel: 'Undo',
          onAction: () async {
            await widget.dao.setHeld(card.id, true);
            await _load();
            widget.onWalletChanged?.call();
          });
    }
  }

  /// Card info sheet: fee, network, and the reward rules (what it earns where).
  Future<void> _showCardInfo(CardInfo card) async {
    final details = await widget.dao.cardDetails(card.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CardInfoSheet(card: card, details: details),
    );
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddCardSheet(
          dao: widget.dao,
          ingest: widget.ingest,
          analytics: widget.analytics,
          country: widget.profile.country),
    );
    if (added == true) {
      await _load();
      widget.onWalletChanged?.call();
      if (mounted) _walletToast('Added to your wallet');
    }
  }

  /// Confirmation banner that slides down from the top — clear of the pinned
  /// "Add a card" button and bottom nav. Optional Undo action.
  void _walletToast(String message,
      {IconData icon = Icons.check_circle,
      String? actionLabel,
      VoidCallback? onAction}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        onDone: entry.remove,
      ),
    );
    overlay.insert(entry);
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
                      const SizedBox(height: 18),
                      for (final c in held)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          // Swipe left reveals a Remove action; the card stops
                          // partway (no full-swipe) so nothing deletes by
                          // accident — the user must tap Remove.
                          child: Slidable(
                            key: ValueKey('card_${c.id}'),
                            groupTag: 'wallet',
                            endActionPane: ActionPane(
                              motion: const DrawerMotion(),
                              extentRatio: 0.30,
                              children: [
                                SlidableAction(
                                  key: Key('remove_${c.id}'),
                                  onPressed: (_) => _remove(c),
                                  backgroundColor: scheme.errorContainer,
                                  foregroundColor: scheme.onErrorContainer,
                                  icon: Icons.delete_outline,
                                  label: 'Remove',
                                  borderRadius:
                                      BorderRadius.circular(kCardRadius),
                                ),
                              ],
                            ),
                            child: CardVisual(
                                card: c, onInfo: () => _showCardInfo(c)),
                          ),
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
  final Analytics analytics;
  final String country;
  const _AddCardSheet(
      {required this.dao,
      required this.analytics,
      required this.country,
      this.ingest});

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  // Card colour is chosen after the fetch, once the card is on screen.
  CardGradient _gradient = randomGradient();
  // Fetched card payload(s); null until the doc is fetched. Non-null flips the
  // sheet from "type a name" to "here's your card — pick a colour".
  List<Map<String, dynamic>>? _fetched;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Step 1: fetch the card's rewards. On success, reveal the card + colours.
  Future<void> _fetch() async {
    final ingest = widget.ingest;
    // Validate/sanitize the card name before it leaves the device.
    final String name;
    try {
      name = sanitizeQuery(_name.text);
    } on InputGuardException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (ingest == null) {
      setState(() => _error = 'Ingestion service not configured.');
      return;
    }
    // Client rate limit (10/min, shared with search).
    if (!queryRateLimiter.tryAcquire()) {
      final secs = queryRateLimiter.retryAfter().inSeconds;
      setState(() => _error = 'Too many requests — try again in ${secs}s.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cards = await ingest.ingest(name, country: widget.country);
      setState(() {
        _busy = false;
        _fetched = cards;
        _gradient = randomGradient(); // assign a colour, highlighted below
      });
    } catch (_) {
      widget.analytics.log(Analytics.cardAddedFail);
      setState(() {
        _busy = false;
        _error = kFriendlyError;
      });
    }
  }

  /// Step 2: persist the fetched card(s) with the chosen colour.
  Future<void> _confirm() async {
    final cards = _fetched;
    if (cards == null) return;
    setState(() => _busy = true);
    try {
      // First card uses the chosen gradient; extras get distinct presets.
      final palette = distinctGradients(_gradient, cards.length);
      for (var i = 0; i < cards.length; i++) {
        await widget.dao.insertExtraction(
          cards[i],
          colorPrimary: palette[i].primary,
          colorSecondary: palette[i].secondary,
        );
      }
      widget.analytics.log(Analytics.cardAddedSuccess);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _busy = false;
        _error = kFriendlyError;
      });
    }
  }

  CardInfo _previewCard(Map<String, dynamic> data, CardGradient g) {
    final c = data['card'] as Map<String, dynamic>;
    return CardInfo(
      id: c['id'] as String,
      name: c['name'] as String? ?? '',
      issuer: c['issuer'] as String? ?? '',
      network: c['network'] as String? ?? 'other',
      colorPrimary: g.primary,
      colorSecondary: g.secondary,
      held: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final fetched = _fetched;
    final palette =
        fetched == null ? const <CardGradient>[] : distinctGradients(_gradient, fetched.length);

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
          Text(fetched == null ? 'Add a card' : 'Pick a colour',
              style: GoogleFontsSafe.title(t)),
          const SizedBox(height: 5),
          Text(
              fetched == null
                  ? 'Type the card name. We find its rewards.'
                  : 'Tap a colour, then add it to your wallet.',
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),

          // --- Step 1: name input (hidden once fetched) ---
          if (fetched == null)
            TextField(
              key: const Key('new_card_field'),
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: 'e.g. Emirates NBD Titanium',
                enabledBorder: _busy
                    ? null
                    : OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: _error != null
                            ? BorderSide(color: scheme.error)
                            : BorderSide.none),
              ),
              onSubmitted: (_) => _fetch(),
            ),

          // --- Step 2: card preview + colour picker ---
          if (fetched != null) ...[
            for (var i = 0; i < fetched.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              CardVisual(card: _previewCard(fetched[i], palette[i])),
            ],
            const SizedBox(height: 18),
            Text('Card colour',
                style: t.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            _GradientPicker(
              selected: _gradient,
              onSelected: (g) => setState(() => _gradient = g),
            ),
          ],

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
              onPressed: fetched == null ? _fetch : _confirm,
              child: Text(fetched == null ? 'Find card' : 'Add card'),
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

/// Success banner that slides in from the top, holds ~2.4s, slides out.
class _TopToast extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _TopToast({
    required this.message,
    required this.onDone,
    this.icon = Icons.check_circle,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(const Duration(milliseconds: 2400));
    await _dismiss();
  }

  Future<void> _dismiss() async {
    if (_closed) return;
    _closed = true;
    if (mounted) await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: Offset.zero)
              .animate(curve),
          child: FadeTransition(
            opacity: curve,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(widget.icon, color: scheme.onPrimary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(widget.message,
                            style: TextStyle(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (widget.actionLabel != null)
                        GestureDetector(
                          onTap: () {
                            widget.onAction?.call();
                            _dismiss();
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(widget.actionLabel!,
                                style: TextStyle(
                                    color: scheme.onPrimary,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                    decorationColor: scheme.onPrimary)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of tappable gradient swatches for the add-card sheet.
class _GradientPicker extends StatelessWidget {
  final CardGradient selected;
  final ValueChanged<CardGradient> onSelected;
  const _GradientPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presetGradients.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final g = presetGradients[i];
          final isSel = g.name == selected.name;
          final a = parseHex(g.primary)!;
          final b = parseHex(g.secondary)!;
          return GestureDetector(
            key: Key('swatch_${g.name}'),
            onTap: () => onSelected(g),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: cardFace(a, b),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? scheme.primary : scheme.outline,
                  width: isSel ? 2.5 : 1,
                ),
              ),
              child: isSel
                  ? Icon(Icons.check, size: 18, color: cardInk(a, b))
                  : null,
            ),
          );
        },
      ),
    );
  }
}
