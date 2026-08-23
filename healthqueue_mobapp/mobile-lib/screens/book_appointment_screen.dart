import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../models/appointment_models.dart' as apt;
import '../models/queue_models.dart';
import '../services/api_service.dart';
import '../services/clinic_service.dart';
import '../state/app_state.dart';

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});
  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  int _step = 1;

  Clinic? _clinic;
  List<Clinic> _allClinics = [];
  bool _fetchingClinics = false;
  String? _selectedServiceName;

  DateTime?    _selectedDate;
  String?      _selectedTime;
  List<String> _availableSlots = [];
  bool         _slotsLoading   = false;

  PatientType _patientType = PatientType.regular;
  final _notesCtrl = TextEditingController();

  bool    _booking = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Clinic && _clinic == null) {
      setState(() => _clinic = args);
    } else if (_clinic == null && !_fetchingClinics) {
      _loadAllClinics();
    }
  }

  Future<void> _loadAllClinics() async {
    setState(() => _fetchingClinics = true);
    try {
      final list = await ClinicService.getDirectory();
      if (mounted) setState(() => _allClinics = list);
    } finally {
      if (mounted) setState(() => _fetchingClinics = false);
    }
  }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  List<String> get _serviceNames =>
      _clinic?.availableServices
          .map((s) => s['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList() ?? [];

  // ── Calendar restriction helpers ──────────────────────────────────────────
  static final _holidays = <DateTime>{
    DateTime(2026, 1, 1),   // New Year's Day
    DateTime(2026, 2, 25),  // EDSA Revolution Anniversary
    DateTime(2026, 3, 30),  // Araw ng Kagitingan
    DateTime(2026, 4, 2),   // Maundy Thursday
    DateTime(2026, 4, 3),   // Good Friday
    DateTime(2026, 4, 4),   // Black Saturday
    DateTime(2026, 5, 1),   // Labor Day
    DateTime(2026, 6, 12),  // Independence Day
    DateTime(2026, 8, 21),  // Ninoy Aquino Day
    DateTime(2026, 8, 31),  // National Heroes Day
    DateTime(2026, 11, 1),  // All Saints' Day
    DateTime(2026, 11, 2),  // All Souls' Day
    DateTime(2026, 11, 30), // Bonifacio Day
    DateTime(2026, 12, 8),  // Immaculate Conception
    DateTime(2026, 12, 24), // Christmas Eve
    DateTime(2026, 12, 25), // Christmas Day
    DateTime(2026, 12, 30), // Rizal Day
    DateTime(2026, 12, 31), // New Year's Eve
    DateTime(2025, 12, 25),
    DateTime(2025, 12, 31),
  };

  bool _isDayAvailable(DateTime day) {
    if (day.weekday == DateTime.sunday) return false;
    final d = DateTime(day.year, day.month, day.day);
    if (_holidays.contains(d)) return false;
    if (_clinic != null) {
      final s = _clinic!.status;
      if (s == 'closed' || s == 'maintenance') return false;
    }
    return true;
  }

  DateTime _nextAvailableDay(DateTime from) {
    var d = from.add(const Duration(days: 1));
    while (!_isDayAvailable(d)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  Future<void> _loadSlots() async {
    if (_clinic == null || _selectedDate == null) return;
    setState(() { _slotsLoading = true; _availableSlots = []; _selectedTime = null; });
    try {
      final d = _selectedDate!;
      final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final raw = await ApiService.getAvailableSlots(clinicId: _clinic!.id, date: dateStr);
      final slots = <String>[];
      for (final s in raw) {
        if (s is String && s.isNotEmpty) {
          slots.add(s);
        } else if (s is Map) {
          final t = s['time']?.toString() ?? s['label']?.toString() ?? '';
          if (t.isNotEmpty) slots.add(t);
        }
      }
      setState(() => _availableSlots = slots.isEmpty ? _defaultSlots() : slots);
    } catch (_) {
      setState(() => _availableSlots = _defaultSlots());
    } finally {
      if (mounted) setState(() => _slotsLoading = false);
    }
  }

  List<String> _defaultSlots() => [
    '8:00 AM','9:00 AM','10:00 AM','11:00 AM',
    '1:00 PM','2:00 PM','3:00 PM','4:00 PM',
  ];

  bool get _canProceedStep1 => _selectedServiceName != null;
  bool get _canProceedStep2 => _selectedDate != null && _selectedTime != null;
  bool get _canConfirm      => _canProceedStep1 && _canProceedStep2;

  void _back() {
    if (_step == 1) { Navigator.pop(context); return; }
    setState(() => _step--);
  }

  void _next() {
    if (_step == 1 && _canProceedStep1) { setState(() => _step = 2); return; }
    if (_step == 2 && _canProceedStep2) { setState(() => _step = 3); return; }
  }

  Future<void> _confirm() async {
    if (!_canConfirm || _booking) return;
    setState(() { _booking = true; _error = null; });
    try {
      final d = _selectedDate!;
      final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final res = await ApiService.bookAppointment({
        'clinicId':        _clinic!.id,
        'serviceName':     _selectedServiceName,
        'appointmentDate': dateStr,
        'timeSlot':        _selectedTime,
        'patientType':     _patientType.label,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      final m    = res;
      final appt = apt.Appointment(
        id:          m['_id']?.toString() ?? m['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        clinicName:  _clinic!.name,
        serviceName: _selectedServiceName ?? '',
        date:        _selectedDate!,
        timeLabel:   _selectedTime ?? '',
        status:      apt.AppointmentStatus.pending,
        notes:       _notesCtrl.text.trim(),
      );
      if (mounted) {
        // Refresh appointment list in AppState so it shows immediately on return
        context.read<AppState>().fetchAppointments();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Appointment booked successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context, appt);
      }
    } on Exception catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.toLowerCase().contains('already have') || msg.toLowerCase().contains('already booked') || msg.toLowerCase().contains('conflict')) {
        if (!mounted) return;
        setState(() { _booking = false; _error = null; });
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(children: [
              Icon(Icons.info_outline, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Appointment Exists', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(msg, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  'Check your Appointments tab to view or manage it.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF2563EB)),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Choose Different Slot')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('View Appointments', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        return;
      }

      if (msg.contains('timed out') || msg.contains('may have been processed')) {
        try {
          final appts = await ApiService.getMyAppointments();
          if (appts.isNotEmpty) {
            if (!mounted) return;
            setState(() { _booking = false; _error = null; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Your appointment may have been booked. Check Appointments tab.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ));
            Navigator.pop(context);
            return;
          }
        } catch (_) {}
      }
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepLabels = ['Select Service', 'Choose Schedule', 'Confirm'];
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0, scrolledUnderElevation: 0,
        backgroundColor: Colors.white, foregroundColor: AppColors.textDark,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: _back),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Book Appointment', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          if (_clinic != null)
            Text(_clinic!.name, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Column(children: [
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: Text(stepLabels[_step - 1], style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600))),
                _StepPill(current: _step, total: 3),
              ]),
            ),
          ]),
        ),
      ),
      body: SafeArea(
        child: _fetchingClinics
            ? const Center(child: CircularProgressIndicator())
            : _clinic == null
            ? _ClinicSelectionList(clinics: _allClinics, onSelect: (c) => setState(() => _clinic = c))
            : _step == 1
            ? _StepService(services: _serviceNames, selected: _selectedServiceName, onSelect: (s) => setState(() => _selectedServiceName = s))
            : _step == 2
            ? _StepSchedule(
                selectedDate:   _selectedDate,
                selectedTime:   _selectedTime,
                availableSlots: _availableSlots,
                slotsLoading:   _slotsLoading,
                // Fixed: Passed your restriction checkers explicitly into step 2 parameters
                nextAvailableDay: _nextAvailableDay,
                isDayAvailable: _isDayAvailable,
                onPickDate: (d) async {
                  setState(() { _selectedDate = d; _selectedTime = null; });
                  await _loadSlots();
                },
                onSelectTime: (t) => setState(() => _selectedTime = t),
              )
            : _StepConfirm(
                clinic:      _clinic!,
                serviceName: _selectedServiceName!,
                date:        _selectedDate!,
                time:        _selectedTime!,
                patientType: _patientType,
                onPatientType: (p) => setState(() => _patientType = p),
                notesCtrl:   _notesCtrl,
                error:       _error,
                booking:     _booking,
                onConfirm:   _confirm,
              ),
      ),
      bottomNavigationBar: _step < 3
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (_step == 1 && !_canProceedStep1) || (_step == 2 && !_canProceedStep2) ? null : _next,
                  child: Text(_step == 2 ? 'Review Booking' : 'Continue', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            )
          : null,
    );
  }
}

