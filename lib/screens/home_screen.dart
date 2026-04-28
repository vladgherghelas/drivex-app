import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../supabase_config.dart';
import '../models/car_model.dart';
import 'car_detail_screen.dart';
import 'bookings_screen.dart';
import 'saved_screen.dart';
import 'profile_screen.dart';
import 'collection_screen.dart';
import 'notifications_screen.dart';
import '../services/favorites_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  int _savedRefreshTrigger = 0;
  String _cat = 'All';
  List<CarModel> _cars = [];
  List<CarModel> _allCars = [];
  bool _loading = true;
  String? _err;
  int _unreadKycCount = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _carsSub;
  RealtimeChannel? _kycChannel;
  // Global notification panel state
  OverlayEntry? _notifOverlay;
  bool _allRead = false;
  final Set<int> _readIds = {};

  static const _bg   = Color(0xFFF1F5F9);
  static const _blue = Color(0xFF00C4B4);
  static const _cats = ['All', 'Electric', 'SUV', 'Luxury', 'Sports'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupStream();
    FavoritesService.instance.init();
    _loadUnreadCount();
    _subscribeKycNotifications();
    try { _allRead = html.window.localStorage['notif_all_read'] == 'true'; } catch (_) {}
  }

  Future<void> _loadUnreadCount() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await supabase.from('kyc_notifications').select('id').eq('user_id', uid).eq('read', false);
      if (mounted) setState(() => _unreadKycCount = (data as List).length);
    } catch (_) {}
  }

  void _subscribeKycNotifications() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _kycChannel = supabase
      .channel('global_kyc_$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyc_notifications',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) {
          if (!mounted) return;
          final status = payload.newRecord['status'] as String? ?? '';
          final message = payload.newRecord['message'] as String? ?? 'KYC status updated';
          setState(() => _unreadKycCount++);
          // Show banner notification
          final color = status == 'approved' ? const Color(0xFF22C55E)
              : status == 'rejected' ? const Color(0xFFEF4444)
              : const Color(0xFF6366F1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              backgroundColor: color,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              content: Row(children: [
                Icon(status == 'approved' ? Icons.verified_rounded
                    : status == 'rejected' ? Icons.cancel_rounded
                    : Icons.manage_search_rounded,
                  color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
              action: SnackBarAction(
                label: 'View',
                textColor: Colors.white.withOpacity(0.85),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => _loadUnreadCount()),
              ),
            ),
          );
        },
      )
      .subscribe();
  }

  // ── App lifecycle ────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS Safari kills the WebSocket when the PWA goes to background.
    // Re-subscribe when the user brings the app back to foreground.
    if (state == AppLifecycleState.resumed) {
      _setupStream();
    }
  }

  // ── Real-time stream (recommended Flutter approach) ──────────────────────
  void _setupStream() {
    // .stream() re-emits the full table snapshot on every INSERT/UPDATE/DELETE.
    // It works for anon clients and handles WebSocket reconnection automatically.
    _carsSub?.cancel();
    _carsSub = supabase
        .from('cars')
        .stream(primaryKey: ['id'])
        .order('rating', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            _allCars = rows.map((e) => CarModel.fromMap(e)).toList();
            _applyFilter(loading: false);
          },
          onError: (_) {
            if (mounted) setState(() { _err = 'Failed to load'; _loading = false; });
          },
        );
  }

  /// Applies the current category filter to _allCars and rebuilds the UI.
  void _applyFilter({bool loading = false}) {
    if (!mounted) return;
    final filtered = _cat == 'All'
        ? _allCars
        : _allCars.where((c) => c.category == _cat).toList();
    setState(() { _cars = filtered; _loading = loading; _err = null; });
  }

  Future<void> _showGlobalNotifications() async {
    if (_notifOverlay != null) { _dismissGlobalNotif(); return; }
    final user = supabase.auth.currentUser;
    final uid = user?.id;
    final firstName = ((user?.userMetadata?['full_name'] as String?) ?? 'Driver').split(' ').first;
    List<_NotifItem> kycItems = [];
    if (uid != null) {
      try {
        final data = await supabase.from('kyc_notifications').select().eq('user_id', uid).order('created_at', ascending: false).limit(5);
        kycItems = (data as List).asMap().entries.map((e) {
          final k = Map<String,dynamic>.from(e.value);
          final status = k['status'] as String? ?? '';
          final message = k['message'] as String? ?? 'KYC status updated';
          final unread = k['read'] == false;
          final dt = DateTime.tryParse(k['created_at'] ?? '')?.toLocal();
          final diff = dt != null ? DateTime.now().difference(dt) : null;
          final t = diff == null ? '' : diff.inMinutes < 1 ? 'Just now' : diff.inHours < 1 ? '${diff.inMinutes}m ago' : diff.inDays < 1 ? '${diff.inHours}h ago' : '${diff.inDays}d ago';
          final icon = status == 'approved' ? Icons.verified_rounded : status == 'rejected' ? Icons.cancel_rounded : Icons.manage_search_rounded;
          final color = status == 'approved' ? const Color(0xFF22C55E) : status == 'rejected' ? const Color(0xFFEF4444) : const Color(0xFF6366F1);
          final title = status == 'approved' ? 'Identity Verified ✓' : status == 'rejected' ? 'Verification Rejected' : 'Documents Under Review';
          return _NotifItem(id: 1000 + e.key, icon: icon, color: color, title: title, body: message, time: t, unread: unread, car: null);
        }).toList();
        await supabase.from('kyc_notifications').update({'read': true}).eq('user_id', uid).eq('read', false);
        if (mounted) setState(() => _unreadKycCount = 0);
      } catch (_) {}
    }
    final dealCar = _cars.isNotEmpty ? _cars.first : null;
    final newCar = _cars.length > 1 ? _cars[1] : dealCar;
    final staticNotifs = <_NotifItem>[
      _NotifItem(id: 0, icon: Icons.waving_hand_rounded, color: const Color(0xFFF59E0B), title: 'Welcome, $firstName! 🎉', body: 'Your DriveX account is ready. Start exploring luxury vehicles!', time: 'Just now', unread: !_allRead && !_readIds.contains(0), car: null),
      if (dealCar != null) _NotifItem(id: 1, icon: Icons.local_offer_rounded, color: const Color(0xFF059669), title: 'Exclusive Deal', body: '20% off ${dealCar.displayName} this weekend!', time: '2h ago', unread: !_allRead && !_readIds.contains(1), car: dealCar),
      _NotifItem(id: 2, icon: Icons.receipt_long_rounded, color: const Color(0xFF00C4B4), title: 'Booking Confirmed', body: 'Your booking has been confirmed. Enjoy your ride!', time: '1d ago', unread: !_allRead && !_readIds.contains(2), car: null),
      if (newCar != null) _NotifItem(id: 3, icon: Icons.directions_car_rounded, color: const Color(0xFF7C3AED), title: 'New Arrival', body: '${newCar.displayName} is now available to book!', time: '3d ago', unread: !_allRead && !_readIds.contains(3), car: newCar),
      _NotifItem(id: 4, icon: Icons.star_rounded, color: const Color(0xFFD4AF37), title: 'Leave a Review', body: 'How was your last DriveX experience?', time: '5d ago', unread: !_allRead && !_readIds.contains(4), car: null),
    ];
    final totalNotifs = [...kycItems, ...staticNotifs].length;
    final allNotifs = [...kycItems, ...staticNotifs].take(5).toList();
    final hasMore = totalNotifs > 5 || kycItems.length >= 5;
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final width = mq.size.width;
    _notifOverlay = OverlayEntry(builder: (_) => Material(
      color: Colors.transparent,
      child: Stack(children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _dismissGlobalNotif, child: Container(color: Colors.black54))),
        Positioned(top: topPad + 62, right: 14, bottom: 90, width: width * 0.87,
          child: Align(alignment: Alignment.topCenter,
            child: _NotifPanel(
              items: allNotifs,
              hasMore: hasMore,
              onDismiss: _dismissGlobalNotif,
              onMarkAllRead: () { _allRead = true; try { html.window.localStorage['notif_all_read'] = 'true'; } catch (_) {} _dismissGlobalNotif(); if (mounted) setState(() {}); },
              onTapItem: (item) { _readIds.add(item.id); _dismissGlobalNotif(); if (item.car != null && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: item.car!))); if (mounted) setState(() {}); },
              onViewAll: () { _dismissGlobalNotif(); Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => _loadUnreadCount()); },
            ))),
      ]),
    ));
    Overlay.of(context, rootOverlay: true).insert(_notifOverlay!);
  }

  void _dismissGlobalNotif() { _notifOverlay?.remove(); _notifOverlay = null; if (mounted) setState(() {}); }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _carsSub?.cancel();
    _kycChannel?.unsubscribe();
    _notifOverlay?.remove();
    super.dispose();
  }

  Widget _bellButton() {
    final hasUnread = !_allRead || _unreadKycCount > 0;
    return GestureDetector(
      onTap: _showGlobalNotifications,
      child: Stack(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]),
          child: const Icon(Icons.notifications_outlined, color: Color(0xFF475569), size: 20)),
        if (hasUnread) Positioned(top: 8, right: 8,
          child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = !_allRead || _unreadKycCount > 0;
    final tabs = [
      _ExploreTab(cars: _cars, loading: _loading, err: _err, cat: _cat,
        unreadCount: _unreadKycCount,
        hasUnread: hasUnread,
        onCat: (c) { setState(() => _cat = c); _applyFilter(); },
        onRefresh: _setupStream,
        onProfile: () => setState(() => _tab = 3),
        onTabChange: (i) => setState(() => _tab = i),
        onShowNotif: _showGlobalNotifications,
      ),
      SavedScreen(refreshTrigger: _savedRefreshTrigger),
      const BookingsScreen(),
      ProfileScreen(unreadKycCount: _unreadKycCount, onNotifRead: _loadUnreadCount),
    ];
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        IndexedStack(index: _tab, children: tabs),
        if (_tab == 1 || _tab == 2)
          SafeArea(child: Align(alignment: Alignment.topRight,
            child: Padding(padding: const EdgeInsets.only(top: 8, right: 16), child: _bellButton()))),
      ]),
      bottomNavigationBar: _BottomNav(
        selected: _tab,
        onTap: (i) => setState(() {
          if (i == 1) _savedRefreshTrigger++;
          _tab = i;
        }),
      ),
    );
  }
}

