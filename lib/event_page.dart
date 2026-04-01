import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EventPage extends StatelessWidget {
  const EventPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5EF),
      appBar: AppBar(
        title: const Text('Cleanup Events'),
        backgroundColor: const Color(0xFF0B8F3A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .orderBy('dateTime')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load events.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = (snapshot.data?.docs ?? []).where((doc) {
              final data = doc.data();
              final status = (data['status'] ?? '').toString().toLowerCase();
              final volunteersNeeded = _readIntValue(
                data['volunteersNeeded'],
                fallback: 0,
              );
              final joinedCount = _readIntValue(
                data['joinedCount'],
                fallback: 0,
              );

              final isUpcoming = status == 'upcoming';
              final isFull =
                  volunteersNeeded > 0 && joinedCount >= volunteersNeeded;

              return isUpcoming && !isFull;
            }).toList();

            if (docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No cleanup events available yet.',
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

                final title = (data['title'] ?? 'Untitled Event').toString();
                final description =
                    (data['description'] ?? 'No description provided.')
                        .toString();
                final location =
                    (data['locationName'] ?? 'Location not provided')
                        .toString();
                final organizer =
                    (data['organizerName'] ?? 'Organizer not provided')
                        .toString();

                final dateTime = _readDateTimeValue(data['dateTime']);
                final dateLabel =
                    (data['dateLabel'] ??
                            (dateTime != null
                                ? _formatDate(dateTime)
                                : 'Date not set'))
                        .toString();
                final timeLabel =
                    (data['timeLabel'] ??
                            (dateTime != null
                                ? _formatTime(dateTime)
                                : 'Time not set'))
                        .toString();
                final durationText = (data['duration'] ?? 'Duration not set')
                    .toString();

                final volunteersNeeded = _readIntValue(
                  data['volunteersNeeded'],
                  fallback: 0,
                );
                final joinedCount = _readIntValue(
                  data['joinedCount'],
                  fallback: 0,
                );

                final status = (data['status'] ?? 'upcoming').toString();
                final isFull =
                    volunteersNeeded > 0 && joinedCount >= volunteersNeeded;

                final progress = volunteersNeeded > 0
                    ? (joinedCount / volunteersNeeded).clamp(0.0, 1.0)
                    : 0.0;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: currentUid == null
                      ? null
                      : FirebaseFirestore.instance
                            .collection('events')
                            .doc(doc.id)
                            .collection('requests')
                            .doc(currentUid)
                            .snapshots(),
                  builder: (context, requestSnapshot) {
                    final requestData = requestSnapshot.data?.data();
                    final requestStatus = (requestData?['status'] ?? '')
                        .toString()
                        .toLowerCase();

                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        _showEventDetails(
                          context,
                          eventId: doc.id,
                          data: data,
                          requestStatus: requestStatus,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  _statusChip(status),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _infoRow(Icons.location_on_outlined, location),
                              const SizedBox(height: 8),
                              _infoRow(
                                Icons.calendar_today_outlined,
                                dateLabel,
                              ),
                              const SizedBox(height: 8),
                              _infoRow(
                                Icons.access_time_outlined,
                                '$timeLabel  •  $durationText',
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.groups_2_outlined,
                                    size: 18,
                                    color: Colors.black54,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '$joinedCount / $volunteersNeeded volunteers',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 7,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFF0B8F3A),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.business_outlined,
                                    size: 18,
                                    color: Colors.black54,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      organizer,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.black45,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _buildAction(
                                    context: context,
                                    eventId: doc.id,
                                    eventData: data,
                                    requestStatus: requestStatus,
                                    isFull: isFull,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _buttonColor(
                                      requestStatus,
                                    ),
                                    foregroundColor: _buttonTextColor(
                                      requestStatus,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                  ),
                                  child: Text(
                                    _buttonText(
                                      requestStatus: requestStatus,
                                      isFull: isFull,
                                    ),
                                  ),
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
            );
          },
        ),
      ),
    );
  }

  static VoidCallback? _buildAction({
    required BuildContext context,
    required String eventId,
    required Map<String, dynamic> eventData,
    required String requestStatus,
    required bool isFull,
  }) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return null;

    final normalizedStatus = (eventData['status'] ?? 'upcoming')
        .toString()
        .toLowerCase();

    if (normalizedStatus == 'completed' ||
        normalizedStatus == 'cancelled' ||
        normalizedStatus == 'ongoing') {
      return null;
    }

    if (requestStatus == 'approved' || requestStatus == 'rejected') {
      return null;
    }

    if (requestStatus == 'pending') {
      return () => _cancelJoinRequest(context, eventId);
    }

    if (isFull) return null;

    return () => _submitJoinRequest(context, eventId, eventData: eventData);
  }

  static String _buttonText({
    required String requestStatus,
    required bool isFull,
  }) {
    if (requestStatus == 'approved') return 'Joined';
    if (requestStatus == 'pending') return 'Cancel Request';
    if (requestStatus == 'rejected') return 'Request Rejected';
    if (isFull) return 'Event Full';
    return 'Request to Join';
  }

  static Color _buttonColor(String requestStatus) {
    if (requestStatus == 'approved') return const Color(0xFFBFE7C7);
    if (requestStatus == 'pending') return Colors.orange.shade100;
    if (requestStatus == 'rejected') return Colors.red.shade100;
    return const Color(0xFF0B8F3A);
  }

  static Color _buttonTextColor(String requestStatus) {
    if (requestStatus == 'approved') return const Color(0xFF2E7D32);
    if (requestStatus == 'pending') return Colors.orange.shade900;
    if (requestStatus == 'rejected') return Colors.red.shade700;
    return Colors.white;
  }

  static Future<void> _submitJoinRequest(
    BuildContext context,
    String eventId, {
    required Map<String, dynamic> eventData,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;

    final requestRef = firestore
        .collection('events')
        .doc(eventId)
        .collection('requests')
        .doc(user.uid);

    final userDoc = await firestore.collection('users').doc(user.uid).get();

    final userData = userDoc.data() ?? {};
    final userName =
        (userData['fullName'] ??
                userData['username'] ??
                userData['name'] ??
                user.displayName ??
                user.email ??
                'Unknown User')
            .toString();

    final ngoUid = (eventData['createdByUid'] ?? '').toString().trim();
    final eventTitle = (eventData['title'] ?? 'Untitled Event').toString();

    try {
      final existing = await requestRef.get();
      if (existing.exists) {
        final currentStatus = (existing.data()?['status'] ?? '')
            .toString()
            .toLowerCase();

        if (currentStatus == 'pending') {
          throw Exception('You already sent a request');
        }
        if (currentStatus == 'approved') {
          throw Exception('You are already approved for this event');
        }
      }

      await requestRef.set({
        'userId': user.uid,
        'userName': userName,
        'userEmail': user.email ?? '',
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (ngoUid.isNotEmpty) {
        await firestore
            .collection('users')
            .doc(ngoUid)
            .collection('notifications')
            .add({
              'type': 'volunteer_request',
              'eventId': eventId,
              'eventTitle': eventTitle,
              'requestUserId': user.uid,
              'requestUserName': userName,
              'requestUserEmail': user.email ?? '',
              'createdAt': FieldValue.serverTimestamp(),
              'isRead': false,
            });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Join request submitted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request failed: $e')));
    }
  }

  static Future<void> _cancelJoinRequest(
    BuildContext context,
    String eventId,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final requestRef = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('requests')
        .doc(user.uid);

    try {
      final snapshot = await requestRef.get();
      if (!snapshot.exists) {
        throw Exception('Request not found');
      }

      final status = (snapshot.data()?['status'] ?? '')
          .toString()
          .toLowerCase();
      if (status != 'pending') {
        throw Exception('Only pending requests can be cancelled');
      }

      await requestRef.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Join request cancelled')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel request failed: $e')));
    }
  }

  static void _showEventDetails(
    BuildContext context, {
    required String eventId,
    required Map<String, dynamic> data,
    required String requestStatus,
  }) {
    final title = (data['title'] ?? 'Untitled Event').toString();
    final description = (data['description'] ?? 'No description provided.')
        .toString();
    final location = (data['locationName'] ?? 'Location not provided')
        .toString();
    final organizer = (data['organizerName'] ?? 'Organizer not provided')
        .toString();
    final contactEmail = (data['organizerEmail'] ?? 'Not provided').toString();
    final contactPhone = (data['organizerPhone'] ?? 'Not provided').toString();

    final dateTime = _readDateTimeValue(data['dateTime']);
    final dateLabel =
        (data['dateLabel'] ??
                (dateTime != null ? _formatDate(dateTime) : 'Date not set'))
            .toString();
    final timeLabel =
        (data['timeLabel'] ??
                (dateTime != null ? _formatTime(dateTime) : 'Time not set'))
            .toString();
    final durationText = (data['duration'] ?? 'Duration not set').toString();

    final volunteersNeeded = _readIntValue(
      data['volunteersNeeded'],
      fallback: 0,
    );
    final joinedCount = _readIntValue(data['joinedCount'], fallback: 0);

    final isFull = volunteersNeeded > 0 && joinedCount >= volunteersNeeded;

    final progress = volunteersNeeded > 0
        ? (joinedCount / volunteersNeeded).clamp(0.0, 1.0)
        : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF3F5EF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: SingleChildScrollView(
              child: Column(
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
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About This Event',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          style: const TextStyle(fontSize: 14.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailCard(
                    child: Column(
                      children: [
                        _detailInfoTile(
                          Icons.location_on_outlined,
                          'Location',
                          location,
                        ),
                        const SizedBox(height: 14),
                        _detailInfoTile(
                          Icons.calendar_today_outlined,
                          'Date',
                          dateLabel,
                        ),
                        const SizedBox(height: 14),
                        _detailInfoTile(
                          Icons.access_time_outlined,
                          'Time & Duration',
                          '$timeLabel ($durationText)',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(
                              Icons.groups_2_outlined,
                              color: Color(0xFF0B8F3A),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Volunteers',
                                style: TextStyle(fontSize: 14.5),
                              ),
                            ),
                            Text(
                              '$joinedCount / $volunteersNeeded',
                              style: const TextStyle(
                                color: Color(0xFF0B8F3A),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF0B8F3A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailCard(
                    color: const Color(0xFFEAF6EE),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contact Organizer',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _detailInfoTile(
                          Icons.person_outline,
                          'Organizer',
                          organizer,
                        ),
                        const SizedBox(height: 12),
                        _detailInfoTile(
                          Icons.email_outlined,
                          'Email',
                          contactEmail,
                        ),
                        const SizedBox(height: 12),
                        _detailInfoTile(
                          Icons.phone_outlined,
                          'Phone',
                          contactPhone,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _buildAction(
                                context: context,
                                eventId: eventId,
                                eventData: data,
                                requestStatus: requestStatus,
                                isFull: isFull,
                              ) ==
                              null
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              final action = _buildAction(
                                context: context,
                                eventId: eventId,
                                eventData: data,
                                requestStatus: requestStatus,
                                isFull: isFull,
                              );
                              action?.call();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _buttonColor(requestStatus),
                        foregroundColor: _buttonTextColor(requestStatus),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _buttonText(
                          requestStatus: requestStatus,
                          isFull: isFull,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _detailCard({
    required Widget child,
    Color color = Colors.white,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  static Widget _detailInfoTile(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF0B8F3A), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Colors.black54),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ],
    );
  }

  static Widget _statusChip(String status) {
    final normalized = status.toLowerCase();

    Color bg;
    Color fg;
    String label;

    if (normalized == 'ongoing') {
      label = 'Ongoing';
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else if (normalized == 'completed') {
      label = 'Completed';
      bg = const Color(0xFFE0E0E0);
      fg = Colors.black54;
    } else if (normalized == 'cancelled') {
      label = 'Cancelled';
      bg = const Color(0xFFFFEBEE);
      fg = Colors.red;
    } else {
      label = 'Upcoming';
      bg = const Color(0xFFDCEBFF);
      fg = const Color(0xFF2F6FE4);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static DateTime? _readDateTimeValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static int _readIntValue(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static String _formatDate(DateTime dt) {
    final monthNames = [
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
    return '${monthNames[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
        ? dt.hour - 12
        : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}
