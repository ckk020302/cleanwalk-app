import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

enum RegisterRole { user, ngo }

class MalaysiaPhoneWithFixed60Formatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(0, 10);

    String formatted;
    if (digits.length <= 2) {
      formatted = digits;
    } else {
      formatted = '${digits.substring(0, 2)}-${digits.substring(2)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _RegisterPageState extends State<RegisterPage> {
  static const Color bgColor = Color(0xFFE9F7EF);
  static const Color primaryGreen = Color(0xFF0AA64B);
  static const Color inputFill = Color(0xFFF6F7F9);

  final _formKey = GlobalKey<FormState>();
  RegisterRole _role = RegisterRole.user;

  final _userFullName = TextEditingController();
  final _userEmail = TextEditingController();
  final _userPhone = TextEditingController();

  final _ngoOrgName = TextEditingController();
  final _ngoEmail = TextEditingController();
  final _ngoPhone = TextEditingController();

  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _hidePass = true;
  bool _hideConfirm = true;
  bool _isSubmitting = false;

  PlatformFile? _proofFile;

  static const int _maxProofBytes = 5 * 1024 * 1024;
  static const List<String> _allowedExt = ['pdf', 'jpg', 'jpeg', 'png'];

  final MalaysiaPhoneWithFixed60Formatter _myPhoneFormatter =
      MalaysiaPhoneWithFixed60Formatter();

  @override
  void dispose() {
    _userFullName.dispose();
    _userEmail.dispose();
    _userPhone.dispose();

    _ngoOrgName.dispose();
    _ngoEmail.dispose();
    _ngoPhone.dispose();

    _password.dispose();
    _confirmPassword.dispose();

    _passwordFocus.dispose();
    _confirmFocus.dispose();

    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _goToLogin() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();

    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  String? _validateEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Email is required';
    final at = s.indexOf('@');
    if (at <= 0 || at == s.length - 1) return 'Enter a valid email';
    final domain = s.substring(at + 1);
    if (!domain.contains('.')) return 'Enter a valid email';
    return null;
  }

  String? _validateDisplayName(String? v, {required String label}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    if (s.length < 2) return '$label is too short';
    if (!RegExp(r'[A-Za-z]').hasMatch(s)) return 'Enter a valid $label';
    return null;
  }

  String? _validateMalaysiaPhoneFixed60(
    String? v, {
    required bool requiredField,
  }) {
    final s = (v ?? '').trim();
    if (!requiredField && s.isEmpty) return null;
    if (requiredField && s.isEmpty) return 'Phone number is required';

    String digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);

    if (digits.length != 9 && digits.length != 10) {
      return 'Enter a valid MY phone (e.g. 0128889999)';
    }
    return null;
  }

  String _normalizeToE164MY(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length != 9 && digits.length != 10) return '';
    return '+60$digits';
  }

  String? _validatePassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Password is required';
    if (s.length < 8) return 'Minimum 8 characters';
    final hasUpper = RegExp(r'[A-Z]').hasMatch(s);
    final hasLower = RegExp(r'[a-z]').hasMatch(s);
    final hasDigit = RegExp(r'\d').hasMatch(s);
    if (!hasUpper || !hasLower || !hasDigit) {
      return 'Must include uppercase, lowercase, and number';
    }
    return null;
  }

  String? _validateConfirmPassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Confirm your password';
    if (s != _password.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _pickProofFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExt,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final ext = (file.extension ?? '').toLowerCase();

    if (!_allowedExt.contains(ext)) {
      _showMessage('Only PDF / JPG / PNG files are allowed.');
      return;
    }

    if (file.size > _maxProofBytes) {
      _showMessage('File too large. Max size is 5MB.');
      return;
    }

    if (file.path == null || file.path!.isEmpty) {
      _showMessage('Unable to access selected file.');
      return;
    }

    setState(() => _proofFile = file);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_role == RegisterRole.ngo && _proofFile == null) {
      _showMessage('Please upload NGO proof document (PDF/JPG/PNG, max 5MB).');
      return;
    }

    TextInput.finishAutofillContext();

    setState(() => _isSubmitting = true);

    try {
      if (_role == RegisterRole.user) {
        await _registerUser();
      } else {
        await _submitNgoApplication();
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _friendlyFirestoreError(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return 'Permission denied. Check Firebase rules.';
      }
      if (e.code == 'unavailable') {
        return 'Firebase unavailable. Check internet / Firebase status.';
      }
      return 'Firebase error: ${e.code}';
    }
    return 'Failed to save data. Please try again.';
  }

  Future<void> _registerUser() async {
    final fullName = _userFullName.text.trim();
    final email = _userEmail.text.trim();
    final phoneRaw = _userPhone.text.trim();
    final phoneE164 = phoneRaw.isEmpty ? '' : _normalizeToE164MY(phoneRaw);
    final password = _password.text;

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'role': 'user',
            'fullName': fullName,
            'email': email,
            'phone': phoneE164,
            'phoneCountry': 'MY',
            'accountStatus': 'active',
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      _showMessage('User account created successfully!');
      _goToLogin();
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email is already registered.';
          break;
        case 'invalid-email':
          msg = 'Invalid email format.';
          break;
        case 'weak-password':
          msg = 'Password is too weak.';
          break;
        default:
          msg = 'Registration failed. Please try again.';
      }
      _showMessage(msg);
    } on TimeoutException {
      try {
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (_) {}
      _showMessage('Saving profile timed out. Please try again.');
    } catch (e) {
      try {
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (_) {}
      _showMessage(_friendlyFirestoreError(e));
    }
  }

  Future<void> _submitNgoApplication() async {
    final orgName = _ngoOrgName.text.trim();
    final email = _ngoEmail.text.trim();
    final phoneE164 = _normalizeToE164MY(_ngoPhone.text.trim());
    final password = _password.text;

    UserCredential? cred;
    String? uploadedFilePath;

    try {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;
      final file = _proofFile;

      if (file == null || file.path == null || file.path!.isEmpty) {
        throw Exception('Proof file is missing.');
      }

      final ext = (file.extension ?? '').toLowerCase();
      final storagePath = 'ngo_proofs/$uid/proof.$ext';

      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      uploadedFilePath = storagePath;

      await storageRef.putFile(
        File(file.path!),
        SettableMetadata(
          contentType: _contentTypeForExtension(ext),
          customMetadata: {
            'uploadedByUid': uid,
            'role': 'ngo',
          },
        ),
      );

      final proofFileUrl = await storageRef.getDownloadURL();

      final batch = FirebaseFirestore.instance.batch();

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final appRef = FirebaseFirestore.instance
          .collection('ngo_applications')
          .doc(uid);
      final accountByEmailRef = FirebaseFirestore.instance
          .collection('accountsByEmail')
          .doc(_emailToKey(email));

      batch.set(userRef, {
        'role': 'ngo',
        'fullName': orgName,
        'email': email,
        'phone': phoneE164,
        'phoneCountry': 'MY',
        'approvalStatus': 'pending',
        'accountStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(appRef, {
        'orgName': orgName,
        'email': email,
        'phone': phoneE164,
        'phoneCountry': 'MY',
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'proofFileName': file.name,
        'proofFileSize': file.size,
        'proofFileExt': ext,
        'proofFileUrl': proofFileUrl,
        'applicantUid': uid,
      }, SetOptions(merge: true));

      batch.set(accountByEmailRef, {
        'role': 'ngo',
        'approvalStatus': 'pending',
        'uid': uid,
        'email': email,
      }, SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 10));

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _showMessage('NGO application submitted for review.');
      _goToLogin();
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email is already registered.';
          break;
        case 'invalid-email':
          msg = 'Invalid email format.';
          break;
        case 'weak-password':
          msg = 'Password is too weak.';
          break;
        default:
          msg = 'NGO registration failed. Please try again.';
      }
      _showMessage(msg);
    } on TimeoutException {
      if (uploadedFilePath != null) {
        try {
          await FirebaseStorage.instance.ref(uploadedFilePath).delete();
        } catch (_) {}
      }
      try {
        await cred?.user?.delete();
      } catch (_) {}
      _showMessage('Submitting application timed out. Please try again.');
    } catch (e) {
      if (uploadedFilePath != null) {
        try {
          await FirebaseStorage.instance.ref(uploadedFilePath).delete();
        } catch (_) {}
      }
      try {
        await cred?.user?.delete();
      } catch (_) {}
      _showMessage(_friendlyFirestoreError(e));
    }
  }

  String _emailToKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',');
  }

  String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1D3B2D),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      prefixText: prefixText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final horizontalPadding = w < 360 ? 16.0 : 22.0;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text(
          "Create Account",
          style: TextStyle(
            color: Color(0xFF0B4F2A),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0B4F2A)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              10,
              horizontalPadding,
              18 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Register as",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D3B2D),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _RoleBox(
                              selected: _role == RegisterRole.user,
                              icon: Icons.person_outline,
                              label: 'User',
                              onTap: () =>
                                  setState(() => _role = RegisterRole.user),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _RoleBox(
                              selected: _role == RegisterRole.ngo,
                              icon: Icons.apartment_outlined,
                              label: 'NGO',
                              onTap: () =>
                                  setState(() => _role = RegisterRole.ngo),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      if (_role == RegisterRole.user) ...[
                        _label("Name"),
                        TextFormField(
                          controller: _userFullName,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            hint: "Enter your full name",
                            icon: Icons.person_outline,
                          ),
                          validator: (v) =>
                              _validateDisplayName(v, label: 'Name'),
                        ),
                        const SizedBox(height: 14),

                        _label("Email"),
                        TextFormField(
                          controller: _userEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            hint: "Enter your email",
                            icon: Icons.email_outlined,
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 14),

                        _label("Contact Number (optional)"),
                        TextFormField(
                          controller: _userPhone,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [_myPhoneFormatter],
                          decoration: _fieldDecoration(
                            hint: "e.g. 0128889999",
                            icon: Icons.phone_outlined,
                            prefixText: "+60 ",
                          ),
                          validator: (v) => _validateMalaysiaPhoneFixed60(
                            v,
                            requiredField: false,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      if (_role == RegisterRole.ngo) ...[
                        _label("Organisation Name"),
                        TextFormField(
                          controller: _ngoOrgName,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            hint: "Enter organisation name",
                            icon: Icons.apartment_outlined,
                          ),
                          validator: (v) => _validateDisplayName(
                            v,
                            label: 'Organisation name',
                          ),
                        ),
                        const SizedBox(height: 14),

                        _label("Email Address"),
                        TextFormField(
                          controller: _ngoEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            hint: "Enter organisation email",
                            icon: Icons.email_outlined,
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 14),

                        _label("Phone Number"),
                        TextFormField(
                          controller: _ngoPhone,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [_myPhoneFormatter],
                          decoration: _fieldDecoration(
                            hint: "e.g. 0128889999",
                            icon: Icons.phone_outlined,
                            prefixText: "+60 ",
                          ),
                          validator: (v) => _validateMalaysiaPhoneFixed60(
                            v,
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(height: 14),

                        _label("NGO Proof Document"),
                        _ProofUploadBox(
                          file: _proofFile,
                          onPick: _pickProofFile,
                          onRemove: () => setState(() => _proofFile = null),
                        ),
                        const SizedBox(height: 14),
                      ],

                      _label("Password"),
                      TextFormField(
                        focusNode: _passwordFocus,
                        controller: _password,
                        obscureText: _hidePass,
                        keyboardType: TextInputType.visiblePassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        onEditingComplete: () => _confirmFocus.requestFocus(),
                        decoration: _fieldDecoration(
                          hint: "Create a password",
                          icon: Icons.lock_outline,
                          suffixIcon: Focus(
                            canRequestFocus: false,
                            descendantsAreFocusable: false,
                            child: IconButton(
                              onPressed: () =>
                                  setState(() => _hidePass = !_hidePass),
                              icon: Icon(
                                _hidePass
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      const SizedBox(height: 14),

                      _label("Confirm Password"),
                      TextFormField(
                        focusNode: _confirmFocus,
                        controller: _confirmPassword,
                        obscureText: _hideConfirm,
                        keyboardType: TextInputType.visiblePassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onEditingComplete: () {
                          FocusScope.of(context).unfocus();
                          _submit();
                        },
                        decoration: _fieldDecoration(
                          hint: "Re-enter your password",
                          icon: Icons.lock_outline,
                          suffixIcon: Focus(
                            canRequestFocus: false,
                            descendantsAreFocusable: false,
                            child: IconButton(
                              onPressed: () =>
                                  setState(() => _hideConfirm = !_hideConfirm),
                              icon: Icon(
                                _hideConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                        ),
                        validator: _validateConfirmPassword,
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submit,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1),
                          label: Text(
                            _role == RegisterRole.user
                                ? "Create Account"
                                : "Submit for Review",
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Already have an account? ",
                            style: TextStyle(color: Colors.black54),
                          ),
                          GestureDetector(
                            onTap: _isSubmitting ? null : _goToLogin,
                            child: const Text(
                              "Log in",
                              style: TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleBox extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoleBox({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? const Color(0xFF0AA64B)
        : const Color(0xFFD0D5DD);
    final bg = selected ? const Color(0xFFE6F4EA) : Colors.white;
    final fg = selected ? const Color(0xFF0AA64B) : const Color(0xFF1D3B2D);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofUploadBox extends StatelessWidget {
  final PlatformFile? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ProofUploadBox({
    required this.file,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0D5DD), width: 1.2),
        color: const Color(0xFFF6F7F9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Upload document (PDF, JPG, PNG) • Max 5MB",
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (file == null)
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file),
              label: const Text("Choose file"),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      file!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}