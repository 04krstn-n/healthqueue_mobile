import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:healthqueue_mobapp/models/appointment_models.dart';
import 'package:provider/provider.dart';

import '../services/clinic_service.dart';
import '../services/api_service.dart';
import '../core/constants/app_colors.dart';
import '../core/routes/app_routes.dart';
import '../state/app_state.dart';
import '../models/queue_models.dart';

class _ScoredClinic {
  final Clinic clinic;
  final double distKm;
  final double score;
  final String explanation;

  const _ScoredClinic({
    required this.clinic,
    required this.distKm,
    required this.score,
    required this.explanation,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Completer<GoogleMapController> _mapCtrl =
      Completer<GoogleMapController>();

  static const LatLng _metroManila = LatLng(14.5995, 120.9842);

  LatLng? _userPos;
  Set<Marker> _markers = {};

  List<Clinic> _clinics = [];
  List<_ScoredClinic> _recommended = [];
  bool _clinicsLoad = true;

  List<dynamic> _notifications = [];
  bool _notifOpen = false;
  int _unreadCount = 0;

  Timer? _timer;

  bool _isClinicOpen(Clinic c) {
    return c.status.toLowerCase() == 'open';
  }

  @override
  void initState() {
    super.initState();

    _loadAll();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<AppState>().fetchQueueStatus();
      context.read<AppState>().fetchAppointments();
      _loadNotifications();
    });

    // Refresh queue status and notifications every 15 seconds.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;

      context.read<AppState>().fetchQueueStatus();
      _loadNotifications();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadClinics(),
      _locateUser(),
    ]);

    _computeRecommendations();
  }

  Future<void> _loadClinics() async {
    try {
      final list = await ClinicService.getDirectory();

      if (mounted) {
        setState(() {
          _clinics = list;
          _clinicsLoad = false;
        });
      }

      _rebuildMarkers();
    } catch (_) {
      if (mounted) {
        setState(() {
          _clinicsLoad = false;
        });
      }
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final list = await ApiService.getNotifications();

      if (mounted) {
        setState(() {
          _notifications = list;
          _unreadCount = list.where((n) => n['isRead'] == false).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    await ApiService.markAllNotificationsRead();

    if (!mounted) return;

    setState(() {
      _notifications = _notifications
          .map(
            (n) => {
              ...n as Map<String, dynamic>,
              'isRead': true,
            },
          )
          .toList();

      _unreadCount = 0;
    });
  }

  Future<void> _locateUser() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }

      var perm = await Geolocator.checkPermission();

      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _userPos = LatLng(
            pos.latitude,
            pos.longitude,
          );
        });

        if (_mapCtrl.isCompleted) {
          final c = await _mapCtrl.future;

          c.animateCamera(
            CameraUpdate.newLatLng(_userPos!),
          );
        }
      }
    } catch (_) {}
  }

  void _computeRecommendations() {
    if (_clinics.isEmpty) return;

    final user = _userPos;

    final scored = _clinics.where(_isClinicOpen).map((c) {
      final dist = (user != null && c.hasLocation)
          ? _distKm(
              user,
              LatLng(
                c.latitude!,
                c.longitude!,
              ),
            )
          : 99.0;

      final wait = c.currentWaitingTime.toDouble();
      final queue = c.queueLength.toDouble();

      final score = wait * 0.6 + dist * 4.0 + queue * 0.5;

      String exp = dist < 2
          ? 'Very close (${dist.toStringAsFixed(1)} km)'
          : dist < 5
              ? 'Nearby (${dist.toStringAsFixed(1)} km)'
              : '${dist.toStringAsFixed(1)} km away';

      exp += wait == 0
          ? ' · No wait'
          : wait < 15
              ? ' · Short wait (~${wait.toInt()} min)'
              : ' · ~${wait.toInt()} min wait';

      return _ScoredClinic(
        clinic: c,
        distKm: dist,
        score: score,
        explanation: exp,
      );
    }).toList()
      ..sort(
        (a, b) => a.score.compareTo(b.score),
      );

    if (mounted) {
      setState(() {
        _recommended = scored.take(3).toList();
      });
    }
  }

  double _distKm(LatLng a, LatLng b) {
    const r = 6371.0;

    final dLat = _rad(
      b.latitude - a.latitude,
    );

    final dLon = _rad(
      b.longitude - a.longitude,
    );

    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return r *
        2 *
        math.atan2(
          math.sqrt(x),
          math.sqrt(1 - x),
        );
  }

  double _rad(double d) {
    return d * math.pi / 180;
  }

  void _rebuildMarkers() {
    final m = <Marker>{};

    for (final c in _clinics) {
      if (!c.hasLocation) continue;

      m.add(
        Marker(
          markerId: MarkerId(c.id),
          position: LatLng(
            c.latitude!,
            c.longitude!,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: c.name,
            snippet: c.address,
          ),
        ),
      );
    }

    if (_userPos != null) {
      m.add(
        Marker(
          markerId: const MarkerId('_user'),
          position: _userPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(
            title: 'You are here',
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers = m;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // NOTIFICATION PANEL
  // ─────────────────────────────────────────────────────────────

  Widget _buildNotifPanel() {
    return Positioned(
      top: 0,
      right: 0,
      left: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _notifOpen = false;
          });
        },
        child: Container(
          color: Colors.black45,
          child: Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.only(
                  top: 58,
                  right: 8,
                  left: 60,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 20,
                      color: Colors.black.withValues(alpha: .15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        14,
                        4,
                        4,
                        2,
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Notifications',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          if (_unreadCount > 0)
                            TextButton(
                              onPressed: _markAllRead,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Mark all read',
                                style: TextStyle(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            onPressed: () {
                              setState(() {
                                _notifOpen = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const Divider(
                      height: 1,
                      thickness: 1,
                    ),

                    // Notifications
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 300,
                      ),
                      child: _notifications.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No notifications',
                                style: TextStyle(
                                  color: Colors.black38,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _notifications.length,
                              separatorBuilder: (_, __) {
                                return const Divider(
                                  height: 1,
                                  thickness: 1,
                                );
                              },
                              itemBuilder: (ctx, i) {
                                final n =
                                    _notifications[i] as Map<String, dynamic>;

                                final read = n['isRead'] == true;

                                return InkWell(
                                  onTap: () async {
                                    await ApiService.markNotificationRead(
                                      n['_id'] as String,
                                    );

                                    if (!mounted) return;

                                    setState(() {
                                      _notifications[i] = {
                                        ...n,
                                        'isRead': true,
                                      };

                                      _unreadCount = _notifications
                                          .where(
                                            (x) =>
                                                (x as Map)['isRead'] == false,
                                          )
                                          .length;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Notification icon
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor:
                                              AppColors.primary.withValues(
                                            alpha: .12,
                                          ),
                                          child: Icon(
                                            _notifIcon(
                                              n['type'] as String?,
                                            ),
                                            size: 16,
                                            color: AppColors.primary,
                                          ),
                                        ),

                                        const SizedBox(width: 12),

                                        // Notification text
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                n['title'] ?? '',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.15,
                                                  fontWeight: read
                                                      ? FontWeight.normal
                                                      : FontWeight.w700,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(
                                                height: 2,
                                              ),
                                              Text(
                                                n['message'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  height: 1.2,
                                                  color: Colors.black54,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _notifIcon(String? type) {
    switch (type) {
      case 'queue_joined':
        return Icons.queue;

      case 'queue_called':
        return Icons.notifications_active;

      case 'queue_completed':
        return Icons.check_circle;

      case 'appointment_booked':
        return Icons.calendar_today;

      case 'appointment_reminder':
        return Icons.alarm;

      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    final qStatus = appState.currentQueueStatus;
    final appts = appState.appointments;

    // Next upcoming appointment
    final now = DateTime.now();

    final upcoming = appts.where((a) {
      return a.date.isAfter(now) &&
          a.status != AppointmentStatus.cancelled &&
          a.status != AppointmentStatus.noShow;
    }).toList()
      ..sort(
        (a, b) => a.date.compareTo(b.date),
      );

    final nextAppt = upcoming.isNotEmpty ? upcoming.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ─────────────────────────────────────────────
              // APP BAR
              // ─────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 105,
                floating: false,
                pinned: true,
                snap: false,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                automaticallyImplyLeading: false,
                actions: [
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.notifications_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _notifOpen = !_notifOpen;
                          });
                        },
                      ),
                      if (_unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$_unreadCount',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.person_outline,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.profile,
                      );
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF2563EB),
                          Color(0xFF1D4ED8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      56,
                      20,
                      16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good ${_greeting()}, ${user?.fullName.split(' ').first ?? 'Patient'}!',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _clinicsLoad
                              ? 'Loading clinics…'
                              : '${_clinics.where(_isClinicOpen).length} clinics open nearby',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ─────────────────────────────────────────────
              // HOME CONTENT
              // ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active queue
                      if (qStatus.inQueue) ...[
                        _sectionTitle(
                          'Your Active Queue',
                        ),
                        _ActiveQueueCard(
                          queueEntry: qStatus.entry!,
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Upcoming appointment
                      if (nextAppt != null) ...[
                        _sectionTitle(
                          'Upcoming Appointment',
                        ),
                        _AppointmentReminderCard(
                          appt: nextAppt,
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Quick actions
                      _sectionTitle('Quick Actions'),

                      _QuickActions(
                        onMap: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.clinicMap,
                          );
                        },
                        onAiInsights: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.aiInsights,
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Recommended clinics
                      _sectionTitle(
                        'Recommended Clinics',
                      ),

                      if (_clinicsLoad)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_recommended.isEmpty)
                        _emptyCard(
                          'No open clinics found nearby',
                        )
                      else
                        Column(
                          children: _recommended
                              .map(
                                (r) => _RecommendationCard(
                                  rec: r,
                                ),
                              )
                              .toList(),
                        ),

                      const SizedBox(height: 24),

                      // Map
                      _sectionTitle(
                        'Nearby Clinics Map',
                      ),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 200,
                          child: GoogleMap(
                            onMapCreated: (c) {
                              if (!_mapCtrl.isCompleted) {
                                _mapCtrl.complete(c);
                              }
                            },
                            initialCameraPosition: const CameraPosition(
                              target: _metroManila,
                              zoom: 12,
                            ),
                            markers: _markers,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.clinicMap,
                            );
                          },
                          child: const Text(
                            'Open Full Map →',
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Notification overlay
          if (_notifOpen) _buildNotifPanel(),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;

    if (h < 12) {
      return 'morning';
    }

    if (h < 18) {
      return 'afternoon';
    }

    return 'evening';
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          msg,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black38,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ACTIVE QUEUE CARD
// ─────────────────────────────────────────────────────────────

class _ActiveQueueCard extends StatelessWidget {
  final QueueEntry queueEntry;

  const _ActiveQueueCard({
    required this.queueEntry,
  });

  @override
  Widget build(BuildContext context) {
    final e = queueEntry;
    final isCalled = e.status == QueueStatus.serving;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCalled
              ? [
                  const Color(0xFF16A34A),
                  const Color(0xFF15803D),
                ]
              : [
                  const Color(0xFF2563EB),
                  const Color(0xFF1D4ED8),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            color:
                (isCalled ? Colors.green : Colors.blue).withValues(alpha: .25),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCalled ? Icons.notifications_active : Icons.queue,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isCalled ? "You're being called!" : 'Active Queue',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  e.status.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.queueNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      e.clinicName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      e.serviceName,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${e.position}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'position',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '~${e.estimatedWait} min',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'ETA',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isCalled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.run_circle_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please proceed to the counter now!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.queueMonitoring,
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(
                  color: Colors.white54,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'View Details',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// APPOINTMENT REMINDER
// ─────────────────────────────────────────────────────────────

class _AppointmentReminderCard extends StatelessWidget {
  final dynamic appt;

  const _AppointmentReminderCard({
    required this.appt,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmtDate(appt.date as DateTime);

    final svcName = (appt.serviceName?.isNotEmpty == true)
        ? appt.serviceName as String
        : (appt.department?.isNotEmpty == true
            ? appt.department as String
            : 'Appointment');

    final clinic = appt.clinicName as String? ?? '';

    final slot = appt.timeLabel as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: .2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today,
              color: Color(0xFF7C3AED),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  svcName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  clinic,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
                Text(
                  '$dateStr${slot.isNotEmpty ? ' · $slot' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7C3AED),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Colors.black26,
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    const days = [
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ];

    return '${days[d.weekday % 7]}, '
        '${months[d.month - 1]} ${d.day}';
  }
}

// ─────────────────────────────────────────────────────────────
// QUICK ACTIONS
// ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final VoidCallback onMap;
  final VoidCallback onAiInsights;

  const _QuickActions({
    required this.onMap,
    required this.onAiInsights,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QABtn(
            icon: Icons.map_outlined,
            label: 'Find Clinic',
            color: const Color(0xFF0D9488),
            bg: const Color(0xFFF0FDFA),
            onTap: onMap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QABtn(
            icon: Icons.auto_awesome_outlined,
            label: 'AI Health\nForecast',
            color: const Color(0xFF7C3AED),
            bg: const Color(0xFFF5F3FF),
            onTap: onAiInsights,
          ),
        ),
      ],
    );
  }
}

class _QABtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _QABtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// RECOMMENDATION CARD
// ─────────────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  final _ScoredClinic rec;

  const _RecommendationCard({
    required this.rec,
  });

  @override
  Widget build(BuildContext context) {
    final c = rec.clinic;
    final wait = c.currentWaitingTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 6,
            color: Colors.black.withValues(alpha: .04),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_hospital_outlined,
                  color: Color(0xFF2563EB),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      rec.explanation,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: wait == 0
                          ? const Color(
                              0xFFF0FDF4,
                            )
                          : const Color(
                              0xFFFFF7ED,
                            ),
                      borderRadius: BorderRadius.circular(
                        99,
                      ),
                    ),
                    child: Text(
                      wait == 0 ? 'No wait' : '~$wait min',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: wait == 0
                            ? const Color(
                                0xFF16A34A,
                              )
                            : const Color(
                                0xFFD97706,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${rec.distKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.joinQueue,
                      arguments: c,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(
                      color: Color(0xFF2563EB),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.queue,
                    size: 14,
                  ),
                  label: const Text(
                    'Queue Here',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.bookAppointment,
                      arguments: c,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                  ),
                  label: const Text(
                    'Book Appt',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}