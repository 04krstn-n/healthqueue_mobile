import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../services/clinic_service.dart';

class ClinicMapScreen extends StatefulWidget {
  const ClinicMapScreen({super.key});
  @override
  State<ClinicMapScreen> createState() => _ClinicMapScreenState();
}

class _ClinicMapScreenState extends State<ClinicMapScreen> with WidgetsBindingObserver {
  final Completer<GoogleMapController> _ctrl = Completer();
  static const LatLng _default = LatLng(14.5995, 120.9842);

  List<Clinic>     _clinics     = [];
  List<_RecClinic> _recommended = [];
  bool             _loading     = true;
  LatLng?          _userPos;
  Clinic?          _selected;
  Set<Marker>      _markers     = {};
  MapType          _mapType     = MapType.normal;
  String           _sortMode    = 'recommended';
  bool             _showCompare = false;
  final List<_RecClinic> _compareList = [];

  // Why we don't have the patient's location yet, so we can show the right
  // prompt instead of just silently falling back to the default map center.
  // One of: null (fine / unknown), 'service_off', 'denied', 'denied_forever'.
  String? _locationIssue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the patient backgrounds the app to turn location on in system
    // settings, retry automatically when they come back instead of making
    // them tap something.
    if (state == AppLifecycleState.resumed && _userPos == null) {
      _retryLocation();
    }
  }

  Future<void> _init() async {
    await Future.wait([_loadClinics(), _locateUser()]);
    _computeRecs();
    _rebuildMarkers();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadClinics() async {
    try {
      final list = await ClinicService.getDirectory();
      if (mounted) setState(() => _clinics = list);
    } catch (_) {}
  }

  Future<void> _locateUser() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locationIssue = 'service_off');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        if (mounted) setState(() => _locationIssue = 'denied');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationIssue = 'denied_forever');
        return;
      }

      // Permission is granted at this point. High-accuracy GPS can be slow
      // or unavailable indoors (and on many emulators with no simulated
      // location set), so try it briefly, then fall back to a faster,
      // lower-accuracy fix (network/cell-based) rather than just giving up.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 6));
      } on TimeoutException {
        try {
          pos = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.medium)
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          pos = null;
        }
      }

      if (pos != null && mounted) {
        setState(() {
          _userPos = LatLng(pos!.latitude, pos.longitude);
          _locationIssue = null;
        });
      } else if (mounted) {
        // Permission granted, but no fix — a real, distinct state from
        // "denied," since re-asking for permission won't fix this.
        setState(() => _locationIssue = 'unavailable');
      }
    } catch (_) {
      if (mounted && _userPos == null) {
        setState(() => _locationIssue ??= 'unavailable');
      }
    }
  }

  // Re-runs location detection (e.g. after the patient returns from system
  // settings) and refreshes distance-based sorting/markers if it succeeds.
  Future<void> _retryLocation() async {
    await _locateUser();
    if (_userPos != null && mounted) {
      _computeRecs();
      _rebuildMarkers();
      setState(() {});
    }
  }

  void _computeRecs() {
    final user = _userPos;
    _recommended = _clinics.map((c) {
      final dist = (user != null && c.hasLocation)
          ? _distKm(user, LatLng(c.latitude!, c.longitude!))
          : 99.0;
      // Use the correct Clinic fields
      final wait  = c.currentWaitingTime.toDouble();
      final queue = c.queueLength.toDouble();
      final score = wait * 0.6 + dist * 4.0 + queue * 0.5;
      String exp = dist < 2
          ? 'Very close · ${dist.toStringAsFixed(1)} km'
          : dist < 5
          ? 'Nearby · ${dist.toStringAsFixed(1)} km'
          : '${dist.toStringAsFixed(1)} km away';
      exp += wait == 0 ? ' · No wait'
          : wait < 15  ? ' · Short wait (~${wait.toInt()} min)'
          : ' · ~${wait.toInt()} min wait';
      return _RecClinic(
        clinic:      c,
        distKm:      dist,
        waitMin:     c.currentWaitingTime,
        queueLen:    c.queueLength,
        score:       score,
        explanation: exp,
      );
    }).toList();

    switch (_sortMode) {
      case 'nearest': _recommended.sort((a, b) => a.distKm.compareTo(b.distKm)); break;
      case 'fastest': _recommended.sort((a, b) => a.waitMin.compareTo(b.waitMin)); break;
      default:        _recommended.sort((a, b) => a.score.compareTo(b.score));
    }
  }

  void _rebuildMarkers() {
    final m = <Marker>{};
    for (int i = 0; i < _recommended.length; i++) {
      final r = _recommended[i];
      final c = r.clinic;
      if (!c.hasLocation) continue;
      final isSel = _selected?.id == c.id;
      final isTop = i < 3;
      m.add(Marker(
        markerId: MarkerId(c.id),
        position: LatLng(c.latitude!, c.longitude!),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isSel  ? BitmapDescriptor.hueAzure
          : isTop ? BitmapDescriptor.hueGreen
          : BitmapDescriptor.hueRed,
        ),
        infoWindow: InfoWindow(
          title:   c.name,
          snippet: '~${r.waitMin} min wait · ${r.queueLen} in queue',
        ),
        onTap: () => _selectClinic(c, r),
      ));
    }
    if (_userPos != null) {
      m.add(Marker(
        markerId: const MarkerId('_user'),
        position: _userPos!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: const InfoWindow(title: 'You are here'),
      ));
    }
    if (mounted) setState(() => _markers = m);
  }

  Future<void> _selectClinic(Clinic c, _RecClinic rec) async {
    final same = _selected?.id == c.id;
    setState(() {
      _selected = same ? null : c;
    });
    _rebuildMarkers();
    if (!same && c.hasLocation && _ctrl.isCompleted) {
      (await _ctrl.future).animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(c.latitude!, c.longitude!), 15));
    }
  }

  Future<void> _centerUser() async {
    if (_userPos == null || !_ctrl.isCompleted) return;
    (await _ctrl.future).animateCamera(
        CameraUpdate.newLatLngZoom(_userPos!, 14));
  }

  Future<void> _handleLocationFix() async {
    switch (_locationIssue) {
      case 'service_off':
        await Geolocator.openLocationSettings();
        break;
      case 'denied_forever':
        await Geolocator.openAppSettings();
        break;
      case 'denied':
      case 'unavailable':
      default:
        // 'denied' — just ask again, the system dialog handles it.
        // 'unavailable' — permission's fine, just retry the fix (moving
        // near a window, waiting for GPS to warm up, etc. helps here).
        await _retryLocation();
        return;
    }
    // Give the patient a moment to flip the setting before we re-check;
    // didChangeAppLifecycleState also retries automatically on resume.
    await Future.delayed(const Duration(milliseconds: 500));
    await _retryLocation();
  }

  void _toggleCompare(Clinic c) {
    final rec = _recommended.firstWhere(
      (r) => r.clinic.id == c.id,
      orElse: () => _RecClinic(clinic: c, distKm: 0,
          waitMin: 0, queueLen: 0, score: 0, explanation: ''),
    );
    setState(() {
      if (_compareList.any((r) => r.clinic.id == c.id)) {
        _compareList.removeWhere((r) => r.clinic.id == c.id);
      } else if (_compareList.length < 3) {
        _compareList.add(rec);
      }
    });
  }

  double _distKm(LatLng a, LatLng b) {
    const r    = 6371.0;
    final dLat = _rad(b.latitude  - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final x    = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  double _rad(double d) => d * math.pi / 180;

  String _travelLabel(double km) {
    final mins = (km / 25 * 60).round().clamp(1, 999);
    return mins < 60
        ? '~$mins min drive'
        : '~${mins ~/ 60}h ${mins % 60}min drive';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Find Clinics',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          if (_compareList.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _showCompare = true),
              child: Text('Compare (${_compareList.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          IconButton(
            icon: Icon(_mapType == MapType.normal
                ? Icons.satellite_alt : Icons.map_outlined),
            onPressed: () => setState(() {
              _mapType = _mapType == MapType.normal
                  ? MapType.satellite : MapType.normal;
              _rebuildMarkers();
            }),
          ),
        ],
      ),
      body: Stack(children: [
        Column(children: [
          // Sort chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _sortChip('Recommended', 'recommended'),
                const SizedBox(width: 8),
                _sortChip('Nearest First', 'nearest'),
                const SizedBox(width: 8),
                _sortChip('Fastest Queue', 'fastest'),
              ]),
            ),
          ),

          if (_locationIssue != null && _userPos == null && !_loading)
            _LocationPrompt(issue: _locationIssue!, onFix: _handleLocationFix),

          // Map
          SizedBox(
            height: 220,
            child: Stack(children: [
              GoogleMap(
                onMapCreated: (c) => _ctrl.complete(c),
                initialCameraPosition: CameraPosition(
                    target: _userPos ?? _default, zoom: 12),
                markers:                _markers,
                mapType:                _mapType,
                myLocationEnabled:      true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled:    false,
              ),
              Positioned(
                bottom: 12, right: 12,
                child: FloatingActionButton.small(
                  onPressed: _centerUser,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: AppColors.primary),
                ),
              ),
            ]),
          ),

          // Clinic list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _recommended.isEmpty
                ? const Center(child: Text('No clinics found',
                    style: TextStyle(color: Colors.black38)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                    itemCount:       _recommended.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final rec = _recommended[i];
                      final c   = rec.clinic;
                      final sel = _selected?.id == c.id;
                      final inCompare =
                          _compareList.any((r) => r.clinic.id == c.id);
                      return GestureDetector(
                        onTap: () => _selectClinic(c, rec),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFFEFF6FF) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sel
                                  ? AppColors.primary : Colors.grey.shade100,
                              width: sel ? 2 : 1,
                            ),
                            boxShadow: sel
                                ? [BoxShadow(blurRadius: 8,
                                    color: AppColors.primary.withValues(alpha: .1))]
                                : [],
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  if (i < 3) Container(
                                    margin: const EdgeInsets.only(right: 5),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFF0FDF4),
                                        borderRadius: BorderRadius.circular(99)),
                                    child: Text('#${i + 1} Recommended',
                                        style: const TextStyle(fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF16A34A))),
                                  ),
                                  _statusDot(c.status),
                                ]),
                                const SizedBox(height: 3),
                                Text(c.name, style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                                Text(
                                  c.address.isNotEmpty ? c.address : 'Location not added',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.address.isNotEmpty ? Colors.black45 : Colors.orange.shade700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(children: [
                                  Icon(
                                    c.hasLocation ? Icons.location_on_outlined : Icons.location_off_outlined,
                                    size: 13,
                                    color: c.hasLocation ? AppColors.primary : Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    c.hasLocation
                                        ? '${c.latitude!.toStringAsFixed(5)}, ${c.longitude!.toStringAsFixed(5)}'
                                        : 'No map location',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: c.hasLocation ? Colors.black38 : Colors.orange.shade700,
                                    ),
                                  ),
                                ]),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${rec.distKm.toStringAsFixed(1)} km',
                                    style: const TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                Text(_travelLabel(rec.distKm),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black38)),
                              ]),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              _infoChip(Icons.timer_outlined,
                                  '~${rec.waitMin} min', Colors.orange),
                              const SizedBox(width: 6),
                              _infoChip(Icons.queue,
                                  '${rec.queueLen} in queue', Colors.blue),
                            ]),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(rec.explanation,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black38,
                                      fontStyle: FontStyle.italic)),
                            ),
                            if (sel) ...[
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(child: OutlinedButton(
                                  onPressed: () => _toggleCompare(c),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: inCompare
                                        ? Colors.red : AppColors.primary,
                                    side: BorderSide(
                                        color: inCompare
                                            ? Colors.red : AppColors.primary),
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text(inCompare ? 'Remove' : 'Compare',
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700)),
                                )),
                                const SizedBox(width: 8),
                                Expanded(child: ElevatedButton(
                                  onPressed: () => Navigator.pushNamed(
                                      context, AppRoutes.joinQueue,
                                    // Was _selected?.clinic — Clinic has no
                                    // `.clinic` field at all, so this could
                                    // never correctly resolve to this card's
                                    // clinic. `c` is the actual clinic this
                                    // specific card represents (the loop
                                    // variable this whole card is built
                                    // from), which is what should be passed
                                    // through to Join Queue regardless of
                                    // whatever `_selected` currently holds.
                                    arguments: c),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Join Queue',
                                      style: TextStyle(fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                )),
                              ]),
                            ],
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),

        if (_showCompare) _buildCompareSheet(),
      ]),
    );
  }

  Widget _sortChip(String label, String mode) {
    final active = _sortMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _sortMode = mode);
        _computeRecs();
        _rebuildMarkers();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: active ? AppColors.primary : Colors.grey.shade200),
        ),
        child: Text(label, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : Colors.black54)),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color), const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10,
          color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _statusDot(String status) {
    final c = status == 'open'   ? const Color(0xFF16A34A)
        : status == 'busy'   ? Colors.orange
        : Colors.red;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(status, style: TextStyle(fontSize: 9, color: c,
          fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _buildCompareSheet() {
    return Positioned.fill(child: GestureDetector(
      onTap: () => setState(() => _showCompare = false),
      child: Container(color: Colors.black54,
        child: Align(alignment: Alignment.bottomCenter,
          child: GestureDetector(onTap: () {},
            child: Container(
              decoration: const BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Compare Clinics',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _showCompare = false)),
                ]),
                const Divider(),
                if (_compareList.isEmpty)
                  const Padding(padding: EdgeInsets.all(20),
                    child: Text('Select up to 3 clinics to compare',
                        style: TextStyle(color: Colors.black38)))
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: _compareList.map((r) => Container(
                        width: 160, margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(r.clinic.name, style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 10),
                          _compareRow('Distance', '${r.distKm.toStringAsFixed(1)} km'),
                          _compareRow('Wait',     '~${r.waitMin} min'),
                          _compareRow('Queue',    '${r.queueLen} patients'),
                          _compareRow('Status',   r.clinic.status),
                          const SizedBox(height: 10),
                          SizedBox(width: double.infinity, child: ElevatedButton(
                            onPressed: () {
                              setState(() => _showCompare = false);
                              Navigator.pushNamed(context, AppRoutes.joinQueue,
                                // Was `_selected?.clinic` in the fallback —
                                // same issue as the card button above:
                                // _selected is already a Clinic, it has no
                                // `.clinic` field to chain off of.
                                arguments: _compareList.isNotEmpty ? _compareList.first.clinic : _selected);
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            child: const Text('Join',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                          )),
                        ]),
                      )).toList(),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _compareRow(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45)),
      Text(val,   style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _RecClinic {
  final Clinic clinic;
  final double distKm;
  final int    waitMin;
  final int    queueLen;
  final double score;
  final String explanation;
  const _RecClinic({required this.clinic, required this.distKm,
      required this.waitMin, required this.queueLen,
      required this.score,   required this.explanation});
}

// ── Location prompt banner ─────────────────────────────────────────────────────
// Shown above the map when we couldn't get the patient's location, so they
// know why nearby clinics/distances aren't showing and can fix it in one tap
// instead of the map silently defaulting to Manila.
class _LocationPrompt extends StatelessWidget {
  final String issue; // 'service_off' | 'denied' | 'denied_forever' | 'unavailable'
  final VoidCallback onFix;
  const _LocationPrompt({required this.issue, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final (text, cta) = switch (issue) {
      'service_off' => (
          'Location services are off, so we can\'t show your position or '
              'sort clinics by distance.',
          'Turn On Location',
        ),
      'denied_forever' => (
          'Location access was denied. Enable it in Settings to see your '
              'position and nearby clinics.',
          'Open Settings',
        ),
      'unavailable' => (
          'Location is allowed, but we couldn\'t get a GPS fix. Make sure '
              'GPS is on and you have a clear signal (or set a location if '
              'you\'re on an emulator), then retry.',
          'Retry',
        ),
      _ => (
          'Allow location access to see your position and sort clinics by '
              'distance.',
          'Allow Location',
        ),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textDark, height: 1.3)),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onFix,
            child: Text(cta,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
