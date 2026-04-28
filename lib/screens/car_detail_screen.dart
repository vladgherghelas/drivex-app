import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/car_model.dart';
import 'booking_summary_screen.dart';
import '../services/favorites_service.dart';
import '../supabase_config.dart';
import '../widgets/app_toast.dart';

const _teal = Color(0xFF00C4B4);
const _dark = Color(0xFF0F172A);
const _slate = Color(0xFF64748B);
const _bg = Color(0xFFF1F5F9);

class CarDetailScreen extends StatefulWidget {
  final CarModel car;
  final List<CarModel> allCars;
  const CarDetailScreen({super.key, required this.car, this.allCars = const []});
  @override
  State<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends State<CarDetailScreen> {
  int _imgIdx = 0;
  bool _expanded = false;
  bool _condExpanded = false;
  final _pageCtrl = PageController();
  String _pickupLoc = 'San Francisco (SFO)';
  String _dropoffLoc = 'San Francisco (SFO)';
  DateTime _pickupDate = DateTime.now().add(const Duration(days: 1));
  DateTime _dropoffDate = DateTime.now().add(const Duration(days: 4));
  TimeOfDay _pickupTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _dropoffTime = const TimeOfDay(hour: 10, minute: 0);
  int get _days => _dropoffDate.difference(_pickupDate).inDays.clamp(1, 365);
  double _discountedRate(int base) {
    if (_days >= 28) return base * 0.75;
    if (_days >= 15) return base * 0.81;
    if (_days >= 8) return base * 0.87;
    if (_days >= 4) return base * 0.94;
    return base.toDouble();
  }

  @override
  void initState() { super.initState(); FavoritesService.instance.addListener(_rebuild); _fetchReviews(); }
  void _rebuild() { if (mounted) setState(() {}); }
  
  List<Map<String, dynamic>> _reviewsData = [];
  bool _reviewsLoading = true;

  Future<void> _fetchReviews() async {
    try {
      final res = await supabase.from('reviews').select().eq('car_id', widget.car.id).eq('status', 'approved').order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _reviewsData = List<Map<String, dynamic>>.from(res);
          _reviewsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  @override
  void dispose() { FavoritesService.instance.removeListener(_rebuild); _pageCtrl.dispose(); super.dispose(); }

  // Only include URLs that are non-empty and valid http(s) links
  List<String> get _imgs {
    final raw = [widget.car.imageUrl, ...widget.car.galleryUrls];
    return raw.where((u) => u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://'))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final similar = widget.allCars.where((c) => c.id != car.id && (c.category == car.category || c.brand == car.brand)).take(6).toList();
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          _appBar(car),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              _infoCard(car),
              const SizedBox(height: 16),
              _rentalCostCard(car),
              const SizedBox(height: 16),
              _specsCard(car),
              if (car.features.isNotEmpty) ...[const SizedBox(height: 16), _featuresCard(car)],
              const SizedBox(height: 16),
              _descCard(car),
              const SizedBox(height: 16),
              _rentalConditionsCard(),
              const SizedBox(height: 16),
              _reviewsCard(car),
            ])),
          ),
          if (similar.isNotEmpty) ...[
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(children: [
                Expanded(child: Text('Similar Vehicles', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: _dark))),
                Text('${similar.length} cars', style: GoogleFonts.inter(fontSize: 13, color: _teal, fontWeight: FontWeight.w600)),
              ]),
            )),
            SliverToBoxAdapter(child: SizedBox(
              height: 210,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                itemCount: similar.length,
                itemBuilder: (_, i) => _SimilarCard(car: similar[i]),
              ),
            )),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
        _bottomBar(car),
      ]),
    );
  }

  // ─── APP BAR ───
  // SliverAppBar with gallery passed DIRECTLY as flexibleSpace (no FlexibleSpaceBar).
  // FlexibleSpaceBar was the culprit stealing all touch events; without it,
  // swipe & tap gestures reach the PageView and GestureDetector inside _gallery.
  Widget _appBar(CarModel car) => SliverAppBar(
    expandedHeight: 340, pinned: true, backgroundColor: _dark, elevation: 0,
    automaticallyImplyLeading: false,
    leading: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24)),
        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
    ),
    actions: [
      GestureDetector(
        onTap: () => FavoritesService.instance.toggle(car.id),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(8), width: 40, height: 40,
          decoration: BoxDecoration(
            color: FavoritesService.instance.isSaved(car.id) ? const Color(0xFFFF4D6D) : Colors.black54,
            borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
          child: Icon(
            FavoritesService.instance.isSaved(car.id) ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
            color: Colors.white, size: 20)),
      ),
      const SizedBox(width: 4),
    ],
    // collapseMode.none prevents the parallax transform that was shifting
    // the dot indicators and counter to the middle of the photo.
    flexibleSpace: FlexibleSpaceBar(
      collapseMode: CollapseMode.none,
      background: _gallery(car),
    ),
  );

  void _openFullscreen(int idx) {
    final imgs = _imgs;
    showDialog(
      context: context, barrierColor: Colors.black,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) {
        int cur = idx;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            PageView.builder(
              controller: PageController(initialPage: idx),
              itemCount: imgs.length,
              onPageChanged: (i) => ss(() => cur = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Image.network(imgs[i], fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38, size: 80)))),
            SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20))),
              const Spacer(),
              StatefulBuilder(builder: (_, ss2) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text('${cur + 1}/${imgs.length}', style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
            ]))),
          ]),
        );
      }),
    );
  }

  // Shown when a car has no valid image URL in the database
  Widget _noImagePlaceholder() => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      // Neutral slate-gray — looks intentional, not broken/green
      colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF1A2332)])),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 88, height: 88,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.12))),
        child: const Icon(Icons.directions_car_outlined, color: Colors.white38, size: 42)),
      const SizedBox(height: 14),
      Text('No photo available', style: GoogleFonts.inter(color: Colors.white30, fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _gallery(CarModel car) {
    final imgs = _imgs;
    return Stack(fit: StackFit.expand, children: [
      // PageView is the ONLY interactive element — receives all swipes and taps
      PageView.builder(
        controller: _pageCtrl, itemCount: imgs.isEmpty ? 1 : imgs.length,
        onPageChanged: (i) => setState(() => _imgIdx = i),
        itemBuilder: (_, i) {
          if (imgs.isEmpty) return _noImagePlaceholder();
          return GestureDetector(
            onTap: () => _openFullscreen(i),
            child: Image.network(
              imgs[i],
              fit: BoxFit.cover,
              // Teal shimmer while loading
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: const Color(0xFF0F172A),
                  child: Center(child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                        : null,
                    color: _teal, strokeWidth: 2)),
                );
              },
              // Branded placeholder instead of dark error screen
              errorBuilder: (_, __, ___) => _noImagePlaceholder(),
            ),
          );
        },
      ),
      // Subtle top-only gradient so back/fav buttons stay readable.
      // No heavy bottom shadow — let the photo breathe.
      IgnorePointer(child: Container(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        stops: const [0.0, 0.30],
        colors: [Colors.black.withOpacity(0.40), Colors.transparent])))),
      if (car.badge != null)
        Positioned(top: 100, left: 16, child: IgnorePointer(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [_teal, Color(0xFF00A896)]), borderRadius: BorderRadius.circular(10)),
          child: Text(car.badge!, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))))),
      if (car.engineType != null)
        Positioned(top: 100, right: 16, child: IgnorePointer(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(car.engineIcon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
            Text(car.engineType!, style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ])))),
      Positioned(bottom: 32, right: 16, child: IgnorePointer(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text('${_imgIdx + 1}/${imgs.isEmpty ? 1 : imgs.length}', style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ])))),
      Positioned(bottom: 10, left: 0, right: 0, child: IgnorePointer(child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate((imgs.isEmpty ? 1 : imgs.length).clamp(0, 8), (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _imgIdx ? 22 : 6, height: 6,
          decoration: BoxDecoration(color: i == _imgIdx ? _teal : Colors.white38, borderRadius: BorderRadius.circular(3)),
        ))))),
    ]);
  }

  // ─── INFO CARD ───
  Widget _infoCard(CarModel car) => _Card(child: Column(children: [
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(car.brand, style: GoogleFonts.inter(fontSize: 13, color: _slate, fontWeight: FontWeight.w500)),
        Text(car.name, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: _dark, height: 1.1)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.star_rounded, color: Color(0xFFFACC15), size: 16),
          const SizedBox(width: 4),
          Text('${car.rating}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _dark)),
          const SizedBox(width: 4),
          Text('(${car.reviewCount} reviews)', style: GoogleFonts.inter(fontSize: 12, color: _slate)),
        ]),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('\$${car.pricePerDay}', style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w900, color: _teal, height: 1)),
        Text('per day', style: GoogleFonts.inter(fontSize: 12, color: _slate)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: car.isAvailable ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(
              color: car.isAvailable ? const Color(0xFF059669) : const Color(0xFFEF4444), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(car.isAvailable ? 'Available Now' : 'Unavailable',
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                color: car.isAvailable ? const Color(0xFF059669) : const Color(0xFFEF4444))),
          ])),
      ]),
    ]),
    const SizedBox(height: 16),
    _buildLocDateRow(),
  ]));

  // ── helpers ──
  String _fmtDate(DateTime d) {
    const wk = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${wk[d.weekday-1]}, ${mo[d.month-1]} ${d.day}';
  }
  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2,'0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  // ── location picker bottom sheet ──
  void _pickLocation(bool isPickup) {
    const locs = [
      ['San Francisco', 'SFO', Icons.flight],
      ['Los Angeles', 'LAX', Icons.flight],
      ['New York', 'JFK', Icons.flight],
      ['Miami', 'MIA', Icons.flight],
      ['Chicago', 'ORD', Icons.flight],
      ['Las Vegas', 'LAS', Icons.flight],
      ['Seattle', 'SEA', Icons.flight],
    ];
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) {
        final cur = isPickup ? _pickupLoc : _dropoffLoc;
        return Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.location_on_rounded, color: _teal, size: 20)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isPickup ? 'Pickup Location' : 'Drop-off Location',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
                Text('Select your preferred location', style: GoogleFonts.inter(fontSize: 12, color: _slate)),
              ]),
            ]),
            const SizedBox(height: 20),
            ...locs.map((l) {
              final label = '${l[0]} (${l[1]})';
              final sel = cur == label;
              return GestureDetector(
                onTap: () {
                  setState(() { if (isPickup) _pickupLoc = label; else _dropoffLoc = label; });
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: sel ? _teal.withOpacity(0.08) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? _teal : const Color(0xFFE2E8F0), width: sel ? 1.5 : 1)),
                  child: Row(children: [
                    Icon(Icons.my_location_rounded, color: sel ? _teal : _slate, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? _dark : _slate))),
                    if (sel) const Icon(Icons.check_circle_rounded, color: _teal, size: 20),
                  ]),
                ),
              );
            }),
          ]),
        );
      }),
    );
  }

  // ── date + time picker bottom sheet ──
  void _pickDateTime(bool isPickup) {
    DateTime tempDate = isPickup ? _pickupDate : _dropoffDate;
    TimeOfDay tempTime = isPickup ? _pickupTime : _dropoffTime;
    // Allow the full current year + next 2 years — no hard block on Jan/Feb/March
    final minDate = DateTime(DateTime.now().year, 1, 1);
    final maxDate = DateTime(DateTime.now().year + 2, 12, 31);

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── drag handle ──
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            // ── title ──
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(isPickup ? Icons.flight_takeoff_rounded : Icons.flight_land_rounded, color: _teal, size: 20)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isPickup ? 'Pickup Date & Time' : 'Drop-off Date & Time',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
                Text('Scroll wheels to select', style: GoogleFonts.inter(fontSize: 12, color: _slate)),
              ]),
            ])),
            const SizedBox(height: 12),
            // ── date wheel (fixed height, unconstrained months) ──
            SizedBox(height: 200, child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: tempDate,
              minimumDate: minDate,
              maximumDate: maxDate,
              onDateTimeChanged: (d) => ss(() => tempDate = d),
            )),
            // ── time row ──
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), child: Column(children: [
              const Divider(height: 24, color: Color(0xFFE2E8F0)),
              Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.access_time_rounded, color: _teal, size: 18)),
                const SizedBox(width: 10),
                Text('${isPickup ? "Pickup" : "Drop-off"} Time',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _dark)),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context, initialTime: tempTime,
                      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(primary: _teal, onPrimary: Colors.white, onSurface: _dark),
                      ), child: child!),
                    );
                    if (t != null) ss(() => tempTime = t);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _teal.withOpacity(0.25))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit_rounded, color: _teal, size: 13),
                      const SizedBox(width: 6),
                      Text(_fmtTime(tempTime), style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: _teal)),
                    ])),
                ),
              ]),
              const SizedBox(height: 20),
              // ── confirm button always visible ──
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () {
                  // Validate: pickup must be today or future, dropoff must be after pickup
                  final today = DateTime.now();
                  if (isPickup && tempDate.isBefore(DateTime(today.year, today.month, today.day))) {
                    AppToast.show(context, 'Pickup date must be today or later', success: false);
                    return;
                  }
                  if (!isPickup && !tempDate.isAfter(_pickupDate)) {
                    AppToast.show(context, 'Drop-off must be after pickup date', success: false);
                    return;
                  }
                  setState(() {
                    if (isPickup) {
                      _pickupDate = tempDate; _pickupTime = tempTime;
                      if (_dropoffDate.isBefore(_pickupDate.add(const Duration(days: 1)))) {
                        _dropoffDate = _pickupDate.add(const Duration(days: 1));
                      }
                    } else { _dropoffDate = tempDate; _dropoffTime = tempTime; }
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text('Confirm Selection', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
              )),
              // Extra bottom padding: respects screen protector / home bar
              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
            ])),
          ]),
        ),
      )),
    );
  }

  // ── unified booking card ──
  Widget _buildLocDateRow() => Column(children: [
    _bookingRow(
      icon: Icons.flight_takeoff_rounded,
      label: 'PICKUP',
      loc: _pickupLoc,
      date: _fmtDate(_pickupDate),
      time: _fmtTime(_pickupTime),
      onLoc: () => _pickLocation(true),
      onDateTime: () => _pickDateTime(true),
      isFirst: true,
    ),
    // connector
    Container(
      margin: const EdgeInsets.symmetric(vertical: 0),
      child: Row(children: [
        const SizedBox(width: 28),
        Container(width: 2, height: 28, color: _teal.withOpacity(0.2)),
        const SizedBox(width: 14),
        Expanded(child: Row(children: [
          Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_teal.withOpacity(0.15), _teal.withOpacity(0.08)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _teal.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_downward_rounded, color: _teal, size: 12),
              const SizedBox(width: 4),
              Text('$_days ${_days == 1 ? "day" : "days"}',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
            ])),
          Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
        ])),
      ]),
    ),
    _bookingRow(
      icon: Icons.flight_land_rounded,
      label: 'DROP-OFF',
      loc: _dropoffLoc,
      date: _fmtDate(_dropoffDate),
      time: _fmtTime(_dropoffTime),
      onLoc: () => _pickLocation(false),
      onDateTime: () => _pickDateTime(false),
      isFirst: false,
    ),
  ]);

  Widget _bookingRow({
    required IconData icon, required String label, required String loc,
    required String date, required String time,
    required VoidCallback onLoc, required VoidCallback onDateTime, required bool isFirst,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(children: [
      // location row
      GestureDetector(
        onTap: onLoc,
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: _teal, size: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.inter(fontSize: 9, color: _slate, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            Text(loc, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _dark), overflow: TextOverflow.ellipsis),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Change', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _slate)),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right_rounded, color: _slate, size: 14),
            ])),
        ]),
      ),
      const SizedBox(height: 10),
      Container(height: 1, color: const Color(0xFFF1F5F9)),
      const SizedBox(height: 10),
      // date+time row
      GestureDetector(
        onTap: onDateTime,
        child: Row(children: [
          const SizedBox(width: 42),
          Expanded(child: Row(children: [
            const Icon(Icons.calendar_today_rounded, color: _teal, size: 14),
            const SizedBox(width: 6),
            Text(date, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
            const SizedBox(width: 12),
            Container(width: 1, height: 14, color: const Color(0xFFE2E8F0)),
            const SizedBox(width: 12),
            const Icon(Icons.access_time_rounded, color: _teal, size: 14),
            const SizedBox(width: 6),
            Text(time, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
          ])),
          Container(padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.edit_rounded, color: _teal, size: 13)),
        ]),
      ),
    ]),
  );

  // ─── SPECS GRID ───
  Widget _specsCard(CarModel car) {
    final specs = <_SE>[
      if (car.year != null) _SE(Icons.calendar_today_outlined, 'Year', '${car.year}'),
      _SE(Icons.category_outlined, 'Category', car.category),
      _SE(Icons.people_alt_outlined, 'Seats', '${car.seats}'),
      if (car.fuelType != null) _SE(Icons.local_gas_station_outlined, 'Fuel Type', car.fuelType!),
      if (car.power != null) _SE(Icons.speed_outlined, 'Horsepower', car.power!),
      if (car.color != null) _SE(Icons.palette_outlined, 'Color', car.color!),
      if (car.transmission != null) _SE(Icons.settings_input_component_outlined, 'Transmission', car.transmission!),
      _SE(Icons.commit_outlined, 'Drive Type', car.drive),
      if (car.bodyType != null) _SE(Icons.directions_car_outlined, 'Body Type', car.bodyType!),
      if (car.engineType != null) _SE(Icons.electric_bolt_outlined, 'Engine', car.engineType!),
      if (car.rangeKm != null) _SE(Icons.battery_charging_full_outlined, 'Range', '${car.rangeKm} km'),
    ];
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecHead('Vehicle Specifications', Icons.info_outline_rounded),
      const SizedBox(height: 14),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 2.7, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: specs.length,
        itemBuilder: (_, i) => _SpecTile(e: specs[i]),
      ),
    ]));
  }

  // ─── FEATURES ───
  Widget _featuresCard(CarModel car) {
    final icons = [Icons.smart_toy_outlined, Icons.speaker_outlined, Icons.ac_unit_outlined, Icons.location_on_outlined,
      Icons.shield_outlined, Icons.camera_alt_outlined, Icons.bluetooth_outlined, Icons.wifi_outlined];
    final feats = car.features;
    final rows = <List<int>>[];
    for (int i = 0; i < feats.length; i += 2) {
      rows.add([i, if (i + 1 < feats.length) i + 1]);
    }
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecHead('Premium Features', Icons.star_outline_rounded),
      const SizedBox(height: 14),
      ...rows.map((pair) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: _teal.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.2))),
            child: Row(children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(color: _teal.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(icons[pair[0] % icons.length], color: _teal, size: 15)),
              const SizedBox(width: 8),
              Expanded(child: Text(feats[pair[0]], style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _dark), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]))),
          const SizedBox(width: 9),
          Expanded(child: pair.length > 1 ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: _teal.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.2))),
            child: Row(children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(color: _teal.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(icons[pair[1] % icons.length], color: _teal, size: 15)),
              const SizedBox(width: 8),
              Expanded(child: Text(feats[pair[1]], style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _dark), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ])) : const SizedBox()),
        ])
      )),
    ]));
  }

  // ─── DESCRIPTION ───
  Widget _descCard(CarModel car) {
    final desc = car.description ?? 'No description available.';
    final long = desc.length > 200;
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecHead('About This Vehicle', Icons.article_outlined),
      const SizedBox(height: 12),
      Text(_expanded ? desc : (long ? '${desc.substring(0, 200)}…' : desc),
        style: GoogleFonts.inter(fontSize: 14, color: _slate, height: 1.7)),
      if (long) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? 'Show less ↑' : 'Read more ↓',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _teal))),
      ],
    ]));
  }

  // ─── RENTAL COST ───
  Widget _rentalCostCard(CarModel car) {
    final tiers = [
      [1, 0, car.pricePerDay.toDouble()],
      [4, 6, car.pricePerDay * 0.94],
      [8, 13, car.pricePerDay * 0.87],
      [15, 19, car.pricePerDay * 0.81],
      [28, 25, car.pricePerDay * 0.75],
    ];
    int activeTier = 0;
    for (int i = tiers.length - 1; i >= 0; i--) {
      if (_days >= (tiers[i][0] as int)) { activeTier = i; break; }
    }
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecHead('Rental Cost', Icons.payments_outlined),
      const SizedBox(height: 14),
      ...List.generate(tiers.length, (i) {
        final minDays = tiers[i][0] as int;
        final discount = tiers[i][1] as int;
        final rate = tiers[i][2] as double;
        final isActive = i == activeTier;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? _teal.withOpacity(0.06) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? _teal.withOpacity(0.3) : const Color(0xFFE2E8F0), width: isActive ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(child: Text(
              i == 0 ? 'From 1 day' : 'From $minDays days',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? _dark : _slate))),
            if (discount > 0) Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(20)),
              child: Text('-$discount%', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${rate.toStringAsFixed(0)}/day',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: isActive ? _teal : _dark)),
              if (discount > 0) Text('\$${car.pricePerDay}/day',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCBD5E1), decoration: TextDecoration.lineThrough)),
            ]),
          ]),
        );
      }),
    ]));
  }

  // ─── RENTAL CONDITIONS ───
  Widget _rentalConditionsCard() {
    final conditions = [
      [Icons.people_outline, 'AGE', 'From 21 years old'],
      [Icons.credit_card_outlined, 'LICENSE', 'Category B'],
      [Icons.verified_outlined, 'EXPERIENCE', 'At least 3 years'],
      [Icons.speed_outlined, 'DAILY MILEAGE', 'Up to 200 km'],
    ];
    final bullets = [
      'The renter is responsible for all traffic violations during the rental period.',
      'A refundable security deposit is required at the time of booking.',
      'A second driver may be added free of charge before contract signing; fee applies after.',
      'Free cancellation or modification up to 24 hours before the rental start time.',
    ];
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecHead('Rental Conditions', Icons.rule_outlined),
      const SizedBox(height: 16),
      // 2x2 grid — each cell has room to breathe, no wrapping
      Row(children: [
        _condCell(conditions[0]),
        const SizedBox(width: 10),
        _condCell(conditions[1]),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _condCell(conditions[2]),
        const SizedBox(width: 10),
        _condCell(conditions[3]),
      ]),
      const SizedBox(height: 14),
      Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _teal.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: _teal, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'All vehicles are insured and have no advertising stickers. They are delivered clean, fully equipped and fueled. If you need a car in the evening or early morning — we are ready to deliver it at the agreed time and address.',
            style: GoogleFonts.inter(fontSize: 12, color: _slate, height: 1.5))),
        ])),
      if (_condExpanded) ...[
        const SizedBox(height: 12),
        ...bullets.map((b) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(margin: const EdgeInsets.only(top: 6, right: 8), width: 5, height: 5, decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle)),
            Expanded(child: Text(b, style: GoogleFonts.inter(fontSize: 12, color: _slate, height: 1.5))),
          ]))),
      ],
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => setState(() => _condExpanded = !_condExpanded),
        child: Row(children: [
          Text(_condExpanded ? 'Hide details' : 'Show details',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _teal)),
          const SizedBox(width: 4),
          Icon(_condExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _teal, size: 18),
        ])),
    ]));
  }

  // ── condition cell helper ──
  Widget _condCell(List<Object> c) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0))),
    child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(c[0] as IconData, color: _teal, size: 18)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c[1] as String, style: GoogleFonts.inter(fontSize: 9, color: _slate, fontWeight: FontWeight.w600, letterSpacing: 0.7)),
        const SizedBox(height: 2),
        Text(c[2] as String, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _dark)),
      ])),
    ]),
  ));

  // ─── REVIEWS ───
  Widget _reviewsCard(CarModel car) {
    if (_reviewsLoading) {
      return _Card(child: const Center(child: CircularProgressIndicator(color: _teal)));
    }

    final reviews = _reviewsData;

    int reviewCount = 0;
    double avgRating = 0.0;
    
    // Recalculate based on real data
    if (reviews.isNotEmpty) {
      reviewCount = reviews.length;
      avgRating = reviews.map((r) => (r['rating'] as num).toDouble()).reduce((a, b) => a + b) / reviewCount;
    }

    // Calculate rating distribution
    Map<int, int> counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (var r in reviews) {
      int rating = (r['rating'] as num).toInt().clamp(1, 5);
      counts[rating] = (counts[rating] ?? 0) + 1;
    }

    double getFraction(int stars) => reviewCount == 0 ? 0 : counts[stars]! / reviewCount;

    final displayReviews = reviews.take(4).toList();

    Widget buildReviewItem(Map<String, dynamic> r, int idx, bool isLast) {
      final rating = (r['rating'] as num).toInt();
      final name = r['name'] as String? ?? 'Anonymous';
      final comment = r['comment'] as String? ?? '';
      final date = DateTime.tryParse(r['created_at'] ?? '');
      String dateStr = '';
      if (date != null) {
        final diff = DateTime.now().difference(date);
        if (diff.inDays > 30) {
          dateStr = '${(diff.inDays / 30).floor()} months ago';
        } else if (diff.inDays > 0) {
          dateStr = '${diff.inDays} days ago';
        } else {
          dateStr = 'Today';
        }
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_teal.withOpacity(0.3), _teal.withOpacity(0.1)]),
                borderRadius: BorderRadius.circular(19)),
              child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'A', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: _teal)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _dark)),
              Text(dateStr, style: GoogleFonts.inter(fontSize: 11, color: _slate)),
            ])),
            Row(children: List.generate(5, (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xFFFACC15), size: 14))),
          ]),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment, style: GoogleFonts.inter(fontSize: 13, color: _slate, height: 1.5)),
          ],
          if (!isLast) ...[const SizedBox(height: 16), Container(height: 1, color: const Color(0xFFF1F5F9))],
        ]),
      );
    }

    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SecHead('Customer Reviews', Icons.rate_review_outlined),
      const SizedBox(height: 16),
      // Summary row
      Row(children: [
        Column(children: [
          Text(avgRating.toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 56, fontWeight: FontWeight.w900, color: _dark, height: 1)),
          const SizedBox(height: 6),
          Row(children: List.generate(5, (i) => Icon(
            i < avgRating.floor() ? Icons.star_rounded : (i < avgRating ? Icons.star_half_rounded : Icons.star_outline_rounded),
            color: const Color(0xFFFACC15), size: 16))),
          const SizedBox(height: 4),
          Text('$reviewCount reviews', style: GoogleFonts.inter(fontSize: 11, color: _slate)),
        ]),
        const SizedBox(width: 24),
        Expanded(child: Column(children: [
          _RatingRow('5', getFraction(5)), _RatingRow('4', getFraction(4)), _RatingRow('3', getFraction(3)), _RatingRow('2', getFraction(2)), _RatingRow('1', getFraction(1)),
        ])),
      ]),
      const SizedBox(height: 20),
      Container(height: 1, color: const Color(0xFFE2E8F0)),
      const SizedBox(height: 16),
      
      if (reviews.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text('No reviews yet.', style: GoogleFonts.inter(color: _slate, fontStyle: FontStyle.italic)),
          ),
        )
      else ...[
        // Written reviews (up to 4)
        ...displayReviews.asMap().entries.map((entry) {
          return buildReviewItem(entry.value, entry.key, entry.key == displayReviews.length - 1 && reviews.length <= 4);
        }),
        
        if (reviews.length > 4) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => Container(
                    height: MediaQuery.of(context).size.height * 0.8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('All Reviews (${reviews.length})', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: reviews.length,
                            itemBuilder: (context, index) {
                              return buildReviewItem(reviews[index], index, index == reviews.length - 1);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text('See all ${reviews.length} reviews', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: _teal)),
            ),
          ),
        ],
      ],
    ]));
  }

  // ─── BOTTOM BAR ───
  Widget _bottomBar(CarModel car) => Positioned(
    bottom: 0, left: 0, right: 0,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      decoration: BoxDecoration(color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 24, offset: const Offset(0, -8))]),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Total for $_days ${_days == 1 ? "day" : "days"}', style: GoogleFonts.inter(fontSize: 11, color: _slate)),
          Text('\$${(_discountedRate(car.pricePerDay) * _days).toStringAsFixed(0)}',
            style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w900, color: _dark)),
        ]),
        const SizedBox(width: 16),
        Expanded(child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingSummaryScreen(
            car: car,
            pickupDate: _pickupDate,
            dropoffDate: _dropoffDate,
            pickupTime: _pickupTime,
            dropoffTime: _dropoffTime,
            pickupLoc: _pickupLoc,
            dropoffLoc: _dropoffLoc,
          ))),
          child: Container(height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00C4B4), Color(0xFF00A896)]),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: _teal.withOpacity(0.45), blurRadius: 20, offset: const Offset(0, 8))]),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Book Now', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ])),
        )),
      ]),
    ),
  );
}

