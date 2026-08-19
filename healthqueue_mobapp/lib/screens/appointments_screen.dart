import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../models/appointment_models.dart' as apt;

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer?             _timer;
  // Track appointment statuses to detect changes
  Map<String, String> _prevStatuses = {};

  static const _pollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchAppointments();
    });
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final prev = Map<String, String>.from(_prevStatuses);
    await context.read<AppState>().fetchAppointments();
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

  void _cancel(String id) {
    context.read<AppState>().updateAppointment(id, status: apt.AppointmentStatus.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final state    = context.watch<AppState>();
    final upcoming = state.upcomingAppointments;
    final past     = state.pastAppointments;

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
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Book Appointment',
            onPressed: _bookNew,
          ),
          const SizedBox(width: 8),
        ],
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
      body: state.apptLoading
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
          return Container(
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
          );
        },
      ),
    );
  }
}
