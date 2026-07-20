import 'package:flutter/material.dart';

/// Athlynk — Greek-luxury design system.
/// Ported 1:1 from iOS `Shared/Theme/Theme.swift` (which mirrors the web
/// `static/css/athlynk.css`): Royal Blue + restrained Gold on white/marble
/// surfaces, navy ink type. Legacy "volt/neon" names kept for source parity
/// with the iOS codebase so cross-referencing screens stays trivial.
///
/// Light-only by design (iOS forces `.preferredColorScheme(.light)`).

// ─────────────────────────────────────────────────────────────── Palette ──

class Palette {
  Palette._();

  // Surfaces
  static const Color void0 = Color(0xFFFFFFFF); // parchment — page background
  static const Color void1 = Color(0xFFF4F6F9); // marble — panel/card base
  static const Color void2 = Color(0xFFE8ECF2); // stone — raised insets/tracks

  /// Hairline border: ink at 12%.
  static const Color line = Color(0x1F0B1D3A);

  // Brand-overridable accents ("Aspetto" feature). Defaults = royal blue +
  // aegean. Mutated by [BrandTheme.apply]; the app remounts via themeVersion.
  static Color _brandPrimary = const Color(0xFF1E3A5F);
  static Color _brandAccent = const Color(0xFF5B89B6);

  /// Primary brand accent (Train tab, primary CTAs). iOS: `magenta`/`bronze`.
  static Color get magenta => _brandPrimary;
  static Color get bronze => _brandPrimary;
  static Color get primary => _brandPrimary;

  /// Secondary accent (Home tab, links, controls). iOS: `cyan`/`aegean`.
  static Color get cyan => _brandAccent;
  static Color get aegean => _brandAccent;
  static Color get control => _brandAccent;

  static const Color defaultPrimary = Color(0xFF1E3A5F);
  static const Color defaultAccent = Color(0xFF5B89B6);

  // Fixed accents
  static const Color lime = Color(0xFF3F7A5E); // Fuel tab, success
  static const Color success = lime;
  static const Color violet = Color(0xFF132A47); // Check tab, deep royal
  static const Color amber = Color(0xFFB8860B); // Altro tab, text-safe gold
  static const Color phase = Color(0xFF5C4A6B); // journey "fasi" plum
  static const Color crimson = Color(0xFFA23B3B); // destructive/error
  static const Color danger = crimson;

  // Ink
  static const Color textHi = Color(0xFF0B1D3A);
  static const Color textMid = Color(0xFF4B5D75);
  static const Color textLow = Color(0xFF7C8CA3);

  // Gold: glow/highlight only — never a solid fill or text color.
  static const Color gold = Color(0xFFFFE066);
  static const Color goldText = Color(0xFF9C7A1F); // gold-safe text (eyebrows)

  /// Rotating accent list used to color list rows/cards distinctly.
  static List<Color> get accents => [cyan, magenta, lime, violet, amber];

  static Color accent(int i) => accents[i % accents.length];

  /// Ink-based shadow color used by panels/glows.
  static const Color inkShadow = Color(0xFF0B1D3A);
}

