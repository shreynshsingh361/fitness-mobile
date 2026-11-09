import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/palette.dart';
import '../core/widgets.dart';
import 'router.dart';

/// The layout is made for a phone. On a wider screen (a browser, a tablet) it stays
/// phone-sized in the middle instead of stretching across.
const _maxWidth = 560.0;

/// Hxvy is always dark: black pages, near-black cards and white as the accent.
ThemeData _theme() {
  final colors = ColorScheme.fromSeed(seedColor: Colors.grey, brightness: Brightness.dark).copyWith(
    primary: Hxvy.accent,
    onPrimary: Hxvy.onButton,
    // Without these the theme picks its own tints (a teal) for some widgets.
    primaryContainer: Hxvy.button,
    onPrimaryContainer: Hxvy.onButton,
    secondary: Hxvy.text,
    onSecondary: Hxvy.onButton,
    tertiary: Hxvy.text,
    onTertiary: Hxvy.onButton,
    tertiaryContainer: Hxvy.cardActive,
    onTertiaryContainer: Hxvy.text,
    surface: Hxvy.black,
    onSurface: Hxvy.text,
    onSurfaceVariant: Hxvy.textMuted,
    surfaceContainerLowest: Hxvy.black,
    surfaceContainerLow: Hxvy.card,
    surfaceContainer: const Color(0xFF1A1A1A),
    surfaceContainerHigh: Hxvy.cardActive,
    surfaceContainerHighest: const Color(0xFF2A2A2A),
    outline: const Color(0xFF5C5C5C),
    outlineVariant: Hxvy.border,
    secondaryContainer: Hxvy.cardActive,
    onSecondaryContainer: Hxvy.text,
  );
  final rounded = BorderRadius.circular(16);

  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: Hxvy.black,
    appBarTheme: const AppBarTheme(
      backgroundColor: Hxvy.black,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Hxvy.card,
      shape: RoundedRectangleBorder(
        borderRadius: rounded,
        side: const BorderSide(color: Hxvy.border),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Hxvy.button,
      foregroundColor: Hxvy.onButton,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: Hxvy.button, foregroundColor: Hxvy.onButton),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Hxvy.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Hxvy.accent, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Hxvy.card,
      shape: RoundedRectangleBorder(
        borderRadius: rounded,
        side: const BorderSide(color: Hxvy.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Hxvy.card),
    popupMenuTheme: PopupMenuThemeData(
      color: Hxvy.cardActive,
      shape: RoundedRectangleBorder(
        borderRadius: rounded,
        side: const BorderSide(color: Hxvy.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Hxvy.border),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Hxvy.cardActive,
      contentTextStyle: TextStyle(color: Hxvy.text),
    ),
    // See-through, so the glass behind it shows (see GlassBar).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: glassBarHeight,
      indicatorColor: Hxvy.accent.withValues(alpha: 0.18),
    ),
  );
}

class HxvyApp extends ConsumerWidget {
  const HxvyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Hxvy',
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    themeMode: ThemeMode.dark,
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => ColoredBox(
      color: Hxvy.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: child,
        ),
      ),
    ),
  );
}
