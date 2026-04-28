import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../supabase_config.dart';
import 'verification_center_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _teal = Color(0xFF00C4B4);
  static const _dark = Color(0xFF0F172A);
  static const _slate = Color(0xFF64748B);
  static const _bg = Color(0xFFF8FAFC);

  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final data = await supabase
          .from('kyc_notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      // Mark all as read
      await supabase.from('kyc_notifications').update({'read': true}).eq('user_id', uid).eq('read', false);
      if (mounted) setState(() { _notifs = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return const Color(0xFF22C55E);
      case 'rejected': return const Color(0xFFEF4444);
      case 'under_review': return const Color(0xFF6366F1);
      default: return const Color(0xFFF59E0B);
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'approved': return Icons.verified_rounded;
      case 'rejected': return Icons.cancel_rounded;
      case 'under_review': return Icons.manage_search_rounded;
      default: return Icons.hourglass_top_rounded;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'approved': return 'Approved';
      case 'rejected': return 'Rejected';
      case 'under_review': return 'Under Review';
      default: return 'Pending';
    }
  }

  String _fmtTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back, color: _dark, size: 20)),
        ),
        title: Text('Notifications', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
        actions: [
          if (_notifs.isNotEmpty)
            TextButton(
              onPressed: _load,
              child: Text('Refresh', style: GoogleFonts.inter(color: _teal, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _notifs.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _teal,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifs.length,
                    itemBuilder: (_, i) => _NotifCard(
                      notif: _notifs[i],
                      statusColor: _statusColor(_notifs[i]['status'] ?? ''),
                      statusIcon: _statusIcon(_notifs[i]['status'] ?? ''),
                      statusLabel: _statusLabel(_notifs[i]['status'] ?? ''),
                      timeAgo: _fmtTime(_notifs[i]['created_at'] ?? ''),
                      onTap: () {
                        if ((_notifs[i]['status'] ?? '') != 'approved') {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationCenterScreen()));
                        }
                      },
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: _teal.withOpacity(0.1)),
      child: const Icon(Icons.notifications_none_rounded, color: _teal, size: 40)),
    const SizedBox(height: 16),
    Text('No notifications yet', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: _dark)),
    const SizedBox(height: 6),
    Text('Your KYC status updates will appear here', style: GoogleFonts.inter(fontSize: 13, color: _slate), textAlign: TextAlign.center),
  ]));
}

class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final Color statusColor;
  final IconData statusIcon;
  final String statusLabel;
  final String timeAgo;
  final VoidCallback onTap;

  const _NotifCard({
    required this.notif, required this.statusColor, required this.statusIcon,
    required this.statusLabel, required this.timeAgo, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = notif['read'] == false;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: unread ? statusColor.withOpacity(0.3) : const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor.withOpacity(0.12)),
            child: Icon(statusIcon, color: statusColor, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor))),
              const Spacer(),
              Text(timeAgo, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
              if (unread) ...[const SizedBox(width: 6), Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor))],
            ]),
            const SizedBox(height: 8),
            Text('KYC Verification Update', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
            const SizedBox(height: 4),
            Text(notif['message'] ?? '', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), height: 1.5)),
            if ((notif['status'] ?? '') != 'approved') ...[
              const SizedBox(height: 10),
              Row(children: [
                Text('Tap to open verification center', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF00C4B4), fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Color(0xFF00C4B4), size: 14),
              ]),
            ],
          ])),
        ]),
      ),
    );
  }
}