class _ExploreTab extends StatefulWidget {
  final List<CarModel> cars;
  final bool loading;
  final String? err;
  final String cat;
  final int unreadCount;
  final bool hasUnread;
  final ValueChanged<String> onCat;
  final VoidCallback onRefresh;
  final VoidCallback onProfile;
  final ValueChanged<int> onTabChange;
  final Future<void> Function() onShowNotif;
  const _ExploreTab({required this.cars, required this.loading, required this.err,
    required this.cat, required this.onCat, required this.onRefresh,
    required this.onProfile, required this.onTabChange, required this.onShowNotif,
    this.unreadCount = 0, this.hasUnread = false});
  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  static const _bg     = Color(0xFFF1F5F9);
  static const _card   = Color(0xFFFFFFFF);
  static const _blue   = Color(0xFF00C4B4);
  static const _border = Color(0xFFE2E8F0);
  static const _cats = ['All', 'Electric', 'SUV', 'Luxury', 'Sports'];
  final _searchCtrl = TextEditingController();
  String _query = '';
  OverlayEntry? _searchOverlay;
  String _location = 'San Francisco Int. Airport (SFO)';

  @override
  void initState() {
    super.initState();
    try {
      final loc = html.window.localStorage['pickup_location'];
      if (loc != null && loc.isNotEmpty) _location = loc;
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchOverlay?.remove();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CarModel> get _displayed => _query.isEmpty ? widget.cars
      : widget.cars.where((c) => c.displayName.toLowerCase().contains(_query.toLowerCase())).toList();

  void _showSearch() {
    if (_searchOverlay != null) { _dismissSearch(); return; }
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final sc = TextEditingController();
    String query = '';

    bool _matches(CarModel c, String q) {
      final lower = q.toLowerCase();
      return c.displayName.toLowerCase().contains(lower) ||
             c.brand.toLowerCase().contains(lower) ||
             c.category.toLowerCase().contains(lower) ||
             (c.engineType ?? '').toLowerCase().contains(lower) ||
             c.drive.toLowerCase().contains(lower) ||
             (c.power ?? '').toLowerCase().contains(lower) ||
             c.seats.toString().contains(lower) ||
             c.features.any((f) => f.toLowerCase().contains(lower));
    }

    _searchOverlay = OverlayEntry(builder: (_) {
      final results = query.isEmpty
          ? widget.cars
          : widget.cars.where((c) => _matches(c, query)).toList();

      return Material(
        color: Colors.transparent,
        child: Stack(children: [
          // Tap-outside to dismiss
          Positioned.fill(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissSearch,
            child: Container(color: Colors.black.withOpacity(0.45)))),

          Positioned(
            top: topPad + 8, left: 12, right: 12, bottom: 90,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 32, offset: const Offset(0, 8))],
              ),
              child: Column(children: [
                // ── Header row: search field + close ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF00C4B4).withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const SizedBox(width: 12),
                          const Icon(Icons.search_rounded, color: Color(0xFF00C4B4), size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(
                            controller: sc, autofocus: true,
                            style: GoogleFonts.inter(color: const Color(0xFF0F172A), fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Brand, model, SUV, Electric, AWD…',
                              hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
                              border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                            onChanged: (v) { query = v; _searchOverlay?.markNeedsBuild(); },
                          )),
                          if (sc.text.isNotEmpty)
                            GestureDetector(
                              onTap: () { sc.clear(); query = ''; _searchOverlay?.markNeedsBuild(); },
                              child: const Padding(padding: EdgeInsets.only(right: 10),
                                child: Icon(Icons.cancel_rounded, color: Color(0xFFCBD5E1), size: 20))),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Close button
                    GestureDetector(
                      onTap: _dismissSearch,
                      child: Container(
                        width: 44, height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Icon(Icons.close_rounded, color: Color(0xFF475569), size: 22),
                      ),
                    ),
                  ]),
                ),

                // ── Result count + Browse All ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(children: [
                    Text(
                      query.isEmpty ? 'All Vehicles' : '${results.length} result${results.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                    const SizedBox(width: 8),
                    const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () { _dismissSearch(); Navigator.push(context, MaterialPageRoute(builder: (_) => CollectionScreen(initialCategory: widget.cat))); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0xFF00C4B4), borderRadius: BorderRadius.circular(8)),
                        child: Text('Browse All', style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)))),
                  ])),
                const SizedBox(height: 8),

                // ── Results list ──
                Expanded(child: results.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_off_rounded, color: const Color(0xFFCBD5E1), size: 52),
                      const SizedBox(height: 12),
                      Text('No vehicles found', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Text('Try "electric", "AWD", "SUV"…', style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 12)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final car = results[i];
                        return GestureDetector(
                          onTap: () { _dismissSearch(); Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car))); },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: Row(children: [
                              ClipRRect(borderRadius: BorderRadius.circular(10),
                                child: CachedNetworkImage(
                                  imageUrl: car.imageUrl, width: 76, height: 60, fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(width: 76, height: 60, color: const Color(0xFFE2E8F0)),
                                  errorWidget: (_, __, ___) => Container(width: 76, height: 60, color: const Color(0xFFE2E8F0),
                                    child: const Icon(Icons.directions_car, color: const Color(0xFFCBD5E1), size: 28)))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(car.displayName, style: GoogleFonts.inter(color: const Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 5),
                                Wrap(spacing: 5, runSpacing: 4, children: [
                                  _searchChip(car.category, const Color(0xFF00C4B4)),
                                  if (car.engineType != null) _searchChip(car.engineType!, const Color(0xFF6366F1)),
                                  _searchChip(car.drive, const Color(0xFFF59E0B)),
                                ]),
                                const SizedBox(height: 5),
                                Text('\$${car.pricePerDay}/day',
                                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF00C4B4), fontWeight: FontWeight.w800)),
                              ])),
                              const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFCBD5E1), size: 14),
                            ]),
                          ),
                        );
                      },
                    ),
                ),
              ]),
            ),
          ),
        ]),
      );
    });
    Overlay.of(context, rootOverlay: true).insert(_searchOverlay!);
  }

  Widget _searchChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
  );

  void _dismissSearch() {
    _searchOverlay?.remove();
    _searchOverlay = null;
  }

  void _showLocation() {
    const locs = ['San Francisco Int. Airport (SFO)', 'Los Angeles (LAX)', 'New York (JFK)', 'Miami (MIA)', 'Chicago (ORD)'];
    showModalBottomSheet(
      context: context, backgroundColor: _card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        Container(height: 4, width: 40, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Pickup Location', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
        const SizedBox(height: 8),
        ...locs.map((l) => ListTile(
          leading: Icon(
            Icons.location_on_outlined,
            color: l == _location ? _blue : const Color(0xFF94A3B8),
            size: 20,
          ),
          trailing: l == _location
              ? const Icon(Icons.check_circle_rounded, color: _blue, size: 18)
              : null,
          title: Text(l, style: GoogleFonts.inter(
              color: l == _location ? const Color(0xFF0F172A) : const Color(0xFF475569),
              fontSize: 14,
              fontWeight: l == _location ? FontWeight.w700 : FontWeight.w400)),
          onTap: () {
            setState(() => _location = l);
            try { html.window.localStorage['pickup_location'] = l; } catch (_) {}
            Navigator.pop(context);
          },
        )),
        const SizedBox(height: 16),
      ]),
    );
  }



  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] as String?) ?? 'Driver';
    final first = name.split(' ').first;
    final featured = widget.cars.where((c) => c.badge != null).toList();
    final featuredList = featured.isEmpty ? widget.cars.take(3).toList() : featured;
    final displayed = _displayed;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: _blue, backgroundColor: _card,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Container(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 8, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header row
            Row(children: [
              GestureDetector(
                onTap: widget.onProfile,
                child: Container(width: 44, height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [_blue, Color(0xFF009BA8)])),
                  child: Center(child: Text(
                    first.isNotEmpty ? first[0].toUpperCase() : 'D',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('WELCOME BACK', style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
                Text(first, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
              ])),
              GestureDetector(
                onTap: widget.onShowNotif,
                child: Stack(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: _card, shape: BoxShape.circle, border: Border.all(color: _border)),
                    child: const Icon(Icons.notifications_outlined, color: Color(0xFF475569), size: 20)),
                  if (widget.hasUnread)
                    Positioned(top: 8, right: 8,
                      child: Container(width: 8, height: 8,
                        decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle))),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            // Search bar
            GestureDetector(
              onTap: _showSearch,
              child: Container(height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                child: Row(children: [
                  const Icon(Icons.search, color: const Color(0xFF94A3B8), size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Search vehicles…', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14))),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectionScreen())),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: _blue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.tune, color: _blue, size: 16)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Location
            GestureDetector(
              onTap: _showLocation,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: _blue.withOpacity(0.07), borderRadius: BorderRadius.circular(13), border: Border.all(color: _blue.withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.location_on, color: _blue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CURRENT PICKUP', style: GoogleFonts.inter(fontSize: 9, color: _blue, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                    Text(_location, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                  ])),
                  const Icon(Icons.chevron_right, color: const Color(0xFF94A3B8), size: 18),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            // Category chips — fit all on screen with equal widths
            SizedBox(
              height: 36,
              child: Row(
                children: List.generate(_cats.length, (i) {
                  final c = _cats[i]; final sel = c == widget.cat;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onCat(c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(right: i < _cats.length - 1 ? 7 : 0),
                        decoration: BoxDecoration(
                          color: sel ? _blue : _card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: sel ? _blue : _border),
                        ),
                        child: Center(
                          child: Text(c,
                            style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : const Color(0xFF475569))),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 22),
          ]),
        )),

        // Featured Collections
        SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Featured Collections', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectionScreen())),
                child: Text('View all', style: GoogleFonts.inter(fontSize: 13, color: _blue, fontWeight: FontWeight.w600))),
            ])),
          SizedBox(height: 230,
            child: widget.loading
                ? _ShimmerCarousel()
                : featuredList.isEmpty
                    ? _EmptyFeatured(category: widget.cat)
                    : PageView.builder(
                        controller: PageController(viewportFraction: 0.88),
                        itemCount: featuredList.length,
                        itemBuilder: (_, i) => _FeaturedCard(car: featuredList[i], allCars: widget.cars),
                      )),
          const SizedBox(height: 24),
        ])),

        // Recommended header
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Recommended for You', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CollectionScreen(initialCategory: widget.cat))),
              child: Text('${displayed.length} cars', style: GoogleFonts.inter(fontSize: 13, color: _blue, fontWeight: FontWeight.w600))),
          ]),
        )),

        if (widget.err != null)
          SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.all(32),
            child: Column(children: [
              const Icon(Icons.wifi_off_rounded, color: const Color(0xFFCBD5E1), size: 48),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: widget.onRefresh, child: const Text('Retry')),
            ])))),

        if (widget.loading)
          SliverList(delegate: SliverChildBuilderDelegate((_, __) => _ShimmerCarCard(), childCount: 5)),

        if (!widget.loading && widget.err == null && displayed.isEmpty)
          SliverToBoxAdapter(child: _EmptyRecommended(category: widget.cat)),

        if (!widget.loading && widget.err == null && displayed.isNotEmpty)
          SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) => _CarTile(car: displayed[i], allCars: widget.cars),
            childCount: displayed.length,
          )),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

