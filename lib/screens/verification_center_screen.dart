import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../models/kyc_models.dart';
import '../widgets/app_toast.dart';
import 'document_scanner_screen.dart';

const _teal = Color(0xFF00C4B4);
const _dark = Color(0xFF0F172A);
const _slate = Color(0xFF64748B);
const _bg = Color(0xFFF8FAFC);

class VerificationCenterScreen extends StatefulWidget {
  const VerificationCenterScreen({super.key});
  @override
  State<VerificationCenterScreen> createState() => _VCState();
}

class _VCState extends State<VerificationCenterScreen> {
  bool _loading = true;
  String _kycStatus = 'unverified';
  String? _rejection;
  int _step = 0;
  bool _submitting = false;
  bool _idTypeSelected = false;
  RealtimeChannel? _realtimeChannel;


  // Captured images
  Uint8List? _licFront, _licBack, _idFront, _idBack, _selfie;
  String _idType = 'passport';

  // OCR
  final _nameC = TextEditingController();
  final _dobC = TextEditingController();
  final _expC = TextEditingController();
  final _numC = TextEditingController();

  final _steps = const [
    _StepInfo('Driver\'s License — Front', 'Position your license on a flat, dark surface. Ensure all 4 corners and text are clearly visible.', Icons.credit_card, true),
    _StepInfo('Driver\'s License — Back', 'Flip your license over. Capture the barcode and magnetic strip clearly.', Icons.flip, true),
    _StepInfo('Identity Document — Front', 'Place your passport photo page or national ID front side on a flat surface.', Icons.badge_outlined, true),
    _StepInfo('Identity Document — Back', 'Flip your ID card over and capture all details clearly.', Icons.flip_camera_android, true),
    _StepInfo('Selfie Verification', 'Use the front camera. Look straight ahead with a neutral expression. Remove sunglasses or hats.', Icons.face_retouching_natural, true),
  ];

