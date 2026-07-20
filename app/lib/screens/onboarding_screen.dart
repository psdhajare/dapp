/// First-run welcome tour: a short swipeable carousel that explains what
/// ToroKard does, shows real screens, and makes the privacy promise explicit.
library;

import 'package:flutter/material.dart';

class _Slide {
  final IconData icon; // shown when [asset] is absent or fails to load
  final String? asset; // real app screenshot, if any
  final String title;
  final String body;
  const _Slide({required this.icon, this.asset, required this.title,
      required this.body});
}

const _slides = <_Slide>[
  _Slide(
    icon: Icons.auto_awesome_outlined,
    asset: 'assets/tour/deck.png',
    title: 'Always pay with your best card',
    body: 'ToroKard instantly shows which of your cards earns the most on '
        'every purchase. Cashback, points and miles, all in real money so '
        'you can compare at a glance.',
  ),
  _Slide(
    icon: Icons.add_card_outlined,
    asset: 'assets/tour/addcard.png',
    title: 'Adding a card is effortless',
    body: 'Just type the card name. We fetch its rewards, fees and offers '
        'for you. You never enter a card number and there is no bank login.',
  ),
  _Slide(
    icon: Icons.palette_outlined,
    asset: 'assets/tour/color.png',
    title: 'Make it truly yours',
    body: 'Pick a colour that matches your real card, so your wallet on '
        'screen feels just like the one in your pocket.',
  ),
  _Slide(
    icon: Icons.travel_explore_outlined,
    asset: 'assets/tour/search.png',
    title: 'Know before you pay',
    body: 'Search any shop or merchant, or choose a category, to see the '
        'winning card and any live offers for the cards in your wallet. '
        'Maximise your savings and cashback on every spend.',
  ),
  _Slide(
    icon: Icons.ios_share_outlined,
    asset: 'assets/tour/share.png',
    title: 'Share with friends',
    body: "Send your best pick to friends and family. Let's save together.",
  ),
  _Slide(
    icon: Icons.receipt_long_outlined,
    asset: 'assets/tour/info.png',
    title: 'Know what you might owe',
    body: 'See each card\'s APR, fees and interest free days up front. You '
        'have every right to know what a late payment could cost you.',
  ),
  _Slide(
    icon: Icons.lock_outline,
    asset: 'assets/tour/wallet.png',
    title: 'Your data stays on your phone',
    body: 'No account, no sign up, no tracking, no card numbers. Everything '
        'lives on this device and works mostly in offline mode.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      _pager.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _isLast ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  key: const Key('tour_skip'),
                  onPressed: _isLast ? null : widget.onDone,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color:
                          i == _index ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('tour_next'),
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_isLast ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;

    final iconBadge = Container(
      width: 96,
      height: 96,
      decoration:
          BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Icon(slide.icon, size: 44, color: scheme.onPrimaryContainer),
    );

    // Screenshot slides show the real screen (rounded + shadow); if the asset
    // is missing they degrade to the icon badge so the tour never breaks.
    Widget visual = iconBadge;
    if (slide.asset != null) {
      visual = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380, maxWidth: 240),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            slide.asset!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => iconBadge,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: DecoratedBox(
              decoration: slide.asset == null
                  ? const BoxDecoration()
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
              child: visual,
            ),
          ),
          const SizedBox(height: 32),
          Text(slide.title,
              textAlign: TextAlign.center, style: t.textTheme.displaySmall),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: t.textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}
