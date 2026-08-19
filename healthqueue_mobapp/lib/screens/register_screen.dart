import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Global key to manage the Form state and trigger layout validation messages
  final _formKey = GlobalKey<FormState>();

  bool _isEmailMode    = true;
  bool _showPassword   = false;
  bool _showConfirm    = false;
  bool _agreed         = false;
  bool _agreedError    = false; // Extra flag to handle visual checkbox error state

  // OTP step (phone registration only)
  bool      _otpStep           = false;
  String    _pendingPhone      = '';
  String    _generatedOtp      = '';
  DateTime? _otpExpiry;
  int       _otpResendCooldown = 0;
  int       _otpAttempts       = 0;
  Timer?    _otpTimer;

  static const _otpValidSeconds    = 120;
  static const _resendCooldownSecs = 30;
  static const _maxOtpAttempts     = 3;

  final _fullNameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _dobCtrl      = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _otpCtrl      = TextEditingController();

  final _phoneRegex = RegExp(r'^(09|\+639)\d{9}$');
  final _passRegex  = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$');

  @override
  void dispose() {
    _otpTimer?.cancel();
    _fullNameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _dobCtrl.dispose(); _passCtrl.dispose(); _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── OTP helpers ────────────────────────────────────────────────────────────
  String _genOtp() =>
      (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
          .toString().substring(0, 6);

  void _startCooldown() {
    _otpTimer?.cancel();
    setState(() => _otpResendCooldown = _resendCooldownSecs);
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_otpResendCooldown > 0) {
          _otpResendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  void _sendOtp() {
    _generatedOtp = _genOtp();
    _otpExpiry    = DateTime.now().add(const Duration(seconds: _otpValidSeconds));
    _otpAttempts  = 0;
    _otpCtrl.clear();
    _startCooldown();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Demo OTP: $_generatedOtp (sent to $_pendingPhone)'),
        duration: const Duration(seconds: 6),
        backgroundColor: AppColors.primary,
      ));
    }
  }

  bool get _otpExpired =>
      _otpExpiry != null && DateTime.now().isAfter(_otpExpiry!);

  int get _otpSecondsLeft =>
      _otpExpiry == null ? 0
      : _otpExpiry!.difference(DateTime.now()).inSeconds.clamp(0, _otpValidSeconds);

  bool _validateOtp() {
    if (_otpExpired) {
      _showErrorDialog('OTP Expired', 'Your OTP has expired. Please request a new one.');
      return false;
    }
    if (_otpAttempts >= _maxOtpAttempts) {
      _showErrorDialog('Too Many Attempts', 'Maximum attempts reached. Please resend OTP.');
      return false;
    }
    if (_otpCtrl.text.trim() != _generatedOtp) {
      _otpAttempts++;
      final left = _maxOtpAttempts - _otpAttempts;
      _showErrorDialog('Wrong OTP', left > 0
          ? 'Incorrect code. $left attempt${left == 1 ? "" : "s"} remaining.'
          : 'No attempts left. Please resend OTP.');
      return false;
    }
    return true;
  }

  // System fallback dialog helper (Only used for fallback/network/OTP issues)
  Future<void> _showErrorDialog(String title, String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        actions: [TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'))],
      ),
    );
  }

  Future<void> _pickDob() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate:   DateTime(1900),
      lastDate:    now,
      initialDate: DateTime(now.year - 20),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx)
            .colorScheme.copyWith(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _dobCtrl.text =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
      // Force validate field right after selection to eliminate validation error text
      _formKey.currentState?.validate();
    }
  }

  // Form Submission Execution Path
  Future<void> _proceedToOtp() async {
    // 1. Reset checkbox error UI flag
    setState(() => _agreedError = !_agreed);

    // 2. Fire structural Form validation (Executes all inline field text logic)
    if (!_formKey.currentState!.validate() || !_agreed) {
      return; // Stops thread if any text field logic returns string rules
    }

    final phone = _phoneCtrl.text.trim();

    if (!_isEmailMode) {
      // Phone routing layout chain logic 
      setState(() { _pendingPhone = phone; _otpStep = true; });
      _sendOtp();
    } else {
      await _doRegister();
    }
  }

  Future<void> _verifyAndRegister() async {
    if (!_validateOtp()) return;
    await _doRegister();
  }

  Future<void> _doRegister() async {
    final appState = context.read<AppState>();
    if (appState.isLoading) return;
    try {
      await appState.register({
        'fullName': _fullNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passCtrl.text,
        if (_dobCtrl.text.isNotEmpty) 'dateOfBirth': _dobCtrl.text,
        'role': 'patient',
      });
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.shell);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.toLowerCase().contains('duplicate') ||
          msg.toLowerCase().contains('already') ||
          msg.toLowerCase().contains('exist')) {
        await _showErrorDialog('Account Already Exists',
            'An account with this ${_isEmailMode ? "email" : "phone number"} '
            'already exists. Please log in instead.');
        if (mounted) setState(() => _otpStep = false);
      } else {
        await _showErrorDialog('Registration Failed', msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AppState>().isLoading;

    if (_otpStep) return _buildOtpScreen(isLoading);
    return _buildFormScreen(isLoading);
  }

  // ── OTP screen ─────────────────────────────────────────────────────────────
  Widget _buildOtpScreen(bool isLoading) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _otpTimer?.cancel();
            setState(() => _otpStep = false);
          },
        ),
        title: const Text('Verify Phone Number',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Enter the 6-digit code sent to\n$_pendingPhone',
              style: const TextStyle(fontSize: 15, color: Colors.black54,
                  height: 1.5)),
          const SizedBox(height: 28),

          // Expiry countdown
          Builder(builder: (_) {
            final left = _otpSecondsLeft;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _otpExpired ? 'OTP has expired'
                    : 'Expires in ${left}s',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: _otpExpired ? Colors.red
                      : left < 30 ? Colors.orange : Colors.green),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: left / _otpValidSeconds,
                  backgroundColor: Colors.grey.shade200,
                  color: _otpExpired ? Colors.red
                      : left < 30 ? Colors.orange : AppColors.primary,
                  minHeight: 3,
                ),
              ),
            ]);
          }),
          const SizedBox(height: 20),

          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                letterSpacing: 10),
            decoration: InputDecoration(
              counterText: '',
              hintText: '------',
              hintStyle: TextStyle(color: Colors.grey.shade300,
                  fontSize: 28, letterSpacing: 10),
              filled: true, fillColor: const Color(0xFFF6F7FB),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isLoading ? null : _verifyAndRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: isLoading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Verify & Create Account',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: _otpResendCooldown > 0
              ? Text('Resend in ${_otpResendCooldown}s',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
              : TextButton(
                  onPressed: _sendOtp,
                  child: const Text('Resend OTP',
                      style: TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      ),
    );
  }

  // ── Registration form ───────────────────────────────────────────────────────
  Widget _buildFormScreen(bool isLoading) {
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
                child: Form(
                  key: _formKey, // Forms process children inputs automatically
                  child: Column(children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias, 
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Image.asset(
                          'assets/icon/healthqueue_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'HealthQueue+',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create your patient account',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 20,
                            color: Colors.black.withOpacity(.1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(
                            child: Text(
                              'Create Account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Center(
                            child: Text(
                              'Sign up to continue',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          _field(
                            'Full Name', 
                            _fullNameCtrl,
                            hint: 'Juan Dela Cruz',
                            icon: Icons.person_outline,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name.' : null,
                          ),
                          const SizedBox(height: 14),

                          _field(
                            'Email Address', 
                            _emailCtrl,
                            hint: 'you@email.com',
                            type: TextInputType.emailAddress,
                            icon: Icons.mail_outline,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your email.' : null,
                          ),
                          const SizedBox(height: 14),

                          _field(
                            'Phone Number', 
                            _phoneCtrl,
                            hint: '09XXXXXXXXX',
                            type: TextInputType.phone,
                            icon: Icons.phone_outlined,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Please enter your phone number.';
                              if (!_phoneRegex.hasMatch(v.trim())) return 'Please use structural format (09XXXXXXXXX).';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          _dobField(),
                          const SizedBox(height: 14),

                          _passField(
                            'Password', 
                            _passCtrl, 
                            _showPassword,
                            () => setState(() => _showPassword = !_showPassword),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please enter a password.';
                              if (!_passRegex.hasMatch(v)) return 'Must contain 8+ characters, uppercase, lowercase, numbers & symbols.';
                              return null;
                            }
                          ),
                          const SizedBox(height: 14),

                          _passField(
                            'Confirm Password', 
                            _confirmCtrl, 
                            _showConfirm,
                            () => setState(() => _showConfirm = !_showConfirm),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please confirm your password.';
                              if (v != _passCtrl.text) return 'Passwords do not match.';
                              return null;
                            }
                          ),
                          const SizedBox(height: 20),

                          // Terms and Conditions Widget Block
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: _agreed,
                                    activeColor: AppColors.primary,
                                    side: BorderSide(color: _agreedError ? Colors.red : Colors.grey.shade400, width: 1.5),
                                    onChanged: (v) {
                                      setState(() {
                                        _agreed = v ?? false;
                                        if (_agreed) _agreedError = false;
                                      });
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _agreed = !_agreed;
                                          if (_agreed) _agreedError = false;
                                        });
                                      },
                                      child: const Text(
                                        'I agree to the Terms of Service and Privacy Policy',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_agreedError)
                                const Padding(
                                  padding: EdgeInsets.only(left: 12, top: 4),
                                  child: Text(
                                    'Please accept the terms and conditions.',
                                    style: TextStyle(color: Colors.red, fontSize: 12),
                                  ),
                                )
                            ],
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isLoading ? null : _proceedToOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Create Account',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.pushReplacementNamed(
                                  context, AppRoutes.login),
                              child: const Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: 'Already have an account? ',
                                    style: TextStyle(color: AppColors.textMuted),
                                  ),
                                  TextSpan(
                                    text: 'Log in',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      );

  // Updated input decorator handling standard custom borders and explicit red error styling
  InputDecoration _inputDeco({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
      
      // Border configuration architecture settings
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String hint = '',
    TextInputType type = TextInputType.text,
    required IconData icon,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextFormField( // Converted from TextField to handle form validations inline
          controller: ctrl,
          keyboardType: type,
          validator: validator,
          decoration: _inputDeco(hint: hint, icon: icon),
        ),
      ],
    );
  }

  Widget _dobField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Date of Birth'),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: _pickDob,
        child: AbsorbPointer(
          child: TextFormField( // Converted from TextField
            controller: _dobCtrl,
            validator: (v) => (v == null || v.isEmpty) ? 'Please select your date of birth.' : null,
            decoration: _inputDeco(
              hint: 'Select date',
              icon: Icons.calendar_today_outlined,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _passField(
    String label, 
    TextEditingController ctrl,
    bool show, 
    VoidCallback toggle, {
    required String? Function(String?) validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      const SizedBox(height: 6),
      TextFormField( // Converted from TextField
        controller: ctrl, 
        obscureText: !show,
        validator: validator,
        decoration: _inputDeco(
          hint: '••••••••',
          icon: Icons.lock_outline,
          suffix: IconButton(
            icon: Icon(
              show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: AppColors.textMuted,
            ),
            onPressed: toggle,
          ),
        ),
      ),
    ]);
  }
}