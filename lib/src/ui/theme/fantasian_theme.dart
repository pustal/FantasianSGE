/// The app's look: a night-sky and parchment palette with brass-gold accents
/// and a crystal blue, inspired by FANTASIAN's hand-built diorama world.
library;

import 'package:flutter/material.dart';

/// Named colours used across the app.
abstract final class FantasianPalette {
  /// Deepest night sky, the dark background.
  static const Color midnight = Color(0xFF0B1028);

  /// Night sky used for dark surfaces.
  static const Color nightSky = Color(0xFF16204A);

  /// Raised dark surface.
  static const Color dusk = Color(0xFF223066);

  /// Brass gold, the primary accent.
  static const Color brass = Color(0xFFE0B456);

  /// Darker gold for text on light backgrounds.
  static const Color bronze = Color(0xFF8A5A14);

  /// Glowing save-crystal blue, the secondary accent.
  static const Color crystal = Color(0xFF6CCBEC);

  /// Deep crystal blue for light mode.
  static const Color deepCrystal = Color(0xFF1F5C9A);

  /// Old parchment, the light background.
  static const Color parchment = Color(0xFFF5ECD7);

  /// Slightly darker parchment for light surfaces.
  static const Color vellum = Color(0xFFEADDBF);

  /// Ink used for text on parchment.
  static const Color ink = Color(0xFF2A2116);

  /// Ember red for errors and warnings.
  static const Color ember = Color(0xFFC2553A);
}

/// Builds the light and dark [ThemeData].
abstract final class FantasianTheme {
  /// Serif display face for titles (bundled, OFL).
  static const String displayFont = 'Cinzel';

  /// Rounded sans face for body text (bundled, OFL).
  static const String bodyFont = 'Nunito';

  /// Parchment theme.
  static ThemeData light() => _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: FantasianPalette.bronze,
      onPrimary: Color(0xFFFFF8E6),
      primaryContainer: Color(0xFFF3D99A),
      onPrimaryContainer: FantasianPalette.ink,
      secondary: FantasianPalette.deepCrystal,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFCDEBF7),
      onSecondaryContainer: Color(0xFF0C2E4F),
      tertiary: FantasianPalette.ember,
      onTertiary: Colors.white,
      error: Color(0xFFA63A22),
      onError: Colors.white,
      errorContainer: Color(0xFFF7D6CB),
      onErrorContainer: Color(0xFF4A1206),
      surface: FantasianPalette.parchment,
      onSurface: FantasianPalette.ink,
      surfaceContainerLowest: Color(0xFFFFFBF1),
      surfaceContainerLow: Color(0xFFF9F1DF),
      surfaceContainer: Color(0xFFF1E5CA),
      surfaceContainerHigh: FantasianPalette.vellum,
      surfaceContainerHighest: Color(0xFFE2D2AE),
      onSurfaceVariant: Color(0xFF5C4B33),
      outline: Color(0xFFB59A66),
      outlineVariant: Color(0xFFD9C59A),
    ),
  );

  /// Night-sky theme.
  static ThemeData dark() => _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: FantasianPalette.brass,
      onPrimary: Color(0xFF2E1F02),
      primaryContainer: Color(0xFF5E4413),
      onPrimaryContainer: Color(0xFFFBE3A0),
      secondary: FantasianPalette.crystal,
      onSecondary: Color(0xFF032A3B),
      secondaryContainer: Color(0xFF184A6E),
      onSecondaryContainer: Color(0xFFD9FAFF),
      tertiary: Color(0xFFE88A6E),
      onTertiary: Color(0xFF3B0F04),
      error: Color(0xFFF2A08A),
      onError: Color(0xFF4A1206),
      errorContainer: Color(0xFF6E2513),
      onErrorContainer: Color(0xFFFFDAD0),
      surface: FantasianPalette.midnight,
      onSurface: Color(0xFFF1E9D6),
      surfaceContainerLowest: Color(0xFF070B1E),
      surfaceContainerLow: Color(0xFF111A3D),
      surfaceContainer: FantasianPalette.nightSky,
      surfaceContainerHigh: Color(0xFF1C2858),
      surfaceContainerHighest: FantasianPalette.dusk,
      onSurfaceVariant: Color(0xFFC9BE9F),
      outline: Color(0xFF7D6B45),
      outlineVariant: Color(0xFF3A4675),
    ),
  );

  /// Shared component styling for both brightnesses.
  static ThemeData _build(ColorScheme scheme) {
    final ThemeData base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: bodyFont,
      scaffoldBackgroundColor: scheme.surface,
    );
    final TextTheme text = base.textTheme;
    // The bundled fonts are variable; FontVariation selects the weight axis.
    TextStyle? display(TextStyle? style, double weight) => style?.copyWith(
      fontFamily: displayFont,
      // Cinzel covers Latin letters only; fall back for symbols and accents.
      fontFamilyFallback: const <String>[bodyFont],
      fontWeight: FontWeight.values[(weight / 100).round() - 1],
      fontVariations: <FontVariation>[FontVariation.weight(weight)],
      letterSpacing: 0.6,
      color: scheme.onSurface,
    );
    TextStyle? body(TextStyle? style, double weight) => style?.copyWith(
      fontWeight: FontWeight.values[(weight / 100).round() - 1],
      fontVariations: <FontVariation>[FontVariation.weight(weight)],
    );

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: display(text.displaySmall, 700),
        headlineMedium: display(text.headlineMedium, 700),
        headlineSmall: display(text.headlineSmall, 600),
        titleLarge: display(text.titleLarge, 600),
        titleMedium: body(text.titleMedium, 700),
        titleSmall: body(text.titleSmall, 700),
        bodyLarge: body(text.bodyLarge, 400),
        bodyMedium: body(text.bodyMedium, 400),
        bodySmall: body(text.bodySmall, 400),
        labelLarge: body(text.labelLarge, 700),
        labelMedium: body(text.labelMedium, 600),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontFamily: bodyFont,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface, fontFamily: bodyFont),
      ),
    );
  }
}
