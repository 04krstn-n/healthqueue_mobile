import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final loggedIn = await context.read<AppState>().restoreSession();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      loggedIn ? AppRoutes.shell : AppRoutes.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Image.asset('assets/icon/healthqueue_logo.png'),
              ),
              const SizedBox(height: 18),
              const Text(
                'HealthQueue+',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Smart healthcare queue management',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
