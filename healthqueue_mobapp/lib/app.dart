import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/chatbot_screen.dart';
import 'screens/queue_monitoring_screen.dart';
import 'screens/profile_screen.dart';
import 'state/app_state.dart';
import 'models/queue_models.dart';
import 'models/appointment_models.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthQueue+',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
    );
  }
}

/// Persistent shell used after login — owns the bottom nav bar.
/// Push individual routes (joinQueue, bookAppointment, etc.) on TOP of this
/// via Navigator.pushNamed — they won't have the bottom nav.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  AppState? _appState;

  // Appointments' own 15s poll (see appointments_screen.dart) now
  // correctly pauses while that tab isn't active, to save CPU — but that
  // means nothing notices a staff-side appointment status change (e.g. a
  // cancellation) while the patient is on a different tab. This timer is
  // deliberately owned here at the shell level, independent of _index,
  // so it keeps running no matter which tab is showing.
  //
  // IMPORTANT — revised after testing showed this spiking Energy Score
  // without a matching CPU increase: that pattern means the cost is
  // radio wake-ups, not processing. Every network call ramps the
  // cellular/WiFi radio to a high-power state and keeps it there for
  // several seconds afterward ("tail energy") — so a small request
  // fired unconditionally every minute, for the entire session, is far
  // more expensive for battery than its CPU footprint would suggest.
  // Two changes from the original version:
  //   1. 3 minutes instead of 60s — cuts the wake-up frequency by 3x.
  //   2. Skip entirely when there's nothing to actually watch — most of
  //      a session, a patient has no active queue entry and no
  //      upcoming appointment, so there's nothing whose status COULD
  //      change. No point waking the radio to check.
  Timer? _apptWatchTimer;

  @override
  void initState() {
    super.initState();
    _apptWatchTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) {
        final s = _appState;
        if (s == null) return;
        // Only bother if there's actually something whose status could
        // change — an active queue entry or a pending appointment. If
        // neither exists, there's nothing for a cancellation/status
        // change to happen TO, so skip the network call (and the radio
        // wake-up it costs) entirely.
        if (s.currentQueue != null) s.fetchQueueStatus();
        if (s.upcomingAppointments.isNotEmpty) s.fetchAppointments();
      },
    );
  }

  // Keep pages alive when switching tabs (IndexedStack never disposes them).
  // DashboardScreen is NOT const here — it needs to know whether it's the
  // currently-visible tab so it can tear down its embedded GoogleMap and
  // pause its own poll timer while sitting off-screen. Without that, the
  // map's native view (and the 15s timer) kept running for the entire app
  // session regardless of which tab the patient was actually looking at —
  // that was the single biggest source of the background CPU/GPU/memory
  // drain (and the FPS drop) reported by the performance test.
  List<Widget> get _pages => [
    DashboardScreen(isActive: _index == 0),
    AppointmentsScreen(isActive: _index == 1),
    const _ChatbotTab(),
    const QueueMonitoringScreen(),
    const ProfileScreen(),
  ];

  // Listening at the shell level (rather than per-screen) means the popup
  // fires no matter which tab the patient is currently looking at — the
  // socket connection that drives this lives in AppState (see
  // AppState.fetchQueueStatus / _queueSocket), so this widget only reacts
  // to the result, it never touches Socket.IO directly.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    if (_appState != appState) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = appState;
      _appState!.addListener(_onAppStateChanged);
      // Catch a call event that was already pending before this shell
      // existed (e.g. it arrived during the login screen's own
      // fetchQueueStatus() call, just before navigating here).
      WidgetsBinding.instance.addPostFrameCallback((_) => _onAppStateChanged());
    }
  }

  @override
  void dispose() {
    _apptWatchTimer?.cancel();
    _appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    final popup = _appState?.pendingCallPopup;
    if (popup != null && mounted) {
      // Clear immediately so the same call event can never trigger the
      // dialog twice, even if this listener fires again before the dialog
      // has finished showing.
      _appState!.dismissCallPopup();
      // QueueMonitoringScreen (tab index 3) already shows its own richer
      // "You're being called" modal — driven by the same AppState-owned
      // socket via _checkPositionChanges. Showing this simpler global popup
      // on top of it while that tab is already active would be a duplicate
      // popup for the same call event, so it's skipped there.
      if (_index != 3) _showCalledDialog(popup);
    }

    final apptChange = _appState?.pendingApptStatusChange;
    if (apptChange != null && mounted) {
      final from = _appState!.pendingApptStatusFrom;
      // Same reasoning as above — clear first so it can't double-fire,
      // and skip while AppointmentsScreen (tab index 1) is already active
      // since its own _refresh() shows a richer, appointment-specific
      // modal for the exact same change.
      _appState!.dismissApptStatusPopup();
      if (_index != 1 && from != null) {
        _showApptStatusDialog(apptChange, from);
      }
    }
  }

  void _showCalledDialog(QueueEntry entry) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.notifications_active_rounded,
            color: Color(0xFF16A34A), size: 40),
        title: const Text(
          "You're being called",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Please proceed to the clinic.\n\n'
          'Queue #${entry.queueNumber}'
          '${entry.clinicName.isNotEmpty ? ' — ${entry.clinicName}' : ''}',
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  void _showApptStatusDialog(Appointment appt, String from) {
    final to = appt.status.name;
    final isBad = to == 'cancelled' || to == 'noShow';
    final color = isBad ? Colors.red : const Color(0xFF16A34A);
    final label = {
      'confirmed': 'Confirmed',
      'cancelled': 'Cancelled',
      'arrived': 'Arrived',
      'serving': 'Now Serving',
      'completed': 'Completed',
      'noShow': 'Marked No-Show',
      'rescheduled': 'Rescheduled',
    }[to] ?? to;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(
          isBad ? Icons.cancel_outlined : Icons.check_circle_outline,
          color: color,
          size: 40,
        ),
        title: Text(
          'Appointment $label',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          isBad
              ? 'Your appointment for ${appt.department} at ${appt.clinicName} has been cancelled.'
              : 'Your appointment at ${appt.clinicName} is now $label.',
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex:        _index,
        type:                BottomNavigationBarType.fixed,
        selectedItemColor:   const Color(0xFF1D4ED8),
        unselectedItemColor: const Color(0xFF64748B),
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today), label: 'Appointments'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          BottomNavigationBarItem(
              icon: Icon(Icons.queue_outlined),
              activeIcon: Icon(Icons.queue), label: 'Queue'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Thin wrapper so ChatbotScreen gets its callbacks without needing context tricks
class _ChatbotTab extends StatelessWidget {
  const _ChatbotTab();
  @override
  Widget build(BuildContext context) => ChatbotScreen(
    onBookAppointment: () => Navigator.pushNamed(context, AppRoutes.bookAppointment),
    onViewQueue:       () => Navigator.pushNamed(context, AppRoutes.queueMonitoring),
  );
}
