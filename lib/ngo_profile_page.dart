import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_page.dart';
import 'ngo_events_page.dart';

class NgoProfilePage extends StatefulWidget {
  const NgoProfilePage({super.key});

  @override
  State<NgoProfilePage> createState() => _NgoProfilePageState();
}

class _NgoProfilePageState extends State<NgoProfilePage> {
  bool _savingProfile = false;

  Future<int> _getCompletedEventsCount(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('events')
        .where('createdByUid', isEqualTo: userId)
        .where('status', isEqualTo: 'completed')
        .get();

    return snapshot.docs.length;
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

    if (parts.isEmpty) return 'N';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String? _validateOrgName(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Organization name cannot be empty';
    if (text.length < 2) return 'Organization name is too short';
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

  Future<void> _updateOrgName(String newName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final error = _validateOrgName(newName);
    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    try {
      setState(() => _savingProfile = true);

      final trimmedName = newName.trim();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'orgName': trimmedName,
      }, SetOptions(merge: true));

      _showSnack('Organization name updated successfully.');
    } catch (e) {
      _showSnack('Failed to update organization name: $e', isError: true);
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

  Future<void> _updateAddress(String newAddress) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final trimmed = newAddress.trim();
    if (trimmed.isEmpty) {
      _showSnack('Address cannot be empty', isError: true);
      return;
    }

    try {
      setState(() => _savingProfile = true);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'address': trimmed,
      }, SetOptions(merge: true));

      _showSnack('Address updated successfully.');
    } catch (e) {
      _showSnack('Failed to update address: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _updateDescription(String newDescription) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final trimmed = newDescription.trim();
    if (trimmed.isEmpty) {
      _showSnack('Description cannot be empty', isError: true);
      return;
    }

    try {
      setState(() => _savingProfile = true);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'description': trimmed,
      }, SetOptions(merge: true));

      _showSnack('Description updated successfully.');
    } catch (e) {
      _showSnack('Failed to update description: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  void _showEditDialog({
    required String title,
    required String initialValue,
    required String hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
    required Future<void> Function(String value) onSave,
  }) {
    final controller = TextEditingController(text: initialValue);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textInputAction:
                maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
            decoration: InputDecoration(hintText: hintText),
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
                await onSave(value);
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

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      width: double.infinity,
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
            'No NGO user is logged in.',
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
                    'Error loading NGO profile: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() ?? {};

            final orgName = (data['orgName'] ??
                    data['fullName'] ??
                    data['name'] ??
                    'NGO Organization')
                .toString();

            final role = 'NGO Organizer';

            final email =
                (data['email'] ?? user.email ?? 'Not available').toString();
            final phone = (data['phone'] ?? 'Not available').toString();
            final address = (data['address'] ?? 'Address / location').toString();
            final description =
                (data['description'] ?? 'Describe your NGO organization')
                    .toString();
            final memberSince = _formatMemberSince(
              data['createdAt'] ?? data['memberSince'],
            );

            return FutureBuilder<int>(
              future: _getCompletedEventsCount(user.uid),
              builder: (context, countSnapshot) {
                final completedEvents = countSnapshot.data ?? 0;

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
                            CircleAvatar(
                              radius: 38,
                              backgroundColor: Colors.white.withAlpha(
                                (0.18 * 255).round(),
                              ),
                              child: Text(
                                _getInitials(orgName),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              orgName,
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
                      _buildStatCard(
                        icon: Icons.history_outlined,
                        value: '$completedEvents',
                        label: 'Completed Events',
                        iconColor: Colors.orange.shade700,
                        bgColor: const Color(0xFFFFF3E0),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Organization Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoTile(
                        icon: Icons.business_outlined,
                        title: 'Organization Name',
                        value: orgName,
                        onEdit: () => _showEditDialog(
                          title: 'Edit Organization Name',
                          initialValue: orgName,
                          hintText: 'Enter organization name',
                          onSave: _updateOrgName,
                        ),
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
                        onEdit: () => _showEditDialog(
                          title: 'Edit Phone Number',
                          initialValue: phone == 'Not available' ? '' : phone,
                          hintText: 'Enter phone number',
                          keyboardType: TextInputType.phone,
                          onSave: _updatePhone,
                        ),
                      ),
                      _buildInfoTile(
                        icon: Icons.place_outlined,
                        title: 'Address',
                        value: address,
                        onEdit: () => _showEditDialog(
                          title: 'Edit Address',
                          initialValue:
                              address == 'Address / location' ? '' : address,
                          hintText: 'Enter NGO address',
                          maxLines: 2,
                          onSave: _updateAddress,
                        ),
                      ),
                      _buildInfoTile(
                        icon: Icons.description_outlined,
                        title: 'Description',
                        value: description,
                        onEdit: () => _showEditDialog(
                          title: 'Edit Description',
                          initialValue: description ==
                                  'Describe your NGO organization'
                              ? ''
                              : description,
                          hintText: 'Describe your NGO organization',
                          maxLines: 4,
                          onSave: _updateDescription,
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
                      _buildActivityTile(
                        context: context,
                        icon: Icons.history_outlined,
                        title: 'Completed Events',
                        subtitle: 'View your completed events only',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const NgoEventsPage(completedOnly: true),
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