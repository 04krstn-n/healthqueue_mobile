import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../models/appointment_models.dart' as apt;

class AppointmentsScreen extends StatefulWidget {
  // Whether this tab is the one currently visible in AppShell's
  // IndexedStack. Without this, the 15s poll timer below runs for the
  // entire app session regardless of which tab the patient is actually
  // looking at — the exact same issue DashboardScreen had with its own
  // timer and embedded map (see app.dart / dashboard_screen.dart).
  final bool isActive;

  const AppointmentsScreen({super.key, this.isActive = true});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer?             _timer;
  // Track appointment statuses to detect changes
  Map<String, String> _prevStatuses = {};
  AppState? _appState;

  static const _pollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    debugPrint('[APPT] initState isActive=${widget.isActive}');
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      debugPrint('[APPT] tab switched to index=${_tabs.index}');
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[APPT] initState postFrameCallback fetch');
      context.read<AppState>().fetchAppointments();
    });
    if (widget.isActive) _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Belt-and-suspenders alongside the context.select() calls in build():
    // in one reproduced case, fetchAppointments() completed and
    // apptLoading correctly flipped to false (confirmed via logging —
    // "fetchAppointments END ... apptLoading=false" fired) but this
    // screen never rebuilt to show it, leaving the spinner stuck until
    // something unrelated (switching the Upcoming/Past sub-tab) forced a
    // rebuild through a completely different path (the TabController
    // listener's own setState()). That means Provider's select()-based
    // rebuild signal was missed in that case — root cause not fully
    // pinned down, but a raw addListener here, the same reliable pattern
    // QueueMonitoringScreen and AppShell already use elsewhere in this
    // app, guarantees a rebuild on every single AppState change
    // regardless of what edge case causes select() to miss one.
    if (_appState == null) {
      _appState = context.read<AppState>();
      _appState!.addListener(_onAppStateChanged);
    }
  }

  void _onAppStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('[APPT] didUpdateWidget oldActive=${oldWidget.isActive} newActive=${widget.isActive}');
    // Start/stop polling as this tab is switched into/out of view — see
    // the isActive doc comment above.
    if (widget.isActive && !oldWidget.isActive) {
      _startPolling();
      // Catch up immediately rather than waiting up to 15s for the first
      // tick, since data may be stale from however long this tab was
      // backgrounded.
      _refresh();
    } else if (!widget.isActive && oldWidget.isActive) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    debugPrint('[APPT] _refresh() called');
    if (!mounted) return;
    final prev = Map<String, String>.from(_prevStatuses);
    await context.read<AppState>().fetchAppointments();
    debugPrint('[APPT] _refresh() fetch completed, mounted=$mounted');
    if (!mounted) return;
    final appts = context.read<AppState>().appointments;
    // Detect status changes and notify
    for (final a in appts) {
      final prevStatus = prev[a.id];
      final curStatus  = a.status.name;
      if (prevStatus != null && prevStatus != curStatus) {
        _showApptStatusModal(a, prevStatus, curStatus);
      }
    }
    // Update tracking map
    _prevStatuses = { for (final a in appts) a.id: a.status.name };
  }

  void _showApptStatusModal(
      apt.Appointment appt, String from, String to) {
    if (!mounted) return;
    final label = {
      'confirmed':  'Confirmed',
      'cancelled':  'Cancelled',
      'arrived':    'Arrived',
      'serving':    'Now Serving',
      'completed':  'Completed',
      'noShow':     'Marked No-Show',
      'rescheduled':'Rescheduled',
    }[to] ?? to;

    final isGood   = ['confirmed', 'completed', 'serving', 'arrived'].contains(to);
    final isBad    = ['cancelled', 'noShow'].contains(to);
    final color    = isBad ? Colors.red : isGood ? const Color(0xFF16A34A) : Colors.orange;
    final icon     = isBad ? Icons.cancel_outlined
                   : isGood ? Icons.check_circle_outline
                   : Icons.info_outline;

    final messages = {
      'confirmed':   'Your appointment at ${appt.clinicName} has been confirmed by the clinic.',
      'cancelled':   'Your appointment for ${appt.department} at ${appt.clinicName} has been cancelled.',
      'serving':     'It is your turn! Please proceed to the service counter at ${appt.clinicName}.',
      'completed':   'Your appointment at ${appt.clinicName} is complete. Thank you!',
      'noShow':      'You were marked as no-show for your appointment at ${appt.clinicName}.',
      'rescheduled': 'Your appointment at ${appt.clinicName} has been rescheduled.',
    };

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('Appointment $label',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
        content: Text(
          messages[to] ?? 'Your appointment status changed to: $label.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
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

  @override
  void dispose() {
    _timer?.cancel();
    _appState?.removeListener(_onAppStateChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bookNew() async {
    final result = await Navigator.pushNamed(context, AppRoutes.bookAppointment);
    if (!mounted) return;
    if (result is apt.Appointment) {
      context.read<AppState>().addAppointment(result);
    }
  }

  Future<void> _cancel(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Appointment?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to cancel this appointment?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Appointment')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final success = await context.read<AppState>().cancelAppointment(id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? 'Your appointment has been cancelled successfully.'
          : 'Could not cancel the appointment. Please try again.'),
      backgroundColor: success ? const Color(0xFF16A34A) : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // select(), not watch() — same reasoning as Dashboard. This tab was
    // rebuilding on every AppState change even while backgrounded.
    final upcoming =
        context.select<AppState, List<apt.Appointment>>((s) => s.upcomingAppointments);
    final past =
        context.select<AppState, List<apt.Appointment>>((s) => s.pastAppointments);
    final apptLoading = context.select<AppState, bool>((s) => s.apptLoading);
    debugPrint('[APPT] build() apptLoading=$apptLoading upcoming=${upcoming.length} past=${past.length}');

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appointments', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text('Manage your scheduled visits',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ],
        ),
        // Book Appointment book-new action already exists as the floating
        // action button below — this duplicated it in the appbar too.
        actions: const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabs,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Past')],
          ),
        ),
      ),
      body: apptLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _ApptList(
                  appointments: upcoming,
                  onCancel: _cancel,
                  emptyMsg: 'No upcoming appointments.\nTap + to book one.',
                  showCancel: true,
                ),
                _ApptList(
                  appointments: past,
                  onCancel: null,
                  emptyMsg: 'No past appointments.',
                  showCancel: false,
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bookNew,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Book Appointment',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _ApptList extends StatelessWidget {
  final List<apt.Appointment> appointments;
  final void Function(String)? onCancel;
  final String emptyMsg;
  final bool showCancel;

  const _ApptList({
    required this.appointments,
    required this.onCancel,
    required this.emptyMsg,
    required this.showCancel,
  });

  Color _statusColor(apt.AppointmentStatus s) {
    switch (s) {
      case apt.AppointmentStatus.confirmed:   return Colors.green;
      case apt.AppointmentStatus.arrived:     return Colors.blue;
      case apt.AppointmentStatus.serving:     return Colors.purple;
      case apt.AppointmentStatus.completed:   return Colors.teal;
      case apt.AppointmentStatus.cancelled:   return Colors.red;
      case apt.AppointmentStatus.noShow:      return Colors.orange;
      case apt.AppointmentStatus.rescheduled: return Colors.amber;
      default:                                return Colors.grey;
    }
  }

  String _statusLabel(apt.AppointmentStatus s) {
    switch (s) {
      case apt.AppointmentStatus.confirmed:   return 'Confirmed';
      case apt.AppointmentStatus.arrived:     return 'Arrived';
      case apt.AppointmentStatus.serving:     return 'Serving';
      case apt.AppointmentStatus.completed:   return 'Completed';
      case apt.AppointmentStatus.cancelled:   return 'Cancelled';
      case apt.AppointmentStatus.noShow:      return 'No Show';
      case apt.AppointmentStatus.rescheduled: return 'Rescheduled';
      default:                                return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.6)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().fetchAppointments(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: appointments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final a = appointments[i];
          final statusColor = _statusColor(a.status);
          return RepaintBoundary(
            // Every 15s refresh (or the 60s cross-tab watch) rebuilds this
            // whole list — without this, every visible card's shadow
            // redraws together even when only one appointment's status
            // actually changed.
            child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(a.clinicName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(_statusLabel(a.status),
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.medical_services_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(child: Text(a.department,
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${a.date.day}/${a.date.month}/${a.date.year}  ${a.timeLabel}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ]),
                  if (a.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.notes_outlined, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Expanded(child: Text(a.notes,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                    ]),
                  ],
                  if (showCancel && onCancel != null && a.isUpcoming) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => onCancel!(a.id),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Cancel Appointment',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}