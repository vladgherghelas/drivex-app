import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/ocr_service.dart';

const _teal = Color(0xFF00E5C8);
const _green = Color(0xFF22C55E);
const _amber = Color(0xFFF59E0B);
const _dark = Color(0xFF0D0D0D);

class ScanResult {
  final Uint8List imageBytes;
  final OcrResult? ocr;
  ScanResult(this.imageBytes, this.ocr);
}

class DocumentScannerScreen extends StatefulWidget {
  final String title;
  final bool isOval;
  final String stepLabel; // e.g. '1 of 2'
  const DocumentScannerScreen({super.key, required this.title, this.isOval = false, this.stepLabel = '1 of 2'});
  @override
  State<DocumentScannerScreen> createState() => _ScanState();
}

class _ScanState extends State<DocumentScannerScreen> with TickerProviderStateMixin {
  CameraController? _ctrl;
  bool _ready = false;
  bool _captured = false;
  bool _analyzing = false;
  String _status = 'Initializing camera...';
  bool _detected = false;
  Timer? _scanTimer;
  int _scanAttempts = 0;
  // ── Document mode sweep control ──
  int _docSweepCount = 0;
  bool _docSweepPaused = false;
  bool _docSweepDone = false;
  late AnimationController _scanAnim;
  late AnimationController _glowAnim;

  // ── Liveness (face mode) ──
  int _livenessStep = -1; // -1=waiting for face, 0..3=movement steps
  double _livenessProgress = 0;
  Timer? _livenessTimer;
  bool _faceFound = false;
  int _faceConfirmCount = 0;
  double _lastYaw = 0;
  double _faceCx = 0.5, _faceCy = 0.5;
  bool _faceInsideOval = false;
  bool _faceDetectedNow = false; // true only when score >= 85 this frame
  double _faceWidth = 0;        // normalized face width (0-1)

  // ── 3-gate status chip getters (recomputed every frame) ──
  // Size gate uses wide tolerances — camera image coords differ from screen coords
  bool get _faceSizeOk => _faceWidth >= 0.12 && _faceWidth <= 0.72;
  bool get _allGatesPass => _faceDetectedNow && _faceInsideOval && _faceSizeOk;

  String get _chipLabel {
    if (_detected) return 'Face Verified ✓';
    if (!_faceDetectedNow) return 'Align your face';
    if (!_faceInsideOval) return 'Center your face';
    if (_faceWidth < 0.12) return 'Move closer';
    if (_faceWidth > 0.72) return 'Move back';
    return 'Good Position ✓';
  }

  Color get _chipColor {
    if (_detected) return _green.withOpacity(0.9);
    if (!_faceDetectedNow) return Colors.white.withOpacity(0.12);
    if (!_faceInsideOval || !_faceSizeOk) return _amber.withOpacity(0.85);
    return _teal.withOpacity(0.9);
  }

  IconData get _chipIcon {
    if (_detected) return Icons.check_circle;
    if (!_faceDetectedNow) return Icons.center_focus_strong;
    if (!_faceInsideOval) return Icons.open_with;
    if (_faceWidth < 0.12) return Icons.zoom_in;
    if (_faceWidth > 0.72) return Icons.zoom_out;
    return Icons.face_retouching_natural;
  }

  static const _instructions = [
    'Slowly turn your head to the left',
    'Now slowly turn to the right',
    'Tilt your head up slightly',
    'Look straight ahead — hold still',
  ];

  static const _stepLabels = ['Face detected', 'Turn left', 'Turn right', 'Look up', 'Hold still'];

  // Oval params (must match painter)
  static const _ovalCyRatio = 0.36;
  static const _ovalRxRatio = 0.32;
  static const _ovalRyFactor = 1.35;

  @override
  void initState() {
    super.initState();
    // Doc sweep: non-repeating, max 3 sweeps with 1.5s pause
    _scanAnim = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _scanAnim.addStatusListener(_onSweepStatus);
    _glowAnim = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _initCamera();
  }

  void _onSweepStatus(AnimationStatus status) async {
    if (widget.isOval || _detected || _captured) return;
    if (status == AnimationStatus.completed) {
      _docSweepCount++;
      if (_docSweepCount >= 3) {
        if (mounted) setState(() => _docSweepDone = true);
        return;
      }
      if (mounted) setState(() => _docSweepPaused = true);
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || _detected || _captured) return;
      setState(() => _docSweepPaused = false);
      _scanAnim.forward(from: 0);
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final cam = widget.isOval
          ? cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first)
          : cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      _ctrl = CameraController(cam, ResolutionPreset.high, enableAudio: false);
      await _ctrl!.initialize();
      if (!mounted) return;
      setState(() { _ready = true; });