// ─── Gallery Preview Overlay ─────────────────────────────────────────────────
void _openGallery(BuildContext context, CarModel car, {int startIndex = 0}) {
  final images = [car.imageUrl, ...car.galleryUrls];
  final ctrl = PageController(initialPage: startIndex);
  int current = startIndex;
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.96),
    builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        PageView.builder(
          controller: ctrl,
          itemCount: images.length,
          onPageChanged: (i) => setSt(() => current = i),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Center(child: Hero(
              tag: '${car.id}_$i',
              child: CachedNetworkImage(
                imageUrl: images[i],
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Color(0xFF00C4B4), strokeWidth: 2)),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 60),
              ),
            )),
          ),
        ),
        // Close
        Positioned(top: 52, right: 16, child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
            child: const Icon(Icons.close, color: Colors.white, size: 20)),
        )),
        // Counter
        Positioned(top: 58, left: 0, right: 0, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Text('${current + 1} / ${images.length}',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ))),
        // Dots
        Positioned(bottom: 48, left: 0, right: 0, child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 20 : 7, height: 7,
            decoration: BoxDecoration(
              color: i == current ? const Color(0xFF00C4B4) : Colors.white38,
              borderRadius: BorderRadius.circular(4),
            ),
          )),
        )),
        // Car name bottom
        Positioned(bottom: 80, left: 0, right: 0, child: Center(child: Text(
          car.displayName,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ))),
      ]),
    )),
  );
}

