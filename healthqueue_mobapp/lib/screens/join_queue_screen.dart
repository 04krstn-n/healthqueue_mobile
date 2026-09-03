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
  int _step = 1;
  bool _loading = false;
  bool _didArgs = false;
  // True only when a clinic arrived pre-selected via route arguments (e.g.
  // from Find Clinics / the dashboard) — distinct from _clinic being
  // non-null, which also happens after a normal in-flow selection in step
  // 1. In the pre-selected case, "Select Clinic" was already done before
  // this screen even opened, so it shouldn't count as a step here.
  // _minStep is the lowest _step this flow can ever reach; display
  // numbering and the back button are both relative to it.
  bool _clinicPreSelected = false;
  int get _minStep => _clinicPreSelected ? 2 : 1;
  int get _totalDisplaySteps => 3 - _minStep + 1;
  int get _displayStep => _step - _minStep + 1;

  List<Clinic> _clinics = [];
  Clinic? _clinic;
  String? _service;

  PatientType _pType = PatientType.regular;

  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didArgs) return;

    _didArgs = true;

    // ------------------------------------------------------------
    // Read pre-selected clinic from dashboard/map
    // ------------------------------------------------------------
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Clinic) {
      _clinic = args;
      _step = 2;
      _clinicPreSelected = true;
    }

    // ------------------------------------------------------------
    // Pre-fill patient type
    // ------------------------------------------------------------
    final user = context.read<AppState>().currentUser;

    if (user != null && user.patientType.isNotEmpty) {
      final map = {
        'Regular': PatientType.regular,
        'Senior Citizen': PatientType.priority,
        'PWD': PatientType.priority,
        'Pregnant': PatientType.priority,
        'Priority': PatientType.priority,
      };

      _pType = map[user.patientType] ?? PatientType.regular;
    }
  }

  // ==============================================================
  // LOAD CLINICS
  // ==============================================================

  Future<void> _loadClinics() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final list = await ClinicService.getDirectory();

      if (!mounted) return;

      setState(() {
        _clinics = list;
      });
    } catch (e) {
      if (mounted) {
        _showError(
          'Could not load clinics. Please check your connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ==============================================================
  // CLINIC GUARDS
  // ==============================================================

  bool _isClosed(Clinic c) {
    return c.status == 'closed' || c.status == 'maintenance';
  }

  bool _isFull(Clinic c) {
    return c.queueLength >= c.maxQueueCapacity && c.maxQueueCapacity > 0;
  }

  // ==============================================================
  // NEXT
  // ==============================================================

  void _next() {
    if (_step == 1) {
      if (_clinic == null) {
        _showError('Please select a clinic.');
        return;
      }

      if (_isClosed(_clinic!)) {
        _showError(
          '${_clinic!.name} is currently ${_clinic!.status}. '
          'Please choose another clinic.',
        );
        return;
      }

      if (_isFull(_clinic!)) {
        _showError(
          '${_clinic!.name} queue is full '
          '(${_clinic!.queueLength}/${_clinic!.maxQueueCapacity}). '
          'Please try another clinic.',
        );
        return;
      }

      setState(() => _step = 2);
      return;
    }

    if (_step == 2) {
      if (_service == null || _service!.trim().isEmpty) {
        _showError('Please select a service.');
        return;
      }

      setState(() => _step = 3);
    }
  }

  // ==============================================================
  // BACK
  // ==============================================================

  void _back() {
    if (_loading) return;

    if (_step <= _minStep) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  // ==============================================================
  // CONFIRMATION DIALOG
  // ==============================================================

  Future<void> _showConfirmDialog() async {
    if (_clinic == null || _service == null) {
      _showError('Please complete all required fields.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Confirm Queue',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow(
              'Clinic',
              _clinic!.name,
            ),
            _confirmRow(
              'Service',
              _service!,
            ),
            _confirmRow(
              'Type',
              _patientTypeLabel(_pType),
            ),
            if (_notesCtrl.text.trim().isNotEmpty)
              _confirmRow(
                'Notes',
                _notesCtrl.text.trim(),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will be added to the live queue. '
                      'Please arrive promptly when called.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Confirm & Join',
              style: TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _doJoin();
    }
  }

  // ==============================================================
  // CONFIRM ROW
  // ==============================================================

  Widget _confirmRow(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // JOIN QUEUE
  // ==============================================================

  Future<void> _doJoin() async {
    if (_loading) return;

    if (_clinic == null) {
      _showError('Please select a clinic.');
      return;
    }

    if (_service == null || _service!.trim().isEmpty) {
      _showError('Please select a service.');
      return;
    }

    setState(() {
      _loading = true;
    });

    final appState = context.read<AppState>();
    final user = appState.currentUser;

    try {
      // ----------------------------------------------------------
      // 1. CREATE QUEUE ENTRY ON SERVER
      // ----------------------------------------------------------

      final res = await ApiService.joinQueue(
        clinicId: _clinic!.id,
        serviceName: _service!,
        notes:
            _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );

      if (!mounted) return;

      // ----------------------------------------------------------
      // 2. READ ENTRY FROM RESPONSE
      // ----------------------------------------------------------

      Map<String, dynamic> entry = {};

      if (res['entry'] is Map) {
        entry = Map<String, dynamic>.from(
          res['entry'] as Map,
        );
      }

      String entryId = entry['_id']?.toString() ??
          entry['id']?.toString() ??
          res['_id']?.toString() ??
          res['entryId']?.toString() ??
          res['id']?.toString() ??
          '';

      String queueNumber = entry['queueNumber']?.toString() ??
          entry['queueNo']?.toString() ??
          res['queueNumber']?.toString() ??
          res['queueNo']?.toString() ??
          res['queue_number']?.toString() ??
          'N/A';

      int estimatedWait = _safeInt(
        entry['estimatedWaitTime'] ??
            entry['estimatedWaitMinutes'] ??
            entry['estimatedWait'] ??
            res['estimatedWaitTime'] ??
            res['estimatedWaitMinutes'] ??
            res['estimatedWait'] ??
            0,
      );

      int position = _safeInt(
        entry['position'] ??
            entry['peopleAhead'] ??
            res['position'] ??
            res['peopleAhead'] ??
            1,
      );

      // ----------------------------------------------------------
      // 3. GET ACTUAL QUEUE FROM SERVER
      //
      // This is important because the join response may not
      // contain all the information needed by AppState.
      // ----------------------------------------------------------

      try {
        final status = await ApiService.getMyQueueStatus();

        if (status is Map) {
          final statusMap = Map<String, dynamic>.from(
            status as Map,
          );

          Map<String, dynamic> serverEntry = {};

          if (statusMap['entry'] is Map) {
            serverEntry = Map<String, dynamic>.from(
              statusMap['entry'] as Map,
            );
          } else if (statusMap['queue'] is Map) {
            serverEntry = Map<String, dynamic>.from(
              statusMap['queue'] as Map,
            );
          }

          if (serverEntry.isNotEmpty) {
            entry = serverEntry;

            entryId = serverEntry['_id']?.toString() ??
                serverEntry['id']?.toString() ??
                entryId;

            queueNumber = serverEntry['queueNumber']?.toString() ??
                serverEntry['queueNo']?.toString() ??
                queueNumber;

            estimatedWait = _safeInt(
              statusMap['estimatedWaitTime'] ??
                  statusMap['estimatedWaitMinutes'] ??
                  statusMap['estimatedWait'] ??
                  serverEntry['estimatedWaitTime'] ??
                  serverEntry['estimatedWaitMinutes'] ??
                  serverEntry['estimatedWait'] ??
                  estimatedWait,
            );

            position = _safeInt(
              statusMap['position'] ??
                  statusMap['peopleAhead'] ??
                  serverEntry['position'] ??
                  serverEntry['peopleAhead'] ??
                  position,
            );
          }
        }
      } catch (_) {
        // The queue was already created.
        // Do not turn a successful join into an error.
      }

      // ----------------------------------------------------------
      // 4. CREATE LOCAL QUEUE RESULT
      // ----------------------------------------------------------

      final result = QueueJoinResult(
        id: entryId,
        entryId: entryId,
        queueNumber: queueNumber,
        clinicId: _clinic!.id,
        clinicName: _clinic!.name,
        serviceName: _service!,
        patientName: user?.fullName ?? '',
        patientEmail: user?.email,
        patientPhone: user?.phone,
        position: position,
        totalAhead: position,
        estimatedWait: estimatedWait,
        estimatedWaitTimeMinutes: estimatedWait,
        joinedAt: DateTime.now(),
      );

      // ----------------------------------------------------------
      // 5. SAVE QUEUE TO APP STATE
      // ----------------------------------------------------------

      appState.addQueueFromJoinResult(result);

      // ----------------------------------------------------------
      // 6. REFRESH APP STATE FROM SERVER
      // ----------------------------------------------------------

      try {
        await appState.fetchQueueStatus();
      } catch (_) {
        // Local result was already saved.
      }

      if (!mounted) return;

      // ----------------------------------------------------------
      // 7. SHOW SUCCESS ONCE ONLY
      // ----------------------------------------------------------

      await _showSuccessDialog(
        queueNumber,
        estimatedWait,
        position,
      );
    }

    // ============================================================
    // ALREADY IN QUEUE
    // ============================================================

    on QueueConflictException catch (e) {
      if (!mounted) return;

      try {
        await appState.fetchQueueStatus();
      } catch (_) {}

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Color(0xFF2563EB),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Already in Queue',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.message,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
              if (e.existingEntry != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Queue #${e.existingEntry!["queueNumber"] ?? "N/A"}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2563EB),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Status: ${e.existingEntry!["status"] ?? "Waiting"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text(
                'View My Queue',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ============================================================
    // OTHER ERROR
    // ============================================================

    catch (e) {
      if (!mounted) return;

      // ----------------------------------------------------------
      // IMPORTANT FALLBACK:
      // Sometimes the backend creates the queue successfully,
      // but the Flutter response parsing fails.
      //
      // Check the server before telling the user that joining
      // failed.
      // ----------------------------------------------------------

      bool serverHasQueue = false;

      Map<String, dynamic> serverEntry = {};

      try {
        final status = await ApiService.getMyQueueStatus();

        if (status is Map) {
          final statusMap = Map<String, dynamic>.from(
            status as Map,
          );

          serverHasQueue = statusMap['inQueue'] == true ||
              statusMap['entry'] != null ||
              statusMap['queue'] != null;

          if (statusMap['entry'] is Map) {
            serverEntry = Map<String, dynamic>.from(
              statusMap['entry'] as Map,
            );
          } else if (statusMap['queue'] is Map) {
            serverEntry = Map<String, dynamic>.from(
              statusMap['queue'] as Map,
            );
          }
        }
      } catch (_) {
        serverHasQueue = false;
      }

      // ----------------------------------------------------------
      // SERVER SAYS USER IS IN QUEUE
      // ----------------------------------------------------------

      if (serverHasQueue && mounted) {
        try {
          await appState.fetchQueueStatus();
        } catch (_) {}

        if (!mounted) return;

        final queueNumber = serverEntry['queueNumber']?.toString() ??
            serverEntry['queueNo']?.toString() ??
            'N/A';

        final estimatedWait = _safeInt(
          serverEntry['estimatedWaitTime'] ??
              serverEntry['estimatedWaitMinutes'] ??
              serverEntry['estimatedWait'] ??
              0,
        );

        final position = _safeInt(
          serverEntry['position'] ?? serverEntry['peopleAhead'] ?? 1,
        );

        await _showSuccessDialog(
          queueNumber,
          estimatedWait,
          position,
        );

        return;
      }

      // ----------------------------------------------------------
      // REAL FAILURE
      // ----------------------------------------------------------

      final msg = e.toString().replaceFirst('Exception: ', '');

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Could Not Join Queue',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ==============================================================
  // SUCCESS DIALOG
  // ==============================================================

  Future<void> _showSuccessDialog(
    String qNum,
    int estWait,
    int position,
  ) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Color(0xFF16A34A),
              size: 26,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Joined Queue!',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow(
              'Queue #',
              qNum,
            ),
            _confirmRow(
              'Clinic',
              _clinic?.name ?? '—',
            ),
            _confirmRow(
              'Service',
              _service ?? '—',
            ),
            _confirmRow(
              'Position',
              '#$position',
            ),
            _confirmRow(
              'Est. Wait',
              '~$estWait min',
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              // Close success dialog
              Navigator.pop(context);

              // Leave Join Queue screen
              Navigator.pop(context);
            },
            child: const Text(
              'OK',
              style: TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // SAFE INT
  // ==============================================================

  int _safeInt(dynamic value) {
    if (value == null) return 0;

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.toInt();
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value.toString(),
        ) ??
        0;
  }

  // ==============================================================
  // ERROR SNACKBAR
  // ==============================================================

  void _showError(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  // ==============================================================
  // PATIENT TYPE LABEL
  // ==============================================================

  String _patientTypeLabel(PatientType t) {
    const map = {
      PatientType.regular: 'Regular',
      PatientType.senior: 'Senior Citizen',
      PatientType.pwd: 'PWD',
      PatientType.pregnant: 'Pregnant',
      PatientType.priority: 'Priority',
    };

    return map[t] ?? 'Regular';
  }

  // ==============================================================
  // BUILD
  // ==============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : _back,
        ),
        title: Text(
          'Join Queue — Step $_displayStep of $_totalDisplaySteps',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text(
                    'Please wait…',
                    style: TextStyle(
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // ------------------------------------------------
                // STEP PROGRESS
                // ------------------------------------------------

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    14,
                    20,
                    0,
                  ),
                  child: Row(
                    children: List.generate(
                      _totalDisplaySteps,
                      (i) => Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(
                            right: i < _totalDisplaySteps - 1 ? 6 : 0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: i < _displayStep
                                ? AppColors.primary
                                : Colors.grey.shade200,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ------------------------------------------------
                // CONTENT
                // ------------------------------------------------

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: [
                      _buildStep1(),
                      _buildStep2(),
                      _buildStep3(),
                    ][_step - 1],
                  ),
                ),

                // ------------------------------------------------
                // CTA
                // ------------------------------------------------

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    28,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading
                          ? null
                          : (_step < 3 ? _next : _showConfirmDialog),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _step < 3 ? 'Continue' : 'Join Queue',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ==============================================================
  // STEP 1
  // ==============================================================

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Clinic',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose where you want to queue',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black45,
          ),
        ),
        const SizedBox(height: 16),
        ..._clinics.map(
          (c) {
            final closed = _isClosed(c);
            final full = _isFull(c);
            final unavailable = closed || full;
            final selected = _clinic?.id == c.id;

            return GestureDetector(
              onTap: unavailable
                  ? null
                  : () {
                      setState(() {
                        _clinic = c;
                        _service = null;
                      });
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(
                  bottom: 10,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: unavailable
                      ? Colors.grey.shade50
                      : selected
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : unavailable
                            ? Colors.grey.shade200
                            : Colors.grey.shade100,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: unavailable
                            ? Colors.grey.shade100
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.local_hospital_outlined,
                        size: 20,
                        color: unavailable ? Colors.grey : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: unavailable
                                        ? Colors.grey
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (closed)
                                _tag(
                                  c.status,
                                  Colors.red.shade100,
                                  Colors.red.shade700,
                                )
                              else if (full)
                                _tag(
                                  'Full',
                                  Colors.orange.shade100,
                                  Colors.orange.shade800,
                                )
                              else
                                _tag(
                                  'Open',
                                  const Color(0xFFF0FDF4),
                                  const Color(0xFF16A34A),
                                ),
                            ],
                          ),
                          Text(
                            c.address,
                            style: TextStyle(
                              fontSize: 11,
                              color: unavailable
                                  ? Colors.grey.shade400
                                  : Colors.black45,
                            ),
                          ),
                          if (!unavailable) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.queue,
                                  size: 12,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${c.queueLength} in queue',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black38,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.timer_outlined,
                                  size: 12,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '~${c.currentWaitingTime} min wait',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 22,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ==============================================================
  // TAG
  // ==============================================================

  Widget _tag(
    String label,
    Color bg,
    Color fg,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  // ==============================================================
  // STEP 2
  // ==============================================================

  Widget _buildStep2() {
    final services = _clinic?.services
            .where(
              (s) => s['isAvailable'] == true,
            )
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Service',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _clinic?.name ?? '',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black45,
          ),
        ),
        const SizedBox(height: 16),
        if (services.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No available services',
                style: TextStyle(
                  color: Colors.black38,
                ),
              ),
            ),
          ),
        ...services.map(
          (s) {
            final name = s['name']?.toString() ?? '';

            final description = s['description']?.toString() ?? '';

            final duration = _safeInt(s['durationMinutes']);

            final selected = _service == name;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _service = name;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(
                  bottom: 9,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFEFF6FF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppColors.primary : Colors.grey.shade100,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (description.isNotEmpty)
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          if (duration > 0)
                            Text(
                              '~$duration min',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black38,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 22,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ==============================================================
  // STEP 3
  // ==============================================================

  Widget _buildStep3() {
    final user = context.read<AppState>().currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confirm Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        _reviewRow(
          'Name',
          user?.fullName ?? '—',
        ),
        _reviewRow(
          'Phone',
          user?.phone.isNotEmpty == true ? user!.phone : '—',
        ),
        _reviewRow(
          'Clinic',
          _clinic?.name ?? '—',
        ),
        _reviewRow(
          'Service',
          _service ?? '—',
        ),
        const SizedBox(height: 16),
        const Text(
          'Patient Type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        // Read-only — patient type comes from the patient's own account
        // (verified by clinic staff, see PatientType docs) and is never
        // something the patient selects here. This used to be a row of
        // tappable chips letting the patient pick any type including
        // "Priority"; the value was never actually sent to the server (the
        // join request doesn't include it), so it didn't affect real queue
        // placement — but it was still misleading UI implying otherwise.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            _patientTypeLabel(_pType),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Notes (optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'e.g. first visit, doctor referral…',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey.shade200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey.shade200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // REVIEW ROW
  // ==============================================================

  Widget _reviewRow(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
