import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';

import 'pick_location_page.dart';

enum DirtinessLevel { low, medium, high }

class _EventSpot {
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

  const _EventSpot({
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

  factory _EventSpot.fromDoc(DocumentSnapshot doc) {
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

    DateTime createdAt = DateTime.now();
    final ts = data['createdAt'];
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    }

    return _EventSpot(
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
      severity: _urgencyToLevel(urgency),
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

class _AreaCluster {
  final String id;
  final LatLng center;
  final String title;
  final String? locationLabel;
  final DirtinessLevel severity;
  final List<_EventSpot> reports;
  final _EventSpot latestReport;

  const _AreaCluster({
    required this.id,
    required this.center,
    required this.title,
    required this.locationLabel,
    required this.severity,
    required this.reports,
    required this.latestReport,
  });

  int get reportCount => reports.length;

  bool get isVerified => reportCount >= 3;
}

class _ClusterBuilder {
  LatLng center;
  final List<_EventSpot> reports;

  _ClusterBuilder({required this.center, required this.reports});
}

class _RecommendedLocation {
  final _AreaCluster area;
  final double distanceMeters;

  const _RecommendedLocation({
    required this.area,
    required this.distanceMeters,
  });
}

class NgoCreateEventPage extends StatefulWidget {
  final double? prefilledLat;
  final double? prefilledLng;
  final String? prefilledLocationName;

  const NgoCreateEventPage({
    super.key,
    this.prefilledLat,
    this.prefilledLng,
    this.prefilledLocationName,
  });

  @override
  State<NgoCreateEventPage> createState() => _NgoCreateEventPageState();
}

class _NgoCreateEventPageState extends State<NgoCreateEventPage> {
  static const double _clusterDistanceMeters = 80;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _volunteersController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedDuration;

  bool _publishing = false;

  String? _selectedLocationLabel;
  double? _selectedLat;
  double? _selectedLng;
  _AreaCluster? _selectedAreaCluster;

  List<_RecommendedLocation> _verifiedRecommendations = [];

  late final Future<List<_RecommendedLocation>> _recommendedFuture;

  static const List<String> _durationOptions = [
    '30 minutes',
    '1 hour',
    '1 hour 30 minutes',
    '2 hours',
    '2 hours 30 minutes',
    '3 hours',
    '4 hours',
    '5 hours',
    '6 hours',
  ];

  @override
  void initState() {
    super.initState();

    _selectedLocationLabel = widget.prefilledLocationName;
    _selectedLat = widget.prefilledLat;
    _selectedLng = widget.prefilledLng;

    _recommendedFuture = _loadRecommendedLocations();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _volunteersController.dispose();
    super.dispose();
  }

  bool _isResolvedStatus(String status) {
    final value = status.trim().toLowerCase();
    return value == 'resolved' ||
        value == 'completed' ||
        value == 'closed' ||
        value == 'cleaned';
  }

  Future<List<_RecommendedLocation>> _loadRecommendedLocations() async {
    final snap = await FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .get();

    final reports = snap.docs
        .map(_EventSpot.fromDoc)
        .where((report) => !_isResolvedStatus(report.status))
        .toList();

    final clusters = _groupReportsIntoAreas(reports);
    final verifiedClusters = clusters.where((c) => c.isVerified).toList();

    final double? baseLat = widget.prefilledLat;
    final double? baseLng = widget.prefilledLng;

    final recommended = verifiedClusters.map((area) {
      double distance = double.infinity;

      if (baseLat != null && baseLng != null) {
        distance = Geolocator.distanceBetween(
          baseLat,
          baseLng,
          area.center.latitude,
          area.center.longitude,
        );
      }

      return _RecommendedLocation(area: area, distanceMeters: distance);
    }).toList();

    recommended.sort((a, b) {
      final aDistance = a.distanceMeters;
      final bDistance = b.distanceMeters;

      if (aDistance == bDistance) {
        return b.area.latestReport.createdAt.compareTo(
          a.area.latestReport.createdAt,
        );
      }
      return aDistance.compareTo(bDistance);
    });

    _verifiedRecommendations = recommended;

    return recommended;
  }

  List<_AreaCluster> _groupReportsIntoAreas(List<_EventSpot> reports) {
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

      return _AreaCluster(
        id: latest.id,
        center: builder.center,
        title: bestLabel.isNotEmpty ? bestLabel : latest.title,
        locationLabel: bestLabel.isNotEmpty ? bestLabel : latest.locationLabel,
        severity: highestSeverity,
        reports: sortedReports,
        latestReport: latest,
      );
    }).toList();

    clusters.sort(
      (a, b) => b.latestReport.createdAt.compareTo(a.latestReport.createdAt),
    );

    return clusters;
  }

  Color _severityColor(DirtinessLevel level) {
    switch (level) {
      case DirtinessLevel.low:
        return const Color(0xFF2E7D32);
      case DirtinessLevel.medium:
        return const Color(0xFFF9A825);
      case DirtinessLevel.high:
        return const Color(0xFFC62828);
    }
  }

  String _severityText(DirtinessLevel level) {
    switch (level) {
      case DirtinessLevel.low:
        return 'Low';
      case DirtinessLevel.medium:
        return 'Moderate';
      case DirtinessLevel.high:
        return 'Severe';
    }
  }

  String _formatDistance(double meters) {
    if (!meters.isFinite) return 'Distance unavailable';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  _RecommendedLocation? _matchNearestVerifiedLocation(
    double lat,
    double lng, {
    double maxDistanceMeters = 120,
  }) {
    _RecommendedLocation? bestMatch;
    double bestDistance = double.infinity;

    for (final item in _verifiedRecommendations) {
      final area = item.area;

      final distance = Geolocator.distanceBetween(
        lat,
        lng,
        area.center.latitude,
        area.center.longitude,
      );

      if (distance <= maxDistanceMeters && distance < bestDistance) {
        bestDistance = distance;
        bestMatch = item;
      }
    }

    return bestMatch;
  }

  Future<void> _pickOtherLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationPage(
          initialLat: _selectedLat ?? widget.prefilledLat,
          initialLng: _selectedLng ?? widget.prefilledLng,
        ),
      ),
    );

    if (!mounted || result == null) return;

    LatLng? pickedPoint;
    String? pickedLabel;

    if (result is Map) {
      final point = result['point'];
      final label = result['label'];

      if (point is LatLng) {
        pickedPoint = point;
        if (label is String && label.trim().isNotEmpty) {
          pickedLabel = label.trim();
        }
      }
    } else if (result is LatLng) {
      pickedPoint = result;
    }

    if (pickedPoint == null) return;

    final matched = _matchNearestVerifiedLocation(
      pickedPoint.latitude,
      pickedPoint.longitude,
    );

    if (matched == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This location is not a verified dirtiness area. Please choose a verified location.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final matchedLabel =
        (matched.area.locationLabel != null &&
                matched.area.locationLabel!.trim().isNotEmpty)
            ? matched.area.locationLabel!
            : matched.area.title;

    setState(() {
      _selectedLat = matched.area.center.latitude;
      _selectedLng = matched.area.center.longitude;
      _selectedLocationLabel = matchedLabel;
      _selectedAreaCluster = matched.area;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pickedLabel != null && pickedLabel.isNotEmpty
              ? 'Nearest verified location selected: $matchedLabel'
              : 'Verified location selected: $matchedLabel',
        ),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final tomorrow = todayOnly.add(const Duration(days: 1));

    final initial = _selectedDate ?? tomorrow;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(tomorrow) ? tomorrow : initial,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 3),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final initialDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime?.hour ?? 8,
      _selectedTime?.minute ?? 0,
    );

    DateTime tempPicked = initialDateTime;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.light,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: false,
                      minuteInterval: 5,
                      initialDateTime: initialDateTime,
                      onDateTimeChanged: (value) {
                        tempPicked = value;
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, tempPicked),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('OK'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = TimeOfDay(
          hour: picked.hour,
          minute: picked.minute,
        );
      });
    }
  }

  Future<void> _pickDuration() async {
    String tempSelected = _selectedDuration ?? _durationOptions[0];

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Duration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 52,
                    perspective: 0.003,
                    diameterRatio: 1.4,
                    controller: FixedExtentScrollController(
                      initialItem: _durationOptions.indexOf(tempSelected) >= 0
                          ? _durationOptions.indexOf(tempSelected)
                          : 0,
                    ),
                    onSelectedItemChanged: (index) {
                      tempSelected = _durationOptions[index];
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: _durationOptions.length,
                      builder: (context, index) {
                        final value = _durationOptions[index];
                        return Center(
                          child: Text(
                            value,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, tempSelected),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('OK'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDuration = picked;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'mm/dd/yy';
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<Map<String, dynamic>> _loadOrganizerData(String uid) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final data = userDoc.data() ?? {};

    final organizerName =
        (data['orgName'] as String?) ??
        (data['fullName'] as String?) ??
        'NGO Organizer';

    final organizerEmail =
        (data['email'] as String?) ??
        FirebaseAuth.instance.currentUser?.email ??
        '';

    final organizerPhone = (data['phone'] as String?) ?? '';

    return {
      'organizerName': organizerName,
      'organizerEmail': organizerEmail,
      'organizerPhone': organizerPhone,
    };
  }

  Future<void> _publishEvent() async {
    final validForm = _formKey.currentState?.validate() ?? false;

    if (!validForm) return;

    if (_selectedLocationLabel == null ||
        _selectedLocationLabel!.trim().isEmpty ||
        _selectedLat == null ||
        _selectedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a verified event location.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedIsVerified =
        _matchNearestVerifiedLocation(
          _selectedLat!,
          _selectedLng!,
          maxDistanceMeters: 30,
        ) !=
        null;

    if (!selectedIsVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only verified dirtiness locations can be used to create events.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedAreaCluster == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a verified recommended area first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose an event date.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final selectedDateOnly = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
    );

    if (!selectedDateOnly.isAfter(todayOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event date must be at least tomorrow.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose an event time.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedDuration == null || _selectedDuration!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose event duration.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to create an event.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _publishing = true);

    try {
      final organizerData = await _loadOrganizerData(currentUser.uid);
      final eventDateTime = _combineDateAndTime(_selectedDate!, _selectedTime!);
      final volunteersNeeded = int.parse(_volunteersController.text.trim());

      final linkedReportId = _selectedAreaCluster?.latestReport.id;
      final linkedReportIds =
          _selectedAreaCluster?.reports.map((r) => r.id).toList() ??
          <String>[];

      await FirebaseFirestore.instance.collection('events').add({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'locationName': _selectedLocationLabel!.trim(),
        'latitude': _selectedLat,
        'longitude': _selectedLng,
        'dateTime': Timestamp.fromDate(eventDateTime),
        'dateLabel': _formatDate(_selectedDate),
        'timeLabel': _formatTime(_selectedTime),
        'duration': _selectedDuration!.trim(),
        'volunteersNeeded': volunteersNeeded,
        'joinedCount': 0,
        'joinedUserIds': <String>[],
        'organizerName': organizerData['organizerName'],
        'organizerEmail': organizerData['organizerEmail'],
        'organizerPhone': organizerData['organizerPhone'],
        'status': 'upcoming',
        'createdByUid': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'linkedReportId': linkedReportId,
        'linkedReportIds': linkedReportIds,
        'sourceAreaReportCount': linkedReportIds.length,
        'issueResolved': false,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event published successfully.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );

      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to publish event: ${e.message ?? e.code}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to publish event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _publishing = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF7F7F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1D3B2D),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0AA64B);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Cleanup Event')),
      body: SafeArea(
        child: FutureBuilder<List<_RecommendedLocation>>(
          future: _recommendedFuture,
          builder: (context, snapshot) {
            final recommendations =
                snapshot.data ?? const <_RecommendedLocation>[];

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Event Title'),
                    TextFormField(
                      controller: _titleController,
                      decoration: _inputDecoration(
                        hint: 'e.g., Beach Cleanup Drive',
                        icon: Icons.title,
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Please enter event title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _sectionLabel('Description'),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 5,
                      decoration: _inputDecoration(
                        hint: 'Describe the cleanup event and its purpose...',
                        icon: Icons.notes,
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Please enter event description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    _sectionLabel('Recommended Verified Locations'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FBF9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8E3)),
                      ),
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : recommendations.isEmpty
                              ? const Text(
                                  'No verified locations available yet.',
                                  style: TextStyle(color: Colors.black54),
                                )
                              : Column(
                                  children: recommendations.take(5).map((item) {
                                    final area = item.area;
                                    final areaLabel =
                                        (area.locationLabel != null &&
                                                area.locationLabel!
                                                    .trim()
                                                    .isNotEmpty)
                                            ? area.locationLabel!
                                            : area.title;

                                    final isSelected =
                                        _selectedLat == area.center.latitude &&
                                        _selectedLng == area.center.longitude &&
                                        _selectedLocationLabel == areaLabel;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? green.withOpacity(0.08)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected
                                              ? green
                                              : const Color(0xFFE4E7EC),
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                        title: Text(
                                          areaLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _miniTag(
                                                text: _formatDistance(
                                                  item.distanceMeters,
                                                ),
                                                color: const Color(0xFF1976D2),
                                              ),
                                              _miniTag(
                                                text:
                                                    '${area.reportCount} reports',
                                                color: const Color(0xFF6A1B9A),
                                              ),
                                              _miniTag(
                                                text: _severityText(
                                                  area.severity,
                                                ),
                                                color: _severityColor(
                                                  area.severity,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        trailing: isSelected
                                            ? const Icon(
                                                Icons.check_circle,
                                                color: green,
                                              )
                                            : const Icon(Icons.chevron_right),
                                        onTap: () {
                                          setState(() {
                                            _selectedLocationLabel = areaLabel;
                                            _selectedLat = area.center.latitude;
                                            _selectedLng =
                                                area.center.longitude;
                                            _selectedAreaCluster = area;
                                          });
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                    ),
                    const SizedBox(height: 18),

                    _sectionLabel('Search Other Location'),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickOtherLocation,
                        icon: const Icon(Icons.search),
                        label: const Text('Search / Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Only locations matched to verified dirtiness areas can be selected.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 18),

                    _sectionLabel('Selected Location'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E7EC)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.place_outlined,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (_selectedLocationLabel != null &&
                                      _selectedLocationLabel!.trim().isNotEmpty)
                                  ? _selectedLocationLabel!
                                  : 'No verified location selected yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color:
                                    (_selectedLocationLabel != null &&
                                            _selectedLocationLabel!
                                                .trim()
                                                .isNotEmpty)
                                        ? Colors.black87
                                        : Colors.black45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('Date'),
                              InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration(
                                    hint: 'mm/dd/yy',
                                    icon: Icons.calendar_today_outlined,
                                  ),
                                  child: Text(
                                    _formatDate(_selectedDate),
                                    style: TextStyle(
                                      color: _selectedDate == null
                                          ? Colors.black45
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('Time'),
                              InkWell(
                                onTap: _pickTime,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration(
                                    hint: '--:--',
                                    icon: Icons.access_time_outlined,
                                  ),
                                  child: Text(
                                    _formatTime(_selectedTime),
                                    style: TextStyle(
                                      color: _selectedTime == null
                                          ? Colors.black45
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    _sectionLabel('Duration'),
                    InkWell(
                      onTap: _pickDuration,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          hint: 'Select duration',
                          icon: Icons.timelapse_outlined,
                        ),
                        child: Text(
                          _selectedDuration ?? 'Select duration',
                          style: TextStyle(
                            color: _selectedDuration == null
                                ? Colors.black45
                                : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    _sectionLabel('Volunteers Needed'),
                    TextFormField(
                      controller: _volunteersController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: _inputDecoration(
                        hint: 'Number of volunteers',
                        icon: Icons.groups_outlined,
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) {
                          return 'Please enter volunteers needed';
                        }

                        final numValue = int.tryParse(text);
                        if (numValue == null || numValue <= 0) {
                          return 'Enter a valid number';
                        }

                        if (numValue > 999) {
                          return 'Maximum is 999 volunteers';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFFAF1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFB7E4C0)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.event_available, color: green),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Event Publication\nOnce created, your event will be visible to CleanWalk users in the Events section.',
                              style: TextStyle(
                                color: Color(0xFF227A36),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _publishing ? null : _publishEvent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _publishing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create & Publish Event',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _miniTag({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}