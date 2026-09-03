import 'package:flutter/material.dart';
import '../../screens/appointments_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/register_screen.dart';
import '../../screens/forgot_password_screen.dart';
import '../../screens/queue_monitoring_screen.dart';
import '../../screens/join_queue_screen.dart';
import '../../screens/chatbot_screen.dart';
import '../../screens/book_appointment_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/clinic_map_screen.dart';
import '../../screens/ai_insights_screen.dart';
import '../../screens/splash_screen.dart';
import '../../app.dart';

class AppRoutes {
  static const splash          = '/';
  static const login           = '/login';
  static const register        = '/register';
  static const forgotPassword  = '/forgot-password';
  static const shell           = '/shell';
  static const dashboard       = '/shell';   // alias kept for compat
  static const queueMonitoring = '/queue';
  static const joinQueue       = '/join-queue';
  static const chatBot         = '/chat';
  static const bookAppointment = '/book-appointment';
  static const appointments    = '/appointments';
  static const profile         = '/profile';
  static const clinicMap       = '/map';
  static const aiInsights      = '/ai-insights';

  static Map<String, WidgetBuilder> get routes => {
    splash:          (_) => const SplashScreen(),
    login:           (_) => const LoginScreen(),
    register:        (_) => const RegisterScreen(),
    forgotPassword:  (_) => const ForgotPasswordScreen(),
    shell:           (_) => const AppShell(),
    // Full-screen routes pushed on top of shell
    joinQueue:       (_) => const JoinQueueScreen(),
    bookAppointment: (_) => const BookAppointmentScreen(),
    clinicMap:       (_) => const ClinicMapScreen(),
    aiInsights:      (_) => const AiInsightsScreen(),
    // Tab screens — still accessible via named route for pushNamed calls
    queueMonitoring: (_) => const QueueMonitoringScreen(),
    appointments:    (_) => const AppointmentsScreen(),
    profile:         (_) => const ProfileScreen(),
    chatBot: (context) => ChatbotScreen(
      onBookAppointment: () => Navigator.pushNamed(context, bookAppointment),
      onViewQueue:       () => Navigator.pushNamed(context, queueMonitoring),
    ),
  };
}