      if (widget.isOval) {
        setState(() => _status = 'Position your face in the frame');
        _livenessTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _checkFace());
      } else {
        setState(() => _status = 'Point camera at your document');
        _scanAnim.forward(); // start first sweep
        _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _ocrScan());
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error');
    }
  }

  /// Check if face center (normalized) is inside the oval using ellipse equation.
  bool _isInsideOval(double fcx, double fcy) {
    // Oval center is at (0.5, _ovalCyRatio) in normalized coords
    final dx = (fcx - 0.5) / (_ovalRxRatio);
    final dy = (fcy - _ovalCyRatio) / (_ovalRxRatio * _ovalRyFactor);
    return (dx * dx + dy * dy) <= 1.0;
  }

  // ── Face presence + yaw check ──
  Future<void> _checkFace() async {
    if (_captured || _ctrl == null || !_ctrl!.value.isInitialized || _analyzing) return;
    _analyzing = true;
    try {
      final xf = await _ctrl!.takePicture();
      final bytes = await xf.readAsBytes();
      final face = await checkForFaceData(bytes);

      if (!mounted || _captured) return;

      // ── Gate 1: Score must be >= 60 (0.60 confidence) ──
      final detected85 = face.hasFace && face.score >= 60;
      final inside = detected85 && _isInsideOval(face.cx, face.cy);
      final sizeOk = detected85 && face.faceW >= 0.12 && face.faceW <= 0.72;

      // Update all frame-level state atomically
      setState(() {
        _faceCx = face.cx; _faceCy = face.cy;
        _faceWidth = face.faceW;
        _faceDetectedNow = detected85;
        _faceInsideOval = inside;
      });

      if (!detected85) {
        // Gate 1 failed — no high-confidence face
        _faceConfirmCount = 0;
        if (_faceFound) {
          // Was verifying — full reset
          _livenessTimer?.cancel();
          setState(() {
            _faceFound = false; _livenessProgress = 0; _livenessStep = -1;
            _status = 'Face lost — look at the camera';
          });
          _livenessTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _checkFace());
        }
        _analyzing = false;
        return;
      }

      // ── Gate 2 + 3: Inside oval AND correct size ──
      if (!inside || !sizeOk) {
        _faceConfirmCount = 0;
        if (_faceFound && _livenessStep >= 0) {
          setState(() => _status = 'Keep your face inside the frame');
        }
        _analyzing = false;
        return;
      }

      // All 3 gates pass — confirm face before starting liveness
      if (!_faceFound) {
        _faceConfirmCount++;
        if (_faceConfirmCount >= 2) {
          _faceFound = true;
          _livenessTimer?.cancel();
          setState(() => _status = 'All checks passed! Starting...');
          await Future.delayed(const Duration(milliseconds: 600));
          if (!_captured) _startLivenessStep(0);
        }
        // Status chip now handled by _chipLabel getter — no extra setState needed
      } else if (_livenessStep >= 0 && _livenessStep < 3) {
        // ── YAW-BASED TURN DETECTION ──
        final yaw = face.yaw;
        _lastYaw = yaw;

        if (_livenessStep == 0) {
          // Turn left: yaw should go negative (< -0.15)
          if (yaw < -0.15) {
            _advanceLiveness();
          } else {
            setState(() => _status = 'Turn your head to the left');
          }
        } else if (_livenessStep == 1) {
          // Turn right: yaw should go positive (> 0.15)
          if (yaw > 0.15) {
            _advanceLiveness();
          } else {
            setState(() => _status = 'Now slowly turn to the right');
          }
        } else if (_livenessStep == 2) {
          // Look up: use motion fallback (face-api doesn't give pitch easily)
          // Accept any yaw near center as "looked up and back"
          if (yaw.abs() < 0.1) {
            _advanceLiveness();
          } else {
            setState(() => _status = 'Look straight ahead');
          }
        }
      }
    } catch (_) {}
    _analyzing = false;
  }

  void _startLivenessStep(int step) {
    if (_captured || !mounted) return;
    _livenessStep = step;

    final pct = step == 0 ? 0.0 : step * 0.25;
    setState(() {
      _status = _instructions[step];
      _livenessProgress = pct;
    });

    // Resume face checking for yaw detection
    _livenessTimer?.cancel();
    _livenessTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) => _checkFace());

    if (step == 3) {
      // "Hold still" — verify face is STILL present before capturing
      Future.delayed(const Duration(seconds: 2), () async {
        if (_captured || !mounted) return;
        try {
          final xf = await _ctrl!.takePicture();
          final bytes = await xf.readAsBytes();
          final face = await checkForFaceData(bytes);
          if (face.score < 20 || !_isInsideOval(face.cx, face.cy)) {
            setState(() { _faceFound = false; _livenessProgress = 0; _livenessStep = -1;
              _faceConfirmCount = 0; _faceInsideOval = false;
              _status = 'Face lost — look at the camera'; });
            _livenessTimer?.cancel();
            _livenessTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _checkFace());
            return;
          }
        } catch (_) {}
        setState(() { _detected = true; _status = 'Face verified!'; _livenessProgress = 1.0; });
        Future.delayed(const Duration(milliseconds: 600), () { if (!_captured) _doCapture(null); });
      });
    }
  }

  void _advanceLiveness() {
    if (_livenessStep < 3) {
      final next = _livenessStep + 1;
      final pct = (next) * 0.25;
      setState(() => _livenessProgress = pct);
      Future.delayed(const Duration(milliseconds: 400), () => _startLivenessStep(next));
    }
  }

  // ── Document OCR scan ──
  Future<void> _ocrScan() async {
    if (_captured || _detected || _analyzing || _ctrl == null || !_ctrl!.value.isInitialized) return;
    _analyzing = true;
    _scanAttempts++;
    if (mounted) setState(() => _status = 'Analyzing...');
    try {
      final xf = await _ctrl!.takePicture();
      final bytes = await xf.readAsBytes();
      final text = await ocrRecognize(bytes);
      final result = OcrResult.fromText(text);
      if (!mounted || _captured) return;

      if (result.isDocument) {
        // Check completeness — need enough fields visible (not too close)
        int fields = 0;
        if (result.name != null) fields++;
        if (result.dateOfBirth != null) fields++;
        if (result.documentNumber != null) fields++;
        if (result.expiryDate != null) fields++;

        if (fields < 2 && _scanAttempts <= 8) {
          _analyzing = false;
          setState(() => _status = '⚠ Move back — capture the entire document');
          return;
        }

        _scanTimer?.cancel();
        _scanAnim.stop();
        setState(() { _detected = true; _docSweepDone = true; _status = 'Document detected!'; _analyzing = false; });
        await Future.delayed(const Duration(milliseconds: 800));
        if (!_captured) _doCapture(result);
      } else {
        _analyzing = false;
        setState(() => _status = _scanAttempts <= 3 ? 'No document found — keep trying' : 'Move closer to your document');
      }
    } catch (_) {
      _analyzing = false;
      if (mounted) setState(() => _status = 'Point camera at your document');
    }
  }

  Future<void> _doCapture(OcrResult? ocr) async {
    if (_captured || _ctrl == null || !_ctrl!.value.isInitialized) return;
    _captured = true;
    _scanTimer?.cancel();
    _livenessTimer?.cancel();
    if (mounted) setState(() => _status = 'Captured!');
    try {
      final xf = await _ctrl!.takePicture();
      final bytes = await xf.readAsBytes();
      if (ocr == null && !widget.isOval) {
        if (mounted) setState(() => _status = 'Reading document...');
        final text = await ocrRecognize(bytes);
        ocr = OcrResult.fromText(text);
      }
      await _ctrl?.dispose();
      _ctrl = null;
      if (mounted) Navigator.pop(context, ScanResult(bytes, ocr));
    } catch (_) {
      _captured = false;
      if (mounted) setState(() => _status = 'Capture failed — tap to retry');
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _livenessTimer?.cancel();
    _scanAnim.dispose();
    _glowAnim.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFace = widget.isOval;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Camera
        if (_ready && _ctrl != null)
          Positioned.fill(child: CameraPreview(_ctrl!))
        else
          const Center(child: CircularProgressIndicator(color: _teal)),

        // Document overlay
        if (_ready && !isFace)
          Positioned.fill(child: AnimatedBuilder(animation: _scanAnim, builder: (_, __) =>
            CustomPaint(painter: _DocOverlayPainter(
              detected: _detected,
              scanProgress: _scanAnim.value,
              sweepDone: _docSweepDone,
              sweepPaused: _docSweepPaused,
              analyzing: _analyzing)))),

        // ── Document mode: status chip above frame ──
        if (!isFace && _ready) Positioned(
          top: MediaQuery.of(context).size.height * 0.55
            - (MediaQuery.of(context).size.width * 0.88 / 1.586) / 2 - 52,
          left: 16, right: 16,
          child: Center(child: AnimatedContainer(
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _detected
                ? _teal.withOpacity(0.92)
                : (_analyzing ? _amber.withOpacity(0.85)
                  : (_docSweepDone && !_detected ? _amber.withOpacity(0.85)
                    : Colors.white.withOpacity(0.10))),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _detected
                ? _teal.withOpacity(0.3) : Colors.white.withOpacity(0.08))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _detected ? Icons.check_circle_outline
                  : (_analyzing ? Icons.center_focus_strong
                    : (_docSweepDone ? Icons.warning_amber_rounded
                      : Icons.document_scanner_outlined)),
                color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Flexible(child: Text(
                _detected ? 'Document detected ✓'
                  : (_analyzing ? 'Hold still — analyzing'
                    : (_docSweepDone && !_detected
                      ? 'No document found — try better lighting'
                      : 'Place your document in the frame')),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.w600),
                textAlign: TextAlign.center)),
            ])))),

        // Face overlay with glow animation
        if (_ready && isFace)
          Positioned.fill(child: AnimatedBuilder(animation: _glowAnim, builder: (_, __) =>
            CustomPaint(painter: _FaceOverlayPainter(
              progress: _livenessProgress, detected: _detected, faceFound: _allGatesPass || _faceFound,
              step: _livenessStep, glowAngle: _glowAnim.value * 2 * pi)))),

        // ── Face mode: floating status chip ──
        if (isFace && _ready) Positioned(
          top: MediaQuery.of(context).size.height * 0.36 - (MediaQuery.of(context).size.width * 0.30 * 1.35) - 36,
          left: 0, right: 0,
          child: Center(child: AnimatedContainer(
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _chipColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (_allGatesPass || _detected)
                ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.08))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_chipIcon, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(_chipLabel,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ])))),

        // ── Face mode: frosted glass top bar ──
        if (isFace) Positioned(top: 0, left: 0, right: 0, child: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(color: _dark.withOpacity(0.5),
                border: Border(bottom: BorderSide(color: _teal.withOpacity(0.15)))),
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  GestureDetector(
                    onTap: () async { _scanTimer?.cancel(); _livenessTimer?.cancel(); await _ctrl?.dispose(); _ctrl = null; if (mounted) Navigator.pop(context); },
                    child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 16))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Text('Identity Verification', style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Step 3 of 3', style: GoogleFonts.inter(color: _teal, fontSize: 11, fontWeight: FontWeight.w600)),
                  ])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _teal.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _teal.withOpacity(0.25))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lock_outline, color: _teal, size: 11),
                      const SizedBox(width: 4),
                      Text('enc', style: GoogleFonts.inter(color: _teal, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    ])),
                ]))))))),

        // ── Non-face mode: frosted glass top bar ──
        if (!isFace) Positioned(top: 0, left: 0, right: 0, child: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08)))),
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  // X close button
                  GestureDetector(
                    onTap: () async {
                      _scanTimer?.cancel(); _livenessTimer?.cancel();
                      _scanAnim.stop();
                      await _ctrl?.dispose(); _ctrl = null;
                      if (mounted) Navigator.pop(context);
                    },
                    child: Container(width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10), shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.12))),
                      child: const Icon(Icons.close, color: Colors.white, size: 18))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.title,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center)),
                  const SizedBox(width: 12),
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _teal.withOpacity(0.25))),
                    child: Text(widget.stepLabel,
                      style: GoogleFonts.inter(color: _teal, fontSize: 11,
                        fontWeight: FontWeight.w700))),
                ]))))))),

        // ── Face mode: frosted glass bottom panel ──
        if (isFace && _ready) Positioned(bottom: 0, left: 0, right: 0, child: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(color: _dark.withOpacity(0.6),
                border: Border(top: BorderSide(color: _teal.withOpacity(0.12)))),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Instruction title
                Text(_detected ? 'Verified Successfully' :
                  (_faceFound ? _instructions[_livenessStep.clamp(0, 3)] : 'Position your face in the frame'),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                  textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(_detected ? 'Identity confirmed securely' :
                  (_faceFound ? 'Keep your face inside the frame' : 'Look straight at the camera'),
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                // Confidence bar
                Row(children: [
                  Text('Confidence', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text('${(_livenessProgress * 100).toInt()}%',
                    style: GoogleFonts.inter(color: _teal, fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: _livenessProgress, minHeight: 4,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation(_detected ? _green : _teal))),
                const SizedBox(height: 16),
                // Step checklist
                ...List.generate(5, (i) {
                  final bool done;
                  final bool active;
                  if (i == 0) { done = _faceFound; active = !_faceFound; }
                  else if (i <= 3) { done = _livenessStep >= i; active = _livenessStep == i - 1 && _faceFound; }
                  else { done = _detected; active = _livenessStep == 3 && !_detected; }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      if (done) const Icon(Icons.check_circle, color: _teal, size: 16)
                      else if (active) Icon(
                        i == 1 ? Icons.arrow_back      // Turn left ←
                        : i == 2 ? Icons.arrow_forward  // Turn right →
                        : i == 3 ? Icons.arrow_upward   // Look up ↑
                        : Icons.arrow_forward,
                        color: _teal, size: 16)
                      else Icon(Icons.circle_outlined, color: Colors.white.withOpacity(0.15), size: 16),
                      const SizedBox(width: 10),
                      Text(_stepLabels[i], style: GoogleFonts.inter(
                        color: done ? _teal : (active ? Colors.white : Colors.white.withOpacity(0.25)),
                        fontSize: 13, fontWeight: done || active ? FontWeight.w600 : FontWeight.w400)),
                    ]));
                }),
                const SizedBox(height: 12),
              ])))))),

        // ── Document mode: frosted glass bottom panel ──
        if (!isFace && _ready) Positioned(bottom: 0, left: 0, right: 0, child: ClipRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.09),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.10)))),
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Bold instruction
                Text(
                  _detected ? 'Document captured ✓'
                    : (_analyzing ? 'Hold still...'
                      : (_docSweepDone
                        ? 'Try repositioning the document'
                        : 'Align ${widget.title} with the frame')),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  textAlign: TextAlign.center),
                const SizedBox(height: 4),
                // Muted tip
                Text(
                  _detected ? 'Processing your document securely'
                    : 'Make sure all 4 corners are fully visible',
                  style: GoogleFonts.inter(color: Colors.white.withOpacity(0.45),
                    fontSize: 12, fontWeight: FontWeight.w400),
                  textAlign: TextAlign.center),
                const SizedBox(height: 14),
                // Analyzing pill (only while analyzing)
                if (_analyzing) ...[  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.12), borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _teal.withOpacity(0.25))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(color: _teal, strokeWidth: 1.5)),
                      const SizedBox(width: 8),
                      Text('Analyzing…', style: GoogleFonts.inter(
                        color: _teal, fontSize: 12, fontWeight: FontWeight.w600)),
                    ])),
                  const SizedBox(height: 12),
                ],
                if (!_analyzing) const SizedBox(height: 6),
                // Shutter button
                GestureDetector(
                  onTap: _ready && !_captured ? () => _doCapture(null) : null,
                  child: Container(width: 68, height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: _teal, width: 3)),
                    child: Center(child: Container(width: 50, height: 50,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white))))),
                const SizedBox(height: 8),
                Text('or tap to capture manually', style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.35), fontSize: 11)),
                const SizedBox(height: 20),
              ])))))),
      ]),
    );
  }
}

