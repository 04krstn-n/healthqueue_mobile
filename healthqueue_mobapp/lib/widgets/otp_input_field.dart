import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_colors.dart';

/// A proper 6-box OTP input — 6 separate 1-character fields with
/// auto-advancing focus, rather than a single TextField faking the look
/// via letterSpacing. That approach (still used nowhere else in the app
/// after this) has a well-known problem: the cursor position and the
/// digits you type don't actually line up with the hint dashes, since
/// it's really just one field with wide letter-spacing, not 6 real boxes.
class OtpInputField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  // When true, boxes render with a red border — set by the parent right
  // after a wrong-code response comes back from the server, so the error
  // is visible on the input itself (item 1: "clearly show an error when
  // the OTP is incorrect"), not only in a separate dialog the user has to
  // dismiss before they can even see which field to fix.
  final bool hasError;

  const OtpInputField({
    super.key,
    required this.controller,
    this.onCompleted,
    this.onChanged,
    this.hasError = false,
  });

  @override
  State<OtpInputField> createState() => _OtpInputFieldState();
}

class _OtpInputFieldState extends State<OtpInputField>
    with SingleTickerProviderStateMixin {
  static const _length = 6;
  late final List<TextEditingController> _boxCtrls;
  late final List<FocusNode> _boxNodes;
  bool _syncingFromController = false;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _boxCtrls = List.generate(_length, (_) => TextEditingController());
    _boxNodes = List.generate(_length, (_) => FocusNode());
    widget.controller.addListener(_syncFromExternalController);
    _syncFromExternalController();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void didUpdateWidget(OtpInputField old) {
    super.didUpdateWidget(old);
    // Rising edge only — shakes once per new error, not on every rebuild
    // while hasError happens to still be true.
    if (widget.hasError && !old.hasError) {
      _shakeCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromExternalController);
    for (final c in _boxCtrls) {
      c.dispose();
    }
    for (final n in _boxNodes) {
      n.dispose();
    }
    _shakeCtrl.dispose();
    super.dispose();
  }

  // Keeps the 6 boxes in sync if the parent screen clears/sets
  // widget.controller directly (e.g. on resend), without fighting the
  // per-box listeners below.
  void _syncFromExternalController() {
    if (_syncingFromController) return;
    final text = widget.controller.text;
    if (text.length == _length && _joinBoxes() == text) return;
    _syncingFromController = true;
    for (int i = 0; i < _length; i++) {
      _boxCtrls[i].text = i < text.length ? text[i] : '';
    }
    _syncingFromController = false;
  }

  String _joinBoxes() => _boxCtrls.map((c) => c.text).join();

  void _updateExternalController() {
    final joined = _joinBoxes();
    _syncingFromController = true;
    widget.controller.text = joined;
    _syncingFromController = false;
    widget.onChanged?.call(joined);
    if (joined.length == _length) {
      FocusScope.of(context).unfocus();
      widget.onCompleted?.call(joined);
    }
  }

  void _onBoxChanged(int index, String value) {
    // Handles pasting the full code into a single box — spreads it
    // across the remaining boxes instead of just keeping one digit.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      for (int i = 0; i < _length; i++) {
        final srcIdx = i - index;
        _boxCtrls[i].text = (srcIdx >= 0 && srcIdx < digits.length) ? digits[srcIdx] : _boxCtrls[i].text;
      }
      final lastFilled = digits.length + index - 1;
      if (lastFilled >= 0 && lastFilled < _length - 1) {
        _boxNodes[lastFilled + 1].requestFocus();
      } else {
        FocusScope.of(context).unfocus();
      }
      _updateExternalController();
      return;
    }

    if (value.isNotEmpty && index < _length - 1) {
      _boxNodes[index + 1].requestFocus();
    }
    _updateExternalController();
  }

  void _onBackspace(int index) {
    if (_boxCtrls[index].text.isEmpty && index > 0) {
      _boxNodes[index - 1].requestFocus();
      _boxCtrls[index - 1].clear();
      _updateExternalController();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        // Decaying horizontal shake: a sine wave whose amplitude falls to
        // zero by the end of the animation, rather than a hard cutoff.
        final t = _shakeCtrl.value;
        final amplitude = 8 * (1 - t);
        final offset = math.sin(t * 4 * math.pi) * amplitude;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_length, (i) {
          return SizedBox(
            width: 46,
            height: 56,
            child: KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace) {
                  _onBackspace(i);
                }
              },
              child: TextField(
                controller: _boxCtrls[i],
                focusNode: _boxNodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: _length, // allows a full pasted code to land in one box (see _onBoxChanged)
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: widget.hasError ? const Color(0xFFDC2626) : null,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: widget.hasError
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFF6F7FB),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: widget.hasError ? const Color(0xFFDC2626) : AppColors.border,
                        width: widget.hasError ? 1.4 : 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: widget.hasError ? const Color(0xFFDC2626) : AppColors.primary,
                        width: 1.5),
                  ),
                ),
                onChanged: (v) => _onBoxChanged(i, v),
              ),
            ),
          );
        }),
      ),
    );
  }
}
