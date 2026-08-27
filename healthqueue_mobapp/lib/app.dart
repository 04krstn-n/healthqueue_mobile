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

  // Keep pages alive when switching tabs
  static const _pages = [
    DashboardScreen(),
    AppointmentsScreen(),
    _ChatbotTab(),
    QueueMonitoringScreen(),
    ProfileScreen(),
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
    _appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    final popup = _appState?.pendingCallPopup;
    if (popup == null || !mounted) return;
    // Clear immediately so the same call event can never trigger the
    // dialog twice, even if this listener fires again before the dialog
    // has finished showing.
    _appState!.dismissCallPopup();
    // QueueMonitoringScreen (tab index 3) already shows its own richer
    // "You're being called" modal — driven by the same AppState-owned
    // socket via _checkPositionChanges. Showing this simpler global popup
    // on top of it while that tab is already active would be a duplicate
    // popup for the same call event, so it's skipped there.
    if (_index == 3) return;
    _showCalledDialog(popup);
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
