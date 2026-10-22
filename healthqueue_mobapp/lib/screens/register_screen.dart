import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../widgets/otp_input_field.dart';
import 'policy_viewer_screen.dart';


class RegisterScreen extends StatefulWidget {
  // When set, the screen opens straight into the OTP step instead of the
  // registration form — used when login reports an unverified account.
  final String? initialUserId;
  final String? initialPhone;

  const RegisterScreen({
    super.key,
    this.initialUserId,
    this.initialPhone,
  });
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Global key to manage the Form state and trigger layout validation messages
  final _formKey = GlobalKey<FormState>();

  bool _showPassword   = false;
  bool _showConfirm    = false;
  bool _agreed         = false;
  bool _agreedError    = false; // Extra flag to handle visual checkbox error state
  // Item 2/3: the checkbox above must not be checkable at all until the
  // user has actually reached the bottom of BOTH the Terms & Agreements
  // and the Privacy Policy in PolicyViewerScreen — set only when that
  // screen pops back `true`.
  bool _hasReadPolicies = false;
  // Both the "(tap to read)" hint and the "please read first" helper line
  // stay hidden until the user actually tries to proceed without having
  // read the policies yet — set true the first time _proceedToOtp blocks
  // on this, not shown unconditionally from the moment the form opens.
  bool _showPolicyHint = false;
  // Shared left-indent so the "please read first" / "please accept"
  // helper lines under the checkbox row line up with the checkbox's LABEL
  // text ("I agree to...") rather than sitting almost flush under the
  // checkbox itself.
  static const double _checkboxLeadWidth = 40;

  // Live password-requirement checklist state, recomputed on every
  // keystroke (see _passCtrl's listener in initState) — item 5's "show a
  // password requirement checklist that updates as the user types".
  bool _pwHasLength  = false;
  bool _pwHasUpper   = false;
  bool _pwHasLower   = false;
  bool _pwHasNumber  = false;
  bool _pwHasSpecial = false;
  bool get _pwAllMet => _pwHasLength && _pwHasUpper && _pwHasLower && _pwHasNumber && _pwHasSpecial;

  // Set right after a wrong-OTP response so OtpInputField shows a red
  // border + shakes once (item 1) instead of only a dialog. Cleared as
  // soon as the user edits the code again.
  bool _otpHasError = false;
  // Brief green checkmark shown right before navigating away on success
  // (item 1: "show a success state ... after successful verification").
  bool _otpSuccess = false;

  // OTP step (phone registration only) — the code itself is generated and
  // verified server-side; this screen just tracks the pending account and a
  // countdown that mirrors the server's 5-minute OTP expiry.
  bool      _otpStep           = false;
  String    _pendingPhone      = '';
  String?   _pendingUserId;
  Map<String, dynamic>? _pendingBody;
  DateTime? _otpExpiry;
  int       _otpResendCooldown = 0;
  int       _otpAttempts       = 0;
  Timer?    _otpTimer;

  static const _otpValidSeconds    = 300; // matches server's 5-minute OTP expiry
  static const _resendCooldownSecs = 30;
  static const _maxOtpAttempts     = 3;

  final _fullNameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _dobCtrl      = TextEditingController();
  String? _gender;
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _otpCtrl      = TextEditingController();

  final _phoneRegex = RegExp(r'^(09|\+639)\d{9}$');
  final _passRegex  = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$');

  @override
  void initState() {
    super.initState();
    if (widget.initialUserId != null && widget.initialUserId!.isNotEmpty) {
      _pendingUserId = widget.initialUserId;
      _pendingPhone  = widget.initialPhone ?? '';
      _otpStep       = true;
      // Any OTP from the original registration may be long expired by now —
      // request a fresh one as soon as this screen opens.
      WidgetsBinding.instance.addPostFrameCallback((_) => _resendOtp());
    }
    _passCtrl.addListener(_updatePasswordChecklist);
  }

  void _updatePasswordChecklist() {
    final v = _passCtrl.text;
    setState(() {
      _pwHasLength  = v.length >= 8;
      _pwHasUpper   = RegExp(r'[A-Z]').hasMatch(v);
      _pwHasLower   = RegExp(r'[a-z]').hasMatch(v);
      _pwHasNumber  = RegExp(r'\d').hasMatch(v);
      _pwHasSpecial = RegExp(r'[^\w\s]').hasMatch(v);
    });
  }

