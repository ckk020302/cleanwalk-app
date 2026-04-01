import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'admin_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color bgColor = Color(0xFFE9F7EF);
  static const Color primaryGreen = Color(0xFF0AA64B);

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _showMessage(String text, {Color? bgColor}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: bgColor));
  }

  String _emailToKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',');
  }

  Future<void> _sendResetEmailWithApprovalGate(String email) async {
    final trimmed = email.trim().toLowerCase();

    if (trimmed.isEmpty || !trimmed.contains('@')) {
      _showMessage("Please enter a valid email.", bgColor: Colors.red);
      return;
    }

    final emailKey = _emailToKey(trimmed);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('accountsByEmail')
          .doc(emailKey)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        try {
          await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmed);
        } on FirebaseAuthException {}

        if (!mounted) return;
        _showMessage(
          "If this email exists, a reset link has been sent.\nAfter resetting, return to CleanWalk and login.",
          bgColor: Colors.green,
        );
        return;
      }

      final data = doc.data() ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase();
      final approvalStatus = (data['approvalStatus'] ?? '')
          .toString()
          .toLowerCase();

      if (role == 'ngo' && approvalStatus != 'approved') {
        _showMessage(
          "NGO account is not approved yet (Pending/Rejected).\nPassword reset is not available.",
          bgColor: Colors.red,
        );
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmed);

      if (!mounted) return;
      _showMessage(
        "If this email exists, a reset link has been sent.\nAfter resetting, return to CleanWalk and login.",
        bgColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage("Error: $e", bgColor: Colors.red);
    }
  }

  void _showForgotPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Reset Password"),
          content: TextField(
            controller: resetEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: "Enter your registered email",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = resetEmailController.text;
                Navigator.pop(context);
                await _sendResetEmailWithApprovalGate(email);
              },
              child: const Text("Send Link"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter email and password.', bgColor: Colors.red);
      return;
    }

    TextInput.finishAutofillContext();

    setState(() => _isLoading = true);

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user?.uid;
      if (uid == null) {
        if (!mounted) return;
        _showMessage('Login failed. Please try again.', bgColor: Colors.red);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _showMessage(
          'Account profile not found in database.',
          bgColor: Colors.red,
        );
        return;
      }

      final data = userDoc.data() ?? {};
      final role = (data['role'] ?? '').toString().toLowerCase();
      final accountStatus = (data['accountStatus'] ?? 'active')
          .toString()
          .toLowerCase();
      final approvalStatus = (data['approvalStatus'] ?? '')
          .toString()
          .toLowerCase();

      if (!mounted) return;

      if (accountStatus == 'disabled') {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _showMessage(
          'This account has been disabled.',
          bgColor: Colors.red,
        );
        return;
      }

      if (role == 'admin') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminShell()),
          (route) => false,
        );
        return;
      }

      if (role == 'ngo') {
        if (approvalStatus.isNotEmpty && approvalStatus != 'approved') {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          _showMessage(
            'NGO account is not approved yet.',
            bgColor: Colors.red,
          );
          return;
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const NgoShell()),
          (route) => false,
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found for this email.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Wrong email or password.';
          break;
        case 'invalid-email':
          message = 'Invalid email format.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        default:
          message = 'Login failed. Please try again.';
      }
      _showMessage(message, bgColor: Colors.red);
    } catch (_) {
      _showMessage(
        'Something went wrong. Please try again.',
        bgColor: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  elevation: 6,
                  shadowColor: const Color(0x22000000),
                  shape: const CircleBorder(),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/cleanwalk_logo.png',
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  "CleanWalk",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0B4F2A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Keep your community clean",
                  style: TextStyle(fontSize: 13, color: Color(0xFF2F6B4A)),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
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
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: Text(
                            "Welcome Back",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0B4F2A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          "Email",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D3B2D),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          enableInteractiveSelection: true,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                          decoration: InputDecoration(
                            hintText: "Enter your email",
                            prefixIcon: const Icon(Icons.email_outlined),
                            filled: true,
                            fillColor: const Color(0xFFF6F7F9),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          "Password",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D3B2D),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          enableInteractiveSelection: true,
                          onSubmitted: (_) => _isLoading ? null : _login(),
                          decoration: InputDecoration(
                            hintText: "Enter your password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: const Color(0xFFF6F7F9),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: const Text(
                              "Forgot password?",
                              style: TextStyle(
                                color: primaryGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _login,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward),
                            label: Text(
                              _isLoading ? "Logging in..." : "Log In",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
                          children: const [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                "or",
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style: TextStyle(color: Colors.black54),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(context, '/register');
                              },
                              child: const Text(
                                "Register now",
                                style: TextStyle(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}