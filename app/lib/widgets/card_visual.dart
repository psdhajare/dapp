import 'package:flutter/material.dart';

import '../dao.dart';
import '../theme/concierge_theme.dart';
import '../util/formatting.dart';

const _fallbackFaces = [
  (Color(0xFF16161F), Color(0xFF2E2E48)), // midnight
  (Color(0xFF0C312D), Color(0xFF1E5F55)), // deep teal
  (Color(0xFF2E1622), Color(0xFF61344A)), // wine
  (Color(0xFF1F2A34), Color(0xFF3F5666)), // slate
];

Color? parseHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Two face hexes from ingestion, else a stable issuer-hashed fallback pair.
(Color, Color) faceColors(CardInfo card) {
  final a = parseHex(card.colorPrimary);
  if (a == null) {
    return _fallbackFaces[card.issuer.hashCode.abs() % _fallbackFaces.length];
  }
  final b = parseHex(card.colorSecondary) ??
      HSLColor.fromColor(a)
          .withLightness(
              (HSLColor.fromColor(a).lightness * 1.35).clamp(0.0, 1.0))
          .toColor();
  return (a, b);
}

// ---------------------------------------------------------------------------
// The card visual (hero)
// ---------------------------------------------------------------------------

class CardVisual extends StatelessWidget {
  final CardInfo card;
  final String? headline; // e.g. "5.00%"
  final String? caption; // e.g. "back on dining"
  final VoidCallback? onRemove;

  const CardVisual({
    super.key,
    required this.card,
    this.headline,
    this.caption,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (a, b) = faceColors(card);
    final ink = cardInk(a, b);
    final inkSoft = ink.withValues(alpha: 0.72);
    final inkFaint = ink.withValues(alpha: 0.5);
    final lightFace = ink != Colors.white;
    final issuer = displayIssuer(card.issuer);

    final semantics = headline != null
        ? 'Best card for ${caption?.replaceFirst('back on ', '') ?? ''}: '
            '$issuer ${card.name}, $headline back'
        : '$issuer ${card.name}';

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
                    child: Text(issuer.toUpperCase(),
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
