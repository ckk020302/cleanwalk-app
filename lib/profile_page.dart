import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'activity_page.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploadingPhoto = false;
  bool _savingProfile = false;

  Future<int> _getReportsCount(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('reports')
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs.length;
  }

  Future<int> _getJoinedEventsCount(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('events')
        .where('joinedUserIds', arrayContains: userId)
        .get();

    final validDocs = snapshot.docs.where((doc) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      return status != 'cancelled';
    }).toList();

    return validDocs.length;
  }

  String _formatMemberSince(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) return 'Not available';

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

    return '${months[date.month - 1]} ${date.year}';
  }

  String _getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String? _validateName(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Name cannot be empty';
    if (text.length < 2) return 'Name is too short';
    return null;
  }

  String? _validatePhone(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Phone number cannot be empty';

    String digits = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('60')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length < 9 || digits.length > 10) {
      return 'Enter a valid phone number';
    }

    return null;
  }

  String _normalizePhone(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('60')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    return '+60$digits';
  }

  Future<void> _updateName(String newName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final error = _validateName(newName);
    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    try {
      setState(() => _savingProfile = true);

      final trimmedName = newName.trim();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fullName': trimmedName,
      }, SetOptions(merge: true));

      await user.updateDisplayName(trimmedName);

      _showSnack('Name updated successfully.');
    } catch (e) {
      _showSnack('Failed to update name: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _updatePhone(String newPhone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final error = _validatePhone(newPhone);
    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    try {
      setState(() => _savingProfile = true);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'phone': _normalizePhone(newPhone),
      }, SetOptions(merge: true));

      _showSnack('Phone number updated successfully.');
    } catch (e) {
      _showSnack('Failed to update phone number: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  void _showEditNameDialog(String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Name'),
          content: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Enter your name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final value = controller.text;
                navigator.pop();
                await _updateName(value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showEditPhoneDialog(String currentPhone) {
    final controller = TextEditingController(text: currentPhone);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Phone Number'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Enter your phone number',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final value = controller.text;
                navigator.pop();
                await _updatePhone(value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _pickAndUploadProfileImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _uploadingPhoto) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );

      if (pickedFile == null) return;

      setState(() => _uploadingPhoto = true);

      final file = File(pickedFile.path);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('${user.uid}.jpg');

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': downloadUrl,
      }, SetOptions(merge: true));

      _showSnack('Profile photo updated successfully.');
    } catch (e) {
      _showSnack('Failed to upload photo: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: bgColor,
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onEdit,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE8F5E9),
          child: Icon(icon, color: Colors.green.shade700),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        trailing: onEdit != null
            ? IconButton(
                onPressed: _savingProfile ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
              )
            : null,
      ),
    );
  }

  Widget _buildActivityTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE8F5E9),
          child: Icon(icon, color: Colors.green.shade700),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'No user is logged in.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF6F8F7),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error loading profile: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() ?? {};

            final name = (data['fullName'] ??
                    data['name'] ??
                    user.displayName ??
                    'CleanWalk User')
                .toString();

            final rawRole = (data['role'] ?? 'Member').toString();
            final role = rawRole.isNotEmpty
                ? rawRole[0].toUpperCase() + rawRole.substring(1)
                : 'Member';

            final email =
                (data['email'] ?? user.email ?? 'Not available').toString();
            final phone = (data['phone'] ?? 'Not available').toString();
            final memberSince = _formatMemberSince(
              data['createdAt'] ?? data['memberSince'],
            );
            final photoUrl = (data['photoUrl'] ?? '').toString();

            return FutureBuilder<List<int>>(
              future: Future.wait([
                _getReportsCount(user.uid),
                _getJoinedEventsCount(user.uid),
              ]),
              builder: (context, countsSnapshot) {
                final reportsCount = countsSnapshot.data?[0] ?? 0;
                final joinedEventsCount = countsSnapshot.data?[1] ?? 0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF2E7D32),
                              Color(0xFF43A047),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _pickAndUploadProfileImage,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 38,
                                    backgroundColor: Colors.white.withAlpha(
                                      (0.18 * 255).round(),
                                    ),
                                    backgroundImage: photoUrl.isNotEmpty
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child: photoUrl.isEmpty
                                        ? Text(
                                            _getInitials(name),
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          )
                                        : null,
                                  ),
                                  if (_uploadingPhoto)
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(90),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: _uploadingPhoto
                                  ? null
                                  : _pickAndUploadProfileImage,
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                'Change Photo',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withAlpha(
                                  (0.16 * 255).round(),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(
                                  (0.18 * 255).round(),
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                role,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _buildStatCard(
                            icon: Icons.flag_outlined,
                            value: '$reportsCount',
                            label: 'Reports',
                            iconColor: Colors.green.shade700,
                            bgColor: const Color(0xFFE8F5E9),
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            icon: Icons.event_outlined,
                            value: '$joinedEventsCount',
                            label: 'Events',
                            iconColor: Colors.orange.shade700,
                            bgColor: const Color(0xFFFFF3E0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoTile(
                        icon: Icons.person_outline,
                        title: 'Name',
                        value: name,
                        onEdit: () => _showEditNameDialog(name),
                      ),
                      _buildInfoTile(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        value: email,
                      ),
                      _buildInfoTile(
                        icon: Icons.phone_outlined,
                        title: 'Phone',
                        value: phone,
                        onEdit: () => _showEditPhoneDialog(
                          phone == 'Not available' ? '' : phone,
                        ),
                      ),
                      _buildInfoTile(
                        icon: Icons.calendar_month_outlined,
                        title: 'Member Since',
                        value: memberSince,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'My Activity',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0F000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ActivityPage(),
                              ),
                            );
                          },
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE8F5E9),
                            child: Icon(
                              Icons.assignment_outlined,
                              color: Colors.green.shade700,
                            ),
                          ),
                          title: const Text(
                            'My Reports',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text('View your submitted reports'),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                      _buildActivityTile(
                        context: context,
                        icon: Icons.event_note_outlined,
                        title: 'My Events',
                        subtitle: 'View your joined events',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyJoinedEventsPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _logout(context),
                          icon: const Icon(Icons.logout),
                          label: const Text('Logout'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFEBEE),
                            foregroundColor: Colors.red.shade700,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class MyJoinedEventsPage extends StatelessWidget {
  const MyJoinedEventsPage({super.key});

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _formatDate(DateTime dt) {
    const monthNames = [
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

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0
        ? 12
        : dt.hour > 12
            ? dt.hour - 12
            : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return const Color(0xFF2F6FE4);
      case 'ongoing':
        return const Color(0xFF2E7D32);
      case 'completed':
        return Colors.grey.shade700;
      case 'cancelled':
        return Colors.red;
      default:
        return const Color(0xFF2F6FE4);
    }
  }

  Color _statusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return const Color(0xFFDCEBFF);
      case 'ongoing':
        return const Color(0xFFE8F5E9);
      case 'completed':
        return const Color(0xFFEEEEEE);
      case 'cancelled':
        return const Color(0xFFFFEBEE);
      default:
        return const Color(0xFFDCEBFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('My Events'),
        backgroundColor: const Color(0xFFF6F8F7),
      ),
      body: user == null
          ? const Center(
              child: Text('You must be logged in to view joined events.'),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('events')
                  .where('joinedUserIds', arrayContains: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Failed to load joined events.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs.where((doc) {
                      final data = doc.data();
                      final status =
                          (data['status'] ?? '').toString().toLowerCase();
                      return status != 'cancelled';
                    }).toList() ??
                    [];

                docs.sort((a, b) {
                  final aDate = _readDateTime(a.data()['dateTime']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final bDate = _readDateTime(b.data()['dateTime']) ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  return aDate.compareTo(bDate);
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'You have not joined any active or completed events yet.',
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
                    final data = docs[index].data();

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
                    final status =
                        (data['status'] ?? 'upcoming').toString().toLowerCase();

                    final dateTime = _readDateTime(data['dateTime']);
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
                    final duration =
                        (data['duration'] ?? 'Duration not set').toString();

                    return Container(
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusBgColor(status),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    status[0].toUpperCase() + status.substring(1),
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
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
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 17,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    location,
                                    style: const TextStyle(fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 17,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    dateLabel,
                                    style: const TextStyle(fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_outlined,
                                  size: 17,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$timeLabel  •  $duration',
                                    style: const TextStyle(fontSize: 13.5),
                                  ),
                                ),
                              ],
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
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}