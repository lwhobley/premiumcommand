import 'package:flutter/material.dart';

/// Broadsheet palette: paper and ink, one interactive accent (cyan), one rare alert
/// accent (magenta), and a warm neutral ramp. Every color in the UI comes from here.
abstract final class AppColors {
  static const background = Color(0xFFF3F2F2); // paper
  static const surface = Color(0xFFEAE9E9);
  static const text = Color(0xFF201E1D); // ink
  static const divider = Color(0x29201E1D); // ink at 16%
  static const muted = neutral700; // secondary text

  static const accent = Color(0xFF0088B0);
  static const accent100 = Color(0xFFE9F8FF);
  static const accent200 = Color(0xFFCBEEFF);
  static const accent300 = Color(0xFF9CDDF5);
  static const accent600 = Color(0xFF1186AC);
  static const accent700 = Color(0xFF006786);
  static const accent800 = Color(0xFF004961);

  static const accent2 = Color(0xFFD6006C);
  static const accent2100 = Color(0xFFFFF1F4);
  static const accent2300 = Color(0xFFFFB3C9);
  static const accent2700 = Color(0xFFAA0B56);
  static const accent2800 = Color(0xFF790E3D);

  static const neutral100 = Color(0xFFF8F4F4);
  static const neutral200 = Color(0xFFEAE7E7);
  static const neutral300 = Color(0xFFD7D3D3);
  static const neutral400 = Color(0xFFBAB6B6);
  static const neutral500 = Color(0xFF9B9797);
  static const neutral600 = Color(0xFF7D7979);
  static const neutral700 = Color(0xFF605D5D);
  static const neutral800 = Color(0xFF444141);
  static const neutral900 = Color(0xFF2D2B2B);

  /// Neutral tag background.
  static const neutralTag = Color(0xFFE3E0E0);

  /// Ink at the given opacity, for hover and pressed fills and hairlines.
  static Color ink(double opacity) => text.withValues(alpha: opacity);
}

/// Spacing scale and the fixed layout measures.
abstract final class AppSpace {
  static const xs = 5.0;
  static const s = 10.0;
  static const m = 15.0;
  static const l = 20.0;
  static const xl = 30.0;
  static const xxl = 40.0;

  /// Horizontal padding of every screen.
  static const screen = 24.0;

  /// Space between sections, and between rows in a list.
  static const section = 32.0;
  static const row = 14.0;

  static const minTap = 44.0;
}

abstract final class AppRadius {
  static const base = 2.0;
  static const sheet = 4.0;
  static final all = BorderRadius.circular(base);
}

/// The one shadow: bottom sheets and dialogs only.
const appSheetShadow = [
  BoxShadow(color: Color(0x38201E1D), offset: Offset(0, 12), blurRadius: 32),
];

abstract final class AppText {
  static const fontFamily = 'SourceSerif4';

