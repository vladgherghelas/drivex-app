import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../supabase_config.dart';
import '../models/car_model.dart';
import '../services/favorites_service.dart';
import 'car_detail_screen.dart';

class SavedScreen extends StatefulWidget {
  final int refreshTrigger;
  const SavedScreen({super.key, this.refreshTrigger = 0});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<CarModel> _savedCars = [];
  bool _isLoading = true;
  static const _blue = Color(0xFF00C4B4);
  static const _card = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    FavoritesService.instance.addListener(_onFavChange);
    _fetchSaved();
  }

  @override
  void didUpdateWidget(SavedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) _fetchSaved();
  }

  void _onFavChange() {
    if (!mounted) return;
    // Remove unsaved cars instantly without a network call
    setState(() => _savedCars =
        _savedCars.where((c) => FavoritesService.instance.isSaved(c.id)).toList());
  }

  @override
  void dispose() {
    FavoritesService.instance.removeListener(_onFavChange);
    super.dispose();
  }

  Future<void> _fetchSaved() async {
    final user = supabase.auth.currentUser;
    if (user == null) { setState(() { _isLoading = false; _savedCars = []; }); return; }
    setState(() => _isLoading = true);
    try {
      final data = await supabase.from('saved_cars').select('car_id, cars(*)').eq('user_id', user.id);
      final cars = (data as List).map((r) => CarModel.fromMap(r['cars'] as Map<String, dynamic>)).toList();
      if (mounted) setState(() { _savedCars = cars; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchSaved, color: _blue, backgroundColor: _card,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Saved', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              if (_savedCars.isNotEmpty)
                Text('${_savedCars.length} vehicles', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8))),
            ]),
          )),

          if (_isLoading)
            SliverList(delegate: SliverChildBuilderDelegate(
              (_, __) => Shimmer.fromColors(
                baseColor: const Color(0xFFE2E8F0), highlightColor: const Color(0xFFF8FAFC),
                child: Container(margin: const EdgeInsets.fromLTRB(16, 0, 16, 12), height: 112,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
              childCount: 4)),

          if (!_isLoading && _savedCars.isEmpty)
            SliverFillRemaining(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 80, height: 80,
                decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.favorite_outline, color: _blue, size: 40)),
              const SizedBox(height: 20),
              Text('No Saved Vehicles', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(supabase.auth.currentUser == null ? 'Sign in to save your favorite cars.' : 'Tap the ❤ icon on any car to save it here.',
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B), height: 1.5), textAlign: TextAlign.center),
            ]))),

          if (!_isLoading && _savedCars.isNotEmpty)
            SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) => _SavedCarTile(car: _savedCars[i]), childCount: _savedCars.length)),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ]),
      ),
    );
  }
}

// ── Identical layout to _CarTile from home_screen ────────────────────────────
class _SavedCarTile extends StatefulWidget {
  final CarModel car;
  const _SavedCarTile({required this.car});
  @override
  State<_SavedCarTile> createState() => _SavedCarTileState();
}

class _SavedCarTileState extends State<_SavedCarTile> {
  static const _blue   = Color(0xFF00C4B4);
  static const _card   = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE2E8F0);

  @override
  void initState() { super.initState(); FavoritesService.instance.addListener(_rebuild); }
  void _rebuild() { if (mounted) setState(() {}); }
  @override
  void dispose() { FavoritesService.instance.removeListener(_rebuild); super.dispose(); }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: const Color(0xFF64748B)),
      const SizedBox(width: 3),
      Text(label, style: GoogleFonts.inter(fontSize: 9, color: const Color(0xFF475569), fontWeight: FontWeight.w600)),
    ]));

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final allImages = [car.imageUrl, ...car.galleryUrls];
    final isSaved = FavoritesService.instance.isSaved(car.id);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car))),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Tappable image → gallery ──
          GestureDetector(
            onTap: () => _openGallery(context, car),
            child: ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Stack(children: [
                CachedNetworkImage(imageUrl: car.imageUrl, width: 100, height: 86, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(width: 100, height: 86, color: const Color(0xFFE2E8F0)),
                  errorWidget: (_, __, ___) => Container(width: 100, height: 86, color: const Color(0xFFE2E8F0),
                    child: const Icon(Icons.directions_car, color: Color(0xFFCBD5E1), size: 32))),
                Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.35)])))),
                if (allImages.length > 1)
                  Positioned(bottom: 5, left: 5, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_library_outlined, color: Colors.white, size: 9),
                      const SizedBox(width: 2),
                      Text('${allImages.length}', style: GoogleFonts.inter(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                    ]))),
              ]))),
          const SizedBox(width: 12),
          // ── Info column ──
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(car.displayName,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis, maxLines: 1)),
              GestureDetector(
                onTap: () => FavoritesService.instance.toggle(car.id),
                child: Icon(isSaved ? Icons.favorite : Icons.favorite_border,
                  color: isSaved ? const Color(0xFFFF4D6D) : const Color(0xFFCBD5E1), size: 20)),
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
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00C4B4), Color(0xFF009BA8)]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: const Color(0xFF00C4B4).withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Text('Book', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)))),
            ]),
          ])),
        ]),
      ),
    );
  }
}

void _openGallery(BuildContext context, CarModel car) {
  final images = [car.imageUrl, ...car.galleryUrls];
  final ctrl = PageController();
  int current = 0;
  showDialog(
    context: context, barrierColor: Colors.black.withOpacity(0.96),
    builder: (_) => StatefulBuilder(builder: (ctx, setSt) => Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        PageView.builder(controller: ctrl, itemCount: images.length,
          onPageChanged: (i) => setSt(() => current = i),
          itemBuilder: (_, i) => GestureDetector(onTap: () => Navigator.pop(ctx),
            child: Center(child: CachedNetworkImage(imageUrl: images[i], fit: BoxFit.contain,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Color(0xFF00C4B4), strokeWidth: 2)),
              errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 60))))),
        Positioned(top: 52, right: 16, child: GestureDetector(onTap: () => Navigator.pop(ctx),
          child: Container(width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
            child: const Icon(Icons.close, color: Colors.white, size: 20)))),
        Positioned(top: 58, left: 0, right: 0, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Text('${current + 1} / ${images.length}',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))))),
        Positioned(bottom: 80, left: 0, right: 0, child: Center(child: Text(car.displayName,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)))),
        Positioned(bottom: 48, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 20 : 7, height: 7,
            decoration: BoxDecoration(color: i == current ? const Color(0xFF00C4B4) : Colors.white38, borderRadius: BorderRadius.circular(4)))))),
      ]),
    )));
}