/// Parses `#RRGGBB` (7 chars incl. `#`, mirrors web `_HEX_RE`); null otherwise.
Color? colorFromHexString(String? s) {
  if (s == null) return null;
  final v = s.trim();
  if (v.length != 7 || !v.startsWith('#')) return null;
  final n = int.tryParse(v.substring(1), radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}

extension ColorHexString on Color {
  /// Round-trips to `#RRGGBB` (uppercase, like iOS `.hexString`).
  String get hexString {
    String c(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${c(r)}${c(g)}${c(b)}'.toUpperCase();
  }
}

// ──────────────────────────────────────────────────────────── BrandTheme ──

/// Per-user white-label override of the two brand colors, persisted like the
/// iOS UserDefaults keys and applied before profile fetch resolves so the app
/// opens in the right colors immediately.
class BrandTheme {
  BrandTheme._();

  static const prefsPrimaryKey = 'athlynk.brand.primary';
  static const prefsAccentKey = 'athlynk.brand.accent';

  /// Bumped on every apply; the root listens and remounts (iOS `.id()` trick).
  static final ValueNotifier<int> themeVersion = ValueNotifier(0);

  /// Loads persisted hex strings into [Palette] (call at bootstrap).
  static void load(String? primaryHex, String? accentHex) {
    Palette._brandPrimary =
        colorFromHexString(primaryHex) ?? Palette.defaultPrimary;
    Palette._brandAccent =
        colorFromHexString(accentHex) ?? Palette.defaultAccent;
  }

  /// Applies + bumps [themeVersion] so the widget tree rebuilds with the new
  /// colors. Persistence is done by the caller (SessionController owns prefs).
  static void apply({Color? primary, Color? accent}) {
    Palette._brandPrimary = primary ?? Palette.defaultPrimary;
    Palette._brandAccent = accent ?? Palette.defaultAccent;
    themeVersion.value++;
  }

  static void reset() => apply();
}

// ─────────────────────────────────────────────────────────────────── Typo ──

/// Type roles. iOS: Didot (poster/display) ≈ Bodoni Moda, SF body ≈ Inter,
/// SF Mono ≈ JetBrains Mono — the substitutions the iOS comments themselves
/// name. All three ship as bundled variable fonts.
class Typo {
  Typo._();

  static const String serif = 'BodoniModa';
  static const String sans = 'Inter';
  static const String monoFamily = 'JetBrainsMono';

  /// Monumental serif display — big headline words & huge numerals.
  static TextStyle poster(double size, {Color color = Palette.textHi}) =>
      TextStyle(
        fontFamily: serif,
        fontSize: size,
        color: color,
        height: 1.04,
        fontWeight: FontWeight.w600,
        fontVariations: [
          const FontVariation('wght', 600),
          FontVariation('opsz', size.clamp(6, 96).toDouble()),
        ],
      );

  /// Smaller serif headings (section/card titles).
  static TextStyle display(double size, {Color color = Palette.textHi}) =>
      TextStyle(
        fontFamily: serif,
        fontSize: size,
        color: color,
        height: 1.12,
        fontWeight: FontWeight.w600,
        fontVariations: [
          const FontVariation('wght', 600),
          FontVariation('opsz', size.clamp(6, 96).toDouble()),
        ],
      );

  /// HUD readouts: stats, timers, loads, eyebrows, badges.
  static TextStyle mono(double size,
      [FontWeight weight = FontWeight.w600, Color color = Palette.textHi]) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.2,
      fontVariations: [FontVariation('wght', _wghtOf(weight))],
    );
  }

  /// Body copy.
  static TextStyle body(double size,
      [FontWeight weight = FontWeight.w400, Color color = Palette.textHi]) {
    return TextStyle(
      fontFamily: sans,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.35,
      fontVariations: [FontVariation('wght', _wghtOf(weight))],
    );
  }

  static double _wghtOf(FontWeight w) => w.value.toDouble();

  /// Eyebrow label style (iOS `voltEyebrow`): mono 11 semibold, tracking 3,
  /// uppercase, goldText — apply `.toUpperCase()` to the string.
  static TextStyle eyebrow({Color color = Palette.goldText, double size = 11}) =>
      mono(size, FontWeight.w600, color).copyWith(letterSpacing: 3);
}

// ────────────────────────────────────────────────────────────────── Space ──

class Space {
  Space._();
  static const double screenH = 22; // horizontal page padding
  static const double section = 22; // vertical space between sections
  static const double card = 16; // card internal padding
  static const double element = 12; // spacing inside a card
}

class AppLayout {
  AppLayout._();

  /// Bottom clearance reserved for the floating tab bar on every scrollable
  /// screen (home-indicator inset + bar height + clearance).
  static const double tabBarClearance = 120;
  static const double screenTop = 64;
}

