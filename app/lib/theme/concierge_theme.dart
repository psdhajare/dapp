// lib/theme/concierge_theme.dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic tokens ColorScheme doesn't cover (cap/hint pills, deck scrim, nav fill).
@immutable
class ConciergeColors extends ThemeExtension<ConciergeColors> {
  const ConciergeColors({
    required this.capBg,
    required this.capInk,
    required this.hintBg,
    required this.hintInk,
    required this.scrimTop,
    required this.scrimBottom,
    required this.navFill,
  });
  final Color capBg, capInk, hintBg, hintInk, scrimTop, scrimBottom, navFill;

  static const light = ConciergeColors(
      capBg: Color(0xFFF5E6CE),
      capInk: Color(0xFF8A5200),
      hintBg: Color(0xFFE4EAF5),
      hintInk: Color(0xFF3B5B9E),
      scrimTop: Color(0x8516110A),
      scrimBottom: Color(0xB816110A), // rgba(22,17,10,.52/.72)
      navFill: Color(0xEBF6F1E8));
  static const dark = ConciergeColors(
      capBg: Color(0x21F0B168),
      capInk: Color(0xFFE8B171), // 13% tints
      hintBg: Color(0x21A9BEE4),
      hintInk: Color(0xFFA9BEE4),
      scrimTop: Color(0x8516110A),
      scrimBottom: Color(0xB816110A),
      navFill: Color(0xEB171310));

  @override
  ConciergeColors copyWith(
          {Color? capBg,
          Color? capInk,
          Color? hintBg,
          Color? hintInk,
          Color? scrimTop,
          Color? scrimBottom,
          Color? navFill}) =>
      ConciergeColors(
          capBg: capBg ?? this.capBg,
          capInk: capInk ?? this.capInk,
          hintBg: hintBg ?? this.hintBg,
          hintInk: hintInk ?? this.hintInk,
          scrimTop: scrimTop ?? this.scrimTop,
          scrimBottom: scrimBottom ?? this.scrimBottom,
          navFill: navFill ?? this.navFill);

  @override
  ConciergeColors lerp(ConciergeColors? o, double t) {
    if (o == null) return this;
    Color f(Color a, Color b) => Color.lerp(a, b, t)!;
    return ConciergeColors(
        capBg: f(capBg, o.capBg),
        capInk: f(capInk, o.capInk),
        hintBg: f(hintBg, o.hintBg),
        hintInk: f(hintInk, o.hintInk),
        scrimTop: f(scrimTop, o.scrimTop),
        scrimBottom: f(scrimBottom, o.scrimBottom),
        navFill: f(navFill, o.navFill));
  }
}

const _light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2F6B4F),
    onPrimary: Color(0xFFF4EFE4),
    secondary: Color(0xFF7D7365),
    onSecondary: Color(0xFFFFFDF8),
    surface: Color(0xFFFFFDF8),
    onSurface: Color(0xFF272219),
    onSurfaceVariant: Color(0xFF7D7365),
    outline: Color(0x1F272219),
    outlineVariant: Color(0x14272219),
    error: Color(0xFFA6392E),
    onError: Color(0xFFFFFDF8),
    errorContainer: Color(0xFFF7DCD6),
    onErrorContainer: Color(0xFF7A2A21),
    inverseSurface: Color(0xFF272219),
    onInverseSurface: Color(0xFFF6F1E8),
    surfaceTint: Colors.transparent);

const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8CBEA3),
    onPrimary: Color(0xFF12271C),
    secondary: Color(0xFFA89D8B),
    onSecondary: Color(0xFF211C15),
    surface: Color(0xFF211C15),
    onSurface: Color(0xFFEFE8DB),
    onSurfaceVariant: Color(0xFFA89D8B),
    outline: Color(0x1CEFE8DB),
    outlineVariant: Color(0x12EFE8DB),
    error: Color(0xFFE8A49B),
    onError: Color(0xFF4A1710),
    errorContainer: Color(0xFF5C241B),
    onErrorContainer: Color(0xFFF7DCD6),
    inverseSurface: Color(0xFFEFE8DB),
    onInverseSurface: Color(0xFF171310),
    surfaceTint: Colors.transparent);

