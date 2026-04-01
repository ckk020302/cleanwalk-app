import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class NgoEventDetailsPage extends StatefulWidget {
  final String eventId;

  const NgoEventDetailsPage({
    super.key,
    required this.eventId,
  });

  @override
  State<NgoEventDetailsPage> createState() => _NgoEventDetailsPageState();
}

class _NgoEventDetailsPageState extends State<NgoEventDetailsPage> {
  final TextEditingController _resolutionNoteController =
      TextEditingController();

  File? _resolutionImageFile;
  bool _submittingResolution = false;

  String get eventId => widget.eventId;

  @override
  void dispose() {
    _resolutionNoteController.dispose();
    super.dispose();
  }

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

  bool _isCompleted(String status) => status.toLowerCase() == 'completed';
  bool _isCancelled(String status) => status.toLowerCase() == 'cancelled';

  Future<void> _notifyUsers({
    required List<String> userIds,
    required String type,
    required String title,
    required String message,
  }) async {
    if (userIds.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final now = FieldValue.serverTimestamp();

    for (final uid in userIds) {
      final cleanUid = uid.trim();
      if (cleanUid.isEmpty) continue;

      final ref = firestore
          .collection('users')
          .doc(cleanUid)
          .collection('notifications')
          .doc();

      batch.set(ref, {
        'type': type,
        'title': title,
        'message': message,
        'eventId': eventId,
        'isRead': false,
        'createdAt': now,
      });
    }

    await batch.commit();
  }

  Future<bool> _allApprovedVolunteersAttendanceMarked() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('requests')
        .where('status', isEqualTo: 'approved')
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final attendanceStatus =
          (data['attendanceStatus'] ?? 'pending').toString().toLowerCase();

      if (attendanceStatus == 'pending' || attendanceStatus.isEmpty) {
        return false;
      }
    }