// ─── SHARED CARD WRAPPER ───
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))]),
    child: child);
}

// ─── SECTION HEADER ───
class _SecHead extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SecHead(this.title, this.icon);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 34, height: 34,
      decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: _teal, size: 17)),
    const SizedBox(width: 10),
    Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
  ]);
}

// ─── SPEC ENTRY MODEL ───
class _SE { final IconData icon; final String label, value; const _SE(this.icon, this.label, this.value); }

// ─── SPEC TILE ───
class _SpecTile extends StatelessWidget {
  final _SE e;
  const _SpecTile({required this.e});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
    child: Row(children: [
      Container(width: 30, height: 30,
        decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(e.icon, color: _teal, size: 15)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(e.label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
        Text(e.value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _dark), overflow: TextOverflow.ellipsis),
      ])),
    ]));
}

// ─── RATING ROW ───
class _RatingRow extends StatelessWidget {
  final String label;
  final double pct;
  const _RatingRow(this.label, this.pct);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.5),
    child: Row(children: [
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: _slate)),
      const SizedBox(width: 4),
      const Icon(Icons.star_rounded, color: Color(0xFFFACC15), size: 11),
      const SizedBox(width: 6),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct, minHeight: 6,
          backgroundColor: const Color(0xFFE2E8F0), valueColor: const AlwaysStoppedAnimation(_teal)))),
      const SizedBox(width: 6),
      Text('${(pct * 100).toInt()}%', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
    ]));
}

// ─── SIMILAR VEHICLE CARD ───
class _SimilarCard extends StatelessWidget {
  final CarModel car;
  const _SimilarCard({required this.car});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car))),
    child: Container(
      width: 175, margin: const EdgeInsets.only(right: 12, bottom: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Stack(children: [
            Image.network(car.imageUrl, height: 115, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(height: 115, color: const Color(0xFFE2E8F0),
                child: const Center(child: Icon(Icons.directions_car, color: Color(0xFFCBD5E1), size: 40)))),
            Positioned(top: 8, right: 8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text('\$${car.pricePerDay}/d', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(car.brand, style: GoogleFonts.inter(fontSize: 10, color: _slate, fontWeight: FontWeight.w500)),
          Text(car.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: _dark), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFACC15), size: 12),
            const SizedBox(width: 3),
            Text('${car.rating}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _dark)),
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(car.category, style: GoogleFonts.inter(fontSize: 10, color: _teal, fontWeight: FontWeight.w700))),
          ]),
        ])),
      ]),
    ),
  );
}