  // Opens the full Terms & Agreements / Privacy Policy viewer. The
  // checkbox stays disabled until this returns `true` (only possible once
  // the user has scrolled to the bottom of both documents — see
  // PolicyViewerScreen) — tapping the link text is what starts that, not
  // an alternate way to skip it.
  Future<void> _openPolicyViewer() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PolicyViewerScreen()),
    );
    if (result == true && mounted) {
      setState(() => _hasReadPolicies = true);
    }
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _fullNameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _dobCtrl.dispose(); _passCtrl.dispose(); _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── OTP helpers ────────────────────────────────────────────────────────────
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

  // Shows the server's OTP-send outcome. In normal (real-SMS) mode this is
  // just a confirmation snackbar. If the server is running without a
  // configured SMS provider (mock mode) or the SMS itself failed to send, the
  // server includes `devOtp` in its response — surface it so the flow is
  // still testable instead of leaving the user stuck with no way to receive
  // a code.
  void _showOtpStatus(Map<String, dynamic> data) {
    final devOtp = data['devOtp']?.toString();
    final message = data['message']?.toString();

    if (devOtp != null && devOtp.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('SMS Not Sent',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          content: Text(
            '${message ?? "SMS could not be sent."}\n\nYour code: $devOtp',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'))],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message ?? 'Verification code sent to your phone.'),
      backgroundColor: AppColors.primary,
    ));
  }

  // Asks the server to (re)send an OTP for the already-created pending
  // account. The initial send happens as a side effect of registration
  // itself (see _proceedToOtp), so this is used for the "Resend OTP" button.
  Future<void> _resendOtp() async {
    if (_pendingUserId == null) return;
    _otpAttempts = 0;
    _otpCtrl.clear();
    setState(() { _otpHasError = false; _otpSuccess = false; });

    try {
      final appState = context.read<AppState>();
      final data = await appState.resendOtp(_pendingUserId!);
      setState(() => _otpExpiry =
          DateTime.now().add(const Duration(seconds: _otpValidSeconds)));
      _startCooldown();
      if (mounted) _showOtpStatus(data);
    } catch (e) {
      if (mounted) {
        await _showErrorDialog(
          'OTP Not Sent',
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  bool get _otpExpired =>
      _otpExpiry != null && DateTime.now().isAfter(_otpExpiry!);

  int get _otpSecondsLeft =>
      _otpExpiry == null ? 0
      : _otpExpiry!.difference(DateTime.now()).inSeconds.clamp(0, _otpValidSeconds);

  // "Expires in 245s" was genuinely hard to read at a glance — a
  // standard M:SS countdown (matching how OTP timers look in basically
  // every other app) is much clearer than a raw seconds count.
  String _formatCountdown(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // Local, UX-only guards before we bother the server. The actual code check
  // happens server-side in AppState.completeRegistration.
  bool _canAttemptOtp() {
    if (_otpExpired) {
      _showErrorDialog('OTP Expired', 'Your OTP has expired. Please request a new one.');
      return false;
    }
    if (_otpAttempts >= _maxOtpAttempts) {
      _showErrorDialog('Too Many Attempts', 'Maximum attempts reached. Please resend OTP.');
      return false;
    }
    if (_otpCtrl.text.trim().length != 6) {
      _showErrorDialog('Invalid Code', 'Enter the 6-digit code sent to your phone.');
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

    if (!_hasReadPolicies) {
      setState(() => _showPolicyHint = true);
      await _showErrorDialog('Terms & Privacy Policy',
          'Please open and read through the Terms & Agreements and Privacy Policy before continuing.');
      return;
    }

    // 2. Fire structural Form validation (Executes all inline field text logic)
    if (!_formKey.currentState!.validate() || !_agreed) {
      return; // Stops thread if any text field logic returns string rules
    }

    final phone = _phoneCtrl.text.trim();
    final body = {
      'fullName': _fullNameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': phone,
      'password': _passCtrl.text,
      if (_dobCtrl.text.isNotEmpty) 'dateOfBirth': _dobCtrl.text,
      'gender': _gender ?? '',
      'role': 'patient',
    };

    final appState = context.read<AppState>();
    if (appState.isLoading) return;

    try {
      // Creates the (unverified) account and has the server text a real OTP.
      final data = await appState.beginRegistration(body);
      final userId = data['userId'].toString();
      setState(() {
        _pendingPhone   = phone;
        _pendingUserId  = userId;
        _pendingBody    = body;
        _otpStep        = true;
        _otpAttempts    = 0;
        _otpExpiry      = DateTime.now().add(const Duration(seconds: _otpValidSeconds));
      });
      _otpCtrl.clear();
      _startCooldown();
      if (mounted) _showOtpStatus(data);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      // Show the server's actual message directly — it already contains
      // the exact wording for a duplicate phone/email (see
      // authController.register's PHONE_IN_USE_MESSAGE), so there's no
      // need to re-detect and paraphrase it here.
      await _showErrorDialog('Registration Failed', msg);
    }
  }

  Future<void> _verifyAndRegister() async {
    if (!_canAttemptOtp()) return;
    if (_pendingUserId == null) return;

    final appState = context.read<AppState>();
    if (appState.isLoading) return;

    setState(() => _otpHasError = false);

    try {
      await appState.completeRegistration(
        userId: _pendingUserId!,
        otp: _otpCtrl.text.trim(),
        fallback: _pendingBody ?? const {},
      );
      if (!mounted) return;
      // Brief success state before navigating away (item 1) — otherwise
      // a correct code just instantly jumps to the home screen with no
      // visible confirmation that verification actually succeeded.
      setState(() => _otpSuccess = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.shell);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.toLowerCase().contains('expired')) {
        setState(() => _otpExpiry = DateTime.now().subtract(const Duration(seconds: 1)));
        await _showErrorDialog('OTP Expired', 'Your OTP has expired. Please request a new one.');
        return;
      }
      setState(() => _otpHasError = true);
      _otpAttempts++; // keeps _canAttemptOtp()'s local pre-check in sync with the server
      // The server is authoritative on attempts remaining/lockout (see
      // authController.verifyOTP's MAX_OTP_ATTEMPTS) — its message text is
      // shown directly rather than re-deriving a count from a local
      // counter that could drift from what the server actually enforced.
      if (msg.toLowerCase().contains('maximum attempts')) {
        await _showErrorDialog('Too Many Attempts', msg);
      } else {
        await _showErrorDialog('Incorrect Code', msg);
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
    final otpComplete = _otpCtrl.text.trim().length == 6;
    // Matches forgot_password_screen.dart's OTP step visual pattern —
    // gradient background, a big icon + title floating above a white
    // elevated card, left-aligned content inside the card, "Back" link
    // below instead of an app bar. The old layout here was a plain white
    // full-page Scaffold with an AppBar; this keeps this screen's own
    // functional additions (error shake, disabled-until-complete button,
    // success state) but adopts the cleaner shared chrome.
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
                  Icon(
                    _otpSuccess ? Icons.check_circle_rounded : Icons.sms_rounded,
                    color: Colors.white,
                    size: 56,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _otpSuccess ? 'Verified!' : 'Enter OTP',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 32),
                  RepaintBoundary(
                    // Same fix as forgot_password_screen.dart/login_screen.dart:
                    // isolates the shadowed card's expensive blur from
                    // repainting every frame of the keyboard's open/close
                    // animation.
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(
                            blurRadius: 20, color: Colors.black.withValues(alpha: .1))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enter the verification code sent to your mobile number.\n$_pendingPhone',
                            style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
                          ),
                          const SizedBox(height: 20),

                          // Expiry countdown
                          Builder(builder: (_) {
                            final left = _otpSecondsLeft;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _otpExpired ? 'OTP has expired'
                                      : 'Expires in ${_formatCountdown(left)}',
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
                              ],
                            );
                          }),
                          const SizedBox(height: 18),

                          OtpInputField(
                            controller: _otpCtrl,
                            hasError: _otpHasError,
                            onChanged: (_) {
                              if (_otpHasError) setState(() => _otpHasError = false);
                              // Rebuilds to re-evaluate `otpComplete` for
                              // the Verify button's enabled state.
                              setState(() {});
                            },
                            onCompleted: (_) {
                              if (!isLoading && !_otpExpired) _verifyAndRegister();
                            },
                          ),
                          if (_otpHasError) ...[
                            const SizedBox(height: 8),
                            const Text('Incorrect code. Please try again.',
                                style: TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                          ],
                          if (_otpSuccess) ...[
                            const SizedBox(height: 8),
                            const Text('Setting up your account…',
                                style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
                          ],
                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (isLoading || !otpComplete || _otpExpired || _otpSuccess)
                                  ? null : _verifyAndRegister,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade300,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: isLoading
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : Text(_otpSuccess ? 'Verified' : 'Verify & Create Account',
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(child: _otpResendCooldown > 0
                              ? Text('Resend in ${_otpResendCooldown}s',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
                              : TextButton(
                                  onPressed: _resendOtp,
                                  child: const Text('Resend OTP',
                                      style: TextStyle(fontWeight: FontWeight.w700)))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      _otpTimer?.cancel();
                      setState(() => _otpStep = false);
                    },
                    child: const Text('Back',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ),
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
                          // Same fix as login_screen.dart/splash_screen.dart
                          // — decode at display size, not full native res.
                          cacheWidth: 150,
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

                    RepaintBoundary(
                      // Same fix as login_screen.dart: without this, the
                      // BoxShadow's blur gets redone every frame of the
                      // keyboard's open/close animation even though this
                      // card's own content isn't changing.
                      child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 20,
                            color: Colors.black.withValues(alpha: .1),
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
                            'Email Address (Optional)', 
                            _emailCtrl,
                            hint: 'you@email.com',
                            type: TextInputType.emailAddress,
                            icon: Icons.mail_outline,
                            // Email is optional — patients without one
                            // (older patients especially) must still be
                            // able to register with just a phone number.
                            // Only validate the FORMAT when something was
                            // actually typed.
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final email = v.trim();
                              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
                              return ok ? null : 'Please enter a valid email address.';
                            },
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

                          _genderField(),
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
                              if (!_passRegex.hasMatch(v)) return 'Password does not meet the requirements below.';
                              return null;
                            }
                          ),
                          // Hidden until the user actually starts typing a
                          // password — showing 5 unmet requirements on an
                          // empty field just reads as clutter before
                          // there's anything to check against.
                          if (_passCtrl.text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _passwordChecklist(),
                          ],
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

                          // Terms and Conditions Widget Block — the checkbox
                          // is disabled and greyed out until the user has
                          // actually reached the bottom of both required
                          // documents via PolicyViewerScreen (item 2/3);
                          // tapping the link text is what opens that screen,
                          // not an alternate route to skip it. The "(tap to
                          // read)" hint and the "please read first" line are
                          // both held back until the user actually tries to
                          // proceed without having read them yet
                          // (_showPolicyHint, set in _proceedToOtp) — showing
                          // either one unconditionally from the very start
                          // of the form reads as a warning before the user
                          // has done anything wrong.
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: _checkboxLeadWidth,
                                    child: Checkbox(
                                      value: _agreed,
                                      activeColor: AppColors.primary,
                                      side: BorderSide(color: _agreedError ? Colors.red : Colors.grey.shade400, width: 1.5),
                                      onChanged: !_hasReadPolicies ? null : (v) {
                                        setState(() {
                                          _agreed = v ?? false;
                                          if (_agreed) _agreedError = false;
                                        });
                                      },
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (!_hasReadPolicies) {
                                          _openPolicyViewer();
                                          return;
                                        }
                                        setState(() {
                                          _agreed = !_agreed;
                                          if (_agreed) _agreedError = false;
                                        });
                                      },
                                      child: Text.rich(TextSpan(children: [
                                        const TextSpan(
                                          text: 'I agree to the ',
                                          style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                                        ),
                                        TextSpan(
                                          text: 'Terms of Service and Privacy Policy',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                            decoration: _hasReadPolicies ? null : TextDecoration.underline,
                                          ),
                                        ),
                                        if (!_hasReadPolicies && _showPolicyHint)
                                          const TextSpan(
                                            text: '  (tap to read)',
                                            style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                                          ),
                                      ])),
                                    ),
                                  ),
                                ],
                              ),
                              if (!_hasReadPolicies && _showPolicyHint)
                                Padding(
                                  padding: const EdgeInsets.only(left: _checkboxLeadWidth, top: 2),
                                  child: const Text(
                                    'Please read the Terms & Agreements and Privacy Policy first.',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ),
                              if (_agreedError)
                                Padding(
                                  padding: const EdgeInsets.only(left: _checkboxLeadWidth, top: 4),
                                  child: const Text(
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
                    ), // closes RepaintBoundary wrapping the card above
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
        borderSide: const BorderSide(color: AppColors.border),
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

  Widget _genderField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Gender'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        // 'value' is deprecated in favor of 'initialValue' — safe swap
        // here since _gender is only ever set via this dropdown's own
        // onChanged, never reset from elsewhere.
        initialValue: _gender,
        isExpanded: true,
        validator: (v) => (v == null || v.isEmpty) ? 'Please select your gender.' : null,
        decoration: _inputDeco(hint: 'Select gender', icon: Icons.wc_outlined),
        items: const [
          DropdownMenuItem(value: 'Male', child: Text('Male', style: TextStyle(fontSize: 13))),
          DropdownMenuItem(value: 'Female', child: Text('Female', style: TextStyle(fontSize: 13))),
        ],
        onChanged: (v) => setState(() => _gender = v),
      ),
    ]);
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

  // Live checklist (item 5) — each row flips satisfied/unsatisfied as the
  // user types, driven by _updatePasswordChecklist's listener on _passCtrl.
  Widget _passwordChecklist() {
    Widget row(bool met, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Icon(
              met ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: met ? const Color(0xFF16A34A) : Colors.grey.shade400,
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
                fontSize: 11.5,
                color: met ? const Color(0xFF16A34A) : AppColors.textMuted,
                fontWeight: met ? FontWeight.w600 : FontWeight.w400)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(_pwHasLength, 'At least 8 characters'),
        row(_pwHasUpper, 'One uppercase letter'),
        row(_pwHasLower, 'One lowercase letter'),
        row(_pwHasNumber, 'One number'),
        row(_pwHasSpecial, 'One special character'),
      ]),
    );
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