  static const screenTitle = TextStyle(
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.68, // -0.02em
    color: AppColors.text,
  );
  static const sectionHeading = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );
  static const rowTitle = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );
  static const body = TextStyle(
    fontSize: 15,
    height: 1.55,
    color: AppColors.text,
  );
  static const meta = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: AppColors.muted,
  );
  static const kicker = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1, // 0.1em
    color: AppColors.accent700,
  );
  static const tag = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const numeral = TextStyle(
    fontSize: 46,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.9,
    color: AppColors.text,
  );
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: AppColors.background,
      primaryContainer: AppColors.accent100,
      onPrimaryContainer: AppColors.accent800,
      secondary: AppColors.accent700,
      onSecondary: AppColors.background,
      secondaryContainer: AppColors.accent100,
      onSecondaryContainer: AppColors.accent800,
      tertiary: AppColors.accent2,
      onTertiary: AppColors.background,
      error: AppColors.accent2700,
      onError: AppColors.background,
      errorContainer: AppColors.accent2100,
      onErrorContainer: AppColors.accent2800,
      surface: AppColors.background,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surface,
      surfaceContainerHighest: AppColors.surface,
      surfaceTint: Colors.transparent,
      outline: AppColors.divider,
      outlineVariant: AppColors.divider,
      shadow: AppColors.text,
      scrim: AppColors.text,
      inverseSurface: AppColors.text,
      onInverseSurface: AppColors.background,
      inversePrimary: AppColors.accent200,
    );

    final shape = RoundedRectangleBorder(borderRadius: AppRadius.all);
    const divider = BorderSide(color: AppColors.divider);

    WidgetStateProperty<Color?> overlay(Color hover, Color pressed) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return pressed;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return hover;
          }
          return null;
        });

    // Focus is a 2px accent outline, offset 2: drawn as the focused button's border.
    WidgetStateProperty<OutlinedBorder?> focusShape(BorderSide rest) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? RoundedRectangleBorder(
                  borderRadius: AppRadius.all,
                  side: const BorderSide(
                    color: AppColors.accent,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                )
              : RoundedRectangleBorder(borderRadius: AppRadius.all, side: rest),
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppText.fontFamily,
    );
    final textTheme = base.textTheme
        .copyWith(
          displayLarge: AppText.numeral,
          headlineLarge: AppText.screenTitle,
          headlineMedium: AppText.screenTitle.copyWith(fontSize: 28),
          headlineSmall: AppText.sectionHeading.copyWith(fontSize: 24),
          titleLarge: AppText.sectionHeading,
          titleMedium: AppText.rowTitle.copyWith(fontSize: 17),
          titleSmall: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: AppText.body.copyWith(fontSize: 16),
          bodyMedium: AppText.body,
          bodySmall: AppText.meta,
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(
          fontFamily: AppText.fontFamily,
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
        );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      disabledColor: AppColors.ink(0.45),
      focusColor: AppColors.accent.withValues(alpha: 0.12),
      hoverColor: AppColors.ink(0.07),
      splashFactory: NoSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: const IconThemeData(color: AppColors.text, size: 22),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 8,
        iconColor: AppColors.accent700,
        textColor: AppColors.text,
        titleTextStyle: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 13,
          height: 1.4,
          color: AppColors.muted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: false,
        constraints: const BoxConstraints(minHeight: AppSpace.minTap),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: AppColors.ink(0.65)),
        labelStyle: const TextStyle(color: AppColors.muted),
        floatingLabelStyle: const TextStyle(color: AppColors.accent700),
        border: OutlineInputBorder(
          borderRadius: AppRadius.all,
          borderSide: divider,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.all,
          borderSide: divider,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.all,
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.all,
          borderSide: const BorderSide(color: AppColors.accent2700),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.all,
          borderSide: const BorderSide(color: AppColors.accent2700, width: 2),
        ),
        errorStyle: const TextStyle(color: AppColors.accent2700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20),
          ),
          shape: focusShape(BorderSide.none),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.background.withValues(alpha: 0.9)
                : AppColors.background,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.accent.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.accent700;
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.accent600;
            }
            return AppColors.accent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18),
          ),
          shape: focusShape(divider),
          side: const WidgetStatePropertyAll(divider),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.ink(0.45)
                : AppColors.text,
          ),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: overlay(AppColors.ink(0.07), AppColors.ink(0.14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, AppSpace.minTap)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          shape: focusShape(BorderSide.none),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.ink(0.45)
                : states.contains(WidgetState.pressed)
                ? AppColors.accent800
                : AppColors.accent700,
          ),
          overlayColor: overlay(
            AppColors.accent.withValues(alpha: 0.10),
            AppColors.accent.withValues(alpha: 0.16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSpace.minTap, AppSpace.minTap),
          ),
          shape: focusShape(BorderSide.none),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.ink(0.45)
                : AppColors.accent700,
          ),
          overlayColor: overlay(
            AppColors.accent.withValues(alpha: 0.10),
            AppColors.accent.withValues(alpha: 0.16),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, AppSpace.minTap)),
          visualDensity: VisualDensity.standard,
          shape: WidgetStatePropertyAll(shape),
          side: const WidgetStatePropertyAll(divider),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppText.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.accent
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.ink(0.45);
            }
            return states.contains(WidgetState.selected)
                ? AppColors.background
                : AppColors.text;
          }),
          overlayColor: overlay(AppColors.ink(0.07), AppColors.ink(0.14)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: shape,
        side: divider,
        backgroundColor: Colors.transparent,
        selectedColor: AppColors.accent,
        disabledColor: AppColors.neutral200,
        checkmarkColor: AppColors.background,
        showCheckmark: false,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.background
                : AppColors.text,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: 0,
        height: 83,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent700
                : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.muted,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: AppColors.ink(0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        titleTextStyle: AppText.sectionHeading.copyWith(
          fontFamily: AppText.fontFamily,
        ),
        contentTextStyle: AppText.body.copyWith(fontFamily: AppText.fontFamily),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 12,
        modalElevation: 12,
        shadowColor: AppColors.ink(0.6),
        showDragHandle: true,
        dragHandleColor: AppColors.neutral400,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: AppColors.ink(0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        textStyle: AppText.body.copyWith(fontFamily: AppText.fontFamily),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sheet),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text,
        contentTextStyle: const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15,
          color: AppColors.background,
        ),
        actionTextColor: AppColors.accent200,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: shape,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.accent700,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.neutral300,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.background
              : AppColors.neutral600,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.neutral300,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: shape,
        side: const BorderSide(color: AppColors.neutral600, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.background),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.neutral600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.background,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: shape,
        extendedTextStyle: const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.text,
          borderRadius: AppRadius.all,
        ),
        textStyle: const TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 13,
          color: AppColors.background,
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        tilePadding: EdgeInsets.zero,
        iconColor: AppColors.accent700,
        collapsedIconColor: AppColors.muted,
        textColor: AppColors.text,
        collapsedTextColor: AppColors.text,
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.accent2,
        textColor: AppColors.background,
        textStyle: TextStyle(
          fontFamily: AppText.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
