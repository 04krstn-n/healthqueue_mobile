import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../services/api_service.dart';
import '../services/clinic_service.dart';
import '../state/app_state.dart';

class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});
  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen>
    with SingleTickerProviderStateMixin {

  bool   _loading = true;
  String _error   = '';

  Map<String, dynamic> _peakData     = {};
  Map<String, dynamic> _prescription = {};
  String               _selectedClinicId   = '';
  String               _selectedClinicName = '';
  List<Map<String, dynamic>> _clinics = [];

  int _tabIndex = 0; // 0=Hourly 1=Weekly 2=Departments

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() => setState(() => _tabIndex = _tabCtrl.index));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  // ── Load clinics + peak data ───────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() { _loading = true; _error = ''; });
    try {
      // Get location
      Position? pos;
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied)
            perm = await Geolocator.requestPermission();
          if (perm != LocationPermission.deniedForever)
            pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium)
                .timeout(const Duration(seconds: 6));
        }
      } catch (_) {}

      final appState = context.read<AppState>();
      final patientType = appState.currentUser?.patientType ?? 'Regular';

      // Load clinics for selector
      final clinicList = await ClinicService.getDirectory();
      _clinics = clinicList.map((c) => {'id': c.id, 'name': c.name}).toList();

      if (_selectedClinicId.isEmpty && _clinics.isNotEmpty) {
        _selectedClinicId   = _clinics.first['id']!;
        _selectedClinicName = _clinics.first['name']!;
      }

      // Load prescription (best route) + peak data for selected clinic in parallel
      final results = await Future.wait([
        ApiService.evaluatePrescription(
          lat: pos?.latitude, lng: pos?.longitude,
          patientType: patientType,
        ),
        ApiService.getBestTimeToQueue(_selectedClinicId),
      ]);

      if (!mounted) return;
      setState(() {
        _prescription = results[0];
        _peakData     = results[1];
        _loading      = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _switchClinic(String id, String name) async {
    setState(() { _selectedClinicId = id; _selectedClinicName = name; _loading = true; });
    try {
      final data = await ApiService.getBestTimeToQueue(id);
      if (!mounted) return;
      setState(() { _peakData = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Peak Hours & Insights',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? _buildLoading()
          : _error.isNotEmpty
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildLoading() => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(strokeWidth: 2),
      SizedBox(height: 14),
      Text('Analyzing queue patterns…',
          style: TextStyle(color: Colors.black45, fontSize: 13)),
    ]),
  );

  Widget _buildError() => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.black26),
        const SizedBox(height: 16),
        Text(_error, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45, fontSize: 13)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          onPressed: _loadData,
        ),
      ]),
    ),
  );

  Widget _buildBody() {
    final recommendation = _peakData['recommendation'] as String?
        ?? 'Morning hours (8–10 AM) tend to have shorter wait times.';
    final avgWait  = _peakData['avgWaitAll']  as int? ?? 18;
    final peakLoad = _peakData['peakLoad']    as int? ?? 35;
    final peakLbl  = _peakData['peakLabel']   as String? ?? '10 AM';

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Subtitle ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Plan your visit with real-time analytics',
              style: TextStyle(color: Colors.black45, fontSize: 12.5)),
        ),

        // ── Clinic selector ─────────────────────────────────────────────────
        if (_clinics.length > 1)
          _ClinicSelector(
            clinics: _clinics,
            selectedId: _selectedClinicId,
            onSelect: (id, name) => _switchClinic(id, name),
          ),

        // ── Prescription recommendation banner ───────────────────────────────
        _RecommendationBanner(
          prescription: _prescription,
          peakData: _peakData,
        ),

        const SizedBox(height: 12),

        // ── Tabs ─────────────────────────────────────────────────────────────
        _TabBar(controller: _tabCtrl),

        const SizedBox(height: 14),

        // ── Stats row ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _StatCard(
              icon: Icons.timer_outlined,
              label: 'Avg Wait Time',
              value: '$avgWait min',
              sub: 'across all hours',
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 12),
            _StatCard(
              icon: Icons.people_alt_outlined,
              label: 'Peak Load',
              value: '$peakLoad',
              sub: 'patients at $peakLbl',
              color: const Color(0xFF2563EB),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // ── Tab content ───────────────────────────────────────────────────────
        if (_tabIndex == 0) _HourlyChart(peakData: _peakData),
        if (_tabIndex == 1) _WeeklyChart(peakData: _peakData),
        if (_tabIndex == 2) _ServicesView(peakData: _peakData,
            clinicName: _selectedClinicName),

        const SizedBox(height: 32),
      ]),
    );
  }
}

// ── Clinic Selector ──────────────────────────────────────────────────────────
class _ClinicSelector extends StatelessWidget {
  final List<Map<String, dynamic>> clinics;
  final String selectedId;
  final void Function(String id, String name) onSelect;
  const _ClinicSelector({required this.clinics, required this.selectedId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: selectedId,
            style: const TextStyle(fontSize: 13, color: Colors.black87,
                fontWeight: FontWeight.w600),
            icon: const Icon(Icons.expand_more, size: 18),
            items: clinics.map((c) => DropdownMenuItem<String>(
              value: c['id'] as String,
              child: Text(c['name'] as String,
                  overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (id) {
              if (id == null) return;
              final name = clinics.firstWhere((c) => c['id'] == id)['name'] as String;
              onSelect(id, name);
            },
          ),
        ),
      ),
    );
  }
}

