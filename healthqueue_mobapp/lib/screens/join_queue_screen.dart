import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../core/constants/app_colors.dart';
import '../services/clinic_service.dart';
import '../services/api_service.dart';
import '../models/queue_models.dart';

class JoinQueueScreen extends StatefulWidget {
  const JoinQueueScreen({super.key});
  @override
  State<JoinQueueScreen> createState() => _JoinQueueScreenState();
}

class _JoinQueueScreenState extends State<JoinQueueScreen> {
  int  _step    = 1;
  bool _loading = false;
  bool _didArgs = false;

  List<Clinic> _clinics  = [];
  Clinic?      _clinic;
  String?      _service;
  PatientType  _pType    = PatientType.regular;
  final _notesCtrl = TextEditingController();

  @override
  void initState()            { super.initState(); _loadClinics(); }
  @override
  void dispose()              { _notesCtrl.dispose(); super.dispose(); }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didArgs) return;
    _didArgs = true;

    // ── Read pre-selected clinic passed as route argument from dashboard/map ──
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Clinic) {
      _clinic = args;
      _step   = 2;   // skip clinic picker — go straight to service selection
    }

    // ── Pre-fill patient type from logged-in user ──
    final u = context.read<AppState>().currentUser;
    if (u != null && u.patientType.isNotEmpty) {
      final map = {
        'Regular':        PatientType.regular,
        'Senior Citizen': PatientType.priority,
        'PWD':            PatientType.priority,
        'Pregnant':       PatientType.priority,
        'Priority':       PatientType.priority,
      };
      _pType = map[u.patientType] ?? PatientType.regular;
    }
  }

  Future<void> _loadClinics() async {
    setState(() => _loading = true);
    try {
      final list = await ClinicService.getDirectory();
      if (mounted) setState(() => _clinics = list);
    } catch (e) {
      _showError('Could not load clinics. Please check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Guard: closed clinic ──────────────────────────────────────────────────
  bool _isClosed(Clinic c) => c.status == 'closed' || c.status == 'maintenance';

  // ── Guard: full queue ─────────────────────────────────────────────────────
  bool _isFull(Clinic c) => c.queueLength >= c.maxQueueCapacity && c.maxQueueCapacity > 0;

  void _next() {
    if (_step == 1) {
      if (_clinic == null) { _showError('Please select a clinic.'); return; }
      if (_isClosed(_clinic!)) {
        _showError('${_clinic!.name} is currently ${_clinic!.status}. Please choose another clinic.');
        return;
      }
      if (_isFull(_clinic!)) {
        _showError('${_clinic!.name} queue is full (${_clinic!.queueLength}/${_clinic!.maxQueueCapacity}). Please try another clinic.');
        return;
      }
      setState(() => _step = 2);
      return;
    }
    if (_step == 2) {
      if (_service == null) { _showError('Please select a service.'); return; }
      setState(() => _step = 3);
    }
  }

  void _back() {
    if (_step == 1) Navigator.pop(context);
    else setState(() => _step--);
  }

  // ── Confirmation dialog ───────────────────────────────────────────────────
  Future<void> _showConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Confirm Queue', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _confirmRow('Clinic',   _clinic!.name),
          _confirmRow('Service',  _service!),
          _confirmRow('Type',     _patientTypeLabel(_pType)),
          if (_notesCtrl.text.trim().isNotEmpty)
            _confirmRow('Notes', _notesCtrl.text.trim()),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'You will be added to the live queue. Please arrive promptly when called.',
                style: TextStyle(fontSize: 11, color: Color(0xFF2563EB)),
              )),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm & Join', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _doJoin();
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );

  Future<void> _doJoin() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.joinQueue(
        clinicId:    _clinic!.id,
        serviceName: _service!,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );
      if (!mounted) return;

      // Safe-cast every response field — server may return int, double, or String
      final entry   = (res['entry'] is Map)
          ? Map<String, dynamic>.from(res['entry'] as Map)
          : <String, dynamic>{};
      final qNum    = entry['queueNumber']?.toString()
          ?? res['queueNumber']?.toString() ?? 'N/A';
      final estWait = _safeInt(
          res['estimatedWaitTime'] ?? res['estimatedWait']
          ?? entry['estimatedWaitMinutes'] ?? 0);
      final position = _safeInt(res['position'] ?? res['peopleAhead'] ?? 1);

      // Refresh queue tab BEFORE dialog so it is ready when user taps OK
      if (mounted) context.read<AppState>().fetchQueueStatus();
      await _showSuccessDialog(qNum, estWait, position);

    } on QueueConflictException catch (e) {
      // 409 — already in queue. Show info, NOT a red error.
      if (!mounted) return;
      context.read<AppState>().fetchQueueStatus();
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.info_outline, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Already in Queue', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(e.message, style: const TextStyle(fontSize: 13)),
            if (e.existingEntry != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Queue #${e.existingEntry!["queueNumber"]}',
                      style: const TextStyle(fontWeight: FontWeight.w800,
                          color: Color(0xFF2563EB), fontSize: 16)),
                  Text('Status: ${e.existingEntry!["status"]}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ],
          ]),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('View My Queue',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

    } catch (e) {
      if (!mounted) return;

      // A type-cast error in response parsing can fire AFTER the server already
      // created the queue entry. Verify before showing the error dialog.
      try {
        final status  = await ApiService.getMyQueueStatus();
        final inQueue = status['inQueue'] == true || status['entry'] != null;
        if (inQueue && mounted) {
          context.read<AppState>().fetchQueueStatus();
          final entry   = (status['entry'] is Map)
              ? Map<String, dynamic>.from(status['entry'] as Map)
              : <String, dynamic>{};
          final qNum    = entry['queueNumber']?.toString() ?? 'N/A';
          final estWait = _safeInt(
              status['estimatedWaitTime'] ?? entry['estimatedWaitMinutes'] ?? 0);
          final pos     = _safeInt(status['peopleAhead'] ?? status['position'] ?? 1);
          await _showSuccessDialog(qNum, estWait, pos);
          return;
        }
      } catch (_) { /* fall through to error dialog */ }

      final msg = e.toString().replaceAll('Exception: ', '');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Could Not Join Queue',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showSuccessDialog(String qNum, int estWait, int position) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 26),
          SizedBox(width: 8),
          Text('Joined Queue!', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          _confirmRow('Queue #',   qNum),
          _confirmRow('Clinic',    _clinic!.name),
          _confirmRow('Service',   _service!),
          _confirmRow('Position',  '#$position'),
          _confirmRow('Est. Wait', '~$estWait min'),
        ]),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, QueueJoinResult(
                queueNumber:  qNum,
                clinicName:   _clinic!.name,
                serviceName:  _service!,
                estimatedWait: estWait,
                position:     position,
                patientName:  '',
                joinedAt:     DateTime.now(),
              ));
            },
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // Safe int cast — handles double, String, null from server JSON
  int _safeInt(dynamic v) {
    if (v == null) return 0;
    if (v is int)    return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }


  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _patientTypeLabel(PatientType t) {
    const map = {
      PatientType.regular: 'Regular', PatientType.senior: 'Senior Citizen',
      PatientType.pwd: 'PWD', PatientType.pregnant: 'Pregnant', PatientType.priority: 'Priority',
    };
    return map[t] ?? 'Regular';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        foregroundColor: AppColors.textDark,
        title: Text('Join Queue — Step $_step of 3', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(), SizedBox(height: 14),
              Text('Please wait…', style: TextStyle(color: Colors.black45)),
            ]))
          : Column(children: [
              // Step progress bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(children: List.generate(3, (i) => Expanded(child: Container(
                  height: 4, margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: i < _step ? AppColors.primary : Colors.grey.shade200,
                  ),
                )))),
              ),
              Expanded(child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: [_buildStep1(), _buildStep2(), _buildStep3()][_step - 1],
              )),
              // Bottom CTA
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : (_step < 3 ? _next : _showConfirmDialog),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      _step < 3 ? 'Continue' : 'Join Queue',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }

  // ── Step 1: Choose clinic ─────────────────────────────────────────────────
  Widget _buildStep1() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Clinic', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Choose where you want to queue', style: TextStyle(fontSize: 12, color: Colors.black45)),
      const SizedBox(height: 16),
      ..._clinics.map((c) {
        final closed = _isClosed(c);
        final full   = _isFull(c);
        final unavail = closed || full;
        final selected = _clinic?.id == c.id;
        return GestureDetector(
          onTap: unavail ? null : () => setState(() => _clinic = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: unavail ? Colors.grey.shade50 : (selected ? const Color(0xFFEFF6FF) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primary : (unavail ? Colors.grey.shade200 : Colors.grey.shade100),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(color: unavail ? Colors.grey.shade100 : const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.local_hospital_outlined, size: 20, color: unavail ? Colors.grey : AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: unavail ? Colors.grey : Colors.black87))),
                  if (closed) _tag(c.status, Colors.red.shade100, Colors.red.shade700)
                  else if (full) _tag('Full', Colors.orange.shade100, Colors.orange.shade800)
                  else _tag('Open', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
                ]),
                Text(c.address, style: TextStyle(fontSize: 11, color: unavail ? Colors.grey.shade400 : Colors.black45)),
                if (!unavail) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.queue, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 3),
                    Text('${c.queueLength} in queue', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                    const SizedBox(width: 10),
                    Icon(Icons.timer_outlined, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 3),
                    Text('~${c.currentWaitingTime} min wait', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                  ]),
                ],
              ])),
              if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 22),
            ]),
          ),
        );
      }).toList(),
    ]);
  }

  Widget _tag(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: fg)),
  );

  // ── Step 2: Choose service ────────────────────────────────────────────────
  Widget _buildStep2() {
    final services = _clinic?.services.where((s) => s['isAvailable'] == true).toList() ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('${_clinic?.name ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
      const SizedBox(height: 16),
      if (services.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(32),
          child: Text('No available services', style: TextStyle(color: Colors.black38)))),
      ...services.map((s) {
        final name     = s['name'] as String? ?? '';
        final selected = _service == name;
        return GestureDetector(
          onTap: () => setState(() => _service = name),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color:  selected ? const Color(0xFFEFF6FF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.primary : Colors.grey.shade100, width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if ((s['description'] as String? ?? '').isNotEmpty)
                  Text(s['description'] as String, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                if ((s['durationMinutes'] as num? ?? 0) > 0)
                  Text('~${s['durationMinutes']} min', style: const TextStyle(fontSize: 10, color: Colors.black38)),
              ])),
              if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 22),
            ]),
          ),
        );
      }).toList(),
    ]);
  }

  // ── Step 3: Patient info + notes ──────────────────────────────────────────
  Widget _buildStep3() {
    final user = context.read<AppState>().currentUser;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Confirm Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      _reviewRow('Name',    user?.fullName ?? '—'),
      _reviewRow('Phone',   user?.phone.isNotEmpty == true ? user!.phone : '—'),
      _reviewRow('Clinic',  _clinic?.name ?? '—'),
      _reviewRow('Service', _service ?? '—'),
      const SizedBox(height: 16),
      const Text('Patient Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8,
        children: PatientType.values.map((t) {
          final sel = _pType == t;
          return GestureDetector(
            onTap: () => setState(() => _pType = t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: sel ? AppColors.primary : Colors.grey.shade200),
              ),
              child: Text(_patientTypeLabel(t),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : Colors.black54)),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      const Text('Notes (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
      const SizedBox(height: 6),
      TextField(
        controller: _notesCtrl, maxLines: 2,
        decoration: InputDecoration(
          hintText: 'e.g. first visit, doctor referral…',
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
    ]);
  }

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );
}
