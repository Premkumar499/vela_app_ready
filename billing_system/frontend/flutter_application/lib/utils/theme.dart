import 'package:flutter/material.dart';

/// Professional ERP / POS colour palette and typography.
/// All colours and text styles are centralised here so reskinning is trivial.
class AppTheme {
  AppTheme._();

  // -------------------------------------------------------------------------
  // Colours
  // -------------------------------------------------------------------------
  static const Color primary = Color(0xFF2E7D32);       // Green 800
  static const Color primaryDark = Color(0xFF1B5E20);   // Green 900
  static const Color primaryLight = Color(0xFF388E3C);  // Green 700
  static const Color accent = Color(0xFF43A047);        // Green 600

  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color tableHeaderColor = Color(0xFFE8F5E9); // Green 50 (colour only)
  static const Color tableRowAlt = Color(0xFFFAFAFA);
  static const Color tableBorder = Color(0xFFBDBDBD);   // Grey 400

  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textOnPrimary = Colors.white;

  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFC62828);
  static const Color warning = Color(0xFFE65100);
  static const Color info = Color(0xFF0277BD);

  static const Color divider = Color(0xFFE0E0E0);
  static const Color cardShadow = Color(0x1A000000);

  // -------------------------------------------------------------------------
  // Misc constants
  // -------------------------------------------------------------------------
  static const double cardRadius = 8.0;

  // -------------------------------------------------------------------------
  // Typography
  // -------------------------------------------------------------------------
  static const TextStyle headingLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary, 
    letterSpacing: 0.2,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    color: textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    color: textSecondary,
  );

  // Renamed from tableHeader → tableHeaderStyle to avoid collision with the Color
  static const TextStyle tableHeaderStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: primaryDark,
    letterSpacing: 0.5,
  );

  static const TextStyle tableCell = TextStyle(
    fontSize: 13,
    color: textPrimary,
  );

  static const TextStyle grandTotal = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 1,
  );

  static const TextStyle grandTotalLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.white70,
  );

  // -------------------------------------------------------------------------
  // MaterialApp ThemeData
  // -------------------------------------------------------------------------
  static ThemeData get themeData => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          primary: primary,
          onPrimary: Colors.white,
          secondary: accent,
          surface: surface,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 2,
          shadowColor: cardShadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(88, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            minimumSize: const Size(88, 44),
            side: const BorderSide(color: primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: tableBorder),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 1,
          space: 1,
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(tableHeaderColor),
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          headingTextStyle: tableHeaderStyle,
          dataTextStyle: tableCell,
          columnSpacing: 16,
          horizontalMargin: 12,
          dividerThickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        fontFamily: 'Roboto',
      );

  // -------------------------------------------------------------------------
  // Reusable decorations
  // -------------------------------------------------------------------------

  static BoxDecoration get panelDecoration => BoxDecoration(
        color: surface,
        border: Border.all(color: tableBorder),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: cardShadow, blurRadius: 4)],
      );

  static BoxDecoration get headerDecoration => const BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      );

  static BoxDecoration tableRowDecoration(int index) => BoxDecoration(
        color: index.isEven ? surface : tableRowAlt,
        border: const Border(
          bottom: BorderSide(color: divider),
        ),
      );
}