// ─── Featured Card ────────────────────────────────────────────────────────────
class _FeaturedCard extends StatefulWidget {
  final CarModel car;
  final List<CarModel> allCars;
  const _FeaturedCard({required this.car, this.allCars = const []});
  @override
  State<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<_FeaturedCard> {
  static const _blue = Color(0xFF00C4B4);

  @override
  void initState() {
    super.initState();
    FavoritesService.instance.addListener(_onFavChange);
  }

  void _onFavChange() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    FavoritesService.instance.removeListener(_onFavChange);
    super.dispose();
  }

  Widget _specPill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.45),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withOpacity(0.15)),
    ),
    child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
  );

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final allImages = [car.imageUrl, ...car.galleryUrls];
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car, allCars: widget.allCars))),
      child: Container(
        margin: const EdgeInsets.only(right: 12, left: 4, bottom: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: _blue.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            // Tappable image → gallery
            GestureDetector(
              onTap: () => _openGallery(context, car),
              child: CachedNetworkImage(imageUrl: car.imageUrl, width: double.infinity, height: 260, fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 260, color: const Color(0xFFE2E8F0)),
                errorWidget: (_, __, ___) => Container(height: 260, color: const Color(0xFFE2E8F0),
                  child: const Icon(Icons.directions_car, color: const Color(0xFFCBD5E1), size: 60)))),
            // Double gradient for depth
            Container(height: 260, decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.08), Colors.transparent, Colors.black.withOpacity(0.92)]))),
            // Gallery hint top-right
            if (allImages.length > 1)
              Positioned(top: 12, right: 52,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.photo_library_outlined, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text('${allImages.length}', style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                )),
            // Badge top left
            if (car.badge != null)
              Positioned(top: 12, left: 12,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(8)),
                  child: Text(car.badge!, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)))),
            // Heart button
            Positioned(top: 10, right: 10,
              child: GestureDetector(
                onTap: () => FavoritesService.instance.toggle(widget.car.id),
                child: Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.25))),
                  child: Icon(
                    FavoritesService.instance.isSaved(widget.car.id) ? Icons.favorite : Icons.favorite_border,
                    color: FavoritesService.instance.isSaved(widget.car.id) ? const Color(0xFFFF4D6D) : Colors.white, size: 19),
                ),
              )),
            // Bottom info panel
            Positioned(bottom: 0, left: 0, right: 0,
              child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (car.engineType != null) _specPill('${car.engineIcon} ${car.engineType!}'),
                    _specPill('🔧 ${car.drive}'),
                    _specPill('🪑 ${car.seats}'),
                    if (car.power != null) _specPill('⚡ ${car.power}'),
                  ]),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(car.displayName, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text(car.priceLabel, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _blue)),
                    ])),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car, allCars: widget.allCars))),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF00C4B4), Color(0xFF00A89A)]),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))],
                        ),
                        child: Text('Book Now', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)))),
                  ]),
                ])),
            ),
          ])),
      ),
    );
  }
}