// ── Recommendation Banner ────────────────────────────────────────────────────
class _RecommendationBanner extends StatelessWidget {
  final Map<String, dynamic> prescription;
  final Map<String, dynamic> peakData;
  const _RecommendationBanner({required this.prescription, required this.peakData});

  @override
  Widget build(BuildContext context) {
    // Use prescription message if it's a routing action, else use peak recommendation
    final status = prescription['status'] as String? ?? '';
    final isCritical = ['ISOLATION_DIRECT_ROUTE','LOCK_REGISTRATION',
        'DISPLAY_SURGE_ALERT'].contains(status);

    final rec = peakData['recommendation'] as String?
        ?? 'Morning hours (8–10 AM) tend to have shorter wait times.';

    final prescMsg = prescription['message'] as String? ?? '';
    final showPrescription = isCritical && prescMsg.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        // Peak-hours best time banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2563EB).withOpacity(.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.access_time_rounded,
                size: 18, color: Color(0xFF2563EB)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Best Time to Visit:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                        color: Color(0xFF2563EB))),
                const SizedBox(height: 2),
                Text(rec, style: const TextStyle(fontSize: 13,
                    color: Colors.black87, height: 1.4)),
              ],
            )),
          ]),
        ),

        // Prescription alert (only when critical)
        if (showPrescription) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(prescMsg,
                  style: const TextStyle(fontSize: 12, color: Colors.black87,
                      height: 1.4))),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Tab bar ──────────────────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final TabController controller;
  const _TabBar({required this.controller});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(blurRadius: 4,
              color: Colors.black.withOpacity(.08), offset: const Offset(0,1))],
        ),
        labelColor: Colors.black87,
        unselectedLabelColor: Colors.black38,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Hourly'),
          Tab(text: 'Weekly'),
          Tab(text: 'Services'),
        ],
      ),
    ),
  );
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value, sub;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value,
      required this.sub, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: Colors.black38),
          const SizedBox(width: 6),
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black45,
                  fontWeight: FontWeight.w500))),
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
            color: color)),
        Text(sub, style: const TextStyle(fontSize: 11, color: Colors.black38)),
      ]),
    ),
  );
}

// ── Hourly Chart ──────────────────────────────────────────────────────────────
class _HourlyChart extends StatelessWidget {
  final Map<String, dynamic> peakData;
  const _HourlyChart({required this.peakData});

  @override
  Widget build(BuildContext context) {
    final rawHourly = peakData['hourlyData'] as List?;
    final hourly = rawHourly != null
        ? rawHourly.cast<Map<String, dynamic>>()
        : _fallbackHourly();

    final maxCount = hourly.fold<int>(1,
        (m, h) => (h['count'] as int? ?? 0) > m ? (h['count'] as int) : m);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bar_chart_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          const Text('Patient Volume by Hour',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
        const SizedBox(height: 2),
        const Text("Today's traffic pattern",
            style: TextStyle(color: Colors.black45, fontSize: 12)),
        const SizedBox(height: 14),
        ...hourly.map((h) => _HourRow(data: h, maxCount: maxCount)),
      ]),
    );
  }

  static List<Map<String, dynamic>> _fallbackHourly() => [
    {'hour':8,  'label':'8 AM',  'count':15,'avgWait':12,'isPeak':false},
    {'hour':9,  'label':'9 AM',  'count':28,'avgWait':25,'isPeak':true },
    {'hour':10, 'label':'10 AM', 'count':35,'avgWait':32,'isPeak':true },
    {'hour':11, 'label':'11 AM', 'count':32,'avgWait':28,'isPeak':true },
    {'hour':12, 'label':'12 PM', 'count':20,'avgWait':18,'isPeak':false},
    {'hour':13, 'label':'1 PM',  'count':18,'avgWait':15,'isPeak':false},
    {'hour':14, 'label':'2 PM',  'count':25,'avgWait':22,'isPeak':false},
    {'hour':15, 'label':'3 PM',  'count':30,'avgWait':27,'isPeak':true },
    {'hour':16, 'label':'4 PM',  'count':22,'avgWait':19,'isPeak':false},
    {'hour':17, 'label':'5 PM',  'count':10,'avgWait':8, 'isPeak':false},
  ];
}

