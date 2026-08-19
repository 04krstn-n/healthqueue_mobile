import 'package:flutter/material.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/chatbot_screen.dart';
import 'screens/queue_monitoring_screen.dart';
import 'screens/profile_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthQueue+',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.login,
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

  // Keep pages alive when switching tabs
  static const _pages = [
    DashboardScreen(),
    AppointmentsScreen(),
    _ChatbotTab(),
    QueueMonitoringScreen(),
    ProfileScreen(),
  ];

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
