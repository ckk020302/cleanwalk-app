import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  void _goToTab(int index) {
    setState(() => _currentIndex = index);
  }

  late final List<Widget> _pages = [
    const AdminManageReportsPage(),
    const AdminNgoVerificationPage(),
    const AdminAnnouncementPage(),
    const AdminProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F7EF),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F8F3),
            boxShadow: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _AdminNavItem(
                icon: Icons.description_outlined,
                activeIcon: Icons.description,
                label: 'Reports',
                selected: _currentIndex == 0,
                onTap: () => _goToTab(0),
              ),
              _AdminNavItem(
                icon: Icons.verified_user_outlined,
                activeIcon: Icons.verified_user,
                label: 'NGO Verify',
                selected: _currentIndex == 1,
                onTap: () => _goToTab(1),
              ),
              _AdminNavItem(
                icon: Icons.campaign_outlined,
                activeIcon: Icons.campaign,
                label: 'Announce',
                selected: _currentIndex == 2,
                onTap: () => _goToTab(2),
              ),
              _AdminNavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                selected: _currentIndex == 3,
                onTap: () => _goToTab(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AdminNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF1D3B2D);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFDDEFD8) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  selected ? activeIcon : icon,
                  color: selected ? dark : Colors.black54,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? dark : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminManageReportsPage extends StatelessWidget {
  const AdminManageReportsPage({super.key});

  static const Color bgColor = Color(0xFFE9F7EF);
  static const Color primaryGreen = Color(0xFF0AA64B);
  static const Color darkGreen = Color(0xFF0B4F2A);

  Future<void> _markAsSeen(
    BuildContext context,
    String reportId,
  ) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin not logged in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
            'adminSeen': true,
            'adminSeenAt': FieldValue.serverTimestamp(),
            'adminSeenBy': adminUid,
          });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report marked as seen.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark report as seen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteReportAndNotifyUser(
    BuildContext context,
    String reportId,
  ) async {
    try {
      final reportRef =
          FirebaseFirestore.instance.collection('reports').doc(reportId);

      final reportSnap = await reportRef.get();

      if (!reportSnap.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report not found.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final data = reportSnap.data() ?? {};
      final userId = (data['userId'] ?? '').toString();
      final title = (data['title'] ?? 'Your report').toString();

      final batch = FirebaseFirestore.instance.batch();

      batch.delete(reportRef);

      if (userId.isNotEmpty) {
        final notifRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc();

        batch.set(notifRef, {
          'type': 'admin_report_deleted',
          'title': 'Report Removed',
          'message':
              '$title was removed by admin because it was inappropriate or invalid.',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report deleted and user notified.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteReport(
    BuildContext context,
    String reportId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text(
          'Delete this report because it contains rude or invalid content?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _deleteReportAndNotifyUser(context, reportId);
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      final dt = value.toDate();
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '-';
  }

  bool _shouldShowReport(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final adminSeen = data['adminSeen'] == true;
    return status != 'resolved' && !adminSeen;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('View Reports'),
        centerTitle: true,
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load reports.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = (snapshot.data?.docs ?? [])
              .where((doc) => _shouldShowReport(doc.data()))
              .toList();

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No reports to review.',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final title = (data['title'] ?? 'Untitled Report').toString();
              final description = (data['description'] ?? '').toString();
              final reporterName =
                  (data['reporterName'] ?? data['fullName'] ?? 'Unknown User')
                      .toString();
              final location =
                  (data['locationLabel'] ?? data['address'] ?? '')
                      .toString();
              final status = (data['status'] ?? 'pending').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0x140AA64B),
                          child: Icon(
                            Icons.report_problem_outlined,
                            color: darkGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: darkGreen,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F7F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _infoRow('Reporter', reporterName),
                    _infoRow('Location', location.isEmpty ? '-' : location),
                    _infoRow('Created', _formatDate(data['createdAt'])),
                    const SizedBox(height: 8),
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: darkGreen,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description.isEmpty ? '-' : description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _markAsSeen(context, doc.id),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Seen'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryGreen,
                              side: const BorderSide(color: primaryGreen),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _confirmDeleteReport(context, doc.id),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminNgoVerificationPage extends StatelessWidget {
  const AdminNgoVerificationPage({super.key});

  static const Color bgColor = Color(0xFFE9F7EF);
  static const Color primaryGreen = Color(0xFF0AA64B);
  static const Color darkGreen = Color(0xFF0B4F2A);

  String _emailToKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',');
  }

  Future<void> _updateNgoStatus({
    required BuildContext context,
    required String applicationId,
    required String email,
    required String newStatus,
  }) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(applicationId);

      final appRef = FirebaseFirestore.instance
          .collection('ngo_applications')
          .doc(applicationId);

      final emailKey = _emailToKey(email);
      final emailRef = FirebaseFirestore.instance
          .collection('accountsByEmail')
          .doc(emailKey);

      final batch = FirebaseFirestore.instance.batch();

      batch.update(appRef, {
        'status': newStatus,
      });

      batch.set(userRef, {
        'approvalStatus': newStatus,
        'accountStatus': newStatus == 'approved' ? 'active' : 'rejected',
        'role': 'ngo',
      }, SetOptions(merge: true));

      batch.set(emailRef, {
        'approvalStatus': newStatus,
        'role': 'ngo',
      }, SetOptions(merge: true));

      await batch.commit();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'approved'
                ? 'NGO approved successfully.'
                : 'NGO rejected successfully.',
          ),
          backgroundColor:
              newStatus == 'approved' ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update NGO status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmApprove({
    required BuildContext context,
    required String applicationId,
    required String email,
    required String orgName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve NGO'),
        content: Text('Approve NGO registration for "$orgName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _updateNgoStatus(
        context: context,
        applicationId: applicationId,
        email: email,
        newStatus: 'approved',
      );
    }
  }

  Future<void> _confirmReject({
    required BuildContext context,
    required String applicationId,
    required String email,
    required String orgName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject NGO'),
        content: Text('Reject NGO registration for "$orgName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _updateNgoStatus(
        context: context,
        applicationId: applicationId,
        email: email,
        newStatus: 'rejected',
      );
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _buildProofPreview(String proofFileUrl) {
    if (proofFileUrl.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: const Text(
          'No proof document preview available.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF5A6B61),
            height: 1.4,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        proofFileUrl,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: double.infinity,
            height: 160,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: const Center(
              child: Text(
                'Unable to load proof image.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5A6B61),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D3B2D),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      final dt = value.toDate();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '-';
  }

  bool _isPending(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    return status == 'pending';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('NGO Verification'),
        centerTitle: true,
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('ngo_applications')
            .orderBy('submittedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load NGO applications.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = (snapshot.data?.docs ?? [])
              .where((doc) => _isPending(doc.data()))
              .toList();

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No pending NGO applications.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final email = (data['email'] ?? '').toString();
              final orgName = (data['orgName'] ?? '').toString();
              final phone = (data['phone'] ?? '').toString();
              final phoneCountry = (data['phoneCountry'] ?? '').toString();
              final proofFileName =
                  (data['proofFileName'] ?? '').toString();
              final proofFileExt =
                  (data['proofFileExt'] ?? '').toString();
              final proofFileSize =
                  (data['proofFileSize'] ?? '').toString();
              final proofFileUrl =
                  (data['proofFileUrl'] ?? '').toString();
              final status = (data['status'] ?? 'pending').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0x140AA64B),
                          child: Icon(
                            Icons.business_outlined,
                            color: darkGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            orgName.isEmpty ? 'Unnamed NGO' : orgName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: darkGreen,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _infoRow('Email', email),
                    _infoRow('Phone', phone),
                    _infoRow('Country', phoneCountry),
                    _infoRow('Proof file', proofFileName),
                    _infoRow('File type', proofFileExt),
                    _infoRow('File size', proofFileSize),
                    _infoRow('Submitted', _formatDate(data['submittedAt'])),
                    const SizedBox(height: 12),
                    const Text(
                      'Proof Document',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: darkGreen,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildProofPreview(proofFileUrl),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmReject(
                              context: context,
                              applicationId: doc.id,
                              email: email,
                              orgName: orgName,
                            ),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _confirmApprove(
                              context: context,
                              applicationId: doc.id,
                              email: email,
                              orgName: orgName,
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminAnnouncementPage extends StatefulWidget {
  const AdminAnnouncementPage({super.key});

  @override
  State<AdminAnnouncementPage> createState() => _AdminAnnouncementPageState();
}

class _AdminAnnouncementPageState extends State<AdminAnnouncementPage> {
  static const Color bgColor = Color(0xFFE9F7EF);
  static const Color primaryGreen = Color(0xFF0AA64B);
  static const Color darkGreen = Color(0xFF0B4F2A);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  String _target = 'all';
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendAnnouncement() async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (adminUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin not logged in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter title and message.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': title,
        'message': message,
        'target': _target,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
      });

      QuerySnapshot<Map<String, dynamic>> usersSnapshot;

      if (_target == 'users') {
        usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'user')
            .get();
      } else if (_target == 'ngos') {
        usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'ngo')
            .get();
      } else {
        usersSnapshot =
            await FirebaseFirestore.instance.collection('users').get();
      }

      final docs = usersSnapshot.docs.where((doc) {
        final role = (doc.data()['role'] ?? '').toString().toLowerCase();
        return role == 'user' || role == 'ngo';
      }).toList();

      for (final userDoc in docs) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userDoc.id)
            .collection('notifications')
            .add({
          'type': 'announcement',
          'title': title,
          'message': message,
          'target': _target,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      _titleController.clear();
      _messageController.clear();
      setState(() => _target = 'all');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announcement sent successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send announcement: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Make Announcement'),
        centerTitle: true,
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Announcement Title',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'e.g. System Maintenance Notice',
                  filled: true,
                  fillColor: const Color(0xFFF6F7F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Target Audience',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F7F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _target,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All Users and NGOs'),
                      ),
                      DropdownMenuItem(
                        value: 'users',
                        child: Text('Users Only'),
                      ),
                      DropdownMenuItem(
                        value: 'ngos',
                        child: Text('NGOs Only'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _target = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Message',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText:
                      'e.g. CleanWalk will be undergoing maintenance tonight from 11:00 PM to 1:00 AM.',
                  filled: true,
                  fillColor: const Color(0xFFF6F7F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _sendAnnouncement,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(
                    _sending ? 'Sending...' : 'Send Announcement',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminProfilePage extends StatelessWidget {
  const AdminProfilePage({super.key});

  static const Color bgColor = Color(0xFFE9F7EF);
  static const Color primaryGreen = Color(0xFF0AA64B);
  static const Color darkGreen = Color(0xFF0B4F2A);

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _logout(context);
    }
  }

  String _formatCreatedAt(dynamic value) {
    if (value is Timestamp) {
      final dt = value.toDate();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.year}';
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: bgColor,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: uid == null
          ? const Center(child: Text('Admin not logged in.'))
          : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() ?? {};
                final email = (data['email'] ??
                        FirebaseAuth.instance.currentUser?.email ??
                        '-')
                    .toString();
                final createdAt = data['createdAt'];

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Column(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: Color(0x140AA64B),
                              child: Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 34,
                                color: darkGreen,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'System Admin',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ProfileInfoCard(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: email,
                      ),
                      const SizedBox(height: 14),
                      _ProfileInfoCard(
                        icon: Icons.verified_user_outlined,
                        label: 'Role',
                        value: 'Admin',
                      ),
                      const SizedBox(height: 14),
                      _ProfileInfoCard(
                        icon: Icons.calendar_month_outlined,
                        label: 'Member Since',
                        value: _formatCreatedAt(createdAt),
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _confirmLogout(context),
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCEAEA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Logout',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0x140AA64B),
            child: Icon(icon, color: const Color(0xFF2F7D44)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D3B2D),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      ],
    ),
  );
}