class _HourRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final int maxCount;
  const _HourRow({required this.data, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    final isPeak  = data['isPeak']   as bool? ?? false;
    final label   = data['label']    as String? ?? '';
    final count   = data['count']    as int? ?? 0;
    final avgWait = data['avgWait']  as int? ?? 0;
    final barFrac = maxCount > 0 ? (count / maxCount).clamp(0.05, 1.0) : 0.1;
    final barColor = isPeak ? const Color(0xFFEA580C) : const Color(0xFF2563EB);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
  SizedBox(
    width: 52,
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),
  ),

  if (isPeak) ...[
    const SizedBox(width: 4),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFEA580C),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'Peak',
        style: TextStyle(
          fontSize: 8,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  ],

  const SizedBox(width: 6),

  Expanded(
    child: Text(
      '$count pts · $avgWait min',
      textAlign: TextAlign.right,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 10,
        color: Colors.black45,
      ),
    ),
  ),
]),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, constraints) => Stack(children: [
          Container(height: 8,
              decoration: BoxDecoration(color: Colors.black.withOpacity(.06),
                  borderRadius: BorderRadius.circular(4))),
          Container(
            height: 8,
            width: constraints.maxWidth * barFrac,
            decoration: BoxDecoration(color: barColor,
                borderRadius: BorderRadius.circular(4)),
          ),
        ])),
      ]),
    );
  }
}

// ── Weekly Chart ──────────────────────────────────────────────────────────────
class _WeeklyChart extends StatelessWidget {
  final Map<String, dynamic> peakData;
  const _WeeklyChart({required this.peakData});

  @override
  Widget build(BuildContext context) {
    final rawWeekly = peakData['weeklyData'] as List?;
    final weekly = rawWeekly != null
        ? rawWeekly.cast<Map<String, dynamic>>()
        : _fallbackWeekly();

    final maxCount = weekly.fold<int>(1,
        (m, d) => (d['count'] as int? ?? 0) > m ? (d['count'] as int) : m);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_today_outlined,
              size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          const Text('Weekly Traffic Pattern',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
        const SizedBox(height: 2),
        const Text('Patient volume by day of week',
            style: TextStyle(color: Colors.black45, fontSize: 12)),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: weekly.map((d) {
            final count = d['count'] as int? ?? 0;
            final barH  = maxCount > 0 ? (count / maxCount * 120).clamp(8.0, 120.0) : 8.0;
            final today = DateTime.now().weekday % 7;
            final idx   = weekly.indexOf(d);
            final isToday = idx == today;
            return Expanded(child: Column(children: [
              Text('$count', style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isToday ? AppColors.primary : Colors.black38)),
              const SizedBox(height: 4),
              Container(
                height: barH,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isToday ? AppColors.primary : const Color(0xFF93C5FD),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Text(d['label'] as String? ?? '',
                  style: TextStyle(fontSize: 10,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color: isToday ? AppColors.primary : Colors.black45)),
            ]));
          }).toList(),
        ),
      ]),
    );
  }

  static List<Map<String, dynamic>> _fallbackWeekly() => [
    {'label':'Sun','count':8},  {'label':'Mon','count':35},
    {'label':'Tue','count':42}, {'label':'Wed','count':38},
    {'label':'Thu','count':40}, {'label':'Fri','count':45},
    {'label':'Sat','count':22},
  ];
}

// ── Services View (real data from QueueEntry.serviceName) ────────────────────
class _ServicesView extends StatelessWidget {
  final Map<String, dynamic> peakData;
  final String clinicName;
  const _ServicesView({required this.peakData, required this.clinicName});

  Color _loadColor(String load) {
    switch (load) {
      case 'High':   return const Color(0xFFEA580C);
      case 'Medium': return const Color(0xFFD97706);
      default:       return const Color(0xFF16A34A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = peakData['servicesData'] as List?;
    final services = raw != null
        ? raw.cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    final hasData = services.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.medical_services_outlined,
              size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          const Text('Service Load',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
        const SizedBox(height: 2),
        Text('30-day queue activity per service at $clinicName',
            style: const TextStyle(color: Colors.black45, fontSize: 12)),
        const SizedBox(height: 14),

        if (!hasData)
          _EmptyServices()
        else
          ...services.map((s) {
            final name    = s['name']    as String? ?? 'Service';
            final avgWait = s['avgWait'] as int?    ?? 0;
            final count   = s['count']   as int?    ?? 0;
            final load    = s['load']    as String? ?? 'Low';
            final color   = _loadColor(load);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(.07)),
              ),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.hourglass_bottom_rounded,
                          size: 12, color: Colors.black38),
                      const SizedBox(width: 3),
                      Text('~$avgWait min avg wait',
                          style: const TextStyle(fontSize: 11,
                              color: Colors.black45)),
                      const SizedBox(width: 10),
                      const Icon(Icons.people_alt_outlined,
                          size: 12, color: Colors.black38),
                      const SizedBox(width: 3),
                      Text('$count visits',
                          style: const TextStyle(fontSize: 11,
                              color: Colors.black45)),
                    ]),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(load,
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: color)),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}

class _EmptyServices extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black.withOpacity(.07)),
    ),
    child: const Column(children: [
      Icon(Icons.medical_services_outlined, size: 36, color: Colors.black26),
      SizedBox(height: 10),
      Text('No service data yet',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black45)),
      SizedBox(height: 4),
      Text('Queue activity will appear here after patients start using the system.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.black38, height: 1.5)),
    ]),
  );
}
