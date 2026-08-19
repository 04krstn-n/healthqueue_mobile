import 'package:flutter/material.dart';
import '../core/routes/app_routes.dart';
import '../core/constants/app_colors.dart';
import '../widgets/pill_toggle.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isEmail    = true;
  bool _showPass   = false;
  bool _isLoading  = false;

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final identifier = _isEmail
        ? _emailCtrl.text.trim()
        : _phoneCtrl.text.trim();
    final pass = _passCtrl.text;

    if (identifier.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please complete all fields.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await context.read<AppState>().login(
          identifier: identifier, password: pass);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.shell);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  // Logo
                  Container(
                    width: 72, height: 72,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    clipBehavior: Clip.antiAlias, 
                      child: Padding(
                        padding: const EdgeInsets.all(10.0), // Adjust padding so the logo doesn't touch the edges
                        child: Image.asset(
                          'assets/icon/healthqueue_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  const Text('HealthQueue+',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26, fontWeight: FontWeight.w900,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  const Text('Patient Portal',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 32),

                  // Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                          blurRadius: 20,
                          color: Colors.black.withOpacity(.1))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Center(
                        child: Text(
                          'Welcome back',
                          textAlign: TextAlign.center,
                          style: TextStyle( fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark ),),
                         ),
                      const SizedBox(height: 4),
                      const Center(
                        child: Text(
                          'Sign in to continue',
                          textAlign: TextAlign.center,
                          style: TextStyle( fontSize: 13,  color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Toggle
                      PillToggle(
                        isEmail: _isEmail,
                        onEmail: () => setState(() => _isEmail = true),
                        onPhone: () => setState(() => _isEmail = false),
                      ),
                      const SizedBox(height: 16),

                      // Identifier field
                      _label(_isEmail ? 'Email Address' : 'Phone Number'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _isEmail ? _emailCtrl : _phoneCtrl,
                        keyboardType: _isEmail
                            ? TextInputType.emailAddress
                            : TextInputType.phone,
                        decoration: _inputDeco(
                          hint: _isEmail
                              ? 'you@email.com'
                              : '09XXXXXXXXX',
                          icon: _isEmail
                              ? Icons.mail_outline
                              : Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Password
                      _label('Password'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passCtrl,
                        obscureText: !_showPass,
                        onSubmitted: (_) => _signIn(),
                        decoration: _inputDeco(
                          hint: '••••••••',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              _showPass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () =>
                                setState(() => _showPass = !_showPass),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Sign-in button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Sign In',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Register link
                      Center(child: TextButton(
                        onPressed: () => Navigator.pushNamed(
                            context, AppRoutes.register),
                        child: const Text.rich(TextSpan(children: [
                          TextSpan(text: "Don't have an account? ",
                              style: TextStyle(color: AppColors.textMuted)),
                          TextSpan(text: 'Register',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
                        ])),
                      )),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textMuted));

  InputDecoration _inputDeco({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      );
}