class Radii {
  Radii._();
  static const double card = 16; // default panel
  static const double field = 14; // inputs/buttons
  static const double chip = 12; // small chips/rows
  static const double hero = 20; // hero/dialog cards
}

// ───────────────────────────────────────────────────────────────── Motion ──

/// Motion tokens. iOS springs approximated with cubic curves tuned to read
/// identically at these durations.
class Motion {
  Motion._();

  /// Feedback: presses, toggles, chips. iOS spring(0.30, 0.70).
  static const Duration snappyDuration = Duration(milliseconds: 300);
  static const Curve snappy = Cubic(0.3, 1.15, 0.35, 1);

  /// Content: cards, layout shifts, reveals. iOS spring(0.55, 0.85).
  static const Duration luxeDuration = Duration(milliseconds: 550);
  static const Curve luxe = Cubic(0.22, 1.0, 0.36, 1);

  /// Big page-enter reveal. iOS spring(0.52, 0.86).
  static const Duration pageEnterDuration = Duration(milliseconds: 520);
  static const Curve pageEnter = Cubic(0.22, 1.0, 0.36, 1);

  /// Staggered list entrance step (per index).
  static const double staggerStep = 0.07;

  /// revealUp entrance. iOS spring(0.6, 0.82).
  static const Duration revealDuration = Duration(milliseconds: 600);
  static const Curve reveal = Cubic(0.2, 0.9, 0.25, 1);

  /// One-shot gold pulse (arrival/success moments).
  static const Duration glowIn = Duration(milliseconds: 320);
  static const Duration glowDecay = Duration(milliseconds: 900);
}

// ──────────────────────────────────────────────────────── Panel & shadows ──

/// The near-universal card style (iOS `voltPanel`): marble fill, hairline
/// stroke (optionally tinted), soft ink shadow.
BoxDecoration voltPanel({
  Color? tint,
  double radius = Radii.card,
  Color fill = Palette.void1,
}) {
  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: tint ?? Palette.line, width: 1),
    boxShadow: const [
      BoxShadow(
        color: Color(0x1A0B1D3A), // ink @ 10%
        blurRadius: 18,
        offset: Offset(0, 10),
      ),
    ],
  );
}

/// iOS `neonGlow` — repurposed long ago into a refined ink shadow ("gentle
/// depth, not glow"). Color param kept for call-site parity; ignored.
List<BoxShadow> neonGlow(Color color,
    {double radius = 14, double opacity = 0.7}) {
  final blur = (radius * 0.55).clamp(4.0, double.infinity);
  final dy = (radius * 0.28).clamp(2.0, double.infinity);
  return [
    BoxShadow(
      color: const Color(0x1F0B1D3A), // ink @ 12%
      blurRadius: blur,
      offset: Offset(0, dy),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────── ThemeData ──

/// Material 3 ThemeData carrying the Athlynk tokens. Light-only (parity with
/// iOS). Tokens live in the static classes above; ThemeData exists so stock
/// Material widgets (switches, pickers, dialogs) blend into the brand.
ThemeData athlynkTheme() {
  final scheme = ColorScheme.light(
    primary: Palette.magenta,
    onPrimary: Palette.void0,
    secondary: Palette.cyan,
    onSecondary: Palette.void0,
    surface: Palette.void0,
    onSurface: Palette.textHi,
    surfaceContainerHighest: Palette.void1,
    outline: Palette.line,
    error: Palette.crimson,
    onError: Palette.void0,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.void0,
    fontFamily: Typo.sans,
    splashFactory: NoSplash.splashFactory, // brand uses press-scale, not ripple
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.cyan,
      selectionColor: Palette.cyan.withValues(alpha: 0.25),
      selectionHandleColor: Palette.cyan,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.void0 : Palette.void0,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.cyan
            : Palette.void2,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Palette.textHi,
      centerTitle: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}
