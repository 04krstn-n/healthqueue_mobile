import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Refresh profile data from server on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshProfile());
  }

  Future<void> _refreshProfile() async {
    setState(() => _isRefreshing = true);
    try {
      await context.read<AppState>().refreshProfile();
    } catch (_) {}
    if (mounted) setState(() => _isRefreshing = false);
  }

  String _initials(String name) {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return 'U';
    return p.length == 1
        ? p.first[0].toUpperCase()
        : (p.first[0] + p.last[0]).toUpperCase();
  }

  void _logout() {
    context.read<AppState>().logout();
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
Widget build(BuildContext context) {
  final appState = context.watch<AppState>();
  final user = appState.currentUser;

  if (user == null) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_outline,
              size: 52,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Not logged in',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.login,
                (_) => false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go to Login'),
            ),
          ],
        ),
      ),
    );
  }

  return Scaffold(
    backgroundColor: const Color(0xFFF6F7FB),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      title: const Text(
        'Profile',
        style: TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => _Sheet(
                title: 'Edit Profile',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionRow(
                      icon: Icons.person_outline,
                      label: 'Edit Personal Information',
                      onTap: () {
                        Navigator.pop(context);
                        _showEditPersonal(context, appState);
                      },
                    ),
                    _ActionRow(
                      icon: Icons.medical_information_outlined,
                      label: 'Edit Medical Information',
                      onTap: () {
                        Navigator.pop(context);
                        _showEditMedical(context, appState);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
          child: const Text(
            'Edit Profile',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refreshProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        child: Column(
          children: [
            // BLUE PROFILE CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white.withOpacity(0.18),
                    child: Text(
                      _initials(user.fullName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    user.fullName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    user.patientType.isNotEmpty
                        ? user.patientType
                        : 'Regular Patient',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Age derived from DOB (server-computed)
                  if (user.age.isNotEmpty)
                    _MiniInfoCard(
                      label: 'Age',
                      value: user.age,
                    ),

                  if (_isRefreshing) ...[
                    const SizedBox(height: 14),
                    const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),

            // PROFILE DETAILS (renamed from Contact Information)
            _SectionCard(
              title: 'Profile Details',
              icon: Icons.person_pin_outlined,
              onEdit: () => _showEditPersonal(context, appState),
              children: [
                _InfoRow(
                  label: 'Phone',
                  value: user.phone.isNotEmpty ? user.phone : '—',
                ),
                _InfoRow(
                  label: 'Email',
                  value: user.email.isNotEmpty ? user.email : '—',
                ),
                _InfoRow(
                  label: 'Date of Birth',
                  value: user.dob.year > 1900
                      ? '${user.dob.day.toString().padLeft(2, '0')}/${user.dob.month.toString().padLeft(2, '0')}/${user.dob.year}'
                      : '—',
                ),
                _InfoRow(
                  label: 'Patient Type',
                  value: user.patientType.isNotEmpty ? user.patientType : 'Regular',
                ),
              ],
            ),

            const SizedBox(height: 14),

            // SETTINGS
            _SectionCard(
              title: 'Preferences & Settings',
              icon: Icons.settings_outlined,
              onEdit: null,
              children: [
                _ActionRow(
                  icon: Icons.notifications_outlined,
                  label: 'Notification Preferences',
                  onTap: () =>
                      _showNotifPrefs(context),
                ),
                _ActionRow(
                  icon: Icons.lock_reset_rounded,
                  label: 'Change Password',
                  onTap: () =>
                      _showChangePassword(context),
                ),
                _ActionRow(
                  icon: Icons.delete_outline_rounded,
                  label: 'Deactivate Account',
                  color: Colors.red,
                  onTap: () =>
                      _confirmDeactivate(context),
                ),
              ],
            ),

            const SizedBox(height: 26),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(
                    color: Colors.red,
                  ),
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      14,
                    ),
                  ),
                ),
                onPressed: _logout,
                icon: const Icon(
                  Icons.logout_rounded,
                ),
                label: const Text(
                  'Log Out',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  // ── Edit Personal Info sheet ──────────────────────────────────────────────
  void _showEditPersonal(BuildContext ctx, AppState appState) {
    final u          = appState.currentUser!;
    final nameCtrl   = TextEditingController(text: u.fullName);
    final phoneCtrl  = TextEditingController(text: u.phone);
    final ageCtrl    = TextEditingController(text: u.age);
    bool saving = false;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSt) => _Sheet(
          title: 'Edit Personal Info',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Field(ctrl: nameCtrl,  label: 'Full Name',    icon: Icons.person_outline),
            _Field(ctrl: phoneCtrl, label: 'Phone Number', icon: Icons.phone_outlined,
                type: TextInputType.phone),
            _Field(ctrl: ageCtrl,   label: 'Age',          icon: Icons.cake_outlined,
                type: TextInputType.number),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                setSt(() => saving = true);
                try {
                  await appState.updateCurrentUserProfile(
                    fullName: nameCtrl.text.trim(),
                    phone:    phoneCtrl.text.trim(),
                    age:      ageCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(sheetCtx);
                  _snack(ctx, 'Personal info updated!');
                } catch (e) {
                  _snack(ctx, 'Error: $e', error: true);
                } finally { setSt(() => saving = false); }
              },
              child: saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Edit Medical Info sheet ───────────────────────────────────────────────
  void _showEditMedical(BuildContext ctx, AppState appState) {
    final u             = appState.currentUser!;
    final philCtrl      = TextEditingController(text: u.philHealthNumber);
    final hmoCtrl       = TextEditingController(text: u.hmoNumber);
    String patientType  = u.patientType.isNotEmpty ? u.patientType : 'Regular';
    bool saving = false;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSt) => _Sheet(
          title: 'Edit Medical Info',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Patient type selector
            const Align(alignment: Alignment.centerLeft,
                child: Text('Patient Type',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 13, color: AppColors.textDark))),
            const SizedBox(height: 8),
            Row(children: ['Regular', 'Senior', 'PWD', 'Priority'].map((t) {
              final sel = patientType == t;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setSt(() => patientType = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sel ? AppColors.primary : Colors.transparent),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            color: sel ? Colors.white : AppColors.textDark,
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
              );
            }).toList()),
            const SizedBox(height: 14),
            _Field(ctrl: philCtrl, label: 'PhilHealth Number', icon: Icons.badge_outlined),
            _Field(ctrl: hmoCtrl,  label: 'HMO Number',        icon: Icons.health_and_safety_outlined),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                setSt(() => saving = true);
                try {
                  await appState.updateCurrentUserProfile(
                    patientType:      patientType,
                    philHealthNumber: philCtrl.text.trim(),
                    hmoNumber:        hmoCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(sheetCtx);
                  _snack(ctx, 'Medical info updated!');
                } catch (e) {
                  _snack(ctx, 'Error: $e', error: true);
                } finally { setSt(() => saving = false); }
              },
              child: saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Notification Preferences sheet ───────────────────────────────────────
  void _showNotifPrefs(BuildContext ctx) {
    bool queueUpdates   = true;
    bool apptReminders  = true;
    bool promotions     = false;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSt) => _Sheet(
          title: 'Notification Preferences',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ToggleRow(
              label: 'Queue Position Updates',
              subtitle: 'Get notified when your queue moves',
              value: queueUpdates,
              onChanged: (v) => setSt(() => queueUpdates = v),
            ),
            _ToggleRow(
              label: 'Appointment Reminders',
              subtitle: 'Reminders before your appointments',
              value: apptReminders,
              onChanged: (v) => setSt(() => apptReminders = v),
            ),
            _ToggleRow(
              label: 'Promotions & Announcements',
              subtitle: 'Health tips and clinic announcements',
              value: promotions,
              onChanged: (v) => setSt(() => promotions = v),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                Navigator.pop(sheetCtx);
                _snack(ctx, 'Notification preferences saved!');
              },
              child: const Text('Save Preferences',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Change Password sheet ─────────────────────────────────────────────────
  void _showChangePassword(BuildContext ctx) {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving       = false;
    String? error;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSt) => _Sheet(
          title: 'Change Password',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Field(ctrl: currentCtrl, label: 'Current Password',
                icon: Icons.lock_outline, obscure: true),
            _Field(ctrl: newCtrl,     label: 'New Password',
                icon: Icons.lock_reset_rounded, obscure: true),
            _Field(ctrl: confirmCtrl, label: 'Confirm New Password',
                icon: Icons.lock_reset_rounded, obscure: true),
            if (error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12))),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: saving ? null : () async {
                final cur = currentCtrl.text.trim();
                final nw  = newCtrl.text.trim();
                final cnf = confirmCtrl.text.trim();
                if (cur.isEmpty || nw.isEmpty || cnf.isEmpty) {
                  setSt(() => error = 'Please fill in all fields.');
                  return;
                }
                if (nw.length < 6) {
                  setSt(() => error = 'New password must be at least 6 characters.');
                  return;
                }
                if (nw != cnf) {
                  setSt(() => error = 'New passwords do not match.');
                  return;
                }
                setSt(() { saving = true; error = null; });
                try {
                  await ApiService.updatePassword(
                      currentPassword: cur, newPassword: nw);
                  if (ctx.mounted) Navigator.pop(sheetCtx);
                  _snack(ctx, 'Password changed successfully!');
                } catch (e) {
                  setSt(() => error = e.toString().replaceAll('Exception: ', ''));
                } finally { setSt(() => saving = false); }
              },
              child: saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Update Password',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Deactivate account ────────────────────────────────────────────────────
  void _confirmDeactivate(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate Account',
            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
        content: const Text(
          'Are you sure? Your account will be deactivated and you will be logged out. Contact support to reactivate.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext ctx, String msg, {bool error = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green.shade600,
    ));
  }
}

// ── Reusable sheet widgets ────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  final String title; final Widget child;
  const _Sheet({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99))),
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft,
            child: Text(title, style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.textDark))),
        const SizedBox(height: 18),
        child,
      ]),
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? type;
  final bool obscure;
  const _Field({required this.ctrl, required this.label, required this.icon,
      this.type, this.obscure = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final void Function(bool) onChanged;
  const _ToggleRow({required this.label, required this.subtitle,
      required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700,
            fontSize: 13, color: AppColors.textDark)),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final String title; final IconData icon;
  final VoidCallback? onEdit; final List<Widget> children;
  const _SectionCard({required this.title, required this.icon,
      required this.onEdit, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
    ),
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textDark))),
          if (onEdit != null)
            TextButton(onPressed: onEdit,
                child: const Text('Edit',
                    style: TextStyle(color: AppColors.primary,
                        fontWeight: FontWeight.w700, fontSize: 12))),
        ]),
      ),
      const Divider(height: 1, color: AppColors.border),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(children: children),
      ),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120,
          child: Text(label, style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: const TextStyle(
          fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textDark))),
    ]),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final Color? color;
  const _ActionRow({required this.icon, required this.label,
      required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 13, color: c))),
          Icon(Icons.chevron_right_rounded, color: c.withOpacity(0.5), size: 18),
        ]),
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  final String label;
  final String value;

  const _MiniInfoCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.15),
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color:
                  Colors.white.withOpacity(
                .8,
              ),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}