TextTheme _text(ColorScheme s) => TextTheme(
    displaySmall: GoogleFonts.newsreader(
        fontSize: 31, fontWeight: FontWeight.w500, height: 1.1, color: s.onSurface),
    headlineLarge: GoogleFonts.newsreader(
        fontSize: 40,
        fontWeight: FontWeight.w500,
        height: 1.0,
        color: s.onSurface,
        fontFeatures: const [
          FontFeature.tabularFigures(),
          FontFeature.liningFigures()
        ]),
    titleMedium: GoogleFonts.newsreader(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
        color: s.onSurface),
    titleSmall: GoogleFonts.sourceSans3(
        fontSize: 14.5, fontWeight: FontWeight.w600, color: s.onSurface),
    bodyMedium:
        GoogleFonts.sourceSans3(fontSize: 14.5, height: 1.4, color: s.onSurface),
    bodySmall: GoogleFonts.sourceSans3(
        fontSize: 12, fontWeight: FontWeight.w500, height: 1.4, color: s.onSurface),
    labelLarge: GoogleFonts.sourceSans3(fontSize: 15, fontWeight: FontWeight.w600),
    labelMedium: GoogleFonts.sourceSans3(fontSize: 10.5, fontWeight: FontWeight.w600),
    labelSmall: GoogleFonts.sourceSans3(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.7,
        color: s.onSurfaceVariant));

ThemeData conciergeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final s = dark ? _dark : _light;
  final x = dark ? ConciergeColors.dark : ConciergeColors.light;
  return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF171310) : const Color(0xFFF6F1E8),
      textTheme: _text(s),
      extensions: [x],
      splashFactory: InkSparkle.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              backgroundColor: s.primary,
              foregroundColor: s.onPrimary,
              textStyle: GoogleFonts.sourceSans3(
                  fontSize: 15, fontWeight: FontWeight.w600))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: s.primary,
          foregroundColor: s.onPrimary,
          elevation: 4,
          shape: const CircleBorder(),
          sizeConstraints:
              const BoxConstraints.tightFor(width: 56, height: 56)),
      navigationBarTheme: NavigationBarThemeData(
          height: 74,
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
              size: 22,
              color: st.contains(WidgetState.selected)
                  ? s.primary
                  : s.onSurfaceVariant)),
          labelTextStyle: WidgetStateProperty.resolveWith((st) =>
              GoogleFonts.sourceSans3(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: st.contains(WidgetState.selected)
                      ? s.primary
                      : s.onSurfaceVariant))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor:
              dark ? const Color(0x14EFE8DB) : const Color(0x0F272219),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          hintStyle:
              GoogleFonts.sourceSans3(fontSize: 14.5, color: s.onSurfaceVariant)),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: s.surface,
          modalBarrierColor: (dark ? Colors.black : const Color(0xFF272219))
              .withValues(alpha: .32),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: s.inverseSurface,
          contentTextStyle: GoogleFonts.sourceSans3(
              fontSize: 13.5, color: s.onInverseSurface),
          actionTextColor:
              dark ? const Color(0xFF2F6B4F) : const Color(0xFF8CBEA3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))));
}

// ---------- Card face rules ----------
const double kCardRadius = 20.0;
const double kCardAspect = 1.586; // ISO 7810

LinearGradient cardFace(Color a, Color b) => LinearGradient(
    begin: Alignment.topLeft,
    end: const Alignment(0.94, 0.77),
    colors: [a, b]); // ≈130°

/// On-card ink switches by face luminance (Apple Card white → espresso).
Color cardInk(Color a, Color b) =>
    Color.lerp(a, b, .5)!.computeLuminance() > .55
        ? const Color(0xF2201A12)
        : Colors.white;

/// Runner-up strip scrim (keeps white ink readable on any face).
LinearGradient deckScrim(ConciergeColors x) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [x.scrimTop, x.scrimBottom]);

// ---------- Motion ----------
abstract final class ConciergeMotion {
  static const Duration stagger = Duration(milliseconds: 130);
  static const Duration entrance = Duration(milliseconds: 260);
  static const Duration chip = Duration(milliseconds: 180);
  static const Duration rerank = Duration(milliseconds: 320);
  static const Duration sheetIn = Duration(milliseconds: 320);
  static const Duration sheetOut = Duration(milliseconds: 240);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const double riseOffset = 12.0;
}
