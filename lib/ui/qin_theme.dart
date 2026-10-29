import 'package:flutter/material.dart';

/// Semantic colors shared by browsing, teaching and timed practice.
@immutable
class QinPalette extends ThemeExtension<QinPalette> {
  const QinPalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.soft,
    required this.ink,
    required this.muted,
    required this.line,
    required this.edge,
    required this.disabled,
    required this.warning,
    required this.error,
    required this.highContrast,
  });
  static const standard = QinPalette(
    background: Color(0xfff8f7f1),
    surface: Color(0xfffffefa),
    primary: Color(0xff285c50),
    soft: Color(0xffeaf0e8),
    ink: Color(0xff1f2d28),
    muted: Color(0xff56645d),
    line: Color(0xffdcded4),
    edge: Color(0xff61776b),
    disabled: Color(0xffe5e9e5),
    warning: Color(0xff8a591f),
    error: Color(0xff963f36),
    highContrast: false,
  );
  static const contrast = QinPalette(
    background: Colors.white,
    surface: Colors.white,
    primary: Colors.black,
    soft: Colors.white,
    ink: Colors.black,
    muted: Color(0xff424242),
    line: Colors.black,
    edge: Colors.black,
    disabled: Color(0xffe0e0e0),
    warning: Colors.black,
    error: Colors.black,
    highContrast: true,
  );
  final Color background, surface, primary, soft, ink, muted, line, edge;
  final Color disabled, warning, error;
  final bool highContrast;
  Color get onPrimary => Colors.white;

  @override
  QinPalette copyWith({bool? highContrast}) =>
      (highContrast ?? this.highContrast) ? contrast : standard;

  // Color transitions must never interpolate timed cues or key states.
  @override
  QinPalette lerp(covariant QinPalette? other, double t) =>
      other == null || t < .5 ? this : other;
}

extension QinContext on BuildContext {
  QinPalette get qin =>
      Theme.of(this).extension<QinPalette>() ?? QinPalette.standard;
}

ThemeData qinTheme({required bool highContrast}) {
  final p = highContrast ? QinPalette.contrast : QinPalette.standard;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final colors = ColorScheme.light(
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.soft,
    onPrimaryContainer: p.ink,
    secondary: p.primary,
    onSecondary: p.onPrimary,
    secondaryContainer: p.soft,
    onSecondaryContainer: p.primary,
    tertiary: p.primary,
    onTertiary: p.onPrimary,
    tertiaryContainer: p.soft,
    onTertiaryContainer: p.ink,
    error: p.error,
    onError: p.onPrimary,
    errorContainer: p.surface,
    onErrorContainer: p.error,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.background,
    surfaceContainer: p.background,
    surfaceContainerHigh: p.soft,
    surfaceContainerHighest: p.disabled,
    outline: p.edge,
    outlineVariant: p.line,
    inverseSurface: p.ink,
    onInverseSurface: p.surface,
    inversePrimary: p.soft,
    surfaceTint: Colors.transparent,
  );
  final button = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(60, 60)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    shape: WidgetStatePropertyAll(shape),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25),
    ),
    animationDuration: Duration.zero,
    elevation: const WidgetStatePropertyAll(0),
  );
  return ThemeData(
    useMaterial3: true,
    extensions: [p],
    colorScheme: colors,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.surface,
    disabledColor: p.muted,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 22,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleSmall: TextStyle(
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      bodyLarge: TextStyle(fontSize: 20, height: 1.45, color: p.ink),
      bodyMedium: TextStyle(fontSize: 20, height: 1.4, color: p.ink),
      bodySmall: TextStyle(fontSize: 18, height: 1.4, color: p.muted),
      labelLarge: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: p.primary,
      ),
      labelMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.muted,
      ),
      labelSmall: TextStyle(fontSize: 14, height: 1.3, color: p.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      leadingWidth: 60,
      titleSpacing: 16,
      titleTextStyle: TextStyle(
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.disabled : p.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.muted : p.onPrimary,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.disabled : p.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.muted : p.primary,
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: p.edge,
            width: s.contains(WidgetState.focused)
                ? 3
                : highContrast
                ? 2
                : 1,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.muted : p.primary,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(60, 60),
        foregroundColor: p.primary,
        shape: shape,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.line, width: highContrast ? 2 : 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 88,
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.highContrast ? p.disabled : p.soft,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.primary : p.muted,
          size: 28,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 18,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? p.primary : p.muted,
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.disabled,
      borderRadius: BorderRadius.circular(4),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 16,
      minTileHeight: 72,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      iconColor: p.primary,
      textColor: p.ink,
      selectedColor: p.primary,
      selectedTileColor: p.soft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: p.surface,
      collapsedBackgroundColor: p.surface,
      iconColor: p.primary,
      collapsedIconColor: p.muted,
      textColor: p.ink,
      collapsedTextColor: p.ink,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.edge,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: p.primary,
      inactiveTrackColor: p.disabled,
      thumbColor: p.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onPrimary : p.edge,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : p.surface,
      ),
      trackOutlineColor: WidgetStatePropertyAll(p.edge),
    ),
  );
}
