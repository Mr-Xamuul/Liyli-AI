import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/user_profile.dart';
import 'screens/google_auth_screen.dart';
import 'screens/main_shell_screen.dart';

import 'services/admin_auth_service.dart';
import 'services/user_auth_service.dart';
import 'services/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  SupabaseConfig.logConfigurationStatus();
  await AdminAuthService.instance.init();
  await UserAuthService.instance.init();
  runApp(const LeyliApp());
}

class LeyliApp extends StatelessWidget {
  const LeyliApp({super.key});

  static const primaryBlue = Color(0xFF0022FF);
  static const silverGrey = Color(0xFFBDBDBD);
  static const deepBlack = Color(0xFF000000);
  static const pureWhite = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primaryBlue,
      onPrimary: pureWhite,
      primaryContainer: const Color(0xFFE8ECFF),
      onPrimaryContainer: deepBlack,
      secondary: deepBlack,
      onSecondary: pureWhite,
      secondaryContainer: const Color(0xFFF2F2F2),
      onSecondaryContainer: deepBlack,
      tertiary: primaryBlue,
      onTertiary: pureWhite,
      tertiaryContainer: const Color(0xFFF5F5F5),
      onTertiaryContainer: deepBlack,
      error: deepBlack,
      onError: pureWhite,
      errorContainer: const Color(0xFFEEEEEE),
      onErrorContainer: deepBlack,
      surface: pureWhite,
      onSurface: deepBlack,
      onSurfaceVariant: deepBlack,
      outline: silverGrey,
      outlineVariant: const Color(0xFFDCDCDC),
      surfaceContainerLowest: pureWhite,
      surfaceContainerLow: const Color(0xFFF9F9F9),
      surfaceContainer: const Color(0xFFF3F3F3),
      surfaceContainerHigh: const Color(0xFFEDEDED),
      surfaceContainerHighest: const Color(0xFFE0E0E0),
    );

    final baseTextTheme = ThemeData.light().textTheme;
    final typography = GoogleFonts.plusJakartaSansTextTheme(
      baseTextTheme,
    ).apply(bodyColor: deepBlack, displayColor: deepBlack);

    return MaterialApp(
      title: 'Leyli AI - Waxbarashada Buugaagta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: pureWhite,
        textTheme: typography,
        appBarTheme: AppBarTheme(
          backgroundColor: pureWhite,
          foregroundColor: deepBlack,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          iconTheme: const IconThemeData(color: deepBlack),
          titleTextStyle: GoogleFonts.plusJakartaSans(
            color: deepBlack,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: pureWhite,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: silverGrey, width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dividerTheme: const DividerThemeData(color: silverGrey, thickness: 1),
        iconTheme: const IconThemeData(color: deepBlack),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: deepBlack),
        ),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: pureWhite,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: silverGrey),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: silverGrey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          ),
        ),
      ),
      home: const AppAuthWrapper(),
    );
  }
}

class AppAuthWrapper extends StatelessWidget {
  const AppAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: UserAuthService.instance.currentUserNotifier,
      builder: (context, user, _) {
        if (user == null) {
          return GoogleAuthScreen(onAuthenticated: () {});
        }
        return MainShellScreen(key: ValueKey('main_shell_${user.id}'));
      },
    );
  }
}