// ── Clinic selection list ─────────────────────────────────────────────────────
class _ClinicSelectionList extends StatelessWidget {
  final List<Clinic>       clinics;
  final void Function(Clinic) onSelect;
  const _ClinicSelectionList({required this.clinics, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (clinics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: clinics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = clinics[i];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const CircleAvatar(
              backgroundColor: Color(0xFFEFF6FF),
              child: Icon(Icons.local_hospital_outlined, color: AppColors.primary, size: 20)),
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text(c.address, style: const TextStyle(fontSize: 11, color: Colors.black45)),
          trailing: const Icon(Icons.chevron_right, color: Colors.black26),
          onTap: () => onSelect(c),
        );
      },
    );
  }
}

// ── Step 1: Service ───────────────────────────────────────────────────────────
class _StepService extends StatelessWidget {
  final List<String>          services;
  final String?               selected;
  final void Function(String) onSelect;
  const _StepService({required this.services, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32),
        child: Text('No services available for this clinic.', style: TextStyle(color: Colors.black38), textAlign: TextAlign.center)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final svc = services[i];
        final sel = selected == svc;
        return GestureDetector(
          onTap: () => onSelect(svc),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFEFF6FF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? AppColors.primary : Colors.grey.shade200, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Expanded(child: Text(svc, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
              if (sel) const Icon(Icons.check_circle, color: AppColors.primary, size: 22),
            ]),
          ),
        );
      },
    );
  }
}