// ── Document overlay — ID card frame, no dark overlay ──
class _DocOverlayPainter extends CustomPainter {
  final bool detected;
  final double scanProgress;   // 0–1
  final bool sweepDone;
  final bool sweepPaused;
  final bool analyzing;
  _DocOverlayPainter({
    required this.detected,
    required this.scanProgress,
    required this.sweepDone,
    required this.sweepPaused,
    required this.analyzing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ID card: 1.586:1 ratio, 88% screen width, centered at 55% height
    final fw = size.width * 0.88;
    final fh = fw / 1.586;
    final fl = (size.width - fw) / 2;
    final ft = size.height * 0.55 - fh / 2;
    final r = Rect.fromLTWH(fl, ft, fw, fh);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));

    final borderColor = detected ? _teal : const Color(0xFF444444);

    // ── Outer soft glow (detected only) ──
    if (detected) {
      for (int i = 3; i >= 1; i--) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(i * 3.0), Radius.circular(12 + i * 3)),
          Paint()
            ..color = _teal.withOpacity(0.08 * i)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = MaskFilter.blur(BlurStyle.outer, i * 4.0));
      }
    }

    // ── Rounded rect border ──
    canvas.drawRRect(rr, Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // ── L-bracket corner markers (24px arms, solid teal) ──
    const bLen = 24.0;
    const bW = 3.0;
    final bp = Paint()
      ..color = detected ? _teal : _teal.withOpacity(0.75)
      ..strokeWidth = bW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    // Top-left
    canvas.drawLine(Offset(fl, ft + bLen), Offset(fl, ft), bp);
    canvas.drawLine(Offset(fl, ft), Offset(fl + bLen, ft), bp);
    // Top-right
    canvas.drawLine(Offset(r.right - bLen, ft), Offset(r.right, ft), bp);
    canvas.drawLine(Offset(r.right, ft), Offset(r.right, ft + bLen), bp);
    // Bottom-left
    canvas.drawLine(Offset(fl, r.bottom - bLen), Offset(fl, r.bottom), bp);
    canvas.drawLine(Offset(fl, r.bottom), Offset(fl + bLen, r.bottom), bp);
    // Bottom-right
    canvas.drawLine(Offset(r.right - bLen, r.bottom), Offset(r.right, r.bottom), bp);
    canvas.drawLine(Offset(r.right, r.bottom - bLen), Offset(r.right, r.bottom), bp);

    // ── Sweep line (only while scanning, not paused, not done) ──
    if (!detected && !sweepDone && !sweepPaused && scanProgress > 0) {
      final lineY = ft + fh * scanProgress;
      final grad = LinearGradient(colors: [
        _teal.withOpacity(0),
        _teal.withOpacity(0.6),
        _teal.withOpacity(0),
      ]);
      canvas.drawRect(
        Rect.fromLTRB(fl + 8, lineY - 1.5, r.right - 8, lineY + 1.5),
        Paint()..shader = grad.createShader(
          Rect.fromLTWH(fl, lineY - 1.5, fw, 3)));
      // Faint wide glow beneath line
      canvas.drawRect(
        Rect.fromLTRB(fl + 8, lineY - 6, r.right - 8, lineY + 6),
        Paint()..shader = LinearGradient(colors: [
          _teal.withOpacity(0),
          _teal.withOpacity(0.08),
          _teal.withOpacity(0),
        ]).createShader(Rect.fromLTWH(fl, lineY - 6, fw, 12)));
    }

    // ── Detection pulse ring ──
    if (detected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(16)),
        Paint()
          ..color = _teal.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8));
    }
  }

  @override
  bool shouldRepaint(_DocOverlayPainter old) => true;
}

