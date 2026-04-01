import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NgoNotificationsPage extends StatelessWidget {
  const NgoNotificationsPage({super.key});

  Future<void> _markAsRead(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(notificationId)
        .update({
      'isRead': true,
    });
  }

  Future<void> _markAllAsRead(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in docs) {
      final data = doc.data();
      final isRead = data['isRead'] == true;
      if (!isRead) {
        batch.update(doc.reference, {'isRead': true});
      }
    }

    await batch.commit();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notifications marked as read')),
    );
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return 'Just now';

    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} day ago';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  String _titleForType(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();

    switch (type) {
      case 'volunteer_request':
        return 'New volunteer request';
      case 'announcement':
        return (data['title'] ?? 'Announcement').toString();
      default:
        return 'Notification';
    }
  }

  String _subtitleForNotification(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    final eventTitle = (data['eventTitle'] ?? 'your event').toString();
    final userName = (data['requestUserName'] ?? 'A user').toString();

    switch (type) {
      case 'volunteer_request':
        return '$userName requested to join "$eventTitle".';
      case 'announcement':
        return (data['message'] ?? 'You have a new announcement.').toString();
      default:
        return 'You have a new notification.';
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'volunteer_request':
        return Icons.group_add_outlined;
      case 'announcement':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color _iconBgForType(String type) {
    switch (type) {
      case 'volunteer_request':
        return const Color(0xFFE8F5E9);
      case 'announcement':
        return const Color(0xFFFFF3E0);
      default:
        return const Color(0xFFF1F3F4);
    }
  }

  Color _iconColorForType(String type) {
    switch (type) {
      case 'volunteer_request':
        return const Color(0xFF2E7D32);
      case 'announcement':
        return const Color(0xFFEF6C00);
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('NGO Notifications')),
        body: const Center(
          child: Text('No NGO account is logged in.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5EF),
      appBar: AppBar(
        title: const Text('NGO Notifications'),
        backgroundColor: const Color(0xFF0B8F3A),
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('notifications')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const SizedBox.shrink();
              }

              return TextButton(
                onPressed: () => _markAllAsRead(context, docs),
                child: const Text(
                  'Read all',
                  style: TextStyle(color: Colors.white),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
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
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No notifications yet.',
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

                final type = (data['type'] ?? '').toString();
                final isRead = data['isRead'] == true;
                final createdAt = data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;

                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () async {
                    await _markAsRead(doc.id);

                    if (!context.mounted) return;

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                                _titleForType(data),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _subtitleForNotification(data),
                                style: const TextStyle(fontSize: 15),
                              ),
                              const SizedBox(height: 16),
                              if ((data['eventTitle'] ?? '').toString().isNotEmpty)
                                _detailRow(
                                  'Event',
                                  (data['eventTitle'] ?? '').toString(),
                                ),
                              if ((data['requestUserName'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _detailRow(
                                  'Volunteer',
                                  (data['requestUserName'] ?? '').toString(),
                                ),
                              if ((data['requestUserEmail'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _detailRow(
                                  'Email',
                                  (data['requestUserEmail'] ?? '').toString(),
                                ),
                              if ((data['target'] ?? '').toString().isNotEmpty)
                                _detailRow(
                                  'Target',
                                  (data['target'] ?? '').toString(),
                                ),
                              _detailRow(
                                'Received',
                                _timeAgo(createdAt),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isRead ? Colors.white : const Color(0xFFF0FAF3),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isRead
                            ? const Color(0xFFE5E7EB)
                            : const Color(0xFFCBE8D1),
                      ),
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _iconBgForType(type),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _iconForType(type),
                              color: _iconColorForType(type),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _titleForType(data),
                                        style: const TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF0B8F3A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _subtitleForNotification(data),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.black87,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _timeAgo(createdAt),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                  ),
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
    );
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}