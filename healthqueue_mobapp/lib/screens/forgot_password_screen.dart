import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../widgets/otp_input_field.dart';

/// Forgot Password flow: phone -> OTP (via Semaphore, same as registration)
/// -> new password. Matches register_screen.dart's visual style and OTP-step
/// pattern (countdown, resend cooldown, attempt limit) for consistency.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // 0 = enter phone, 1 = enter OTP, 2 = new password, 3 = done
  int _step = 0;
  bool _busy = false;

  final _phoneCtrl    = TextEditingController();
  final _otpCtrl      = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _showPass    = false;
  bool _showConfirm = false;

  String? _resetId;
  String? _resetToken;

  DateTime? _otpExpiry;
  int _otpResendCooldown = 0;
  int _otpAttempts = 0;
  Timer? _otpTimer;

  static const _otpValidSeconds    = 300; // matches server's 5-minute OTP expiry
  static const _resendCooldownSecs = 30;
  static const _maxOtpAttempts     = 3;

  final _phoneRegex = RegExp(r'^(09|\+639)\d{9}$');
  final _passRegex  = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$');

  @override
  void dispose() {
    _otpTimer?.cancel();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

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

  bool get _otpExpired =>
      _otpExpiry != null && DateTime.now().isAfter(_otpExpiry!);

  int get _otpSecondsLeft =>
      _otpExpiry == null ? 0
      : _otpExpiry!.difference(DateTime.now()).inSeconds.clamp(0, _otpValidSeconds);

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

  // Shows devOtp when SMS isn't configured/failed — same pattern as
  // register_screen.dart, so the flow stays testable without real SMS.
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

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || !_phoneRegex.hasMatch(phone)) {
      await _showErrorDialog('Invalid Phone Number',
          'Please enter a valid phone number (09XXXXXXXXX).');
      return;
    }

    setState(() => _busy = true);
    try {
      final data = await context.read<AppState>().requestPasswordReset(phone);
      final resetId = data['resetId']?.toString();
      if (resetId == null || resetId.isEmpty) {
        throw Exception('Something went wrong. Please try again.');
      }
      setState(() {
        _resetId = resetId;
        _step = 1;
        _otpAttempts = 0;
        _otpExpiry = DateTime.now().add(const Duration(seconds: _otpValidSeconds));
      });
      _otpCtrl.clear();
      _startCooldown();
      if (mounted) _showOtpStatus(data);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      await _showErrorDialog('Could Not Send Code', msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    if (_otpResendCooldown > 0) return;
    _otpAttempts = 0;
    _otpCtrl.clear();
    setState(() => _busy = true);
    try {
      final data = await context.read<AppState>().requestPasswordReset(_phoneCtrl.text.trim());
      setState(() => _otpExpiry =
          DateTime.now().add(const Duration(seconds: _otpValidSeconds)));
      _startCooldown();
      if (mounted) _showOtpStatus(data);
    } catch (e) {
      if (mounted) {
        await _showErrorDialog('Code Not Sent',
            e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_otpExpired) {
      await _showErrorDialog('Code Expired', 'Your code has expired. Please request a new one.');
      return;
    }
    if (_otpAttempts >= _maxOtpAttempts) {
      await _showErrorDialog('Too Many Attempts', 'Maximum attempts reached. Please resend the code.');
      return;
    }
    if (_otpCtrl.text.trim().length != 6) {
      await _showErrorDialog('Invalid Code', 'Enter the 6-digit code sent to your phone.');
      return;
    }
    if (_resetId == null) return;

    setState(() => _busy = true);
    try {
      final data = await context.read<AppState>()
          .verifyPasswordResetOtp(_resetId!, _otpCtrl.text.trim());
      final token = data['resetToken']?.toString();
      if (token == null || token.isEmpty) {
        throw Exception('Something went wrong. Please try again.');
      }
      setState(() {
        _resetToken = token;
        _step = 2;
      });
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.toLowerCase().contains('expired')) {
        setState(() => _otpExpiry = DateTime.now().subtract(const Duration(seconds: 1)));
        await _showErrorDialog('Code Expired', 'Your code has expired. Please request a new one.');
        return;
      }
      _otpAttempts++;
      final left = _maxOtpAttempts - _otpAttempts;
      await _showErrorDialog('Incorrect Code', left > 0
          ? 'Incorrect code. $left attempt${left == 1 ? "" : "s"} remaining.'
          : 'No attempts left. Please resend the code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitNewPassword() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (!_passRegex.hasMatch(pass)) {
      await _showErrorDialog('Weak Password',
          'Password must contain 8+ characters, uppercase, lowercase, numbers & symbols.');
      return;
    }
    if (pass != confirm) {
      await _showErrorDialog('Passwords Do Not Match', 'Please make sure both passwords match.');
      return;
    }
    if (_resetId == null || _resetToken == null) return;

    setState(() => _busy = true);
    try {
      await context.read<AppState>().confirmPasswordReset(
        resetId: _resetId!,
        resetToken: _resetToken!,
        newPassword: pass,
      );
      if (!mounted) return;
      setState(() => _step = 3);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      await _showErrorDialog('Could Not Reset Password', msg);
    } finally {
      if (mounted) setState(() => _busy = false);
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
                  if (_step != 3) ...[
                    const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 56),
                    const SizedBox(height: 14),
                    const Text('Reset Password',
                        style: TextStyle(color: Colors.white, fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 32),
                  ],
                  Container(
                    padding: const EdgeInsets.all(24),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                          blurRadius: 20, color: Colors.black.withValues(alpha: .1))],
                    ),
                    child: switch (_step) {
                      0 => _phoneStep(),
                      1 => _otpStep(),
                      2 => _newPasswordStep(),
                      _ => _doneStep(),
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_step != 3)
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to Login',
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

  Widget _phoneStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Forgot your password?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      const SizedBox(height: 6),
      const Text('Enter your registered phone number and we\'ll send you a verification code.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
      const SizedBox(height: 20),
      _label('Phone Number'),
      const SizedBox(height: 6),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        onSubmitted: (_) => _sendCode(),
        decoration: _inputDeco(hint: '09XXXXXXXXX', icon: Icons.phone_outlined),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _sendCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Send Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }

  Widget _otpStep() {
    final left = _otpSecondsLeft;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Enter the 6-digit code sent to\n${_phoneCtrl.text.trim()}',
          style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5)),
      const SizedBox(height: 20),
      Text(
        _otpExpired ? 'Code has expired' : 'Expires in ${left}s',
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
          color: _otpExpired ? Colors.red : left < 30 ? Colors.orange : AppColors.primary,
          minHeight: 3,
        ),
      ),
      const SizedBox(height: 18),
      OtpInputField(
        controller: _otpCtrl,
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 12),
      Center(child: _otpResendCooldown > 0
          ? Text('Resend in ${_otpResendCooldown}s',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500))
          : TextButton(
              onPressed: _busy ? null : _resendCode,
              child: const Text('Resend Code', style: TextStyle(fontWeight: FontWeight.w700)))),
    ]);
  }

  Widget _newPasswordStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Create New Password',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      const SizedBox(height: 6),
      const Text('Choose a strong password for your account.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      const SizedBox(height: 20),
      _label('New Password'),
      const SizedBox(height: 6),
      TextField(
        controller: _passCtrl,
        obscureText: !_showPass,
        decoration: _inputDeco(
          hint: '••••••••',
          icon: Icons.lock_outline,
          suffix: IconButton(
            icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20, color: AppColors.textMuted),
            onPressed: () => setState(() => _showPass = !_showPass),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _label('Confirm New Password'),
      const SizedBox(height: 6),
      TextField(
        controller: _confirmCtrl,
        obscureText: !_showConfirm,
        onSubmitted: (_) => _submitNewPassword(),
        decoration: _inputDeco(
          hint: '••••••••',
          icon: Icons.lock_outline,
          suffix: IconButton(
            icon: Icon(_showConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20, color: AppColors.textMuted),
            onPressed: () => setState(() => _showConfirm = !_showConfirm),
          ),
        ),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _submitNewPassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Reset Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }

  Widget _doneStep() {
    return Column(children: [
      const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 56),
      const SizedBox(height: 16),
      const Text('Password Reset!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      const SizedBox(height: 6),
      const Text('Your password has been updated. You can now log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.login, (route) => false),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Back to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted));

  InputDecoration _inputDeco({required String hint, required IconData icon, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      );
}
