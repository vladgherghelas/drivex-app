import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../widgets/app_toast.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _name     = TextEditingController();
  final _phone    = TextEditingController();
  final _confirm  = TextEditingController();

  bool _isLogin       = true;
  bool _obscure       = true;
  bool _obscureConf   = true;
  bool _loading       = false;
  bool _agreeTerms    = false;

  late AnimationController _animCtrl;
  late Animation<double>   _fade;

  static const _blue = Color(0xFF00C4B4);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade     = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone, _confirm]) c.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    AppToast.show(context, msg, success: ok);
  }

  Future<void> _handleAuth() async {
    final em = _email.text.trim();
    final pw = _password.text;
    if (em.isEmpty || pw.isEmpty) { _snack('Please enter your email and password.'); return; }
    if (!_isLogin) {
      if (_name.text.trim().isEmpty)  { _snack('Full name is required.');      return; }
      if (_phone.text.trim().isEmpty) { _snack('Phone number is required.');   return; }
      if (pw != _confirm.text)        { _snack('Passwords do not match.');      return; }
      if (!_agreeTerms)               { _snack('Please accept the Terms of Service.'); return; }
    }
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(email: em, password: pw);
      } else {
        await supabase.auth.signUp(email: em, password: pw,
          data: {'full_name': _name.text.trim(), 'phone': _phone.text.trim()});
        _snack('Account created! Signing you in…', ok: true);
        await Future.delayed(const Duration(milliseconds: 800));
        await supabase.auth.signInWithPassword(email: em, password: pw);
      }
      if (mounted) Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') || msg.contains('already exists')) {
        _snack('This email is already registered. Please sign in.');
        if (!_isLogin) setState(() { _isLogin = true; _agreeTerms = false; });
      } else if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
        _snack('Incorrect email or password. Please try again.');
      } else if (msg.contains('email not confirmed')) {
        _snack('Please check your email and confirm your account.');
      } else if (msg.contains('weak password')) {
        _snack('Password must be at least 6 characters.');
      } else if (msg.contains('rate limit')) {
        _snack('Too many attempts. Please wait a moment and try again.');
      } else {
        _snack(e.message);
      }
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle() {
    _animCtrl.forward(from: 0);
    setState(() { _isLogin = !_isLogin; _agreeTerms = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        // ── Hero background ────────────────────────────────────────────────
        Positioned.fill(child: Image.network(
          'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?w=1200&q=85',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0F172A)),
        )),
        // ── Multi-stop gradient ────────────────────────────────────────────
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.55),
                Colors.black.withOpacity(0.30),
                Colors.black.withOpacity(0.72),
                const Color(0xFF0F172A).withOpacity(0.97),
              ],
              stops: const [0, 0.25, 0.6, 1],
            ),
          ),
        )),

        // ── Main content ───────────────────────────────────────────────────
        SafeArea(
          bottom: false,
          child: Column(children: [
            // ── Top bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                _IconBtn(
                  icon: Icons.arrow_back_ios_new, size: 16,
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const OnboardingScreen())),
                ),
                const Spacer(),
                Row(children: [
                  Container(width: 28, height: 28,
                    decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.directions_car, color: Colors.white, size: 16)),
                  const SizedBox(width: 7),
                  Text('DriveX', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900,
                      color: Colors.white, letterSpacing: -0.3)),
                ]),
                const Spacer(),
                const SizedBox(width: 40),
              ]),
            ),

            // ── Hero section (fills available space above form) ────────────
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: _isLogin ? _SignInHero() : _SignUpHero(),
                ),
              ),
            ),

            // ── Glass form card ──────────────────────────────────────────────
            FadeTransition(
              opacity: _fade,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  left: 14, right: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom
                        + MediaQuery.of(context).padding.bottom
                        + 14,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xED0D1929),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 12))],
                  ),
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(children: [
                    // Tab switcher
                    Container(height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.1))),
                      child: Row(children: [
                        _Tab(label: 'Sign In',  active: _isLogin,  onTap: () { if (!_isLogin)  _toggle(); }),
                        _Tab(label: 'Sign Up',  active: !_isLogin, onTap: () { if (_isLogin)   _toggle(); }),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Social buttons
                    Row(children: [
                      Expanded(child: _SocialBtn(label: 'Google', icon: Icons.g_mobiledata_rounded,
                        onTap: () => _snack('Google login coming soon.'))),
                      const SizedBox(width: 10),
                      Expanded(child: _SocialBtn(label: 'Apple', icon: Icons.apple,
                        onTap: () => _snack('Apple login coming soon.'))),
                    ]),
                    const SizedBox(height: 14),

                    Row(children: [
                      const Expanded(child: Divider(color: Colors.white12)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('or with email', style: GoogleFonts.inter(color: Colors.white24, fontSize: 11))),
                      const Expanded(child: Divider(color: Colors.white12)),
                    ]),
                    const SizedBox(height: 14),

                    // Sign-up extra fields
                    if (!_isLogin) ...[
                      _Field(ctrl: _name,  hint: 'Full Name',     icon: Icons.person_outline),
                      const SizedBox(height: 10),
                      _Field(ctrl: _phone, hint: 'Phone Number',  icon: Icons.phone_outlined, type: TextInputType.phone),
                      const SizedBox(height: 10),
                    ],

                    _Field(ctrl: _email,    hint: 'Email Address', icon: Icons.email_outlined, type: TextInputType.emailAddress),
                    const SizedBox(height: 10),
                    _Field(ctrl: _password, hint: 'Password',      icon: Icons.lock_outline, obscure: _obscure,
                      suffix: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.white30, size: 18))),

                    if (!_isLogin) ...[
                      const SizedBox(height: 10),
                      _Field(ctrl: _confirm, hint: 'Confirm Password', icon: Icons.lock_outline, obscure: _obscureConf,
                        suffix: GestureDetector(
                          onTap: () => setState(() => _obscureConf = !_obscureConf),
                          child: Icon(_obscureConf ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: Colors.white30, size: 18))),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => setState(() => _agreeTerms = !_agreeTerms),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          AnimatedContainer(duration: const Duration(milliseconds: 200),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: _agreeTerms ? _blue : Colors.transparent,
                              border: Border.all(color: _agreeTerms ? _blue : Colors.white24, width: 1.5),
                              borderRadius: BorderRadius.circular(5)),
                            child: _agreeTerms ? const Icon(Icons.check, color: Colors.white, size: 13) : null),
                          const SizedBox(width: 10),
                          Expanded(child: Text.rich(TextSpan(
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(text: 'Terms of Service', style: GoogleFonts.inter(color: _blue, fontSize: 12, decoration: TextDecoration.underline)),
                              const TextSpan(text: ' and '),
                              TextSpan(text: 'Privacy Policy', style: GoogleFonts.inter(color: _blue, fontSize: 12, decoration: TextDecoration.underline)),
                            ],
                          ))),
                        ]),
                      ),
                    ],

                    if (_isLogin) ...[
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight,
                        child: GestureDetector(onTap: () {},
                          child: Text('Forgot password?',
                            style: GoogleFonts.inter(color: _blue, fontSize: 13, fontWeight: FontWeight.w600)))),
                    ],

                    const SizedBox(height: 18),

                    // CTA button
                    SizedBox(width: double.infinity, height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _handleAuth,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue, foregroundColor: Colors.white,
                          disabledBackgroundColor: _blue.withOpacity(0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0),
                        child: _loading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_isLogin ? 'Sign In' : 'Create Account',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Toggle link
                    Center(child: GestureDetector(onTap: _toggle,
                      child: Text.rich(TextSpan(
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                        children: [
                          TextSpan(text: _isLogin ? "Don't have an account? " : 'Already have an account? '),
                          TextSpan(text: _isLogin ? 'Sign Up' : 'Sign In',
                            style: GoogleFonts.inter(color: _blue, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      )),
                    )),
                  ]),
                ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Sign In hero (centered tagline) ───────────────────────────────────────────
class _SignInHero extends StatelessWidget {
  static const _blue = Color(0xFF00C4B4);
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      // Pill badge
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _blue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _blue.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
          const SizedBox(width: 6),
          Text('Rated 4.9 · 1,200+ rentals', style: GoogleFonts.inter(
              fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 18),
      Text('Luxury\nDriving\nRedefined.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white,
          height: 1.05, letterSpacing: -1.5,
        )),
      const SizedBox(height: 14),
      Text("The world's finest vehicles,\nat your fingertips.",
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.6)),
    ]);
  }
}

