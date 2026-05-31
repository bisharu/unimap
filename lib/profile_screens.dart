import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
            color: Colors.black.withValues(alpha: 0.05),
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
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
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
                    color: Colors.black.withValues(alpha: 0.05),
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
  String _email = 'Loading...';

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
            _email = doc.data()?['email'] ?? 'N/A';
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
                  const SizedBox(height: 20),
                  ProfileValueDisplay(label: 'Email', value: _email, isLoading: _isLoading),
                  const SizedBox(height: 20),
                  ProfileValueDisplay(label: 'ID', value: _studentId, isLoading: _isLoading),
                  const SizedBox(height: 20),
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
                          shadowColor: const Color(0xFF6C63FF).withValues(alpha: 0.4),
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
// SCREEN 2: PASSWORD CHANGE (FIREBASE RESET FLOW)
// ─────────────────────────────────────────────────────────────────────────────

class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _emailController = TextEditingController();
  
  int _currentStep = 0; // 0: Confirm, 1: Success
  bool _isLoading = false;
  String? _registeredEmail;
  bool _fetchingEmail = true;

  @override
  void initState() {
    super.initState();
    _fetchRegisteredEmail();
  }

  Future<void> _fetchRegisteredEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          final email = doc.data()?['email'];
          if (email != null && email.toString().contains('@')) {
            setState(() {
              _registeredEmail = email.toString();
              _emailController.text = email.toString();
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching email: $e");
      }
    }
    if (mounted) setState(() => _fetchingEmail = false);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError("Please enter a valid email address.");
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _nextStep();
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Failed to send reset link.");
    } catch (e) {
      _showError("Error: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          ProfileHeader(
            title: 'Change Password',
            onBack: _currentStep > 0 ? _prevStep : null,
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildConfirmStep(),
                _buildSuccessStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContainer({
    required String title,
    required String subtitle,
    required Widget child,
    required String buttonText,
    required VoidCallback onButtonPressed,
    IconData? buttonIcon,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'googlesans',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'googlesans',
              fontSize: 16,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          child,
          const SizedBox(height: 60),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : onButtonPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: const Color(0xFF6C63FF).withValues(alpha: 0.3),
              ),
              child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        buttonText,
                        style: const TextStyle(
                          fontFamily: 'googlesans',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (buttonIcon != null) ...[
                        const SizedBox(width: 8),
                        Icon(buttonIcon, color: Colors.white, size: 20),
                      ],
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmStep() {
    String maskedEmail = "";
    if (_registeredEmail != null) {
      final parts = _registeredEmail!.split('@');
      if (parts[0].length > 3) {
        maskedEmail = "${parts[0].substring(0, 3)}***@${parts[1]}";
      } else {
        maskedEmail = "***@${parts[1]}";
      }
    }

    return _buildStepContainer(
      title: "Password Reset",
      subtitle: _registeredEmail != null 
        ? "We will send a secure password reset link to your registered email: $maskedEmail"
        : "Enter your email address to receive a secure password reset link.",
      buttonText: "Send Reset Link",
      buttonIcon: Icons.send_rounded,
      onButtonPressed: _sendResetLink,
      child: _fetchingEmail 
        ? const Center(child: CircularProgressIndicator())
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _emailController,
              readOnly: _registeredEmail != null,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Email Address",
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF1E3A5F)),
                suffixIcon: _registeredEmail != null ? const Icon(Icons.verified_rounded, color: Colors.green, size: 20) : null,
              ),
            ),
          ),
    );
  }

  Widget _buildSuccessStep() {
    return _buildStepContainer(
      title: "Link Sent!",
      subtitle: "A password reset link has been sent to ${_emailController.text}. \n\nPlease check your inbox (and spam folder) to set your new password.",
      buttonText: "Back to Profile",
      buttonIcon: Icons.arrow_back_rounded,
      onButtonPressed: () => Navigator.pop(context),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mark_email_read_rounded, size: 80, color: Colors.green.shade600),
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
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFormValid = _selectedFeedbackType != null && _feedbackController.text.trim().isNotEmpty;

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
                  _feedbackOption(Icons.help_rounded, "Other Issues"),
                  const SizedBox(height: 40),
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
                      onChanged: (val) {
                        setState(() {});
                      },
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
                      onPressed: (!isFormValid || _isSubmitting)
                          ? null
                          : () async {
                              setState(() {
                                _isSubmitting = true;
                              });
                              final String text = _feedbackController.text.trim();

                              try {
                                final user = FirebaseAuth.instance.currentUser;
                                String userName = 'Anonymous';
                                String userEmail = 'anonymous@unimap.com';

                                if (user != null) {
                                  userEmail = user.email ?? '';
                                  final userDoc = await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(user.uid)
                                      .get();
                                  if (userDoc.exists) {
                                    userName = userDoc.data()?['name'] ?? 'No Name';
                                    if (userEmail.isEmpty) {
                                      userEmail = userDoc.data()?['email'] ?? '';
                                    }
                                  }
                                }

                                await FirebaseFirestore.instance.collection('feedback').add({
                                  'type': _selectedFeedbackType,
                                  'text': text,
                                  'userId': user?.uid ?? 'anonymous',
                                  'userName': userName,
                                  'userEmail': userEmail,
                                  'timestamp': FieldValue.serverTimestamp(),
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text("Thank you for your feedback!"),
                                      backgroundColor: Colors.green.shade700,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                  Navigator.pop(context);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Error: ${e.toString()}"),
                                      backgroundColor: Colors.red.shade700,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isSubmitting = false;
                                  });
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        disabledBackgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Submit",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
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
