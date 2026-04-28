import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Light status bar: transparent background with dark icons/text
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,    // Android: dark icons
    statusBarBrightness: Brightness.light,        // iOS: dark icons (light status bar)
    systemNavigationBarColor: Color(0xFFF1F5F9),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const DriveXApp());
}

class DriveXApp extends StatelessWidget {
  const DriveXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DriveX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF00C4B4),
          secondary: Color(0xFF009BA8),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C4B4),
            foregroundColor: Colors.white,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF1F5F9),
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const AppGate(),
    );
  }
}

/// Decides whether to show splash → onboarding → login, or go straight to home
class AppGate extends StatefulWidget {
  const AppGate({super.key});
  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  @override
  void initState() {
    super.initState();
    // Listen for auth state changes (login / logout)
    supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else if (data.event == AuthChangeEvent.signedOut) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // If already logged in skip splash, else show splash → onboarding → login
    final session = supabase.auth.currentSession;
    if (session != null) {
      return const HomeScreen();
    }
    return const SplashScreen();
  }
}
