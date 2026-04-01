import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'report_issue_page.dart';
import 'report_service.dart';

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Activity'),
          centerTitle: true,
        ),
        body: const SafeArea(
          child: Center(
            child: Text(
              'No user is logged in.',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Activity'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('reports')
              .where('userId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'You have not submitted any reports yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final location =
                    (data['location'] as Map?)?.cast<String, dynamic>() ?? {};

                final title = _readString(
                  data,
                  ['title', 'category', 'areaName', 'locationName', 'spotTitle'],
                  fallback: 'Unnamed Location',
                );

                final reason = _readString(
                  data,
                  ['reason', 'description', 'details', 'reportReason'],
                  fallback: 'No reason provided.',
                );

                final severity = _readString(
                  data,
                  ['severity', 'urgency', 'dirtinessLevel', 'level'],
                  fallback: 'Unknown',
                );

                final status = _readString(
                  data,
                  ['status'],
                  fallback: 'pending',
                ).toLowerCase();

                final bool isCompleted = status == 'resolved' ||
                    status == 'completed' ||
                    status == 'closed' ||
                    status == 'cleaned';

                final address = _firstNonEmpty([
                  location['label'],
                  data['address'],
                  data['locationAddress'],
                ]);

                final reportedBy = _readString(
                  data,
                  ['reportedBy', 'reportedByName', 'userName', 'reporterName'],
                  fallback: user.displayName ?? user.email ?? 'Unknown User',
                );

                final createdAt = _readTimestamp(
                  data,
                  ['createdAt', 'timestamp', 'reportedAt'],
                );

                final imageUrls = (data['imageUrls'] as List?)
                        ?.map((e) => e.toString())
                        .where((e) => e.trim().isNotEmpty)
                        .toList() ??
                    [];

                final firstImageUrl =
                    imageUrls.isNotEmpty ? imageUrls.first : null;

                final bool addressLooksLikeCoordinates =
                    _looksLikeCoordinates(address);

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (firstImageUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              firstImageUrl,
                              width: double.infinity,
                              height: 170,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: double.infinity,
                                  height: 170,
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: const Text('Failed to load image'),
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  width: double.infinity,
                                  height: 170,
                                  color: Colors.grey.shade100,
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _statusChip(status),
                            const SizedBox(width: 8),
                            _severityChip(severity),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        if (address.isNotEmpty && !addressLooksLikeCoordinates) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  address,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              createdAt != null
                                  ? _formatDateTime(createdAt)
                                  : 'Time unavailable',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                reportedBy,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isCompleted
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ReportIssuePage.edit(
                                              reportId: doc.id,
                                              reportData: data,
                                              source: (data['source'] ?? 'map')
                                                  .toString(),
                                            ),
                                          ),
                                        );
                                      },
                                child: const Text('Edit'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  _showReportDetails(
                                    context,
                                    docId: doc.id,
                                    title: title,
                                    reason: reason,
                                    severity: severity,
                                    status: status,
                                    address: address,
                                    reportedBy: reportedBy,
                                    createdAt: createdAt,
                                    rawData: data,
                                  );
                                },
                                child: const Text('View Details'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: isCompleted
                                ? null
                                : () => _confirmDelete(context, doc.id),
                            icon: Icon(
                              Icons.delete_outline,
                              color: isCompleted ? Colors.grey : Colors.red,
                            ),
                            label: Text(
                              'Delete Report',
                              style: TextStyle(
                                color: isCompleted ? Colors.grey : Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Future<void> _confirmDelete(BuildContext context, String reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Report'),
          content: const Text(
            'Are you sure you want to delete this report? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await ReportService.deleteReport(reportId: reportId);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report deleted successfully')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  static String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  static bool _looksLikeCoordinates(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('lat ') || lower.contains('lng ');
  }

  static DateTime? _readTimestamp(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
    }
    return null;
  }

  static Widget _severityChip(String severity) {
    final normalized = severity.toLowerCase();

    Color bgColor;
    Color textColor = Colors.white;
    String label;

    if (normalized == 'high' || normalized == 'severe') {
      bgColor = Colors.red;
      label = 'High';
    } else if (normalized == 'medium' || normalized == 'moderate') {
      bgColor = Colors.orange;
      label = 'Medium';
    } else if (normalized == 'low') {
      bgColor = Colors.green;
      label = 'Low';
    } else {
      bgColor = Colors.grey;
      label = severity;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  static Widget _statusChip(String status) {
    final normalized = status.toLowerCase();

    Color bgColor;
    Color textColor = Colors.white;
    String label;

    if (normalized == 'resolved' ||
        normalized == 'completed' ||
        normalized == 'closed' ||
        normalized == 'cleaned') {
      bgColor = Colors.green;
      label = 'Completed';
    } else if (normalized == 'in_progress') {
      bgColor = Colors.orange;
      label = 'In Progress';
    } else {
      bgColor = Colors.grey;
      label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  static void _showReportDetails(
    BuildContext context, {
    required String docId,
    required String title,
    required String reason,
    required String severity,
    required String status,
    required String address,
    required String reportedBy,
    required DateTime? createdAt,
    required Map<String, dynamic> rawData,
  }) {
    final location = (rawData['location'] as Map?)?.cast<String, dynamic>() ?? {};
    final latitude = location['lat'] ?? rawData['latitude'];
    final longitude = location['lng'] ?? rawData['longitude'];
    final imageUrls = (rawData['imageUrls'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        [];

    final bool addressLooksLikeCoordinates = _looksLikeCoordinates(address);
    final bool isCompleted = status == 'resolved' ||
        status == 'completed' ||
        status == 'closed' ||
        status == 'cleaned';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statusChip(status),
                    const SizedBox(width: 8),
                    _severityChip(severity),
                  ],
                ),
                if (imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      imageUrls.first,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: double.infinity,
                          height: 220,
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Text('Failed to load image'),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Reason / Details',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reported By',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reportedBy,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Submitted Time',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  createdAt != null
                      ? _formatDateTime(createdAt)
                      : 'Time unavailable',
                  style: const TextStyle(fontSize: 15),
                ),
                if (address.isNotEmpty && !addressLooksLikeCoordinates) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Address',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    address,
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
                if (latitude != null && longitude != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Coordinates',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Latitude: $latitude\nLongitude: $longitude',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isCompleted
                            ? null
                            : () {
                                Navigator.pop(bottomSheetContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReportIssuePage.edit(
                                      reportId: docId,
                                      reportData: rawData,
                                      source: (rawData['source'] ?? 'map').toString(),
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isCompleted
                            ? null
                            : () async {
                                Navigator.pop(bottomSheetContext);
                                await _confirmDelete(context, docId);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}