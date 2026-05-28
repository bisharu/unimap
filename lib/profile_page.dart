import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'profile_screens.dart';
import 'skeleton.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  Timer? _timer;
  late VideoPlayerController _videoController;
  String _timeRemaining = "00:00:30";

  @override
  void initState() {
    super.initState();
    _startTimer();
    _fetchUserData();
    _videoController = VideoPlayerController.asset('assets/Video/profileBack.mp4')
      ..initialize().then((_) {
        _videoController.setVolume(0.0);
        _videoController.setLooping(true);
        _videoController.play();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoController.dispose();
    super.dispose();
  }

  void _startTimer() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final lastSignIn = user.metadata.lastSignInTime;
        if (lastSignIn != null) {
          final expiryTime = lastSignIn.add(const Duration(seconds: 30));
          final remaining = expiryTime.difference(DateTime.now());
          if (remaining.isNegative) {
            timer.cancel();
            FirebaseAuth.instance.signOut();
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          } else {
            if (mounted) {
              setState(() {
                _timeRemaining = _formatDuration(remaining);
              });
            }
          }
        }
      });
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (mounted) {
          setState(() {
            if (doc.exists) {
              _userData = doc.data();
            }
            _isLoading = false;
          });
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
    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user?.isAnonymous ?? false;
    final String name = isGuest ? 'Guest User' : (_userData?['name'] ?? 'UniMap User');
    final String email = isGuest ? '' : (user?.email ?? 'N/A');
    
    String displayId = "Timed Session (30s)";
    if (!isGuest) {
      displayId = _userData?['studentId'] ?? 'ID: N/A';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(context, name, displayId, email, isGuest),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                if (isGuest)
                   _buildMenuItem(Icons.timer_outlined, 'Session Ends in: $_timeRemaining', isGuest: true)
                else ...[
                  _buildMenuItem(Icons.lock_reset_rounded, 'Change Password', onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PasswordChangeScreen()));
                  }),
                  _buildMenuItem(Icons.copy_rounded, 'Terms & Conditions', onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()));
                  }),
                  _buildMenuItem(Icons.speaker_notes_rounded, 'Feedback', onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackBottomSheet()));
                  }),
                ],
                const Divider(height: 24, indent: 24, endIndent: 24),
/*
                // AI Assistant entry — available to all users
                _buildAiAssistantItem(context),
*/
                const Divider(height: 40, indent: 24, endIndent: 24),
                _buildMenuItem(Icons.logout_rounded, 'Logout', 
                  color: const Color(0xFFD9534F), 
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                    }
                  }
                ),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String name, String id, String email, bool isGuest) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF1E3A5F),
              child: _videoController.value.isInitialized
                  ? Opacity(
                      opacity: 0.75,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController.value.size.width,
                          height: _videoController.value.size.height,
                          child: VideoPlayer(_videoController),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 30,
              left: 24,
              right: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 4),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name.trim()[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _isLoading && !isGuest
                      ? const Skeleton(width: 140, height: 20)
                      : Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'googlesans',
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: Colors.white,
                          ),
                        ),
                    const SizedBox(height: 4),
                    _isLoading && !isGuest
                      ? const Skeleton(width: 100, height: 14)
                      : Text(
                          id,
                          style: TextStyle(
                            fontFamily: 'googlesans',
                            fontSize: 14,
                            color: isGuest ? Colors.amber[300] : Colors.white70,
                            fontWeight: isGuest ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                    if (!isGuest) ...[
                      const SizedBox(height: 2),
                      _isLoading
                        ? const Skeleton(width: 120, height: 12)
                        : Text(
                            email,
                            style: const TextStyle(
                              fontFamily: 'googlesans',
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ],
),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, {Color? color, bool isGuest = false, VoidCallback? onTap}) {
    final itemColor = color ?? const Color(0xFF1E3A5F);
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: itemColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: itemColor, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'googlesans',
          fontSize: 16,
          fontWeight: isGuest ? FontWeight.w700 : FontWeight.w500,
          color: isGuest ? Colors.amber[900] : itemColor,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.black26),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }

  /*
  Widget _buildAiAssistantItem(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final RoomSearchItem? selectedRoom = await Navigator.push<RoomSearchItem>(
          context,
          MaterialPageRoute(
            builder: (_) => AIAssistantScreen(allRooms: const []),
          ),
        );
        // If a room was deep-linked, pop profile page so user lands on the map
        if (selectedRoom != null && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // AI Icon
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                'assets/images/aiIcon.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            // Label + subtitle
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UniMap AI Assistant',
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ask anything about the campus',
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
  */

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          const Text(
            'Version 1.0.0',
            style: TextStyle(
              fontFamily: 'googlesans',
              fontSize: 12,
              color: Colors.black26,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Created by BTS',
              style: TextStyle(
                fontFamily: 'googlesans',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
