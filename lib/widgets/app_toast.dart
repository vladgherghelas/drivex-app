import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppToast {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context,
    String message, {
    bool success = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    _entry?.remove();
    _entry = null;

    final mq     = MediaQuery.of(context);
    final topPad = mq.padding.top;

    _entry = OverlayEntry(builder: (_) => _ToastWidget(
      message: message,
      success: success,
      topPad: topPad,
      onDone: () { _entry?.remove(); _entry = null; },
      duration: duration,
    ));

    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool success;
  final double topPad;
  final VoidCallback onDone;
  final Duration duration;

  const _ToastWidget({
    required this.message,
    required this.success,
    required this.topPad,
    required this.onDone,
    required this.duration,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _slide = Tween<Offset>(
            begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _ctrl.reverse();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isErr = !widget.success;
    final bgColor   = isErr ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);
    final iconColor = isErr ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    final textColor = isErr ? const Color(0xFF991B1B) : const Color(0xFF166534);
    final borderClr = isErr ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC);

    return Positioned(
      top: widget.topPad + 14,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: GestureDetector(
              onTap: () { _ctrl.reverse().then((_) => widget.onDone()); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderClr, width: 1.3),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Icon circle
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withOpacity(0.12),
                      border: Border.all(color: iconColor.withOpacity(0.35), width: 1.5),
                    ),
                    child: Icon(
                      isErr ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      color: iconColor,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Message
                  Expanded(
                    child: Text(
                      widget.message,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Close
                  GestureDetector(
                    onTap: () { _ctrl.reverse().then((_) => widget.onDone()); },
                    child: Icon(Icons.close_rounded, color: iconColor.withOpacity(0.6), size: 17),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
