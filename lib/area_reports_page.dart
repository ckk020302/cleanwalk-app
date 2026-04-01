import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'report_issue_page.dart';

class AreaReport {
  final String id;
  final String title;
  final String description;
  final String reporterName;
  final DateTime createdAt;
  final List<String> imageUrls;
  final String urgency;
  final String status;
  final double? lat;
  final double? lng;
  final String? locationLabel;

  const AreaReport({
    required this.id,
    required this.title,
    required this.description,
    required this.reporterName,
    required this.createdAt,
    required this.imageUrls,
    required this.urgency,
    required this.status,
    this.lat,
    this.lng,
    this.locationLabel,
  });

  static AreaReport fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final location = (data['location'] as Map?)?.cast<String, dynamic>();

    DateTime createdAt = DateTime.now();
    final ts = data['createdAt'];
    if (ts is Timestamp) createdAt = ts.toDate();

    final imageUrls = (data['imageUrls'] is List)
        ? (data['imageUrls'] as List).whereType<String>().toList()
        : <String>[];

    return AreaReport(
      id: (data['reportId'] as String?) ?? doc.id,
      title:
          (data['title'] as String?) ??
          (data['category'] as String?) ??
          'Report',
      description: (data['description'] as String?) ?? '',
      reporterName: (data['reporterName'] as String?) ?? 'Anonymous',
      createdAt: createdAt,
      imageUrls: imageUrls,
      urgency: (data['urgency'] as String?) ?? 'Low',
      status: (data['status'] as String?) ?? 'Pending',
      lat: (location?['lat'] as num?)?.toDouble(),
      lng: (location?['lng'] as num?)?.toDouble(),
      locationLabel: (location?['label'] as String?),
    );
  }
}

class AreaReportsPage extends StatelessWidget {
  final String areaTitle;
  final List<AreaReport> reports;
  final double? areaLat;
  final double? areaLng;
  final double radiusMeters;
  final bool isNgo;

  const AreaReportsPage({
    super.key,
    required this.areaTitle,
    this.reports = const [],
    this.areaLat,
    this.areaLng,
    this.radiusMeters = 600,
    this.isNgo = false,
  });

  bool _isResolvedStatus(String status) {
    final value = status.trim().toLowerCase();
    return value == 'resolved' ||
        value == 'completed' ||
        value == 'closed' ||
        value == 'cleaned';
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  double _degToRad(double deg) => deg * pi / 180.0;

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  Color _urgencyColor(String u) {
    switch (u.toLowerCase()) {
      case 'high':
        return const Color(0xFFC62828);
      case 'medium':
        return const Color(0xFFF9A825);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  Color _statusColor(String status) {
    if (_isResolvedStatus(status)) {
      return Colors.grey;
    }
    return const Color(0xFF1976D2);
  }

  Widget _proofPreview(AreaReport r) {
    if (r.imageUrls.isEmpty) {
      return Container(
        color: const Color(0xFFEFEFEF),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 32),
            SizedBox(height: 6),
            Text('No online image', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return Image.network(
      r.imageUrls.first,
      fit: BoxFit.cover,
    );
  }

  Stream<List<AreaReport>> _firestoreReportsStream() {
    return FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map((snap) {
          final all = snap.docs.map(AreaReport.fromDoc).toList();

          final active = all
              .where((r) => !_isResolvedStatus(r.status))
              .toList();

          if (areaLat == null || areaLng == null) return active;

          return active.where((r) {
            if (r.lat == null || r.lng == null) return false;
            final d = _distanceMeters(areaLat!, areaLng!, r.lat!, r.lng!);
            return d <= radiusMeters;
          }).toList();
        });
  }

  void _openReportIssue(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportIssuePage(
          prefilledAreaName: areaTitle,
          prefilledLat: areaLat,
          prefilledLng: areaLng,
          source: 'area_reports',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usingDemo = reports.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: Text(areaTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: usingDemo
                ? _buildList(context, reports)
                : StreamBuilder<List<AreaReport>>(
                    stream: _firestoreReportsStream(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final data = snapshot.data!;
                      return _buildList(context, data);
                    },
                  ),
          ),
          if (!isNgo)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => _openReportIssue(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0AA64B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Report Issue in This Area',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<AreaReport> sorted) {
    if (sorted.isEmpty) {
      return const Center(
        child: Text('No active reports in this area.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final r = sorted[i];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(r.status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        r.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(r.status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _proofPreview(r),
                  ),
                ),
                const SizedBox(height: 10),
                Text(r.description),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _urgencyColor(r.urgency).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        r.urgency,
                        style: TextStyle(
                          color: _urgencyColor(r.urgency),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Reported by: ${r.reporterName}'),
                Text(_timeAgo(r.createdAt)),
              ],
            ),
          ),
        );
      },
    );
  }
}