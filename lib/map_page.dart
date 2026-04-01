import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'report_issue_page.dart';
import 'area_reports_page.dart';
import 'pick_location_page.dart';
import 'ngo_create_event_page.dart';

enum DirtinessLevel { low, medium, high }

class FirestoreSpot {
  final String id;
  final String title;
  final String description;
  final String reporterName;
  final DateTime createdAt;
  final LatLng point;
  final String? locationLabel;
  final DirtinessLevel severity;
  final String urgency;
  final String status;

  const FirestoreSpot({
    required this.id,
    required this.title,
    required this.description,
    required this.reporterName,
    required this.createdAt,
    required this.point,
    required this.locationLabel,
    required this.severity,
    required this.urgency,
    required this.status,
  });

  factory FirestoreSpot.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final location = (data['location'] as Map?)?.cast<String, dynamic>() ?? {};

    final lat =
        (location['lat'] as num?)?.toDouble() ??
        (data['latitude'] as num?)?.toDouble() ??
        3.1390;
    final lng =
        (location['lng'] as num?)?.toDouble() ??
        (data['longitude'] as num?)?.toDouble() ??
        101.6869;

    final urgency =
        (data['urgency'] as String?) ?? (data['severity'] as String?) ?? 'Low';
    final severity = _urgencyToLevel(urgency);

    DateTime createdAt = DateTime.now();
    final ts = data['createdAt'];
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    }

    return FirestoreSpot(
      id: (data['reportId'] as String?) ?? doc.id,
      title:
          (data['title'] as String?) ??
          (data['category'] as String?) ??
          'Report',
      description: (data['description'] as String?) ?? '',
      reporterName:
          (data['reportedBy'] as String?) ??
          (data['reporterName'] as String?) ??
          'Anonymous',
      createdAt: createdAt,
      point: LatLng(lat, lng),
      locationLabel:
          (location['label'] as String?) ??
          (data['address'] as String?) ??
          (data['locationLabel'] as String?),
      severity: severity,
      urgency: urgency,
      status: (data['status'] as String?) ?? 'Pending',
    );
  }

  static DirtinessLevel _urgencyToLevel(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'high':
      case 'severe':
        return DirtinessLevel.high;
      case 'medium':
      case 'moderate':
        return DirtinessLevel.medium;
      default:
        return DirtinessLevel.low;
    }
  }
}

class AreaCluster {
  final String id;
  final LatLng center;
  final String title;
  final String? locationLabel;
  final DirtinessLevel severity;
  final String status;
  final List<FirestoreSpot> reports;
  final FirestoreSpot latestReport;

  const AreaCluster({
    required this.id,
    required this.center,
    required this.title,
    required this.locationLabel,
    required this.severity,
    required this.status,
    required this.reports,
    required this.latestReport,
  });

  int get reportCount => reports.length;

  bool get isVerified => reportCount >= 3;
}

class _ClusterBuilder {
  LatLng center;
  final List<FirestoreSpot> reports;

  _ClusterBuilder({required this.center, required this.reports});
}

class MapPage extends StatefulWidget {
  final bool isNgo;

  const MapPage({super.key, this.isNgo = false});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const double _clusterDistanceMeters = 80;

  final MapController _mapController = MapController();

  LatLng _center = const LatLng(3.1390, 101.6869);
  LatLng? _userPoint;

  bool _loadingLocation = true;
  String? _locationError;

  DirtinessLevel? _filter;
  String? _searchedLocationLabel;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  bool _isResolvedStatus(String status) {
    final value = status.trim().toLowerCase();
    return value == 'resolved' ||
        value == 'completed' ||
        value == 'closed' ||
        value == 'cleaned';
  }

