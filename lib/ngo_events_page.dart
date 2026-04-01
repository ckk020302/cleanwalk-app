import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'ngo_event_details_page.dart';

class NgoEventsPage extends StatelessWidget {
  final bool completedOnly;

  const NgoEventsPage({
    super.key,
    this.completedOnly = false,
  });

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return const Color(0xFF2E7D32);
      case 'ongoing':
        return const Color(0xFF1976D2);
      case 'completed':
        return const Color(0xFF616161);
      case 'cancelled':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  String _statusText(String status) {
    if (status.trim().isEmpty) return 'Upcoming';
    return status[0].toUpperCase() + status.substring(1);
  }

  DateTime _sortDateFromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final dateTime = data['dateTime'];
    final createdAt = data['createdAt'];

    if (dateTime is Timestamp) return dateTime.toDate();
    if (createdAt is Timestamp) return createdAt.toDate();

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEventCard(
    BuildContext context,
    QueryDocumentSnapshot doc,
  ) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final title = (data['title'] as String?) ?? 'Untitled Event';
    final dateLabel = (data['dateLabel'] as String?) ?? '--/--/--';
    final timeLabel = (data['timeLabel'] as String?) ?? '--:--';
    final locationName = (data['locationName'] as String?) ?? 'No location';
    final duration = (data['duration'] as String?) ?? '-';
    final volunteersNeeded =
        (data['volunteersNeeded'] as num?)?.toInt() ?? 0;
    final joinedCount = (data['joinedCount'] as num?)?.toInt() ?? 0;
    final status = (data['status'] as String?) ?? 'upcoming';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NgoEventDetailsPage(eventId: doc.id),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E7EC)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _statusColor(status).withOpacity(0.25),
                ),
              ),
              child: Text(
                _statusText(status),
                style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18),
                const SizedBox(width: 8),
                Text(dateLabel),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.access_time_outlined, size: 18),
                const SizedBox(width: 8),
                Text('$timeLabel • $duration'),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.place_outlined, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(locationName)),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              '$joinedCount / $volunteersNeeded volunteers joined',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NgoEventDetailsPage(eventId: doc.id),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Manage Event'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    final query = FirebaseFirestore.instance
        .collection('events')
        .where('createdByUid', isEqualTo: currentUser?.uid);

    return Scaffold(
      appBar: AppBar(
        title: Text(completedOnly ? 'Past Events' : 'NGO Events'),
      ),
      body: currentUser == null
          ? const Center(child: Text('You must be logged in.'))
          : StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = [...snapshot.data!.docs]
                  ..sort((a, b) =>
                      _sortDateFromDoc(b).compareTo(_sortDateFromDoc(a)));

                if (docs.isEmpty) {
                  return const Center(child: Text('No events found.'));
                }

                // 🔥 GROUP EVENTS
                final upcoming = docs.where((d) {
                  final s = (d['status'] ?? '').toString();
                  return s == 'upcoming' || s == 'ongoing';
                }).toList();

                final completed = docs.where((d) {
                  return (d['status'] ?? '') == 'completed';
                }).toList();

                final cancelled = docs.where((d) {
                  return (d['status'] ?? '') == 'cancelled';
                }).toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (completedOnly) ...[
                      _buildSectionTitle('Completed Events'),
                      ...completed.map(
                          (doc) => _buildEventCard(context, doc)),
                    ] else ...[
                      if (upcoming.isNotEmpty) ...[
                        _buildSectionTitle('Upcoming Events'),
                        ...upcoming.map(
                            (doc) => _buildEventCard(context, doc)),
                      ],
                      if (cancelled.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSectionTitle('Cancelled Events'),
                        ...cancelled.map(
                            (doc) => _buildEventCard(context, doc)),
                      ],
                    ],
                  ],
                );
              },
            ),
    );
  }
}