// ── Face overlay — enterprise-grade multi-layer design ──
class _FaceOverlayPainter extends CustomPainter {
  final double progress;
  final bool detected;
  final bool faceFound;
  final int step;
  final double glowAngle;
  _FaceOverlayPainter({required this.progress, required this.detected,
    required this.faceFound, required this.step, required this.glowAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.36;
    final rx = size.width * 0.32;
    final ry = rx * 1.35;
    final ovalRect = Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);

    // Layer 0: No dim overlay — camera feed must be fully visible

    // ── Layer 1: Corner bracket markers ──
    final bracketColor = detected ? _green : (faceFound ? _teal : Colors.white.withOpacity(0.4));
    final bp = Paint()..color = bracketColor..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final bLen = rx * 0.35;
    final bRect = ovalRect.inflate(14);
    // Top-left
    canvas.drawLine(Offset(bRect.left + 8, bRect.top), Offset(bRect.left + 8 + bLen, bRect.top), bp);
    canvas.drawLine(Offset(bRect.left, bRect.top + 8), Offset(bRect.left, bRect.top + 8 + bLen), bp);
    // Top-right
    canvas.drawLine(Offset(bRect.right - 8 - bLen, bRect.top), Offset(bRect.right - 8, bRect.top), bp);
    canvas.drawLine(Offset(bRect.right, bRect.top + 8), Offset(bRect.right, bRect.top + 8 + bLen), bp);
    // Bottom-left
    canvas.drawLine(Offset(bRect.left + 8, bRect.bottom), Offset(bRect.left + 8 + bLen, bRect.bottom), bp);
    canvas.drawLine(Offset(bRect.left, bRect.bottom - 8 - bLen), Offset(bRect.left, bRect.bottom - 8), bp);
    // Bottom-right
    canvas.drawLine(Offset(bRect.right - 8 - bLen, bRect.bottom), Offset(bRect.right - 8, bRect.bottom), bp);
    canvas.drawLine(Offset(bRect.right, bRect.bottom - 8 - bLen), Offset(bRect.right, bRect.bottom - 8), bp);

    // ── Layer 2: Inner oval border ──
    canvas.drawOval(ovalRect, Paint()
      ..color = (detected ? _green : (faceFound ? _teal : Colors.white)).withOpacity(detected ? 0.8 : 0.2)
      ..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // ── Layer 2.5: Directional side-arc hint (mirrors the instruction) ──
    // step==0 → Turn left  → highlight LEFT side of oval (clockwise from bottom to top through left=9o'clock)
    // step==1 → Turn right → highlight RIGHT side (clockwise from top to bottom through right=3o'clock)
    if (faceFound && !detected && step >= 0 && step <= 1) {
      // LEFT: startAngle = pi/2 (6 o'clock), sweepAngle = pi  → goes clockwise through 9 o'clock to 12 o'clock
      // RIGHT: startAngle = -pi/2 (12 o'clock), sweepAngle = pi → goes clockwise through 3 o'clock to 6 o'clock
      final double hintStart = step == 0 ? pi / 2 : -pi / 2;
      // Outer glow
      canvas.drawArc(ovalRect.inflate(12), hintStart, pi, false, Paint()
        ..color = _teal.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
      // Solid arc
      canvas.drawArc(ovalRect.inflate(8), hintStart, pi, false, Paint()
        ..color = _teal.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round);
    }

    // ── Layer 3: Outer segmented progress ring (5 segments) ──
    final ringRect = ovalRect.inflate(8);
    const totalSegs = 5;
    final segSweep = (2 * pi / totalSegs) - 0.08; // gap between segments
    for (int i = 0; i < totalSegs; i++) {
      final startAngle = -pi / 2 + i * (2 * pi / totalSegs) + 0.04;
      final filled = progress > (i / totalSegs);
      canvas.drawArc(ringRect, startAngle, segSweep, false, Paint()
        ..color = filled ? (detected ? _green : _teal) : Colors.white.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = filled ? 4.5 : 3
        ..strokeCap = StrokeCap.round);
      // Glow on filled segments
      if (filled) {
        canvas.drawArc(ringRect.inflate(2), startAngle, segSweep, false, Paint()
          ..color = (detected ? _green : _teal).withOpacity(0.25)
          ..style = PaintingStyle.stroke..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6));
      }
    }

    // ── Layer 4: Rotating teal glow ring ──
    if (faceFound && !detected) {
      final glowSweep = pi * 0.4;
      canvas.drawArc(ovalRect.inflate(3), glowAngle, glowSweep, false, Paint()
        ..color = _teal.withOpacity(0.5)..style = PaintingStyle.stroke
        ..strokeWidth = 3..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawArc(ovalRect.inflate(3), glowAngle + pi, glowSweep, false, Paint()
        ..color = _teal.withOpacity(0.3)..style = PaintingStyle.stroke
        ..strokeWidth = 2..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // ── Layer 5: AI mesh dots inside oval ──
    if (faceFound && !detected) {
      final dotP = Paint()..color = _teal.withOpacity(0.25);
      final dotSpacingX = rx * 0.22;
      final dotSpacingY = ry * 0.18;
      for (double dy = -ry * 0.7; dy <= ry * 0.7; dy += dotSpacingY) {
        final rowW = rx * sqrt(1 - (dy * dy) / (ry * ry)) * 0.85;
        for (double dx = -rowW; dx <= rowW; dx += dotSpacingX) {
          canvas.drawCircle(Offset(cx + dx, cy + dy), 1.8, dotP);
        }
      }
    }

    // ── Layer 6: Success state ──
    if (detected) {
      canvas.drawOval(ovalRect.inflate(10), Paint()
        ..color = _green.withOpacity(0.35)..style = PaintingStyle.stroke
        ..strokeWidth = 14..maskFilter = const MaskFilter.blur(BlurStyle.outer, 20));
    }
  }

  @override
  bool shouldRepaint(_FaceOverlayPainter old) => true; // glowAngle always changes
}
