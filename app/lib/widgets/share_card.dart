import 'package:flutter/material.dart';

import '../dao.dart';
import 'card_visual.dart';

/// A branded, screenshot-style poster of the user's best card for a category.
/// Fixed logical size so it renders identically off-screen for capture.
class ShareCard extends StatelessWidget {
  final CardInfo card;
  final String category; // e.g. 'dining'
  final String headline; // e.g. '5%'
  final String caption; // e.g. 'back on dining'

  const ShareCard({
    super.key,
    required this.card,
    required this.category,
    required this.headline,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 380,
      color: t.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My best card for $category',
            style: t.textTheme.displaySmall,
          ),
          const SizedBox(height: 24),
          CardVisual(card: card, headline: headline, caption: caption),
          const SizedBox(height: 26),
          Text(
            'ToroKard · always pay with your best card',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