// ── Step 2: Schedule ──────────────────────────────────────────────────────────
class _StepSchedule extends StatelessWidget {
  final DateTime?              selectedDate;
  final String?                selectedTime;
  final List<String>           availableSlots;
  final bool                   slotsLoading;
  final void Function(DateTime) onPickDate;
  final void Function(String)  onSelectTime;
  
  // Fixed: Declared missing handlers inside constructor footprint
  final DateTime Function(DateTime) nextAvailableDay;
  final bool Function(DateTime) isDayAvailable;

  const _StepSchedule({
    required this.selectedDate, required this.selectedTime,
    required this.availableSlots, required this.slotsLoading,
    required this.onPickDate, required this.onSelectTime,
    required this.nextAvailableDay, required this.isDayAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pick a Date', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: nextAvailableDay(now),
              firstDate:   now.add(const Duration(days: 1)),
              lastDate:    now.add(const Duration(days: 90)),
              selectableDayPredicate: (day) => isDayAvailable(day),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary)),
                child: child!,
              ),
            );
            if (picked != null) onPickDate(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selectedDate != null ? const Color(0xFFEFF6FF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selectedDate != null ? AppColors.primary : Colors.grey.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                selectedDate == null ? 'Select a date' : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                style: TextStyle(fontWeight: FontWeight.w600, color: selectedDate != null ? AppColors.textDark : AppColors.textMuted),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Available Time Slots', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 10),
        if (slotsLoading)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (availableSlots.isEmpty && selectedDate != null)
          const Text('No slots available. Try another date.', style: TextStyle(color: Colors.black38))
        else if (availableSlots.isEmpty)
          const Text('Select a date to see available time slots.', style: TextStyle(color: Colors.black38))
        else
          Wrap(spacing: 8, runSpacing: 8,
            children: availableSlots.map((t) {
              final sel = selectedTime == t;
              return GestureDetector(
                onTap: () => onSelectTime(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? AppColors.primary : Colors.grey.shade200),
                  ),
                  child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? Colors.white : AppColors.textDark)),
                ),
              );
            }).toList()),
      ]),
    );
  }
}

// ── Step 3: Confirm ───────────────────────────────────────────────────────────
class _StepConfirm extends StatelessWidget {
  final Clinic                    clinic;
  final String                    serviceName;
  final DateTime                  date;
  final String                    time;
  final PatientType               patientType;
  final void Function(PatientType) onPatientType;
  final TextEditingController     notesCtrl;
  final String?                   error;
  final bool                      booking;
  final VoidCallback              onConfirm;

  const _StepConfirm({
    required this.clinic, required this.serviceName,
    required this.date, required this.time,
    required this.patientType, required this.onPatientType,
    required this.notesCtrl, required this.error,
    required this.booking, required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(children: [
            _row('Clinic',   clinic.name),
            _row('Service',  serviceName),
            _row('Date',     '${date.day}/${date.month}/${date.year}'),
            _row('Time',     time),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('Patient Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: PatientType.values.map((t) {
            final sel = patientType == t;
            return GestureDetector(
              onTap: () => onPatientType(t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: sel ? AppColors.primary : Colors.grey.shade200),
                ),
                child: Text(t.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.black54)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('Notes (optional)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: notesCtrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Any special requests or medical notes…',
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: booking ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: booking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Confirm Booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
      ]),
    );
  }

  Widget _row(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45))),
      Expanded(child: Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );
}

// ── Step pill ─────────────────────────────────────────────────────────────────
class _StepPill extends StatelessWidget {
  final int current, total;
  const _StepPill({required this.current, required this.total});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
    child: Text('Step $current of $total', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
  );
}