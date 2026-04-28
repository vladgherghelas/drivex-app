import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animateProgress();
  }

  Future<void> _animateProgress() async {
    await Future.delayed(const Duration(milliseconds: 300));
    for (int i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 60));
      if (mounted) setState(() => _progress = i / 100.0);
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D1117), Color(0xFF0D1117)],
              ),
            ),
            child: Image.network(
              'https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=800&q=80',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.65),
              colorBlendMode: BlendMode.darken,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0D1117),
                      const Color(0xFF1A2332),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          Column(
            children: [
              const Spacer(flex: 2),

              // Logo icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E3A5F).withOpacity(0.8),
                  border: Border.all(
                    color: const Color(0xFF00C4B4).withOpacity(0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.electric_car,
                  color: Color(0xFF00C4B4),
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),

              // Brand name
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Drive',
                      style: GoogleFonts.inter(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    TextSpan(
                      text: 'X',
                      style: GoogleFonts.inter(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF00C4B4),
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'E L I T E   C A R   R E N T A L',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.white60,
                  letterSpacing: 4,
                ),
              ),

              const Spacer(flex: 3),

              // Progress section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Initializing systems...',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF00C4B4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00C4B4),
                        ),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Powered by Next-Gen Mobility',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ],
      ),
    );
  }
}