  @override
  void initState() { super.initState(); _loadStatus(); _subscribeRealtime(); }
  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _nameC.dispose(); _dobC.dispose(); _expC.dispose(); _numC.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _realtimeChannel = supabase
      .channel('kyc_notify_$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyc_notifications',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) {
          final status = payload.newRecord['status'] as String? ?? '';
          final message = payload.newRecord['message'] as String? ?? '';
          if (!mounted) return;
          setState(() => _kycStatus = status);
          AppToast.show(context, message,
            success: status == 'approved',
            duration: const Duration(seconds: 5));
        },
      )
      .subscribe();
  }

  Future<void> _loadStatus() async {
    final u = supabase.auth.currentUser;
    if (u == null) { setState(() => _loading = false); return; }
    try {
      final p = await supabase.from('profiles').select('kyc_status').eq('id', u.id).maybeSingle();
      final d = await supabase.from('kyc_documents').select('rejection_reason').eq('user_id', u.id).order('submitted_at', ascending: false).limit(1).maybeSingle();
      if (mounted) setState(() { _kycStatus = p?['kyc_status'] ?? 'unverified'; _rejection = d?['rejection_reason']; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Uint8List? _bytesForStep(int s) => [_licFront, _licBack, _idFront, _idBack, _selfie][s];
  void _setBytesForStep(int s, Uint8List? b) => setState(() { [() => _licFront = b, () => _licBack = b, () => _idFront = b, () => _idBack = b, () => _selfie = b][s](); });

  Future<void> _capture() async {
    final isSelfie = _step == 4;
    final title = _steps[_step].title;
    final result = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(builder: (_) => DocumentScannerScreen(
        title: title,
        isOval: isSelfie,
      )),
    );
    if (result != null && mounted) {
      _setBytesForStep(_step, result.imageBytes);
      // Auto-fill OCR fields if extracted
      if (result.ocr != null && result.ocr!.isDocument) {
        final o = result.ocr!;
        if (o.name != null && _nameC.text.isEmpty) _nameC.text = o.name!;
        if (o.dateOfBirth != null && _dobC.text.isEmpty) _dobC.text = o.dateOfBirth!;
        if (o.expiryDate != null && _expC.text.isEmpty) _expC.text = o.expiryDate!;
        if (o.documentNumber != null && _numC.text.isEmpty) _numC.text = o.documentNumber!;
      }
    }
  }

  void _next() {
    if (_step < 4) { setState(() => _step++); }
    else { setState(() => _step = 5); } // go to review
  }

  void _back() {
    if (_step == 5) { setState(() => _step = 4); }
    else if (_step > 0) { setState(() => _step--); }
    else { Navigator.pop(context); }
  }

  bool get _canSubmit => _licFront != null && _licBack != null && _idFront != null && _idBack != null && _selfie != null;

  Future<String?> _upload(Uint8List bytes, String name) async {
    final uid = supabase.auth.currentUser!.id;
    try {
      await supabase.storage.from('kyc-documents').uploadBinary('$uid/$name', bytes, fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
      return supabase.storage.from('kyc-documents').getPublicUrl('$uid/$name');
    } catch (_) { return null; }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      final lf = await _upload(_licFront!, 'lic_f_$ts.jpg');
      final lb = _licBack != null ? await _upload(_licBack!, 'lic_b_$ts.jpg') : null;
      final idf = await _upload(_idFront!, 'id_f_$ts.jpg');
      final idb = _idBack != null ? await _upload(_idBack!, 'id_b_$ts.jpg') : null;
      final sf = await _upload(_selfie!, 'selfie_$ts.jpg');
      if (lf == null || idf == null || sf == null) throw Exception('Upload failed');
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('kyc_documents').insert({
        'user_id': uid, 'document_type': 'drivers_license',
        'front_url': lf, 'back_url': lb, 'selfie_url': sf, 'status': 'pending',
        'submitted_at': DateTime.now().toIso8601String(),
        'notes': 'id_type:$_idType|id_front:$idf${idb != null ? "|id_back:$idb" : ""}',
      });
      await supabase.from('profiles').update({'kyc_status': 'pending'}).eq('id', uid);
      if (mounted) { setState(() { _kycStatus = 'pending'; _submitting = false; }); AppToast.show(context, '✓ Submitted for review', success: true); }
    } catch (e) {
      if (mounted) { AppToast.show(context, 'Error: $e', success: false); setState(() => _submitting = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _teal)));
    if (_kycStatus == 'approved') return _statusScreen(Icons.verified_rounded, const Color(0xFF34D399), 'Identity Verified', 'You can now book any vehicle.');
    if (_kycStatus == 'pending') return _statusScreen(Icons.hourglass_top_rounded, Colors.orange, 'Under Review', 'Usually verified within 24 hours.');
    if (_step == 5) return _reviewScreen();
    return _guideScreen();
  }

  // ── Status screens ──────────────────────────────────────────
  Widget _statusScreen(IconData icon, Color c, String title, String sub) => Scaffold(
    backgroundColor: _bg,
    body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.15)),
        child: Icon(icon, color: c, size: 52)),
      const SizedBox(height: 24),
      Text(title, style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w900, color: _dark)),
      const SizedBox(height: 8),
      Text(sub, style: GoogleFonts.inter(fontSize: 14, color: _slate), textAlign: TextAlign.center),
      if (_rejection != null) ...[const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
          child: Text('Reason: $_rejection', style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade700)))],
      const SizedBox(height: 32),
      SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: () => Navigator.pop(context),
        style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
        child: Text('Back', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)))),
    ])))));

  // ── ID Type Picker ──────────────────────────────────────────
  List<Widget> _buildIdTypePicker() {
    final types = [
      ('passport', Icons.book_outlined, 'Passport', 'International travel document\nwith photo page'),
      ('national_id', Icons.credit_card_outlined, 'National ID', 'Government-issued identity card\n(front + back required)'),
    ];
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Select Your ID Type', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _dark)),
          const SizedBox(height: 4),
          Text('Choose the document you will be scanning', style: GoogleFonts.inter(fontSize: 12, color: _slate)),
          const SizedBox(height: 12),
          ...types.map((t) {
            final selected = _idType == t.$1 && _idTypeSelected;
            return GestureDetector(
              onTap: () => setState(() { _idType = t.$1; _idTypeSelected = true; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected ? _teal.withOpacity(0.08) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? _teal : const Color(0xFFE2E8F0), width: selected ? 2 : 1)),
                child: Row(children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: selected ? _teal.withOpacity(0.15) : const Color(0xFFE2E8F0)),
                    child: Icon(t.$2, color: selected ? _teal : _slate, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.$3, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? _teal : _dark)),
                    Text(t.$4, style: GoogleFonts.inter(fontSize: 11, color: _slate, height: 1.4)),
                  ])),
                  if (selected) const Icon(Icons.check_circle_rounded, color: _teal, size: 22),
                ]),
              ),
            );
          }),
        ]),
      ),
    ];
  }

  // ── Guide + Capture screen ──────────────────────────────────
  Widget _guideScreen() {
    final info = _steps[_step];
    final bytes = _bytesForStep(_step);
    final isOptional = !info.required_;

    return Scaffold(backgroundColor: _bg, body: SafeArea(child: Column(children: [
      // Header
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [
        GestureDetector(onTap: _back, child: Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)]),
          child: const Icon(Icons.arrow_back, color: _dark, size: 20))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Step ${_step + 1} of 5', style: GoogleFonts.inter(fontSize: 11, color: _slate, fontWeight: FontWeight.w600)),
          Text(info.title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: _dark)),
        ])),
      ])),

      // Progress
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: (_step + 1) / 5, minHeight: 4, backgroundColor: const Color(0xFFE2E8F0), valueColor: const AlwaysStoppedAnimation(_teal)))),

      // Content
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
        const SizedBox(height: 8),

        // Document frame / preview
        if (bytes != null)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]),
            child: ClipRRect(borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                Image.memory(bytes, fit: BoxFit.contain, width: double.infinity),
                Positioned(top: 12, right: 12, child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E),
                    boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withOpacity(0.4), blurRadius: 8)]),
                  child: const Icon(Icons.check, color: Colors.white, size: 18))),
              ])),
          )
        else
          Container(
            width: double.infinity, height: 200,
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 6))]),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _teal.withOpacity(0.15)),
                child: Icon(info.icon, color: _teal.withOpacity(0.7), size: 32)),
              const SizedBox(height: 12),
              Text(_step == 4 ? 'Take a selfie' : 'Scan your document',
                style: GoogleFonts.inter(color: Colors.white.withOpacity(0.6), fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Tap the button below to start', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.3), fontSize: 11)),
            ])),
          ),
        const SizedBox(height: 20),

        // Instructions
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lightbulb_outline, color: Color(0xFFD97706), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(info.hint, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E), height: 1.5))),
          ])),
        const SizedBox(height: 20),

        // ID Type selector (step 2 only, before a photo is taken)
        if (_step == 2) ..._buildIdTypePicker(),

        // Capture button
        SizedBox(width: double.infinity, height: 54, child: ElevatedButton.icon(
          onPressed: (_step == 2 && !_idTypeSelected) ? null : _capture,
          icon: Icon(bytes != null ? Icons.refresh : Icons.camera_alt_outlined, size: 20),
          label: Text(bytes != null ? 'Retake Photo' : (_step == 2 && !_idTypeSelected ? 'Select ID type first' : 'Open Camera'),
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: (_step == 2 && !_idTypeSelected) ? Colors.grey.shade300 : (bytes != null ? const Color(0xFF475569) : _teal),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade500,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))),
        )),
        const SizedBox(height: 12),

        // Next
        SizedBox(width: double.infinity, height: 54, child: ElevatedButton(
          onPressed: bytes != null ? _next : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: bytes != null ? _teal : Colors.grey.shade300,
            foregroundColor: Colors.white, disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))),
          child: Text(bytes != null ? 'Continue →' : 'Capture to continue',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
              color: bytes != null ? Colors.white : Colors.grey.shade500)),
        )),
        const SizedBox(height: 32),
      ]))),
    ])));
  }

  // ── Review & Submit screen ──────────────────────────────────
  Widget _reviewScreen() {
    final items = [
      _ReviewItem('License Front', _licFront, true),
      _ReviewItem('License Back', _licBack, true),
      _ReviewItem('ID Front', _idFront, true),
      _ReviewItem('ID Back', _idBack, true),
      _ReviewItem('Selfie', _selfie, true),
    ];

    return Scaffold(backgroundColor: _bg, body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [
        GestureDetector(onTap: _back, child: Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)]),
          child: const Icon(Icons.arrow_back, color: _dark, size: 20))),
        const SizedBox(width: 14),
        Text('Review & Submit', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: _dark)),
      ])),

      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Thumbnails grid
        ...items.map((it) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(width: 52, height: 52, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF1F5F9)),
              child: it.bytes != null
                ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(it.bytes!, fit: BoxFit.cover, width: 52, height: 52))
                : Icon(it.required_ ? Icons.warning_amber_rounded : Icons.remove_circle_outline, color: it.required_ ? Colors.red : _slate, size: 22)),
            title: Text(it.label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _dark)),
            subtitle: Text(it.bytes != null ? '✓ Captured' : (it.required_ ? '✗ Missing' : 'Skipped'),
              style: GoogleFonts.inter(fontSize: 11, color: it.bytes != null ? const Color(0xFF34D399) : (it.required_ ? Colors.red : _slate))),
            trailing: it.bytes != null
              ? GestureDetector(onTap: () => setState(() => _step = items.indexOf(it)),
                  child: Text('Retake', style: GoogleFonts.inter(fontSize: 12, color: _teal, fontWeight: FontWeight.w700)))
              : it.required_ ? GestureDetector(onTap: () => setState(() => _step = items.indexOf(it)),
                  child: Text('Add', style: GoogleFonts.inter(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w700)))
              : null,
          )))),

        const SizedBox(height: 20),

        // Submit
        SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
          onPressed: _canSubmit && !_submitting ? _submit : null,
          style: ElevatedButton.styleFrom(backgroundColor: _canSubmit ? _teal : Colors.grey.shade300, foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
          child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text('Submit for Review', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
        )),
        if (!_canSubmit) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('Complete all required items above', style: GoogleFonts.inter(fontSize: 12, color: Colors.red), textAlign: TextAlign.center)),
        const SizedBox(height: 32),
      ]))),
    ])));
  }

  Widget _field(String l, TextEditingController c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
    controller: c, style: GoogleFonts.inter(fontSize: 13, color: _dark),
    decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true, fillColor: _bg, labelText: l, labelStyle: GoogleFonts.inter(fontSize: 11, color: _slate),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.black.withOpacity(0.08))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.black.withOpacity(0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _teal, width: 1.5)))));
}

