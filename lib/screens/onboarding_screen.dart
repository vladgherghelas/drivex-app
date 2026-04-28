import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  int _currentPage = 0;

  static const _slides = [
    _Slide(
      tag: 'LUXURY FLEET',
      title: 'Drive the\nFuture',
      body:
          'The world\'s most advanced electric & luxury vehicles, delivered to your door.',
      image:
          'https://images.unsplash.com/photo-1617788138017-80ad40651399?w=900&q=85',
      accent: Color(0xFF00C4B4),
    ),
    _Slide(
      tag: 'INSTANT ACCESS',
      title: 'Book in\nSeconds',
      body:
          'Skip the queues. AI-powered verification means you\'re on the road in minutes.',
      image:
          'https://images.unsplash.com/photo-1555215695-3004980ad54e?w=900&q=85',
      accent: Color(0xFF7C3AED),
    ),
    _Slide(
      tag: 'TRAVEL IN STYLE',
      title: 'Arrive\nUnforgettable',
      body:
          'From weekend escapes to executive arrivals — every journey, a statement.',
      image:
          'https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=900&q=85',
      accent: Color(0xFF0891B2),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int idx) {
    _fadeCtrl.forward(from: 0);
    setState(() => _currentPage = idx);
  }

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentPage];
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(children: [
        // Full-bleed page swipe
        PageView.builder(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          itemCount: _slides.length,
          itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
        ),

        // Top logo bar - fixed, no skip
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: slide.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_car,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text('DriveX',
                  style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5)),
            ]),
          ),
        ),

        // Bottom overlay - content + controls
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF0F172A).withOpacity(0.85),
                  const Color(0xFF0F172A),
                ],
                stops: const [0, 0.35, 1],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    // Tag label
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: slide.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: slide.accent.withOpacity(0.4)),
                      ),
                      child: Text(slide.tag,
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: slide.accent,
                              letterSpacing: 1.8)),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(slide.title,
                        style: GoogleFonts.inter(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.05,
                            letterSpacing: -1.2)),
                    const SizedBox(height: 14),

                    // Body
                    Text(slide.body,
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            color: Colors.white60,
                            height: 1.55)),
                    const SizedBox(height: 36),

                    // Dots + button row
                    Row(children: [
                      // Dots
                      Row(
                        children: List.generate(
                          _slides.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _currentPage ? 24 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _currentPage
                                  ? slide.accent
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Next button
                      GestureDetector(
                        onTap: _next,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: _currentPage == _slides.length - 1
                              ? 160
                              : 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: slide.accent,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Center(
                            child: _currentPage == _slides.length - 1
                                ? Text('Get Started',
                                    style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white))
                                : const Icon(Icons.arrow_forward,
                                    color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Slide {
  final String tag, title, body, image;
  final Color accent;
  const _Slide(
      {required this.tag,
      required this.title,
      required this.body,
      required this.image,
      required this.accent});
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.network(
        slide.image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFF0D1117),
          child: Center(
            child: Icon(Icons.directions_car,
                color: slide.accent.withOpacity(0.4), size: 80),
          ),
        ),
      ),
      // Vignette overlay
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.1),
              Colors.black.withOpacity(0.05),
              Colors.black.withOpacity(0.7),
              const Color(0xFF0F172A),
            ],
            stops: const [0, 0.2, 0.45, 0.75, 1],
          ),
        ),
      ),
    ]);
  }
}
