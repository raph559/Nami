import 'package:flutter/material.dart';

/// "Salle obscure" tokens, see DESIGN.md.
abstract final class Nami {
  static const ground = Color(0xFF0A0A0B);
  static const text = Color(0xFFEDEAE4);
  static const textSecondary = Color(0xFFB8B3AA);
  static const textMuted = Color(0xFF8F8B83);
  static final line = text.withValues(alpha: 0.12);

  static const serif = 'InstrumentSerif';
  static const sans = 'HankenGrotesk';

  static const radiusImage = 4.0;
  static const radiusButton = 6.0;

  static const heroTitle = TextStyle(fontFamily: serif, fontSize: 42, height: 1.02, color: text);
  static const pageTitle = TextStyle(fontFamily: serif, fontSize: 38, height: 1.04, color: text);
  static const section = TextStyle(fontFamily: serif, fontSize: 26, height: 1.1, color: text);
  static const body = TextStyle(fontFamily: sans, fontSize: 15, height: 1.45, color: text);
  static const meta = TextStyle(fontFamily: sans, fontSize: 14, height: 1.35, color: textSecondary);
  static const caption = TextStyle(fontFamily: sans, fontSize: 12, height: 1.3, color: textSecondary);

  /// Borders of controls: 45 % text over ground is 3.9:1, above the 3:1
  /// minimum for component boundaries.
  static final border = text.withValues(alpha: 0.45);

  /// The anime's own color is the only accent; without one, the text color.
  /// Dark colors are lightened until they reach 4.5:1 on the ground, since
  /// the accent is also used for small text ("Up next").
  static Color accentOf(Color? animeColor) {
    var c = animeColor ?? text;
    for (var i = 0; i < 20 && contrast(c, ground) < 4.5; i++) {
      c = Color.lerp(c, Colors.white, 0.12)!;
    }
    return c;
  }

  /// WCAG 2.x contrast ratio.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: text,
      onPrimary: ground,
      secondary: textSecondary,
      surface: ground,
      onSurface: text,
      surfaceContainerHighest: Color(0xFF1A1A1C),
      error: Color(0xFFFF8A80),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: sans);
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton));
    return base.copyWith(
      scaffoldBackgroundColor: ground,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: ground,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontFamily: serif, fontSize: 28, color: text),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: text,
          foregroundColor: ground,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          textStyle: const TextStyle(fontFamily: sans, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: border),
          shape: buttonShape,
          textStyle: const TextStyle(fontFamily: sans, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: textSecondary, minimumSize: const Size(48, 44)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ground,
        selectedColor: text,
        side: BorderSide(color: border),
        labelStyle: const TextStyle(fontFamily: sans, fontSize: 13, color: text),
        secondaryLabelStyle: const TextStyle(fontFamily: sans, fontSize: 13, color: ground),
        checkmarkColor: ground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ground,
        indicatorColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: sans,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? text : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? text : textMuted, size: 24),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        titleTextStyle: TextStyle(fontFamily: sans, fontSize: 15, color: text),
        subtitleTextStyle: TextStyle(fontFamily: sans, fontSize: 13, color: textSecondary),
        iconColor: textSecondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? ground : textMuted),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? text : const Color(0xFF2A2A2D),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? text : border),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: const TextStyle(color: textMuted),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: border)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: text)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF131315),
        dragHandleColor: textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: TextStyle(fontFamily: sans, color: ground),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: text),
      focusColor: text.withValues(alpha: 0.18),
    );
  }
}
