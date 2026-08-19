import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// PillToggle — supports two calling conventions:
///
/// A) Login style (original):
///   PillToggle(isEmail: true, onEmail: () {}, onPhone: () {})
///
/// B) Register style (new):
///   PillToggle(left: 'Email', right: 'Phone', activeLeft: true, onToggle: (v) {})
class PillToggle extends StatelessWidget {
  // Convention A
  final bool?          isEmail;
  final VoidCallback?  onEmail;
  final VoidCallback?  onPhone;

  // Convention B
  final String?         left;
  final String?         right;
  final bool?           activeLeft;
  final void Function(bool)? onToggle;

  const PillToggle({
    super.key,
    // A
    this.isEmail,
    this.onEmail,
    this.onPhone,
    // B
    this.left,
    this.right,
    this.activeLeft,
    this.onToggle,
  });

  // Resolved values
  bool   get _leftActive => activeLeft ?? isEmail ?? true;
  String get _leftLabel  => left  ?? 'Email';
  String get _rightLabel => right ?? 'Phone';

  void _onLeft()  { onEmail?.call(); onToggle?.call(true);  }
  void _onRight() { onPhone?.call(); onToggle?.call(false); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _Pill(
            label:  _leftLabel,
            active: _leftActive,
            onTap:  _onLeft,
          )),
          const SizedBox(width: 6),
          Expanded(child: _Pill(
            label:  _rightLabel,
            active: !_leftActive,
            onTap:  _onRight,
          )),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: active ? [BoxShadow(
          color: Colors.black.withOpacity(.08),
          blurRadius: 4, offset: const Offset(0, 2),
        )] : [],
      ),
      child: Center(
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: active ? AppColors.primary : const Color(0xFF6B7280),
        )),
      ),
    ),
  );
}
