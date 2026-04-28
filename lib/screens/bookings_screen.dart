import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  static const _blue = Color(0xFF00C4B4);
  static const _card = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookings() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() { _isLoading = false; _bookings = []; });
      return;
    }
    try {
      setState(() => _isLoading = true);
      final data = await supabase
          .from('bookings')
          .select('*, cars(name, brand, image_url, category)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel Booking',
            style: GoogleFonts.inter(
                color: const Color(0xFF0F172A), fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to cancel this booking?',
            style: GoogleFonts.inter(color: const Color(0xFF64748B))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Keep', style: GoogleFonts.inter(color: _blue))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Cancel',
                  style: GoogleFonts.inter(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    await supabase
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', bookingId);
    _fetchBookings();
  }

  List<Map<String, dynamic>> _filtered(String tab) {
    switch (tab) {
      case 'upcoming':
        return _bookings
            .where((b) =>
                ['confirmed', 'pending', 'active'].contains(b['status']))
            .toList();
      case 'past':
        return _bookings
            .where((b) => b['status'] == 'completed')
            .toList();
      default:
        return _bookings
            .where((b) => b['status'] == 'cancelled')
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Bookings',
                  style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A))),
              GestureDetector(
                onTap: _fetchBookings,
                child:
                    const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 42,
          decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
                color: _blue, borderRadius: BorderRadius.circular(10)),
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
            labelColor: const Color(0xFF0F172A),
            unselectedLabelColor: const Color(0xFF94A3B8),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
              Tab(text: 'Cancelled')
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoading
              ? _buildShimmer()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_filtered('upcoming')),
                    _buildList(_filtered('past')),
                    _buildList(_filtered('cancelled')),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      itemCount: 3,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE2E8F0),
        highlightColor: const Color(0xFFF8FAFC),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          height: 130,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: _blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.calendar_month_outlined,
                color: _blue, size: 36),
          ),
          const SizedBox(height: 16),
          Text('No bookings here',
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A))),
          const SizedBox(height: 8),
          Text('Your rentals will appear here.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchBookings,
      color: _blue,
      backgroundColor: _card,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) =>
            _BookingCard(booking: list[i], onCancel: _cancelBooking),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final Future<void> Function(String) onCancel;
  static const _blue = Color(0xFF00C4B4);

  const _BookingCard({required this.booking, required this.onCancel});

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed': return _blue;
      case 'active': return const Color(0xFF059669);
      case 'completed': return const Color(0xFF94A3B8);
      case 'cancelled': return Colors.redAccent;
      default: return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final car = booking['cars'] as Map<String, dynamic>?;
    final status = booking['status'] as String? ?? 'pending';
    final pickupDate = booking['pickup_date'] as String? ?? '';
    final returnDate = booking['return_date'] as String? ?? '';
    final total = booking['total_amount'];
    final confirmNo = booking['confirmation_no'] as String? ?? '';

    String dateRange = '$pickupDate → $returnDate';
    try {
      final p = DateTime.parse(pickupDate);
      final r = DateTime.parse(returnDate);
      dateRange =
          '${DateFormat('MMM d').format(p)} - ${DateFormat('MMM d, yyyy').format(r)}';
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (car?['image_url'] != null)
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: Stack(children: [
              CachedNetworkImage(
                imageUrl: car!['image_url'] as String,
                height: 100, width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(height: 100, color: const Color(0xFFE2E8F0)),
                errorWidget: (_, __, ___) =>
                    Container(height: 100, color: const Color(0xFFE2E8F0)),
              ),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent, Colors.black.withOpacity(0.75)
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 10, left: 12,
                child: Text('${car['brand']} ${car['name']}',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A))),
              ),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _statusColor(status).withOpacity(0.5)),
                  ),
                  child: Text(status.toUpperCase(),
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(status),
                          letterSpacing: 0.5)),
                ),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 13, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text(dateRange,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: const Color(0xFF475569))),
              ]),
              Text(
                '\$${total?.toString() ?? '0'}',
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _blue),
              ),
            ]),
            if (confirmNo.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.tag, size: 12, color: Color(0xFFCBD5E1)),
                const SizedBox(width: 4),
                Text(confirmNo,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: const Color(0xFF94A3B8))),
              ]),
            ],
            if (['confirmed', 'pending'].contains(status)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 36,
                child: OutlinedButton(
                  onPressed: () => onCancel(booking['id'] as String),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Cancel Booking',
                      style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (status == 'completed') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 36,
                child: OutlinedButton(
                  onPressed: () => _showReviewDialog(context, booking),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _blue.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Leave a Review',
                      style: GoogleFonts.inter(
                          color: _blue,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  void _showReviewDialog(BuildContext context, Map<String, dynamic> booking) {
    int rating = 5;
    final controller = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Leave a Review', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('How was your experience?', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: const Color(0xFFFACC15),
                        size: 36,
                      ),
                      onPressed: () => setState(() => rating = index + 1),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Share your thoughts (optional)',
                    hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _blue),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setState(() => isSubmitting = true);
                        try {
                          final user = supabase.auth.currentUser;
                          final profileData = await supabase.from('profiles').select('full_name, email').eq('id', user!.id).single();
                          
                          await supabase.from('reviews').insert({
                            'car_id': booking['car_id'],
                            'user_id': user.id,
                            'rating': rating,
                            'comment': controller.text.trim(),
                            'status': 'pending',
                            'name': profileData['full_name'] ?? 'User',
                            'email': profileData['email'] ?? user.email ?? 'Unknown',
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Review submitted successfully!', style: GoogleFonts.inter()),
                              backgroundColor: const Color(0xFF10B981),
                            ));
                          }
                        } catch (e) {
                          setState(() => isSubmitting = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Failed to submit review.', style: GoogleFonts.inter()),
                              backgroundColor: Colors.redAccent,
                            ));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Submit', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
