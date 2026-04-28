import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/car_model.dart';

class PaymentSuccessScreen extends StatefulWidget {
  final CarModel car;
  final String confirmationNo;
  final double totalAmount;
  final DateTime pickupDate;
  final DateTime returnDate;

  const PaymentSuccessScreen({
    super.key,
    required this.car,
    required this.confirmationNo,
    required this.totalAmount,
    required this.pickupDate,
    required this.returnDate,
  });

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  static const _teal = Color(0xFF00C4B4);
  static const _dark = Color(0xFF0F172A);
  static const _slate = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    Future.delayed(const Duration(milliseconds: 200), _ctrl.forward);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, MMM d, yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(children: [
              const SizedBox(height: 24),

              // ── Animated checkmark ──
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C4B4), Color(0xFF00A896)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: _teal.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 28),

              Text('Booking Request Sent!', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w900, color: _dark)),
              const SizedBox(height: 10),
              Text(
                'Your booking request has been successfully submitted.\nA rental contract will be sent to your email shortly for digital signing.',
                style: GoogleFonts.inter(fontSize: 14, color: _slate, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // ── Confirmation card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Column(children: [
                  // Confirmation number badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _teal.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.tag, color: _teal, size: 16),
                      const SizedBox(width: 6),
                      Text(widget.confirmationNo, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: _teal, letterSpacing: 1)),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Vehicle
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(widget.car.imageUrl, width: 72, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 72, height: 52, color: Colors.grey.shade200,
                          child: const Icon(Icons.directions_car, color: Colors.grey))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.car.displayName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: _dark)),
                      Text(widget.car.category, style: GoogleFonts.inter(fontSize: 12, color: _slate)),
                    ])),
                  ]),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),

                  // Dates
                  _InfoRow(Icons.flight_takeoff_rounded, 'Pickup', fmt.format(widget.pickupDate)),
                  const SizedBox(height: 10),
                  _InfoRow(Icons.flight_land_rounded, 'Drop-off', fmt.format(widget.returnDate)),
                  const SizedBox(height: 10),
                  _InfoRow(Icons.payments_outlined, 'Total Amount', '\$${widget.totalAmount.toStringAsFixed(2)}'),
                  const SizedBox(height: 10),
                  _InfoRow(Icons.info_outline_rounded, 'Status', 'Pending Review'),
                ]),
              ),
              const SizedBox(height: 20),

              // ── What's next card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1D4ED8).withOpacity(0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF1D4ED8), size: 20),
                    const SizedBox(width: 8),
                    Text("What happens next?", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _dark)),
                  ]),
                  const SizedBox(height: 14),
                  _StepItem('1', 'Our team reviews your booking request', Icons.search_rounded),
                  _StepItem('2', 'A contract is sent to your email for e-signing', Icons.description_outlined),
                  _StepItem('3', 'Once signed, payment details are arranged with the agent', Icons.handshake_outlined),
                  _StepItem('4', 'Your car is delivered at the agreed time & address', Icons.local_shipping_outlined),
                ]),
              ),
              const SizedBox(height: 28),

              // ── Back to home ──
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                  child: Text('Back to Home', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: Text('View My Bookings', style: GoogleFonts.inter(fontSize: 14, color: _teal, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  static const _teal = Color(0xFF00C4B4);
  static const _slate = Color(0xFF64748B);
  static const _dark = Color(0xFF0F172A);

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 32, height: 32, decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: _teal, size: 16)),
    const SizedBox(width: 12),
    Text(label, style: GoogleFonts.inter(fontSize: 13, color: _slate)),
    const Spacer(),
    Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _dark)),
  ]);
}

class _StepItem extends StatelessWidget {
  final String step, text;
  final IconData icon;
  static const _teal = Color(0xFF00C4B4);
  static const _slate = Color(0xFF64748B);

  const _StepItem(this.step, this.text, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 26, height: 26, decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(13)),
        child: Center(child: Text(step, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)))),
      const SizedBox(width: 10),
      Icon(icon, size: 16, color: _teal),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: _slate, height: 1.4))),
    ]),
  );
}