class _CarTile extends StatefulWidget {
  final CarModel car;
  final List<CarModel> allCars;
  const _CarTile({required this.car, this.allCars = const []});
  @override
  State<_CarTile> createState() => _CarTileState();
}

class _CarTileState extends State<_CarTile> {
  static const _card = Color(0xFFFFFFFF);
  static const _blue = Color(0xFF00C4B4);
  static const _border = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    FavoritesService.instance.addListener(_onFavChange);
  }

  void _onFavChange() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    FavoritesService.instance.removeListener(_onFavChange);
    super.dispose();
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: const Color(0xFF64748B)),
      const SizedBox(width: 3),
      Text(label, style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569), fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final allImages = [car.imageUrl, ...car.galleryUrls];
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car, allCars: widget.allCars))),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Tappable image → gallery ──
          GestureDetector(
            onTap: () => _openGallery(context, car),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(children: [
                CachedNetworkImage(imageUrl: car.imageUrl, width: 100, height: 86, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(width: 100, height: 86, color: const Color(0xFFE2E8F0)),
                  errorWidget: (_, __, ___) => Container(width: 100, height: 86, color: const Color(0xFFE2E8F0),
                    child: const Icon(Icons.directions_car, color: const Color(0xFFCBD5E1), size: 32))),
                Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.35)])))),
                if (allImages.length > 1)
                  Positioned(bottom: 5, left: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.photo_library_outlined, color: Colors.white, size: 9),
                        const SizedBox(width: 2),
                        Text('${allImages.length}', style: GoogleFonts.inter(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ]))),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          // ── Info column ──
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(car.displayName,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis, maxLines: 1)),
              GestureDetector(
                onTap: () => FavoritesService.instance.toggle(car.id),
                child: Icon(
                  FavoritesService.instance.isSaved(car.id) ? Icons.favorite : Icons.favorite_border,
                  color: FavoritesService.instance.isSaved(car.id) ? const Color(0xFFFF4D6D) : const Color(0xFFCBD5E1),
                  size: 20)),
            ]),
            const SizedBox(height: 5),
            Wrap(spacing: 4, runSpacing: 4, children: [
              if (car.engineType != null) _chip(Icons.local_gas_station_outlined, car.engineType!),
              _chip(Icons.settings_outlined, car.drive),
              _chip(Icons.people_outline, '${car.seats}'),
              if (car.power != null) _chip(Icons.bolt_outlined, car.power!),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 12),
                  const SizedBox(width: 3),
                  Text(car.rating.toStringAsFixed(1),
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF475569), fontWeight: FontWeight.w600)),
                  const SizedBox(width: 3),
                  Text('(${car.reviewCount})', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                ]),
                const SizedBox(height: 2),
                Text(car.priceLabel, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: _blue)),
              ]),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car, allCars: widget.allCars))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00C4B4), Color(0xFF00A89A)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: _blue.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: Text('Book', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)))),
            ]),
          ])),
        ]),
      ),
    );
  }
}


