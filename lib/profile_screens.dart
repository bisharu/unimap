import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'skeleton.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class ProfileHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const ProfileHeader({
    super.key,
    required this.title,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: topPadding + 10, bottom: 20, left: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA), // Cleaner off-white
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
              ],
            ),
            child: IconButton(
              onPressed: onBack ?? () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'googlesans',
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E3A5F),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileValueDisplay extends StatelessWidget {
  final String label;
  final String value;
  final bool isPassword;
  final bool isLoading;

  const ProfileValueDisplay({
    super.key,
    required this.label,
    required this.value,
    this.isPassword = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 8),
          child: isLoading 
            ? const Skeleton(width: 60, height: 18)
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'googlesans',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
        ),
        isLoading 
          ? const Skeleton(width: double.infinity, height: 50, borderRadius: 30)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFE1EBF5), // Blue/lavender from design
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                isPassword ? '*' * value.length : value,
                style: const TextStyle(
                  fontFamily: 'googlesans',
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
            ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 1: MY PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  bool _isLoading = true;
  String _name = 'Loading...';
  String _studentId = 'Loading...';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (doc.exists && mounted) {
          setState(() {
            _name = doc.data()?['name'] ?? 'N/A';
            _studentId = doc.data()?['studentId'] ?? 'N/A';
            _isLoading = false;
          });
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfileHeader(title: 'My Profile'),
          const SizedBox(height: 60),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  ProfileValueDisplay(label: 'Name', value: _name, isLoading: _isLoading),
                  const SizedBox(height: 24),
                  ProfileValueDisplay(label: 'ID', value: _studentId, isLoading: _isLoading),
                  const SizedBox(height: 24),
                  ProfileValueDisplay(
                      label: 'Password', value: '********', isPassword: true, isLoading: _isLoading),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const PasswordChangeScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF), // Purple from design
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 6,
                          shadowColor: const Color(0xFF6C63FF).withOpacity(0.4),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Request to change password',
                              style: TextStyle(
                                fontFamily: 'googlesans',
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2: PASSWORD CHANGE
// ─────────────────────────────────────────────────────────────────────────────

class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  Timer? _timer;
  int _secondsRemaining = 120;
  bool _isTimerRunning = false;

  void _startTimer() {
    setState(() {
      _secondsRemaining = 120;
      _isTimerRunning = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            _isTimerRunning = false;
            _timer?.cancel();
          }
        });
      }
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    fontSize: 28,
                    color: Colors.black,
                    height: 1.2,
                  ),
                  children: [
                    TextSpan(text: 'Share your '),
                    TextSpan(
                        text: 'Email\n',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: 'to get '),
                    TextSpan(
                        text: 'OTP',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 60),
            
            // EMAIL FIELD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.black12, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          hintText: 'Enter your email address',
                          hintStyle: TextStyle(color: Colors.black38, fontSize: 16),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF6C9CFF),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white),
                        onPressed: () {
                          if (_emailController.text.isNotEmpty) {
                            _startTimer();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 40),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Link shared to ${_emailController.text}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'googlesans',
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF1E3A5F),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // OTP FIELD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.black12, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              hintText: 'Enter the OTP',
                              hintStyle: TextStyle(color: Colors.black38, fontSize: 16),
                              border: InputBorder.none,
                              counterText: "",
                              contentPadding: EdgeInsets.symmetric(horizontal: 16),
                            ),
                          ),
                        ),
                        if (_isTimerRunning)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              _formatTime(_secondsRemaining),
                              style: const TextStyle(
                                color: Color(0xFF6C9CFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_isTimerRunning && _secondsRemaining == 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 8),
                      child: TextButton(
                        onPressed: _startTimer,
                        child: const Text('Resend OTP'),
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 60),
            
            // VERIFY BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: SizedBox(
                width: double.infinity,
                  child: ElevatedButton(
                  onPressed: () {
                    if (_otpController.text.isNotEmpty) {
                       Navigator.push(
                         context,
                         MaterialPageRoute(builder: (context) => const SetNewPasswordScreen()),
                       );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Verify OTP',
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3: SET NEW PASSWORD
// ─────────────────────────────────────────────────────────────────────────────

class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();
  bool _isPassVisible = false;
  bool _isConfirmPassVisible = false;

  @override
  void dispose() {
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    fontSize: 28,
                    color: Colors.black,
                    height: 1.2,
                  ),
                  children: [
                    TextSpan(text: 'Set your '),
                    TextSpan(
                        text: 'New\n',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(
                        text: 'Password',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 60),
            
            // NEW PASSWORD FIELD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.black12, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _passController,
                  obscureText: !_isPassVisible,
                  decoration: InputDecoration(
                    hintText: 'New Password',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 16),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPassVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        color: Colors.black38,
                      ),
                      onPressed: () => setState(() => _isPassVisible = !_isPassVisible),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // CONFIRM PASSWORD FIELD
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.black12, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _confirmPassController,
                  obscureText: !_isConfirmPassVisible,
                  decoration: InputDecoration(
                    hintText: 'Confirm Password',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 16),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPassVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        color: Colors.black38,
                      ),
                      onPressed: () => setState(() => _isConfirmPassVisible = !_isConfirmPassVisible),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 60),
            
            // RESET BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final password = _passController.text;
                    final confirmPassword = _confirmPassController.text;

                    if (password.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a new password')),
                      );
                      return;
                    }

                    if (password.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password must be at least 6 characters')),
                      );
                      return;
                    }

                    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(password)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password must contain both letters and numbers')),
                      );
                      return;
                    }

                    if (password != confirmPassword) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Passwords do not match')),
                      );
                      return;
                    }

                    if (password.isNotEmpty && password == confirmPassword) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(
                           content: const Text('Password reset successfully!'),
                           backgroundColor: Colors.green.shade700,
                           behavior: SnackBarBehavior.floating,
                         ),
                       );
                       // Go back to profile or login
                       Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Reset Password',
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3: TERMS & CONDITIONS
// ─────────────────────────────────────────────────────────────────────────────

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfileHeader(title: 'Terms & Conditions'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('1. Acceptance of Terms'),
                  _buildSectionText(
                      'By accessing and using UniMap, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use the application.'),
                  const SizedBox(height: 24),
                  _buildSectionTitle('2. User Conduct'),
                  _buildSectionText(
                      'Users are expected to use UniMap responsibly. Any attempt to disrupt the service, scrape data without permission, or use the app for illegal activities is strictly prohibited.'),
                  const SizedBox(height: 24),
                  _buildSectionTitle('3. Privacy Policy'),
                  _buildSectionText(
                      'Your privacy is important to us. Please refer to our Privacy Policy to understand how we collect, use, and protect your data.'),
                  const SizedBox(height: 24),
                  _buildSectionTitle('4. Limitation of Liability'),
                  _buildSectionText(
                      'UniMap is provided "as is" without any warranties. We are not liable for any damages arising from the use of this application.'),
                  const SizedBox(height: 40),
                  const Center(
                    child: Text(
                      'Last updated: May 2026',
                      style: TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 12,
                        color: Colors.black38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'googlesans',
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E3A5F),
        ),
      ),
    );
  }

  Widget _buildSectionText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'googlesans',
        fontSize: 14,
        color: Colors.black87,
        height: 1.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 4: FEEDBACK BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class FeedbackBottomSheet extends StatefulWidget {
  const FeedbackBottomSheet({super.key});

  @override
  State<FeedbackBottomSheet> createState() => _FeedbackBottomSheetState();
}