class _StepInfo {
  final String title, hint;
  final IconData icon;
  final bool required_;
  const _StepInfo(this.title, this.hint, this.icon, this.required_);
}

class _ReviewItem {
  final String label;
  final Uint8List? bytes;
  final bool required_;
  const _ReviewItem(this.label, this.bytes, this.required_);
}

// ── Document frame overlay ──────────────────────────────────
class _DocFrameOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(size.width * 0.08, size.height * 0.12, size.width * 0.92, size.height * 0.88);
    // Dim outside
    canvas.drawPath(Path.combine(PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)))),
      Paint()..color = Colors.black.withOpacity(0.45));
    // Corner brackets
    final p = Paint()..color = _teal..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const len = 24.0;
    // Top-left
    canvas.drawLine(Offset(r.left, r.top + len), Offset(r.left, r.top), p);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + len, r.top), p);
    // Top-right
    canvas.drawLine(Offset(r.right - len, r.top), Offset(r.right, r.top), p);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + len), p);
    // Bottom-left
    canvas.drawLine(Offset(r.left, r.bottom - len), Offset(r.left, r.bottom), p);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + len, r.bottom), p);
    // Bottom-right
    canvas.drawLine(Offset(r.right - len, r.bottom), Offset(r.right, r.bottom), p);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - len), p);
  }
  @override
  bool shouldRepaint(_) => false;
}

// ── Selfie oval overlay ─────────────────────────────────────
class _OvalOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: size.width * 0.55, height: size.height * 0.82);
    canvas.drawPath(Path.combine(PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addOval(oval)), Paint()..color = Colors.black.withOpacity(0.5));
    canvas.drawOval(oval, Paint()..color = _teal..strokeWidth = 2.5..style = PaintingStyle.stroke);
  }
  @override
  bool shouldRepaint(_) => false;
}
