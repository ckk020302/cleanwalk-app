import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5EF),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF0B8F3A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (user != null)
            TextButton(
              onPressed: () => _markAllAsRead(user.uid),
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: user == null
          ? const Center(
              child: Text('You must be logged in to view notifications.'),
            )
          : Column(
              children: [
                const SizedBox(height: 12),
                _buildFilters(),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('notifications')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Failed to load notifications.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final allDocs = snapshot.data?.docs ?? [];
                      final docs = allDocs.where((doc) {
                        if (_selectedFilter == 'all') return true;
                        final type = (doc.data()['type'] ?? '').toString();
                        return _matchesFilter(type, _selectedFilter);
                      }).toList();

                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 72,
                                  color: Colors.black38,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'You will see volunteer updates, event reminders, and report resolution updates here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();

                          final title =
                              (data['title'] ?? 'Notification').toString();
                          final message =
                              (data['message'] ?? 'No message').toString();
                          final type = (data['type'] ?? '').toString();
                          final isRead = (data['isRead'] ?? false) == true;
                          final createdAt = _readDateTime(data['createdAt']);

                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              await _markAsRead(user.uid, doc.id);

                              if (!mounted) return;

                              _showNotificationDetails(
                                context,
                                title: title,
                                message: message,
                                timeText: _formatTimeAgo(createdAt),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isRead
                                    ? Colors.white
                                    : const Color(0xFFEAF6EE),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: isRead
                                      ? const Color(0xFFE5E7EB)
                                      : const Color(0xFFCFE8D6),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: _iconBackground(type),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        _iconForType(type),
                                        color: _iconColor(type),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  style: TextStyle(
                                                    fontSize: 15.5,
                                                    fontWeight: isRead
                                                        ? FontWeight.w600
                                                        : FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              if (!isRead)
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFF0B8F3A),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            message,
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              color: Colors.black87,
                                              height: 1.35,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                _typeLabel(type),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: _iconColor(type),
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                _formatTimeAgo(createdAt),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 42,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('all', 'All'),
          const SizedBox(width: 8),
          _filterChip('volunteer', 'Volunteer'),
          const SizedBox(width: 8),
          _filterChip('event', 'Events'),
          const SizedBox(width: 8),
          _filterChip('report', 'Reports'),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _selectedFilter == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: const Color(0xFF0B8F3A),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? const Color(0xFF0B8F3A) : const Color(0xFFE0E0E0),
        ),
      ),
    );
  }

  static bool _matchesFilter(String type, String filter) {
    if (filter == 'volunteer') {
      return type == 'volunteer_approved' || type == 'volunteer_rejected';
    }
    if (filter == 'event') {
      return type == 'event_reminder' ||
          type == 'event_cancelled' ||
          type == 'event_rescheduled' ||
          type == 'event_completed';
    }
    if (filter == 'report') {
      return type == 'report_resolved';
    }
    return true;
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'volunteer_approved':
        return Icons.verified_rounded;
      case 'volunteer_rejected':
        return Icons.cancel_outlined;
      case 'event_reminder':
        return Icons.event_available_rounded;
      case 'event_cancelled':
        return Icons.event_busy_rounded;
      case 'event_rescheduled':
        return Icons.schedule_rounded;
      case 'event_completed':
        return Icons.task_alt_rounded;
      case 'report_resolved':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  static Color _iconColor(String type) {
    switch (type) {
      case 'volunteer_approved':
      case 'event_reminder':
      case 'event_completed':
      case 'report_resolved':
        return const Color(0xFF2E7D32);
      case 'volunteer_rejected':
      case 'event_cancelled':
        return Colors.red;
      case 'event_rescheduled':
        return const Color(0xFF1976D2);
      default:
        return Colors.black54;
    }
  }

  static Color _iconBackground(String type) {
    switch (type) {
      case 'volunteer_approved':
      case 'event_reminder':
      case 'event_completed':
      case 'report_resolved':
        return const Color(0xFFE8F5E9);
      case 'volunteer_rejected':
      case 'event_cancelled':
        return const Color(0xFFFFEBEE);
      case 'event_rescheduled':
        return const Color(0xFFE3F2FD);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'volunteer_approved':
      case 'volunteer_rejected':
        return 'Volunteer';
      case 'event_reminder':
      case 'event_cancelled':
      case 'event_rescheduled':
      case 'event_completed':
        return 'Event';
      case 'report_resolved':
        return 'Report';
      default:
        return 'General';
    }
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _formatTimeAgo(DateTime? time) {
    if (time == null) return 'Just now';

    final diff = DateTime.now().difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.day}/${time.month}/${time.year}';
  }

  Future<void> _markAsRead(String uid, String notificationId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({
      'isRead': true,
    });
  }

  Future<void> _markAllAsRead(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  void _showNotificationDetails(
    BuildContext context, {
    required String title,
    required String message,
    required String timeText,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF3F5EF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  timeText,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}