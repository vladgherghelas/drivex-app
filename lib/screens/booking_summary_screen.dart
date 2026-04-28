import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import '../models/car_model.dart';
import 'payment_success_screen.dart';
import 'verification_center_screen.dart';

class BookingSummaryScreen extends StatefulWidget {
  final CarModel car;
  final DateTime pickupDate;
  final DateTime dropoffDate;
  final TimeOfDay pickupTime;
  final TimeOfDay dropoffTime;
  final String pickupLoc;
  final String dropoffLoc;

  const BookingSummaryScreen({
    super.key,
    required this.car,
    required this.pickupDate,
    required this.dropoffDate,
    required this.pickupTime,
    required this.dropoffTime,
    required this.pickupLoc,
    required this.dropoffLoc,
  });

  @override
  State<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends State<BookingSummaryScreen> {
  bool _agreedToTerms = true;
  bool _isLoading = false;
  bool _isCheckingVerification = true;
  bool _isVerified = false;
  String _kycStatus = 'unverified';

  // Promo code
  final _promoCtrl = TextEditingController();
  double _promoDiscount = 0.0;
  String? _promoMsg;
  bool _promoLoading = false;
  bool _promoApplied = false;

  static const _teal = Color(0xFF00C4B4);
  static const _dark = Color(0xFF0F172A);
  static const _slate = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _checkVerification();
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkVerification() async {
    final user = supabase.auth.currentUser;
    if (user == null) { setState(() { _isCheckingVerification = false; _isVerified = false; _kycStatus = 'unverified'; }); return; }
    try {
      final profile = await supabase.from('profiles').select('kyc_status,license_verified').eq('id', user.id).maybeSingle();
      final status = profile?['kyc_status'] as String? ?? 'unverified';
      setState(() {
        _kycStatus = status;
        _isVerified = status == 'approved' || profile?['license_verified'] == true;
        _isCheckingVerification = false;
      });
    } catch (_) {
      setState(() { _isCheckingVerification = false; _isVerified = false; _kycStatus = 'unverified'; });
    }
  }

  int get _days => widget.dropoffDate.difference(widget.pickupDate).inDays.clamp(1, 365);
  double _discountedRate(int base) {
    if (_days >= 28) return base * 0.75;
    if (_days >= 15) return base * 0.81;
    if (_days >= 8) return base * 0.87;
    if (_days >= 4) return base * 0.94;
    return base.toDouble();
  }

  double get _subtotal => _discountedRate(widget.car.pricePerDay) * _days;
  double get _insurance => 45.0;
  double get _taxes => 32.50;
  double get _total => _subtotal + _insurance + _taxes - _promoDiscount;

  String _fmtDate(DateTime d) => DateFormat('EEE, MMM d, yyyy').format(d);
  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? "AM" : "PM"}';
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _promoLoading = true; _promoMsg = null; });
    try {
      final now = DateTime.now().toIso8601String();
      final result = await supabase.from('coupons')
          .select()
          .eq('code', code)
          .eq('active', true)
          .or('expires_at.is.null,expires_at.gt.$now')
          .maybeSingle();
      if (result == null) {
        setState(() { _promoMsg = 'Invalid or expired promo code.'; _promoLoading = false; _promoApplied = false; });
      } else {
        final pct = (result['discount_percent'] as num).toDouble();
        setState(() {
          _promoDiscount = (_subtotal * pct / 100);
          _promoMsg = '✓ ${result['description'] ?? 'Discount applied'} (${pct.toInt()}% off)';
          _promoLoading = false;
          _promoApplied = true;
        });
      }
    } catch (_) {
      setState(() { _promoMsg = 'Could not verify code. Try again.'; _promoLoading = false; });
    }
  }

  Future<void> _confirmBooking() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to the terms first.'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final confirmNo = '#DX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      await supabase.from('bookings').insert({
        'user_id': user.id,
        'car_id': widget.car.id,
        'pickup_date': DateFormat('yyyy-MM-dd').format(widget.pickupDate),
        'return_date': DateFormat('yyyy-MM-dd').format(widget.dropoffDate),
        'pickup_location': widget.pickupLoc,
        'total_amount': _total.toStringAsFixed(2),
        'status': 'pending',
        'confirmation_no': confirmNo,
        'payment_method': 'contract',
        'notes': _promoApplied ? 'Promo: ${_promoCtrl.text.trim().toUpperCase()} (-\$${_promoDiscount.toStringAsFixed(2)})' : null,
      });
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => PaymentSuccessScreen(
            car: widget.car,
            confirmationNo: confirmNo,
            totalAmount: _total,
            pickupDate: widget.pickupDate,
            returnDate: widget.dropoffDate,
          )),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking failed: $e'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVerificationBlockedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.badge_outlined, color: Colors.orange)),
          const SizedBox(width: 12),
          Expanded(child: Text('Verification Required', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: _dark))),
        ]),
        content: Text(
          'You need to verify your driver\'s license before making a booking.\n\nGo to Profile → Driver\'s License to upload your documents.',
          style: GoogleFonts.inter(fontSize: 14, color: _slate, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK', style: GoogleFonts.inter(color: _teal, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.car;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F5F9),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back, color: _dark),
        ),
        title: Text('Review & Book', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _dark)),
        centerTitle: true,
      ),
      body: _isCheckingVerification
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Car banner ──
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(children: [
                    Image.network(car.imageUrl, height: 180, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(height: 180, color: Colors.grey.shade200)),
                    Container(height: 180,
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.75)]))),
                    Positioned(bottom: 16, left: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(car.category.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF60A5FA), letterSpacing: 1.5)),
                      Text(car.displayName, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(car.priceLabel, style: GoogleFonts.inter(fontSize: 14, color: _teal, fontWeight: FontWeight.w700)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Verification banner ──
                if (!_isVerified && _kycStatus == 'pending')
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Documents Under Review', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF92400E))),
                        Text('Your documents are being reviewed. You can book once approved.', style: GoogleFonts.inter(fontSize: 12, color: _slate, height: 1.4)),
                      ])),
                    ]),
                  )
                else if (!_isVerified)
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationCenterScreen()));
                      setState(() => _isCheckingVerification = true);
                      await _checkVerification();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Document Verification Required', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.orange.shade700)),
                          Text('You must verify your driver\'s license to proceed with a booking.', style: GoogleFonts.inter(fontSize: 12, color: _slate, height: 1.4)),
                        ])),
                        const Icon(Icons.chevron_right, color: Colors.orange),
                      ]),
                    ),
                  ),

                // ── Rental Dates ──
                Text('Rental Dates', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _dark)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _DateCard(label: 'PICKUP', date: _fmtDate(widget.pickupDate), time: _fmtTime(widget.pickupTime), icon: Icons.flight_takeoff)),
                  const SizedBox(width: 12),
                  Expanded(child: _DateCard(label: 'DROP-OFF', date: _fmtDate(widget.dropoffDate), time: _fmtTime(widget.dropoffTime), icon: Icons.flight_land)),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.2))),
                  child: Row(children: [
                    const Icon(Icons.location_on, color: _teal, size: 18),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('PICKUP LOCATION', style: GoogleFonts.inter(fontSize: 9, color: _teal, letterSpacing: 1.2)),
                      Text(widget.pickupLoc, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.deepPurple.withOpacity(0.18))),
                  child: Row(children: [
                    Icon(Icons.location_on_outlined, color: Colors.deepPurple.shade300, size: 18),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('DROP-OFF LOCATION', style: GoogleFonts.inter(fontSize: 9, color: Colors.deepPurple, letterSpacing: 1.2)),
                      Text(widget.dropoffLoc, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 24),

                // ── Price Breakdown ──
                Text('Price Breakdown', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _dark)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Column(children: [
                    _PriceRow(label: '\$${_discountedRate(car.pricePerDay).toStringAsFixed(0)} × $_days ${_days == 1 ? "day" : "days"}', value: '\$${_subtotal.toStringAsFixed(0)}'),
                    const SizedBox(height: 12),
                    const _PriceRow(label: 'Premium Insurance', value: '\$45.00'),
                    const SizedBox(height: 12),
                    const _PriceRow(label: 'Airport Tax & Fees', value: '\$32.50'),
                    if (_promoApplied) ...[
                      const SizedBox(height: 12),
                      _PriceRow(label: 'Promo Code (${_promoCtrl.text.trim().toUpperCase()})', value: '-\$${_promoDiscount.toStringAsFixed(2)}', valueColor: const Color(0xFF34D399)),
                    ],
                    const Divider(color: Color(0xFFE2E8F0), height: 28),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Total', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: _dark)),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('\$${_total.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: _teal)),
                        Text('ALL TAXES INCLUDED', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8), letterSpacing: 1)),
                      ]),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Promo Code ──
                Text('Promo Code', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: _dark)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _promoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Enter code (e.g. SUMMER20)',
                        hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                        filled: true, fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withOpacity(0.08))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withOpacity(0.08))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
                        prefixIcon: const Icon(Icons.local_offer_outlined, color: _teal, size: 18),
                      ),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _dark),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _promoLoading ? null : _applyPromo,
                      style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                      child: _promoLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Apply', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
                if (_promoMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_promoMsg!, style: GoogleFonts.inter(fontSize: 12, color: _promoApplied ? const Color(0xFF34D399) : Colors.redAccent, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 20),

                // ── Protection banner ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: _teal.withOpacity(0.2))),
                  child: Row(children: [
                    const Icon(Icons.verified_user_outlined, color: _teal, size: 24),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Premium Protection Included', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
                      Text('Zero deductible, theft protection & 24/7 roadside assistance.', style: GoogleFonts.inter(fontSize: 12, color: _slate)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Contract info banner ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1D4ED8).withOpacity(0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF1D4ED8).withOpacity(0.2))),
                  child: Row(children: [
                    const Icon(Icons.description_outlined, color: Color(0xFF1D4ED8), size: 24),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Contract via Email', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
                      Text('After confirmation, a rental contract will be sent to your email for digital signing. No payment is collected now.', style: GoogleFonts.inter(fontSize: 12, color: _slate, height: 1.4)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Terms ──
                Row(children: [
                  Checkbox(value: _agreedToTerms, onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                    activeColor: _teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                  Expanded(child: RichText(text: TextSpan(
                    style: GoogleFonts.inter(fontSize: 13, color: _slate),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(text: 'Rental Agreement', style: GoogleFonts.inter(color: _teal, decoration: TextDecoration.underline, fontSize: 13)),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Cancellation Policy', style: GoogleFonts.inter(color: _teal, decoration: TextDecoration.underline, fontSize: 13)),
                      const TextSpan(text: '.'),
                    ],
                  ))),
                ]),
                const SizedBox(height: 16),

                // ── Confirm Button ──
                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    onPressed: (!_isVerified)
                        ? _showVerificationBlockedDialog
                        : (_agreedToTerms && !_isLoading) ? _confirmBooking : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isVerified ? _teal : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(_isVerified ? Icons.send_rounded : Icons.lock_outline_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _isVerified ? 'Send Booking Request — \$${_total.toStringAsFixed(2)}' : 'Verify Documents to Continue',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ]),
                  ),
                ),
                const SizedBox(height: 10),
                Center(child: Text('No payment now. Contract will be sent for signing.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)))),
                const SizedBox(height: 32),
              ]),
            ),
    );
  }
}

class _DateCard extends StatelessWidget {
  final String label, date, time;
  final IconData icon;
  static const _teal = Color(0xFF00C4B4);

  const _DateCard({required this.label, required this.date, required this.time, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black.withOpacity(0.08)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: _teal, size: 14),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8), letterSpacing: 1)),
      ]),
      const SizedBox(height: 6),
      Text(date, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
      const SizedBox(height: 2),
      Text(time, style: GoogleFonts.inter(fontSize: 11, color: _teal, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _PriceRow({required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B))),
    Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF0F172A))),
  ]);
}
