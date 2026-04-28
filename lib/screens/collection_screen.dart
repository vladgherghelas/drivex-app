import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/car_model.dart';
import '../supabase_config.dart';
import 'car_detail_screen.dart';
import '../services/favorites_service.dart';

class CollectionScreen extends StatefulWidget {
  final String? initialCategory;
  const CollectionScreen({super.key, this.initialCategory});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  static const _bg = Color(0xFFF1F5F9);
  static const _card = Color(0xFFFFFFFF);
  static const _blue = Color(0xFF00C4B4);
  static const _border = Color(0xFFE2E8F0);
  static const _cats = ['All', 'Electric', 'SUV', 'Luxury', 'Sports'];

  List<CarModel> _all = [];
  List<CarModel> _filtered = [];
  bool _loading = true;
  String _cat = 'All';
  String _query = '';
  double _maxPrice = 2000;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory ?? 'All';
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final data = await supabase.from('cars').select().order('rating', ascending: false);
      final cars = (data as List).map((e) => CarModel.fromMap(e)).toList();
      if (mounted) setState(() { _all = cars; _loading = false; _applyFilters(); });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filtered = _all.where((c) {
        final matchCat = _cat == 'All' || c.category == _cat;
        final matchQ = _query.isEmpty ||
            c.displayName.toLowerCase().contains(_query.toLowerCase()) ||
            c.category.toLowerCase().contains(_query.toLowerCase());
        final matchPrice = c.pricePerDay <= _maxPrice;
        return matchCat && matchQ && matchPrice;
      }).toList();
    });
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setModal) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Filters', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              GestureDetector(
                onTap: () { setState(() { _cat = 'All'; _maxPrice = 2000; }); _applyFilters(); Navigator.pop(ctx); },
                child: Text('Reset', style: GoogleFonts.inter(fontSize: 13, color: _blue, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 20),
            Text('Category', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: _cats.map((c) {
              final sel = c == _cat;
              return GestureDetector(
                onTap: () => setModal(() => _cat = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? _blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? _blue : _border),
                  ),
                  child: Text(c, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF475569))),
                ),
              );
            }).toList()),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Max Price', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
              Text('\$${_maxPrice.toInt()}/day', style: GoogleFonts.inter(fontSize: 13, color: _blue, fontWeight: FontWeight.w700)),
            ]),
            Slider(
              value: _maxPrice, min: 200, max: 2000, divisions: 18,
              activeColor: _blue, inactiveColor: _border,
              onChanged: (v) => setModal(() => _maxPrice = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () { _applyFilters(); Navigator.pop(ctx); },
                style: ElevatedButton.styleFrom(backgroundColor: _blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                child: Text('Apply Filters', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                child: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0F172A), size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Text('All Vehicles', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
            const Spacer(),
            Text('${_filtered.length} cars', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8))),
          ]),
        ),
        // Search + filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(13), border: Border.all(color: _border)),
                child: Row(children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: const Color(0xFF94A3B8), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.inter(color: const Color(0xFF0F172A), fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search cars…',
                      hintStyle: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 14),
                      border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) { _query = v; _applyFilters(); },
                  )),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _showFilters,
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.tune, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
        // Category chips
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _cats[i];
              final sel = c == _cat;
              return GestureDetector(
                onTap: () { setState(() => _cat = c); _applyFilters(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? _blue : _card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: sel ? _blue : _border),
                  ),
                  child: Text(c, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF475569))),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Car grid
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _blue, strokeWidth: 2))
              : _filtered.isEmpty
                  ? Center(child: Text('No cars found', style: GoogleFonts.inter(color: const Color(0xFF94A3B8))))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.75),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _CarGridCard(car: _filtered[i]),
                    ),
        ),
      ])),
    );
  }
}

class _CarGridCard extends StatefulWidget {
  final CarModel car;
  const _CarGridCard({required this.car});
  @override
  State<_CarGridCard> createState() => _CarGridCardState();
}

class _CarGridCardState extends State<_CarGridCard> {
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

  @override
  Widget build(BuildContext context) {
    final car = widget.car;
    final isSaved = FavoritesService.instance.isSaved(car.id);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CarDetailScreen(car: car))),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: car.imageUrl, height: 110, width: double.infinity, fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 110, color: Colors.white),
                errorWidget: (_, __, ___) => Container(height: 110, color: const Color(0xFFF1F5F9),
                  child: const Icon(Icons.directions_car, color: Colors.black26, size: 36)),
              ),
            ),
            // Heart button
            Positioned(
              top: 7, right: 7,
              child: GestureDetector(
                onTap: () => FavoritesService.instance.toggle(car.id),
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Icon(
                    isSaved ? Icons.favorite : Icons.favorite_border,
                    color: isSaved ? const Color(0xFFFF4D6D) : Colors.white,
                    size: 15,
                  ),
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _blue.withOpacity(0.08), borderRadius: BorderRadius.circular(5)),
                child: Text(car.category, style: GoogleFonts.inter(fontSize: 9, color: _blue, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 5),
              Text(car.displayName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 12),
                const SizedBox(width: 3),
                Text(car.rating.toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              Text(car.priceLabel, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _blue)),
            ]),
          ),
        ]),
      ),
    );
  }
}
