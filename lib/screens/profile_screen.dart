import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../supabase_config.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'verification_center_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int unreadKycCount;
  final VoidCallback? onNotifRead;
  const ProfileScreen({super.key, this.unreadKycCount = 0, this.onNotifRead});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  int _totalBookings = 0;
  bool _isLoading = true;
  bool _isSigningOut = false;

  static const _teal = Color(0xFF00C4B4);
  static const _card = Color(0xFFFFFFFF);
  static const _dark = Color(0xFF0F172A);
  static const _slate = Color(0xFF64748B);

  @override
  void initState() { super.initState(); _fetchProfile(); }

  Future<void> _fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) { setState(() => _isLoading = false); return; }
    try {
      final profile = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
      final bookingData = await supabase.from('bookings').select('id').eq('user_id', user.id);
      if (mounted) setState(() {
        _profile = profile ?? {};
        _totalBookings = (bookingData as List).length;
        _isLoading = false;
      });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    await supabase.auth.signOut();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  // ── KYC status helpers ──
  String _kycLabel(String? s) {
    switch (s) {
      case 'approved': return 'Verified';
      case 'pending': return 'Pending';
      case 'rejected': return 'Rejected';
      default: return 'Unverified';
    }
  }
  Color _kycColor(String? s) {
    switch (s) {
      case 'approved': return const Color(0xFF22C55E);
      case 'pending': return const Color(0xFFF59E0B);
      case 'rejected': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8);
    }
  }
  IconData _kycIcon(String? s) {
    switch (s) {
      case 'approved': return Icons.verified_rounded;
      case 'pending': return Icons.hourglass_top_rounded;
      case 'rejected': return Icons.cancel_rounded;
      default: return Icons.shield_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final name = _profile?['full_name'] as String? ?? user?.userMetadata?['full_name'] as String? ?? 'DriveX Member';
    final email = _profile?['email'] as String? ?? user?.email ?? '';
    final phone = _profile?['phone'] as String? ?? 'Not set';
    final memberSince = user?.createdAt != null ? DateTime.parse(user!.createdAt).year.toString() : '2024';
    final loyaltyPoints = _profile?['loyalty_points'] as int? ?? 0;
    final kycStatus = _profile?['kyc_status'] as String?;
    final initials = name.trim().split(' ').map((p) => p.isNotEmpty ? p[0].toUpperCase() : '').take(2).join();
    final kycColor = _kycColor(kycStatus);

    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _fetchProfile, color: _teal, backgroundColor: _card,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(children: [
                  // Header
                  Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Profile', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: _dark)),
                      GestureDetector(
                        onTap: _signOut,
                        child: _isSigningOut
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                            : Container(width: 40, height: 40,
                                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
                                child: const Icon(Icons.logout, color: Colors.redAccent, size: 20)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Avatar
                  Container(width: 80, height: 80,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [_teal, Color(0xFF1D4ED8)])),
                    child: Center(child: Text(initials, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)))),
                  const SizedBox(height: 14),
                  Text(name, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
                  const SizedBox(height: 4),
                  Text(email, style: GoogleFonts.inter(fontSize: 13, color: _slate)),
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: _teal.withOpacity(0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.shield_outlined, color: _teal, size: 14),
                      const SizedBox(width: 6),
                      Text('Member since $memberSince', style: GoogleFonts.inter(fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
                    ])),
                  const SizedBox(height: 24),

                  // Stats row — 3rd box is now KYC status
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      _StatBox(label: 'Bookings', value: _totalBookings.toString()),
                      const SizedBox(width: 12),
                      _StatBox(label: 'Points', value: loyaltyPoints.toString()),
                      const SizedBox(width: 12),
                      // KYC Status Box
                      Expanded(child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationCenterScreen())).then((_) => _fetchProfile()),
                        child: Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          decoration: BoxDecoration(color: kycColor.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kycColor.withOpacity(0.35)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
                          child: Column(children: [
                            Icon(_kycIcon(kycStatus), color: kycColor, size: 20),
                            const SizedBox(height: 4),
                            Text(_kycLabel(kycStatus), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: kycColor)),
                            const SizedBox(height: 2),
                            Text('Verification', style: GoogleFonts.inter(fontSize: 10, color: _slate)),
                          ]),
                        ),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Info tiles
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Account Details', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: _dark)),
                      const SizedBox(height: 12),
                      _InfoTile(icon: Icons.person_outline, label: 'Full Name', value: name),
                      _InfoTile(icon: Icons.email_outlined, label: 'Email', value: email),
                      _InfoTile(icon: Icons.phone_outlined, label: 'Phone', value: phone),
                      const SizedBox(height: 24),

                      Text('More', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: _dark)),
                      const SizedBox(height: 12),

                      // Driver's License → VerificationCenterScreen
                      _MenuTile(
                        icon: Icons.badge_outlined,
                        label: 'Driver\'s License & ID',
                        trailing: kycStatus == 'approved'
                            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                                child: Text('Verified', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF22C55E))))
                            : kycStatus == 'pending'
                                ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                                    child: Text('Pending', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFF59E0B))))
                                : null,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationCenterScreen())).then((_) => _fetchProfile()),
                      ),

                      // Notifications with badge
                      _MenuTile(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        badge: widget.unreadKycCount > 0 ? widget.unreadKycCount : null,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => widget.onNotifRead?.call()),
                      ),
                      _MenuTile(icon: Icons.lock_outline, label: 'Privacy & Security', onTap: () {}),
                      _MenuTile(icon: Icons.help_outline, label: 'Help & Support', onTap: () {}),
                      const SizedBox(height: 20),

                      SizedBox(width: double.infinity, height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
                          label: Text('Sign Out', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red.withOpacity(0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ]),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  static const _teal = Color(0xFF00C4B4);
  const _StatBox({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black.withOpacity(0.06)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(children: [
      Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _teal)),
      const SizedBox(height: 4),
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
    ]),
  ));
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black.withOpacity(0.06)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
    child: Row(children: [
      Icon(icon, color: const Color(0xFF00C4B4), size: 18),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
        Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
      ])),
    ]),
  );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;
  final Widget? trailing;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.badge, this.trailing});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF00C4B4), size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)))),
        if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
        if (badge != null && badge! > 0)
          Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(10)),
            child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 18),
      ]),
    ),
  );
}
