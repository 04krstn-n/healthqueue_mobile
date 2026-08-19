import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';

class QueueMonitoringScreen extends StatefulWidget {
  const QueueMonitoringScreen({super.key});
  @override
  State<QueueMonitoringScreen> createState() => _QueueMonitoringScreenState();
}

class _QueueMonitoringScreenState extends State<QueueMonitoringScreen>
    with WidgetsBindingObserver {
  Timer?                   _timer;
  Map<String, dynamic>?   _status;
  bool                     _loading = true;
  bool                     _refreshing = false;
  String                   _error = '';
  // Track previous position to detect "you're next"
  int?                     _prevPosition;
  bool                     _showNextWarning = false;
  // Called notification shown only once per call event
  bool                     _calledBannerShown = false;
  static const _pollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetch();
    _timer = Timer.periodic(_pollInterval, (_) => _fetch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume polling when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _timer?.cancel();
      _fetch();
      _timer = Timer.periodic(_pollInterval, (_) => _fetch());
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  Future<void> _fetch({bool manual = false}) async {
    if (manual) setState(() => _refreshing = true);
    try {
      final res = await ApiService.getMyQueueStatus();
      if (!mounted) return;
      setState(() {
        _status     = res;
        _loading    = false;
        _refreshing = false;
        _error      = '';
      });
      _checkPositionChanges(res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error      = e.toString().replaceAll('Exception: ', '');
        _loading    = false;
        _refreshing = false;
      });
    }
  }

  // Track previous status for change detection
  String _prevStatus = '';

  void _checkPositionChanges(Map<String, dynamic> res) {
    if (res['inQueue'] != true) {
      // Queue ended — check if status changed (cancelled / completed)
      if (_prevStatus.isNotEmpty &&
          !['', 'waiting', 'serving'].contains(_prevStatus)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showStatusModal(_prevStatus));
        _prevStatus = '';
      }
      return;
    }

    final entry     = res['entry'] as Map<String, dynamic>?;
    final pos       = res['position'] as int? ?? 1;
    final status    = entry?['status'] as String? ?? '';
    final qNum      = entry?['queueNumber']?.toString() ?? '';
    final prevNoShow = res['prevPatientNoShow'] == true;  // server flag

    // ── Position approaching (3rd in line) ─────────────────────────────
    if (_prevPosition != null && _prevPosition! > 3 && pos <= 3 && pos > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          _showApproachingModal(pos, qNum));
    }

    // ── You're next (became #1) ─────────────────────────────────────────
    if (_prevPosition != null && _prevPosition! > 1 && pos == 1) {
      setState(() => _showNextWarning = true);
      _autoHideNextWarning();
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          _showYoureNextModal(qNum, prevNoShow: prevNoShow));
    }

    // ── Being called / serving ──────────────────────────────────────────
    if (status == 'serving' && !_calledBannerShown) {
      _calledBannerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showCalledModal(qNum));
    }
    if (status != 'serving') _calledBannerShown = false;

    // ── Status changed: cancelled / completed ───────────────────────────
    if (_prevStatus.isNotEmpty && _prevStatus != status &&
        ['cancelled', 'completed', 'no_show'].contains(status)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showStatusModal(status));
    }

    _prevPosition = pos;
    _prevStatus   = status;
  }

  void _showApproachingModal(int pos, String qNum) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.access_time, color: Color(0xFFD97706), size: 24),
          SizedBox(width: 8),
          Text('Getting Closer!',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You are #$pos in line${qNum.isNotEmpty ? " (Queue #$qNum)" : ""}.',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Please make your way back to the clinic soon so you do not miss your turn.',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
          ),
        ]),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showYoureNextModal(String qNum, {bool prevNoShow = false}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFFFFBEB),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 26),
          SizedBox(width: 8),
          Text("You're Next!",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17,
                  color: Color(0xFFD97706))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (prevNoShow) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200)),
              child: const Row(children: [
                Icon(Icons.person_off_outlined, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'The patient before you was marked as no-show — you are now first in line.',
                  style: TextStyle(fontSize: 12, color: Colors.red,
                      fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          ],
          Text(
            'You are now #1 in line${qNum.isNotEmpty ? " (Queue #$qNum)" : ""}. '
            'Please proceed to the service counter immediately.',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ]),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            child: const Text("I'm on my way!",
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showCalledModal(String qNum) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF0FDF4),
        title: const Row(children: [
          Icon(Icons.campaign_outlined, color: Color(0xFF16A34A), size: 28),
          SizedBox(width: 8),
          Text('You Are Being Called!',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16,
                  color: Color(0xFF16A34A))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Queue #$qNum — Please proceed to the service counter now.',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Your slot may be forfeited if you do not arrive within the grace period.',
              style: TextStyle(fontSize: 12, color: Color(0xFF166534), height: 1.4),
            ),
          ),
        ]),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            child: const Text('Proceeding Now!',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showStatusModal(String status) {
    if (!mounted) return;
    final isCancel    = status == 'cancelled';
    final isComplete  = status == 'completed';
    final icon  = isCancel   ? Icons.cancel_outlined
                : isComplete ? Icons.check_circle_outline
                             : Icons.info_outline;
    final color = isCancel   ? Colors.red
                : isComplete ? const Color(0xFF16A34A)
                             : Colors.orange;
    final title = isCancel   ? 'Queue Cancelled'
                : isComplete ? 'Service Completed'
                             : 'Queue Updated';
    final msg   = isCancel
        ? 'Your queue entry has been cancelled. You can join again from the dashboard.'
        : isComplete
        ? 'You have been served. Thank you for using HealthQueue+!'
        : 'Your queue status has been updated to: $status.';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        content: Text(msg, style: const TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _autoHideNextWarning() {
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showNextWarning = false);
    });
  }



  Future<void> _cancelQueue(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Queue?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('You will lose your current queue position.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No, Stay')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Leave'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.cancelQueue(id);
      if (mounted) {
        context.read<AppState>().cancelQueue(id);
        setState(() { _loading = true; _prevPosition = null; _calledBannerShown = false; });
        await _fetch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  bool get _inQueue =>
      _status != null && _status!.isNotEmpty && _status!['inQueue'] == true;

  @override
  Widget build(BuildContext context) {
    final entry    = _inQueue ? (_status!['entry'] as Map<String, dynamic>?) : null;
    final position = _inQueue ? (_status!['position'] as int? ?? 1) : 0;
    final ahead    = _inQueue ? (_status!['peopleAhead'] as int? ?? 0) : 0;
    final wait     = _inQueue ? (_status!['estimatedWaitTime'] as int? ?? 0) : 0;
    final qStatus  = entry?['status'] as String? ?? '';
    final called   = qStatus == 'serving';
    final graceRem = _status?['graceRemaining'] as int?;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Queue Status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          if (_refreshing)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _fetch(manual: true),
              tooltip: 'Refresh now',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(), SizedBox(height: 12),
              Text('Loading queue status…', style: TextStyle(color: Colors.black38)),
            ]))
          : _error.isNotEmpty
          ? _buildErrorState()
          : !_inQueue
          ? _buildNoQueueState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [

                // ── "You're next" warning banner ────────────────────────
                if (_showNextWarning)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Expanded(child: Text(
                        "You're next! Please be ready to approach the counter.",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      )),
                    ]),
                  ),

                // ── Called / serving banner ─────────────────────────────
                if (called)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.notifications_active, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text('You are being called!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        graceRem != null
                            ? 'Please proceed to the counter within $graceRem minute${graceRem == 1 ? "" : "s"}.'
                            : 'Please proceed to the counter now!',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ]),
                  ),

                // ── Main queue card ─────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black.withValues(alpha: .06), offset: const Offset(0, 4))],
                  ),
                  child: Column(children: [
                    Text(entry?['queueNumber'] ?? '—',
                        style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: AppColors.primary, height: 1)),
                    const SizedBox(height: 4),
                    const Text('Your Queue Number', style: TextStyle(fontSize: 12, color: Colors.black38)),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _statCol('Clinic',    entry?['clinic']?['name'] ?? entry?['clinicName'] ?? '—'),
                      _statCol('Service',   entry?['serviceName'] ?? '—'),
                    ]),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _numCol(position.toString(), 'Your Position'),
                      _numCol(ahead.toString(), 'People Ahead'),
                      _numCol('~$wait min', 'Est. Wait'),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Queue progression bar ───────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Queue Progress', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      _statusChip(qStatus),
                    ]),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _progressValue(qStatus, position, ahead),
                        backgroundColor: Colors.grey.shade100,
                        color: called ? const Color(0xFF16A34A) : AppColors.primary,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Start', style: TextStyle(fontSize: 10, color: Colors.black38)),
                      Text(called ? 'Being served now' : (position == 1 ? "You're next!" : '$ahead ahead of you'),
                          style: TextStyle(fontSize: 10, color: called ? const Color(0xFF16A34A) : Colors.black45,
                              fontWeight: FontWeight.w600)),
                      const Text('Done', style: TextStyle(fontSize: 10, color: Colors.black38)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Status updates timeline ─────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Status Updates', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 12),
                    _timelineItem('Joined queue', _formatTime(entry?['joinedAt']), true, const Color(0xFF16A34A)),
                    _timelineItem('Waiting your turn', qStatus == 'waiting' ? 'Now' : '—',
                        qStatus != 'waiting' || ahead < 3, qStatus == 'waiting' ? AppColors.primary : Colors.grey.shade300),
                    _timelineItem('Being served', qStatus == 'serving' ? 'Now' : '—',
                        qStatus == 'serving', qStatus == 'serving' ? const Color(0xFF16A34A) : Colors.grey.shade300),
                    _timelineItem('Completed', '—', false, Colors.grey.shade300, isLast: true),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Auto-refresh indicator ──────────────────────────────
                Center(child: Text('Auto-refreshing every 10 seconds',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
                const SizedBox(height: 16),

                // ── Leave queue ─────────────────────────────────────────
                if (!called)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _cancelQueue(entry?['_id'] ?? ''),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Leave Queue', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                const SizedBox(height: 32),
              ]),
            ),
    );
  }

  double _progressValue(String status, int pos, int ahead) {
    if (status == 'serving') return 0.9;
    if (status == 'done' || status == 'completed') return 1.0;
    if (pos == 1) return 0.75;
    if (ahead <= 2) return 0.6;
    if (ahead <= 5) return 0.4;
    return 0.15;
  }

  Widget _buildErrorState() {
    final isOffline = _error.toLowerCase().contains('connect') ||
        _error.toLowerCase().contains('network') || _error.toLowerCase().contains('socket');
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(isOffline ? Icons.wifi_off_rounded : Icons.error_outline,
            size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(isOffline ? 'No Internet Connection' : 'Something went wrong',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(isOffline ? 'Check your Wi-Fi or mobile data and try again.' : _error,
            style: const TextStyle(fontSize: 12, color: Colors.black45), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _fetch(manual: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]),
    ));
  }

  Widget _buildNoQueueState() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
          decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
          child: const Icon(Icons.queue_outlined, size: 38, color: AppColors.primary)),
        const SizedBox(height: 20),
        const Text("You're not in any queue", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Join a queue to see your status here',
            style: TextStyle(fontSize: 13, color: Colors.black45), textAlign: TextAlign.center),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.joinQueue),
          icon: const Icon(Icons.add),
          label: const Text('Join a Queue', style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              minimumSize: const Size(200, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]),
    ));
  }

  Widget _statCol(String label, String val) => Expanded(child: Column(children: [
    Text(val, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.black38)),
  ]));

  Widget _numCol(String val, String label) => Column(children: [
    Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.black38)),
  ]);

  Widget _statusChip(String s) {
    final map = {
      'waiting': [Colors.orange.shade50, Colors.orange.shade700],
      'serving': [const Color(0xFFF0FDF4), const Color(0xFF16A34A)],
      'done':    [const Color(0xFFF0FDF4), const Color(0xFF16A34A)],
      'completed':[const Color(0xFFF0FDF4), const Color(0xFF16A34A)],
      'skipped': [Colors.grey.shade100, Colors.grey.shade600],
    };
    final c = map[s] ?? [Colors.grey.shade100, Colors.grey.shade600];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(99)),
      child: Text(s.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c[1])),
    );
  }

  Widget _timelineItem(String label, String time, bool active, Color color, {bool isLast = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        if (!isLast) Container(width: 2, height: 28, color: Colors.grey.shade200),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              color: active ? Colors.black87 : Colors.black38)),
          Text(time, style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ]),
      )),
    ]);
  }

  String _formatTime(dynamic iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m ${d.hour < 12 ? "AM" : "PM"}';
    } catch (_) { return '—'; }
  }
}