// ── Sign Up hero (feature badges) ─────────────────────────────────────────────
class _SignUpHero extends StatelessWidget {
  static const _blue = Color(0xFF00C4B4);
  @override
  Widget build(BuildContext context) {
    final perks = [
      _Perk(icon: Icons.directions_car_rounded, color: _blue,           label: '10+ Luxury Cars'),
      _Perk(icon: Icons.shield_rounded,         color: Color(0xFF059669), label: 'Fully Insured'),
      _Perk(icon: Icons.bolt_rounded,           color: const Color(0xFFF59E0B), label: 'Instant Booking'),
    ];
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('Join DriveX', textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w900,
            color: Colors.white, letterSpacing: -1)),
      const SizedBox(height: 8),
      Text('Luxury meets freedom.\nCreate your free account.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.55)),
      const SizedBox(height: 22),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: perks
        .map((p) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _PerkChip(perk: p)))
        .toList()),
    ]);
  }
}

class _Perk {
  final IconData icon; final Color color; final String label;
  const _Perk({required this.icon, required this.color, required this.label});
}

class _PerkChip extends StatelessWidget {
  final _Perk perk;
  const _PerkChip({required this.perk});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: perk.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: perk.color.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(perk.icon, color: perk.color, size: 20),
        const SizedBox(height: 5),
        Text(perk.label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon; final double size; final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.size, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(width: 40, height: 40,
      decoration: BoxDecoration(color: Colors.white12,
        borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: Icon(icon, color: Colors.white, size: size)));
}

class _Tab extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  static const _blue = Color(0xFF00C4B4);
  const _Tab({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(onTap: onTap,
      child: AnimatedContainer(duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.all(4), alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _blue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 10)] : [],
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700,
          color: active ? Colors.white : Colors.white38)))));
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint; final IconData icon;
  final bool obscure; final Widget? suffix; final TextInputType? type;
  const _Field({required this.ctrl, required this.hint, required this.icon,
    this.obscure = false, this.suffix, this.type});
  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Colors.white.withOpacity(0.1))),
    child: Row(children: [
      const SizedBox(width: 14),
      Icon(icon, color: Colors.white30, size: 18),
      const SizedBox(width: 10),
      Expanded(child: TextField(controller: ctrl, obscureText: obscure, keyboardType: type,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(hintText: hint,
          hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 14),
          border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero))),
      if (suffix != null) ...[suffix!, const SizedBox(width: 12)],
    ]),
  );
}

class _SocialBtn extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _SocialBtn({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.1))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ])));
}