class _ShimmerCarousel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: const Color(0xFFE2E8F0), highlightColor: const Color(0xFFF8FAFC),
    child: Container(margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))));
}

class _ShimmerCarCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: const Color(0xFFE2E8F0), highlightColor: const Color(0xFFF8FAFC),
    child: Container(margin: const EdgeInsets.fromLTRB(16, 0, 16, 12), height: 96,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))));
}

class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  static const _blue = Color(0xFF00C4B4);
  const _BottomNav({required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06)))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _NI(icon: Icons.explore_outlined, active: Icons.explore, label: 'Explore', i: 0, sel: selected, onTap: onTap),
              _NI(icon: Icons.favorite_outline, active: Icons.favorite, label: 'Saved', i: 1, sel: selected, onTap: onTap),
              _NI(icon: Icons.receipt_long_outlined, active: Icons.receipt_long, label: 'Bookings', i: 2, sel: selected, onTap: onTap),
              _NI(icon: Icons.person_outline, active: Icons.person, label: 'Profile', i: 3, sel: selected, onTap: onTap),
            ]),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}

class _NI extends StatelessWidget {
  final IconData icon, active;
  final String label;
  final int i, sel;
  final ValueChanged<int> onTap;
  static const _blue = Color(0xFF00C4B4);
  const _NI({required this.icon, required this.active, required this.label, required this.i, required this.sel, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = i == sel;
    return GestureDetector(
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: s ? _blue.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(s ? active : icon, color: s ? _blue : const Color(0xFF94A3B8), size: 22),
          const SizedBox(height: 3),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: s ? FontWeight.w700 : FontWeight.w400, color: s ? _blue : const Color(0xFF94A3B8))),
        ]),
      ),
    );
  }
}