    return true;
  }

  Future<void> _cancelEvent(
    BuildContext context,
    Map<String, dynamic> eventData,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Cancel Event'),
          content: const Text(
            'Are you sure you want to cancel this event?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Yes, Cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final eventTitle = (eventData['title'] ?? 'Cleanup Event').toString();
    final joinedUserIds = (eventData['joinedUserIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    await FirebaseFirestore.instance.collection('events').doc(eventId).update({
      'status': 'cancelled',
    });

    await _notifyUsers(
      userIds: joinedUserIds,
      type: 'event_cancelled',
      title: 'Event Cancelled',
      message: 'Your cleanup event "$eventTitle" has been cancelled.',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Event cancelled successfully.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _markEventCompleted(
    BuildContext context,
    Map<String, dynamic> eventData,
  ) async {
    final allMarked = await _allApprovedVolunteersAttendanceMarked();

    if (!allMarked) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please mark all volunteer attendance before completing the event.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Mark Event as Completed'),
          content: const Text(
            'Are you sure this cleanup event has been completed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
              ),
              child: const Text('Yes, Complete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final eventTitle = (eventData['title'] ?? 'Cleanup Event').toString();
    final joinedUserIds = (eventData['joinedUserIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    await FirebaseFirestore.instance.collection('events').doc(eventId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });

    await _notifyUsers(
      userIds: joinedUserIds,
      type: 'event_completed',
      title: 'Event Completed',
      message: 'The cleanup event "$eventTitle" has been marked as completed.',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Event marked as completed.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  Future<TimeOfDay?> _pickCustomTime(
    BuildContext context,
    TimeOfDay initialTime,
  ) async {
    final now = DateTime.now();
    final initialDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      initialTime.hour,
      initialTime.minute,
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
                            backgroundColor: const Color(0xFF3E6F3A),
                            foregroundColor: Colors.white,
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

    if (picked == null) return null;

    return TimeOfDay(
      hour: picked.hour,
      minute: picked.minute,
    );
  }

  Future<void> _showRescheduleDialog(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    DateTime initialDate = DateTime.now();
    final dateTime = data['dateTime'];
    if (dateTime is Timestamp) {
      initialDate = dateTime.toDate();
    }

    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final tomorrow = todayOnly.add(const Duration(days: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(tomorrow) ? tomorrow : initialDate,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 3),
    );

    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await _pickCustomTime(
      context,
      TimeOfDay.fromDateTime(initialDate),
    );

    if (pickedTime == null || !context.mounted) return;

    final selectedDateOnly = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
    );

    if (!selectedDateOnly.isAfter(todayOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rescheduled event date must be at least tomorrow.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final dateLabel =
        '${pickedDate.month.toString().padLeft(2, '0')}/${pickedDate.day.toString().padLeft(2, '0')}/${pickedDate.year.toString().substring(2)}';

    final hour = pickedTime.hourOfPeriod == 0 ? 12 : pickedTime.hourOfPeriod;
    final minute = pickedTime.minute.toString().padLeft(2, '0');
    final suffix = pickedTime.period == DayPeriod.am ? 'AM' : 'PM';
    final timeLabel = '$hour:$minute $suffix';

    await FirebaseFirestore.instance.collection('events').doc(eventId).update({
      'dateTime': Timestamp.fromDate(newDateTime),
      'dateLabel': dateLabel,
      'timeLabel': timeLabel,
    });

    final eventTitle = (data['title'] ?? 'Cleanup Event').toString();
    final joinedUserIds = (data['joinedUserIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    await _notifyUsers(
      userIds: joinedUserIds,
      type: 'event_rescheduled',
      title: 'Event Rescheduled',
      message:
          'Your cleanup event "$eventTitle" has been rescheduled to $dateLabel at $timeLabel.',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Event rescheduled successfully.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _approveVolunteerRequest(
    BuildContext context, {
    required String requestId,
    required Map<String, dynamic> requestData,
  }) async {
    final requestRef = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('requests')
        .doc(requestId);

    final eventRef = FirebaseFirestore.instance.collection('events').doc(eventId);

    try {
      String approvedUserId = '';
      String eventTitle = 'Cleanup Event';
      String locationName = 'selected location';

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final eventSnap = await tx.get(eventRef);
        final requestSnap = await tx.get(requestRef);

        if (!eventSnap.exists) {
          throw Exception('Event not found');
        }
        if (!requestSnap.exists) {
          throw Exception('Request not found');
        }

        final eventData = eventSnap.data() ?? {};
        final currentRequestData = requestSnap.data() ?? {};

        final requestStatus =
            (currentRequestData['status'] ?? 'pending').toString().toLowerCase();
        if (requestStatus == 'approved') {
          throw Exception('This request is already approved');
        }

        final userId = (currentRequestData['userId'] ?? '').toString().trim();
        if (userId.isEmpty) {
          throw Exception('Request user ID is missing');
        }

        approvedUserId = userId;
        eventTitle = (eventData['title'] ?? 'Cleanup Event').toString();
        locationName =
            (eventData['locationName'] ?? 'selected location').toString();

        final volunteersNeeded =
            (eventData['volunteersNeeded'] as num?)?.toInt() ?? 0;
        final joinedUserIds = (eventData['joinedUserIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        if (volunteersNeeded > 0 && joinedUserIds.length >= volunteersNeeded) {
          throw Exception('Event is already full');
        }

        if (!joinedUserIds.contains(userId)) {
          joinedUserIds.add(userId);
        }

        tx.update(requestRef, {
          'status': 'approved',
          'attendanceStatus': 'pending',
          'reviewedAt': FieldValue.serverTimestamp(),
        });

        tx.update(eventRef, {
          'joinedUserIds': joinedUserIds,
          'joinedCount': joinedUserIds.length,
        });
      });

      if (approvedUserId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(approvedUserId)
            .collection('notifications')
            .add({
          'type': 'volunteer_approved',
          'title': 'Volunteer Application Approved',
          'message':
              'You have been selected as a volunteer for "$eventTitle" at $locationName.',
          'eventId': eventId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Volunteer request approved'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approve failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectVolunteerRequest(
    BuildContext context, {
    required String requestId,
  }) async {
    final requestRef = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('requests')
        .doc(requestId);

    final eventRef = FirebaseFirestore.instance.collection('events').doc(eventId);

    try {
      final requestSnap = await requestRef.get();
      final eventSnap = await eventRef.get();

      if (!requestSnap.exists) {
        throw Exception('Request not found');
      }

      final requestData = requestSnap.data() ?? {};
      final eventData = eventSnap.data() ?? {};

      final userId = (requestData['userId'] ?? '').toString().trim();
      final eventTitle = (eventData['title'] ?? 'Cleanup Event').toString();
      final locationName =
          (eventData['locationName'] ?? 'selected location').toString();

      await requestRef.update({
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      if (userId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .add({
          'type': 'volunteer_rejected',
          'title': 'Volunteer Application Rejected',
          'message':
              'Your application for "$eventTitle" at $locationName was not selected.',
          'eventId': eventId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Volunteer request rejected'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reject failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _setAttendance({
    required BuildContext context,
    required String requestId,
    required String attendanceStatus,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final eventRef = firestore.collection('events').doc(eventId);
    final requestRef = eventRef.collection('requests').doc(requestId);

    try {
      await firestore.runTransaction((tx) async {
        final requestSnap = await tx.get(requestRef);
        final eventSnap = await tx.get(eventRef);

        if (!requestSnap.exists) {
          throw Exception('Volunteer request not found');
        }

        if (!eventSnap.exists) {
          throw Exception('Event not found');
        }

        final requestData = requestSnap.data() ?? {};
        final eventData = eventSnap.data() ?? {};

        final userId = (requestData['userId'] ?? '').toString().trim();
        if (userId.isEmpty) {
          throw Exception('User ID not found in request');
        }

        final joinedUserIds = (eventData['joinedUserIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        tx.update(requestRef, {
          'attendanceStatus': attendanceStatus,
          'attendanceMarkedAt': FieldValue.serverTimestamp(),
        });

        if (attendanceStatus == 'absent') {
          joinedUserIds.remove(userId);
        } else if (attendanceStatus == 'attended') {
          if (!joinedUserIds.contains(userId)) {
            joinedUserIds.add(userId);
          }
        }

        tx.update(eventRef, {
          'joinedUserIds': joinedUserIds,
          'joinedCount': joinedUserIds.length,
        });
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Volunteer marked as $attendanceStatus'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update attendance: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickResolutionImage() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select Proof Photo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.camera_alt_outlined),
                    title: const Text('Take Photo'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from Gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (source == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 75,
      );

      if (picked == null) return;

      setState(() {
        _resolutionImageFile = File(picked.path);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitResolution(Map<String, dynamic> eventData) async {
    final linkedReportId =
        (eventData['linkedReportId'] ?? '').toString().trim();

    final linkedReportIds = (eventData['linkedReportIds'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];

    final note = _resolutionNoteController.text.trim();

    if (linkedReportIds.isEmpty && linkedReportId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This event is not linked to any report.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_resolutionImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a proof photo first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a resolution note.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _submittingResolution = true;
    });

    try {
      final fileName = 'resolution_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('event_resolutions')
          .child(eventId)
          .child(fileName);

      await storageRef.putFile(_resolutionImageFile!);
      final photoUrl = await storageRef.getDownloadURL();

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final resolvedAt = FieldValue.serverTimestamp();

      final reportIdsToUpdate = <String>{...linkedReportIds};
      if (reportIdsToUpdate.isEmpty && linkedReportId.isNotEmpty) {
        reportIdsToUpdate.add(linkedReportId);
      }

      batch.update(firestore.collection('events').doc(eventId), {
        'resolutionPhotoUrl': photoUrl,
        'resolutionNote': note,
        'resolvedAt': resolvedAt,
        'issueResolved': true,
      });

      for (final reportId in reportIdsToUpdate) {
        final reportRef = firestore.collection('reports').doc(reportId);
        final reportSnap = await reportRef.get();

        if (!reportSnap.exists) continue;

        final reportData = reportSnap.data() ?? {};
        final reporterUserId = (reportData['userId'] ?? '').toString().trim();
        final locationName = (reportData['locationName'] ??
                eventData['locationName'] ??
                'your reported area')
            .toString();

        batch.update(reportRef, {
          'status': 'resolved',
          'resolutionPhotoUrl': photoUrl,
          'resolutionNote': note,
          'resolvedAt': resolvedAt,
          'resolvedByEventId': eventId,
        });

        if (reporterUserId.isNotEmpty) {
          final notificationRef = firestore
              .collection('users')
              .doc(reporterUserId)
              .collection('notifications')
              .doc();

          batch.set(notificationRef, {
            'type': 'report_resolved',
            'title': 'Report Resolved',
            'message':
                'The cleanliness issue you reported at $locationName has been resolved.',
            'reportId': reportId,
            'eventId': eventId,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _resolutionImageFile = null;
        _resolutionNoteController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reportIdsToUpdate.length > 1
                ? 'Cleanliness issues resolved successfully.'
                : 'Cleanliness issue resolved successfully.',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit resolution: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingResolution = false;
        });
      }
    }
  }

  Widget _sectionCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: child,
    );
  }

  Widget _volunteerRequestTile(
    BuildContext context, {
    required String requestId,
    required Map<String, dynamic> data,
  }) {
    final userName =
        (data['userName'] ?? data['name'] ?? data['userEmail'] ?? 'Unknown user')
            .toString();
    final userEmail = (data['userEmail'] ?? '').toString();
    final status = (data['status'] ?? 'pending').toString().toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            child: Icon(Icons.person),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (userEmail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    userEmail,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (status == 'pending') ...[
            TextButton(
              onPressed: () => _approveVolunteerRequest(
                context,
                requestId: requestId,
                requestData: data,
              ),
              child: const Text('Accept'),
            ),
            TextButton(
              onPressed: () => _rejectVolunteerRequest(
                context,
                requestId: requestId,
              ),
              child: const Text(
                'Reject',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: status == 'approved'
                    ? Colors.green.withOpacity(0.10)
                    : Colors.red.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status[0].toUpperCase() + status.substring(1),
                style: TextStyle(
                  color: status == 'approved'
                      ? const Color(0xFF2E7D32)
                      : Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _acceptedVolunteerTile(Map<String, dynamic> data) {
    final userName =
        (data['userName'] ?? data['name'] ?? data['userEmail'] ?? 'Unknown user')
            .toString();
    final userEmail = (data['userEmail'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const CircleAvatar(
            child: Icon(Icons.person),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (userEmail.isNotEmpty)
                  Text(
                    userEmail,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle,
            color: Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }

  Widget _attendanceVolunteerTile(
    BuildContext context, {
    required String requestId,
    required Map<String, dynamic> data,
  }) {
    final userName =
        (data['userName'] ?? data['name'] ?? data['userEmail'] ?? 'Unknown user')
            .toString();
    final userEmail = (data['userEmail'] ?? '').toString();
    final attendanceStatus =
        (data['attendanceStatus'] ?? 'pending').toString().toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                child: Icon(Icons.person),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (userEmail.isNotEmpty)
                      Text(
                        userEmail,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setAttendance(
                    context: context,
                    requestId: requestId,
                    attendanceStatus: 'attended',
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: attendanceStatus == 'attended'
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFD0D5DD),
                    ),
                    backgroundColor: attendanceStatus == 'attended'
                        ? const Color(0xFFE8F5E9)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Attended',
                    style: TextStyle(color: Color(0xFF2E7D32)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setAttendance(
                    context: context,
                    requestId: requestId,
                    attendanceStatus: 'absent',
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: attendanceStatus == 'absent'
                          ? Colors.red
                          : const Color(0xFFD0D5DD),
                    ),
                    backgroundColor: attendanceStatus == 'absent'
                        ? const Color(0xFFFFEBEE)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Absent',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resolutionPreviewCard() {
    if (_resolutionImageFile == null) {
      return OutlinedButton.icon(
        onPressed: _pickResolutionImage,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Upload Proof Photo'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            _resolutionImageFile!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickResolutionImage,
                icon: const Icon(Icons.refresh),
                label: const Text('Change Photo'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _resolutionImageFile = null;
                  });
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0AA64B);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .snapshots(),
        builder: (context, eventSnapshot) {
          if (eventSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!eventSnapshot.hasData || !eventSnapshot.data!.exists) {
            return const Center(
              child: Text('Event not found.'),
            );
          }

          final data = eventSnapshot.data!.data() ?? {};

          final title = (data['title'] as String?) ?? 'Untitled Event';
          final description =
              (data['description'] as String?) ?? 'No description available.';
          final dateLabel = (data['dateLabel'] as String?) ?? '--/--/--';
          final timeLabel = (data['timeLabel'] as String?) ?? '--:--';
          final duration = (data['duration'] as String?) ?? '-';
          final locationName =
              (data['locationName'] as String?) ?? 'No location';
          final volunteersNeeded =
              (data['volunteersNeeded'] as num?)?.toInt() ?? 0;
          final joinedCount = (data['joinedCount'] as num?)?.toInt() ?? 0;
          final status = (data['status'] as String?) ?? 'upcoming';
          final issueResolved = data['issueResolved'] == true;
          final resolutionPhotoUrl =
              (data['resolutionPhotoUrl'] as String?) ?? '';
          final resolutionNote = (data['resolutionNote'] as String?) ?? '';

          final canManageActions =
              !_isCancelled(status) && !_isCompleted(status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
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
                      const SizedBox(height: 14),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'About this event',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(description),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .doc(eventId)
                      .collection('requests')
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, requestSnapshot) {
                    if (requestSnapshot.hasError) {
                      return _sectionCard(
                        child: Text(
                          'Failed to load volunteer requests.\n${requestSnapshot.error}',
                        ),
                      );
                    }

                    if (!requestSnapshot.hasData) {
                      return _sectionCard(
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }

                    final requests = requestSnapshot.data!.docs;

                    return _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Volunteer Requests',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (requests.isEmpty)
                            const Text(
                              'No pending volunteer requests yet.',
                              style: TextStyle(color: Colors.black54),
                            )
                          else
                            ...requests.map(
                              (doc) => _volunteerRequestTile(
                                context,
                                requestId: doc.id,
                                data: doc.data(),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .doc(eventId)
                      .collection('requests')
                      .where('status', isEqualTo: 'approved')
                      .snapshots(),
                  builder: (context, approvedSnapshot) {
                    if (approvedSnapshot.hasError) {
                      return _sectionCard(
                        child: Text(
                          'Failed to load accepted volunteers.\n${approvedSnapshot.error}',
                        ),
                      );
                    }

                    if (!approvedSnapshot.hasData) {
                      return _sectionCard(
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }

                    final approved = approvedSnapshot.data!.docs;

                    return _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Accepted Volunteers',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (approved.isEmpty)
                            const Text(
                              'No accepted volunteers yet.',
                              style: TextStyle(color: Colors.black54),
                            )
                          else
                            ...approved.map(
                              (doc) => _acceptedVolunteerTile(doc.data()),
                            ),
                        ],
                      ),
                    );
                  },
                ),

                if (!_isCancelled(status)) ...[
                  const SizedBox(height: 20),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('events')
                        .doc(eventId)
                        .collection('requests')
                        .where('status', isEqualTo: 'approved')
                        .snapshots(),
                    builder: (context, attendanceSnapshot) {
                      if (attendanceSnapshot.hasError) {
                        return _sectionCard(
                          child: Text(
                            'Failed to load volunteer attendance.\n${attendanceSnapshot.error}',
                          ),
                        );
                      }

                      if (!attendanceSnapshot.hasData) {
                        return _sectionCard(
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      }

                      final volunteers = attendanceSnapshot.data!.docs;

                      return _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Manage Volunteers',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Mark each volunteer as attended or absent before completing the event.',
                              style: TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            if (volunteers.isEmpty)
                              const Text(
                                'No approved volunteers to manage.',
                                style: TextStyle(color: Colors.black54),
                              )
                            else
                              ...volunteers.map(
                                (doc) => _attendanceVolunteerTile(
                                  context,
                                  requestId: doc.id,
                                  data: doc.data(),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],

                if (_isCompleted(status)) ...[
                  const SizedBox(height: 20),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resolve Cleanliness Issue',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (issueResolved) ...[
                          const Text(
                            'This issue has already been marked as resolved.',
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (resolutionPhotoUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                resolutionPhotoUrl,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                          if (resolutionNote.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              resolutionNote,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ],
                        ] else ...[
                          _resolutionPreviewCard(),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _resolutionNoteController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Enter resolution note',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _submittingResolution
                                  ? null
                                  : () => _submitResolution(data),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: _submittingResolution
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.task_alt),
                              label: Text(
                                _submittingResolution
                                    ? 'Submitting...'
                                    : 'Submit Resolution',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (canManageActions) ...[
                  const SizedBox(height: 20),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Event Actions',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _markEventCompleted(context, data),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.verified),
                            label: const Text('Mark as Completed'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showRescheduleDialog(context, data),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.schedule),
                            label: const Text('Reschedule Event'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _cancelEvent(context, data),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: const BorderSide(color: Colors.red),
                            ),
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            label: const Text(
                              'Cancel Event',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}