class _FeedbackBottomSheetState extends State<FeedbackBottomSheet> {
  String? _selectedFeedbackType;
  bool _isLoading = true;
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const ProfileHeader(title: 'Feedback'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "How can we improve?",
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Your feedback helps us make UniMap better for everyone.",
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _feedbackOption(Icons.bug_report_rounded, "Report a Bug"),
                  _feedbackOption(Icons.lightbulb_rounded, "Suggest a Feature"),
                  _feedbackOption(Icons.star_rounded, "Rate the App"),
                  _feedbackOption(Icons.help_rounded, "Other Issues"),
                  const SizedBox(height: 60),
                  if (_selectedFeedbackType != null) ...[
                    Text(
                      "Details for: $_selectedFeedbackType",
                      style: const TextStyle(
                        fontFamily: 'googlesans',
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A5F),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _feedbackController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: "Tell us more...",
                        filled: true,
                        fillColor: const Color(0xFFF1F4F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        final String text = _feedbackController.text.trim();
                        if (text.isEmpty) return;

                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          await FirebaseFirestore.instance.collection('feedback').add({
                            'text': text,
                            'userId': user?.uid ?? 'anonymous',
                            'timestamp': FieldValue.serverTimestamp(),
                          });

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Thank you for your feedback!")),
                            );
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: ${e.toString()}")),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        "Submit",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackOption(IconData icon, String label) {
    bool isSelected = _selectedFeedbackType == label;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE1EBF5) : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: const Color(0xFF6C63FF), width: 1.5) : null,
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1E3A5F)),
        title: Text(
          label,
          style: const TextStyle(fontFamily: 'googlesans', fontWeight: FontWeight.w600),
        ),
        trailing: Icon(
          isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
          size: 18,
          color: isSelected ? const Color(0xFF6C63FF) : Colors.black26,
        ),
        onTap: () {
          setState(() {
            _selectedFeedbackType = label;
          });
        },
      ),
    );
  }
}