// ─── Notification Data ─────────────────────────────────────────────────────────
class _NotifItem {
  final int id;
  final IconData icon;
  final Color color;
  final String title, body, time;
  final bool unread;
  final CarModel? car;
  const _NotifItem({required this.id, required this.icon, required this.color,
    required this.title, required this.body, required this.time,
    required this.unread, required this.car});
}

// ─── Notification Panel Overlay ────────────────────────────────────────────────
class _NotifPanel extends StatefulWidget {
  final List<_NotifItem> items;
  final bool hasMore;
  final VoidCallback onDismiss;
  final VoidCallback onMarkAllRead;
  final ValueChanged<_NotifItem> onTapItem;
  final VoidCallback? onViewAll;
  const _NotifPanel({required this.items, required this.onDismiss,
    required this.onMarkAllRead, required this.onTapItem,
    this.hasMore = false, this.onViewAll});
  @override
  State<_NotifPanel> createState() => _NotifPanelState();
}

class _NotifPanelState extends State<_NotifPanel> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  static const _blue  = Color(0xFF00C4B4);
  static const _panel = Color(0xFAF8FAFC);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(begin: const Offset(0.15, -0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final unreadCount = widget.items.where((n) => n.unread).length;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 36, offset: const Offset(0, 10))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(children: [
                if (unreadCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(10)),
                    child: Text('$unreadCount new', style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                ],
                Text('Notifications', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                const Spacer(),
                if (unreadCount > 0)
                  GestureDetector(
                    onTap: widget.onMarkAllRead,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: _blue.withOpacity(0.15), borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _blue.withOpacity(0.3))),
                      child: Text('Mark all read', style: GoogleFonts.inter(fontSize: 11, color: _blue, fontWeight: FontWeight.w700)),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(width: 28, height: 28,
                    decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close, color: Color(0xFF64748B), size: 15))),
              ]),
            ),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            // Scrollable items list — constrained so it never clips off screen
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.items.asMap().entries.map((e) {
                    final n = e.value;
                    final isLast = e.key == widget.items.length - 1;
                    final tappable = n.car != null;
                    return Column(children: [
                      GestureDetector(
                        onTap: () => widget.onTapItem(n),
                        child: Container(
                          color: n.unread ? const Color(0xFFF0FDFA) : Colors.transparent,
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: n.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: n.color.withOpacity(0.3)),
                              ),
                              child: Icon(n.icon, color: n.color, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(n.title,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)))),
                                if (n.unread)
                                  Container(width: 7, height: 7, margin: const EdgeInsets.only(left: 6, top: 2),
                                    decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle)),
                              ]),
                              const SizedBox(height: 3),
                              Text(n.body, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), height: 1.4)),
                              const SizedBox(height: 4),
                              Row(children: [
                                Text(n.time, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCBD5E1), fontWeight: FontWeight.w500)),
                                if (tappable) ...[
                                  const SizedBox(width: 8),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: n.color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                                    child: Text('View car', style: GoogleFonts.inter(fontSize: 10, color: n.color, fontWeight: FontWeight.w700))),
                                ],
                              ]),
                            ])),
                            if (tappable)
                              Padding(padding: const EdgeInsets.only(left: 8, top: 4),
                                child: Icon(Icons.arrow_forward_ios_rounded, color: const Color(0xFFCBD5E1), size: 12)),
                          ]),
                        ),
                      ),
                      if (!isLast) const Divider(color: Color(0xFFE2E8F0), height: 1, indent: 66),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            // Footer — "View all" when there are more, else "Mark all as read"
            GestureDetector(
              onTap: widget.hasMore && widget.onViewAll != null ? widget.onViewAll : widget.onMarkAllRead,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: widget.hasMore ? _blue.withOpacity(0.06) : Colors.transparent,
                  border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    widget.hasMore ? 'View all notifications' : 'Mark all as read',
                    style: GoogleFonts.inter(fontSize: 13, color: _blue, fontWeight: FontWeight.w700)),
                  if (widget.hasMore) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, color: _blue, size: 14),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Empty state: Featured section ──────────────────────────────────────────
