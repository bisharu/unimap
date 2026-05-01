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
      decoration: const BoxDecoration(
        color: Color(0xFFE0DFD5), // Light beige from design
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onBack ?? () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 22),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'googlesans',
              fontSize: 23, // Set to 23px as requested
              fontWeight: FontWeight.w500,
              color: Colors.black,
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
          const SizedBox(height: 80),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Text.....',
              style: TextStyle(
                fontFamily: 'googlesans',
                fontSize: 18,
                color: Colors.black,
              ),
            ),
          ),
        ],
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
  // null means show options, string means show details for that option
  String? _selectedFeedbackType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Simulate loading options
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDetail = _selectedFeedbackType != null;
    
    // Bottom padding for keyboard if on detail screen
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      // Increase height slightly when keyboard is open
      height: MediaQuery.of(context).size.height * (isDetail ? 0.45 : 0.7) + bottomInset,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 60,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF42C2FF), // Cyan handle from design
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          
          if (isDetail)
             // Detail View Header
             Padding(
               padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Expanded(
                     child: Text(
                       _selectedFeedbackType!,
                       style: const TextStyle(
                         fontFamily: 'googlesans',
                         fontSize: 28,
                         fontWeight: FontWeight.bold,
                         color: Colors.black,
                       ),
                     ),
                   ),
                   IconButton(
                     onPressed: () => setState(() => _selectedFeedbackType = null), 
                     icon: const Icon(Icons.close_rounded, size: 28, color: Colors.black),
                   ),
                 ],
               ),
             )
          else
             // Options View Header
             const Padding(
               padding: EdgeInsets.fromLTRB(32, 40, 32, 40),
               child: Text(
                 'Feedback',
                 style: TextStyle(
                   fontFamily: 'googlesans',
                   fontSize: 32,
                   fontWeight: FontWeight.w500,
                   color: Colors.black,
                 ),
               ),
             ),

          // Content Box
          Expanded(
            child: _isLoading && !isDetail 
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Skeleton(width: double.infinity, height: 110, borderRadius: 24),
                      const SizedBox(height: 32),
                      const Skeleton(width: double.infinity, height: 110, borderRadius: 24),
                    ],
                  ),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isDetail ? _buildDetailView() : _buildOptionsView(),
                ),
          ),
          
          if (isDetail) SizedBox(height: bottomInset > 0 ? bottomInset : 20),
        ],
      ),
    );
  }

  Widget _buildOptionsView() {
    return Padding(
      key: const ValueKey('optionsView'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _feedbackCard(
            icon: Icons.report_gmailerrorred_rounded,
            title: 'Report an issue',
            description: 'Tell us if something is unusual or not working properly',
          ),
          const SizedBox(height: 32),
          _feedbackCard(
            icon: Icons.lightbulb_outline_rounded,
            title: 'Suggest any adjustments',
            description: 'Share your ideas on how we can improve further',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailView() {
    return Padding(
      key: const ValueKey('detailView'),
      padding: const EdgeInsets.all(24.0),
      child: Align(
        alignment: Alignment.bottomCenter,
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
              const Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Tell us how we can improve',
                    hintStyle: TextStyle(color: Colors.black38, fontSize: 16),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF6C9CFF), // Blue send button background
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.volunteer_activism_rounded, color: Colors.white, size: 40),
                            const SizedBox(height: 12),
                            const Text(
                              'Thank you for helping us iterate\nand improve.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
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
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      ),
                    );
                    Navigator.pop(context); // Close the entire bottom sheet
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feedbackCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFeedbackType = title;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F6F8), // Light cyan from design
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 44, color: Colors.black),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