  Future<void> _initLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loadingLocation = false;
          _locationError = 'Location services are disabled.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _loadingLocation = false;
          _locationError = 'Location permission denied.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loadingLocation = false;
          _locationError =
              'Location permission permanently denied. Enable it in Settings.';
        });
        return;
      }

      Position? pos;

      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } on TimeoutException {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          pos = lastKnown;
        } else {
          rethrow;
        }
      }

      final user = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _userPoint = user;
        _center = user;
        _loadingLocation = false;
      });

      _mapController.move(user, 16);
    } catch (e) {
      setState(() {
        _loadingLocation = false;
        _locationError =
            'Failed to get location. You can still use Pick on Map.';
      });
    }
  }

  Future<void> _openSearchLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationPage(
          initialLat: _center.latitude,
          initialLng: _center.longitude,
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (result is Map) {
      final point = result['point'];
      final label = result['label'];

      if (point is LatLng) {
        setState(() {
          _center = point;
          if (label is String && label.trim().isNotEmpty) {
            _searchedLocationLabel = label.trim();
          }
        });

        _mapController.move(point, 16);
      }
      return;
    }

    if (result is LatLng) {
      setState(() {
        _center = result;
      });
      _mapController.move(result, 16);
    }
  }

  Color _levelColor(DirtinessLevel level) {
    switch (level) {
      case DirtinessLevel.low:
        return const Color(0xFF2E7D32);
      case DirtinessLevel.medium:
        return const Color(0xFFF9A825);
      case DirtinessLevel.high:
        return const Color(0xFFC62828);
    }
  }

  String _levelText(DirtinessLevel level) {
    switch (level) {
      case DirtinessLevel.low:
        return 'Low';
      case DirtinessLevel.medium:
        return 'Moderate';
      case DirtinessLevel.high:
        return 'Severe';
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  Stream<List<FirestoreSpot>> _reportsStream() {
    return FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(FirestoreSpot.fromDoc)
              .where((report) => !_isResolvedStatus(report.status))
              .toList(),
        );
  }

  List<AreaCluster> _groupReportsIntoAreas(List<FirestoreSpot> reports) {
    final List<_ClusterBuilder> builders = [];

    for (final report in reports) {
      _ClusterBuilder? matchedCluster;

      for (final cluster in builders) {
        final distance = Geolocator.distanceBetween(
          report.point.latitude,
          report.point.longitude,
          cluster.center.latitude,
          cluster.center.longitude,
        );

        if (distance <= _clusterDistanceMeters) {
          matchedCluster = cluster;
          break;
        }
      }

      if (matchedCluster == null) {
        builders.add(_ClusterBuilder(center: report.point, reports: [report]));
      } else {
        matchedCluster.reports.add(report);

        final avgLat =
            matchedCluster.reports
                .map((r) => r.point.latitude)
                .reduce((a, b) => a + b) /
            matchedCluster.reports.length;

        final avgLng =
            matchedCluster.reports
                .map((r) => r.point.longitude)
                .reduce((a, b) => a + b) /
            matchedCluster.reports.length;

        matchedCluster.center = LatLng(avgLat, avgLng);
      }
    }

    final clusters = builders.map((builder) {
      final sortedReports = [...builder.reports]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final latest = sortedReports.first;

      DirtinessLevel highestSeverity = DirtinessLevel.low;
      for (final report in sortedReports) {
        if (report.severity == DirtinessLevel.high) {
          highestSeverity = DirtinessLevel.high;
          break;
        }
        if (report.severity == DirtinessLevel.medium) {
          highestSeverity = DirtinessLevel.medium;
        }
      }

      final bestLabel = sortedReports
          .map((r) => r.locationLabel)
          .whereType<String>()
          .firstWhere((label) => label.trim().isNotEmpty, orElse: () => '');

      return AreaCluster(
        id: latest.id,
        center: builder.center,
        title: bestLabel.isNotEmpty ? bestLabel : latest.title,
        locationLabel: bestLabel.isNotEmpty ? bestLabel : latest.locationLabel,
        severity: highestSeverity,
        status: latest.status,
        reports: sortedReports,
        latestReport: latest,
      );
    }).toList();

    clusters.sort(
      (a, b) => b.latestReport.createdAt.compareTo(a.latestReport.createdAt),
    );

    return clusters;
  }

  List<AreaCluster> _applyFilter(List<AreaCluster> clusters) {
    if (_filter == null) return clusters;
    return clusters.where((c) => c.severity == _filter).toList();
  }

  void _openAreaSheet(AreaCluster area) {
    final latest = area.latestReport;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          area.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _levelColor(area.severity).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _levelColor(area.severity).withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: _levelColor(area.severity),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Dirtiness Level: ${_levelText(area.severity)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _levelColor(area.severity),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: area.isVerified
                              ? const Color(0xFF2E7D32).withOpacity(0.12)
                              : const Color(0xFFF9A825).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: area.isVerified
                                ? const Color(0xFF2E7D32).withOpacity(0.35)
                                : const Color(0xFFF9A825).withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          area.isVerified
                              ? 'Verified Location'
                              : 'Pending Verification',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: area.isVerified
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFF9A825),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    latest.description.isNotEmpty
                        ? latest.description
                        : 'No description provided.',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const Divider(height: 20),
                  if (area.locationLabel != null &&
                      area.locationLabel!.trim().isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(area.locationLabel!)),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.layers_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Related reports in this area: ${area.reportCount}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          area.isVerified
                              ? 'This area has enough reports to be considered verified.'
                              : 'This area needs at least 3 reports to be verified.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Latest report by: ${latest.reporterName}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 18),
                      const SizedBox(width: 8),
                      Text(_timeAgo(latest.createdAt)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AreaReportsPage(
                                  areaTitle: area.locationLabel ?? area.title,
                                  reports: const [],
                                  areaLat: area.center.latitude,
                                  areaLng: area.center.longitude,
                                  isNgo: widget.isNgo,
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'View Reports',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onMainActionPressed() {
    if (widget.isNgo) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NgoCreateEventPage(
            prefilledLat: _userPoint?.latitude,
            prefilledLng: _userPoint?.longitude,
            prefilledLocationName: _searchedLocationLabel,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportIssuePage(
          source: "map",
          prefilledAreaName: _userPoint != null ? "Current GPS Location" : null,
          prefilledLat: _userPoint?.latitude,
          prefilledLng: _userPoint?.longitude,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.isNgo ? 'CleanWalk NGO Map' : 'CleanWalk Map',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'My location',
            onPressed: _initLocation,
            icon: _loadingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2E7D32),
        onPressed: _onMainActionPressed,
        icon: Icon(
          widget.isNgo
              ? Icons.event_available_outlined
              : Icons.add_a_photo_outlined,
        ),
        label: Text(widget.isNgo ? 'Create Event' : 'Report'),
      ),
      body: StreamBuilder<List<FirestoreSpot>>(
        stream: _reportsStream(),
        builder: (context, snapshot) {
          final allReports = snapshot.data ?? const <FirestoreSpot>[];
          final allClusters = _groupReportsIntoAreas(allReports);
          final visibleClusters = _applyFilter(allClusters);

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: _center, initialZoom: 15),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.cleanwalk',
                  ),
                  MarkerLayer(
                    markers: visibleClusters.map((area) {
                      return Marker(
                        point: area.center,
                        width: 46,
                        height: 46,
                        child: GestureDetector(
                          onTap: () => _openAreaSheet(area),
                          child: _ClusterPin(
                            color: _levelColor(area.severity),
                            count: area.reportCount,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_userPoint != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _userPoint!,
                          width: 48,
                          height: 48,
                          child: const _UserDot(),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white.withOpacity(0.96),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _openSearchLocation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.black54),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  (_searchedLocationLabel == null ||
                                          _searchedLocationLabel!
                                              .trim()
                                              .isEmpty)
                                      ? 'Search location...'
                                      : _searchedLocationLabel!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        (_searchedLocationLabel == null ||
                                                _searchedLocationLabel!
                                                    .trim()
                                                    .isEmpty)
                                            ? Colors.black45
                                            : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_searchedLocationLabel != null &&
                                  _searchedLocationLabel!.trim().isNotEmpty)
                                IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    setState(() {
                                      _searchedLocationLabel = null;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.black45,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.black45,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: _filter == null,
                            onTap: () => setState(() => _filter = null),
                            color: green,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Severe',
                            selected: _filter == DirtinessLevel.high,
                            onTap: () =>
                                setState(() => _filter = DirtinessLevel.high),
                            color: _levelColor(DirtinessLevel.high),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Moderate',
                            selected: _filter == DirtinessLevel.medium,
                            onTap: () =>
                                setState(() => _filter = DirtinessLevel.medium),
                            color: _levelColor(DirtinessLevel.medium),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Low',
                            selected: _filter == DirtinessLevel.low,
                            onTap: () =>
                                setState(() => _filter = DirtinessLevel.low),
                            color: _levelColor(DirtinessLevel.low),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 110,
                child: _LegendCard(
                  items: const [
                    _LegendItem(color: Color(0xFFC62828), label: 'Severe'),
                    _LegendItem(color: Color(0xFFF9A825), label: 'Moderate'),
                    _LegendItem(color: Color(0xFF2E7D32), label: 'Low'),
                    _LegendItem(color: Color(0xFF1976D2), label: 'You'),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                bottom: 110,
                child: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withOpacity(0.94),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      'Grouped Areas: ${visibleClusters.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                Container(
                  color: Colors.white.withOpacity(0.45),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              if (_locationError != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_locationError!)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ClusterPin extends StatelessWidget {
  final Color color;
  final int count;

  const _ClusterPin({
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.20),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFF1976D2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              spreadRadius: 2,
              color: Color(0x331976D2),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.15)
              : Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : Colors.black12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? color : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  final List<_LegendItem> items;
  const _LegendCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withOpacity(0.94),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Map Guide',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(i.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
}