class _EmptyFeatured extends StatelessWidget {
  final String category;
  const _EmptyFeatured({required this.category});
  static const _blue   = Color(0xFF00C4B4);
  static const _card   = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE2E8F0);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 210,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFE8F5F3), const Color(0xFFF1F5F9)],
          ),
          border: Border.all(color: _blue.withOpacity(0.15)),
          boxShadow: [BoxShadow(color: _blue.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Stack(children: [
          // Decorative glow
          Positioned(top: -30, right: -20,
            child: Container(width: 130, height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blue.withOpacity(0.06),
              ),
            ),
          ),
          // Content
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [_blue.withOpacity(0.25), _blue.withOpacity(0.05)]),
                border: Border.all(color: _blue.withOpacity(0.3), width: 1.5),
              ),
              child: const Icon(Icons.directions_car_outlined, color: _blue, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'No $category cars featured',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            Text(
              'Switch to "All" to explore our full fleet',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
          ])),
        ]),
      ),
    );
  }
}

// ── Empty state: Recommended section ─────────────────────────────────────
class _EmptyRecommended extends StatelessWidget {
  final String category;
  const _EmptyRecommended({required this.category});
  static const _blue   = Color(0xFF00C4B4);  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(children: [
        const SizedBox(height: 20),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [_blue.withOpacity(0.18), _blue.withOpacity(0.0)],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.search_off_rounded, color: Color(0xFF00C4B4), size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          'No $category cars available',
          style: GoogleFonts.inter(
            fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We don’t have any $category vehicles\nin the fleet right now.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), height: 1.55),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _blue.withOpacity(0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.info_outline_rounded, color: _blue, size: 14),
            const SizedBox(width: 6),
            Text('Try “All” to see all available cars',
              style: GoogleFonts.inter(fontSize: 12, color: _blue, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}
