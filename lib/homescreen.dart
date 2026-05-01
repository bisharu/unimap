import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screens.dart';
import 'skeleton.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchFocused = false;
  bool _isFetchingLocation = false;
  bool _isInitializing = true;
  String? _userName;

  // Animation controller for the location button pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Simulate map/UI initialization
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _isInitializing = false);
    });
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            _userName = doc.data()?['name'];
          });
        }
      } catch (e) {
        debugPrint("Error fetching user name: $e");
      }
    }
  }

  String _getUserInitial() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "?";
    if (user.isAnonymous) return "G";
    if (_userName != null && _userName!.isNotEmpty) {
      return _userName![0].toUpperCase();
    }
    return user.email != null && user.email!.isNotEmpty 
        ? user.email![0].toUpperCase() 
        : "U";
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
    });

    // Check & request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      setState(() {
        _isFetchingLocation = false;
      });
      _showLocationSnackbar('Location permission denied. Please enable it in settings.');
      return;
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _isFetchingLocation = false;
      });
      _showLocationSnackbar(
          '📍 Location found: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
    } catch (e) {
      setState(() {
        _isFetchingLocation = false;
      });
      _showLocationSnackbar('Could not get your location. Please try again.');
    }
  }

  void _showLocationSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontFamily: 'googlesans', fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E3A5F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows content to take more space if needed
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProfileBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ensure system bars remain transparent on this screen
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
    ));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── 1. MAP BACKGROUND PLACEHOLDER ──────────────────────────────────
          Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFFADBDD9), // Light blue-grey (map placeholder)
            child: CustomPaint(
              painter: _MapGridPainter(),
            ),
          ),

          // ── 2. TOP SEARCH BAR ───────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _buildSearchBar(context),
          ),

          // ── 3. LOCATION BUTTON (bottom center) ─────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 28,
            left: 0,
            right: 0,
            child: Center(child: _buildLocationButton()),
          ),
        ],
      ),
    );
  }

  // ── SEARCH BAR ────────────────────────────────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    if (_isInitializing) {
      return const Skeleton(
        height: 52,
        borderRadius: 30,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isSearchFocused ? 0.18 : 0.10),
            blurRadius: _isSearchFocused ? 20 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.search_rounded,
            color: _isSearchFocused
                ? const Color(0xFF1E3A5F)
                : Colors.black54,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onFocusChange: (focused) =>
                  setState(() => _isSearchFocused = focused),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  fontFamily: 'googlesans',
                  fontSize: 14,
                  color: Colors.black87,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search location by name, room no., etc',
                  hintStyle: TextStyle(
                    fontFamily: 'googlesans',
                    color: Colors.black38,
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Profile icon button
          GestureDetector(
            onTap: () => _showProfileMenu(context),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7), // Light black
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _getUserInitial(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCATION BUTTON ───────────────────────────────────────────────────────
  Widget _buildLocationButton() {
    if (_isInitializing) {
      return const Skeleton(
        width: 58,
        height: 58,
        shape: BoxShape.circle,
      );
    }
    return ScaleTransition(
      scale: _pulseAnimation,
      child: GestureDetector(
        onTap: _isFetchingLocation ? null : _getCurrentLocation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5B5FEF).withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isFetchingLocation
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Color(0xFF5B5FEF),
                      strokeWidth: 2.5,
                    ),
                  )
                : Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5B5FEF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── PROFILE BOTTOM SHEET ──────────────────────────────────────────────────
class _ProfileBottomSheet extends StatefulWidget {
  @override
  State<_ProfileBottomSheet> createState() => _ProfileBottomSheetState();
}

class _ProfileBottomSheetState extends State<_ProfileBottomSheet> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  Timer? _timer;
  String _timeRemaining = "00:00:30";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
              // Immediately clear navigator stack to return to Auth screen
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
        if (doc.exists && mounted) {
          setState(() {
            _userData = doc.data();
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
    final String email = isGuest ? 'Timed Session (30s)' : (user?.email ?? 'Not logged in');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4)),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Avatar + name section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E5D6A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: Colors.white, size: 28),
                      ),
                      if (isGuest)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.timer_rounded, size: 12, color: Colors.black),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _isLoading && !isGuest
                          ? const Skeleton(width: 100, height: 16)
                          : Text(
                              name,
                              style: const TextStyle(
                                fontFamily: 'googlesans',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                        _isLoading && !isGuest
                          ? const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Skeleton(width: 140, height: 12),
                            )
                          : Text(
                              email,
                              style: TextStyle(
                                fontFamily: 'googlesans',
                                fontSize: 13,
                                color: isGuest ? Colors.amber[900] : Colors.black45,
                                fontWeight: isGuest ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24, indent: 20, endIndent: 20),
            if (isGuest)
              _menuItem(Icons.timer_outlined, 'Session Ends in: $_timeRemaining', context, isGuest: true)
            else ...[
              _menuItem(Icons.person_outline_rounded, 'My Profile', context),
              _menuItem(Icons.copy_rounded, 'Terms & Conditions', context),
              _menuItem(Icons.speaker_notes_rounded, 'Feedback', context),
            ],
            const Divider(height: 20, indent: 20, endIndent: 20),
            _menuItem(Icons.logout_rounded, 'Logout', context,
                color: const Color(0xFFD9534F)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, BuildContext context,
      {Color? color, bool isGuest = false}) {
    final itemColor = color ?? const Color(0xFF1E3A5F);
    return ListTile(
      leading: Icon(icon, color: itemColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'googlesans',
          fontSize: 15,
          fontWeight: isGuest ? FontWeight.w700 : FontWeight.w500,
          color: isGuest ? Colors.amber[900] : itemColor,
        ),
      ),
      onTap: isGuest && label.contains('Session Ends') ? null : () async {
        if (label == 'Logout') {
          // Immediately sign out and clear navigator stack to return to Auth screen
          await FirebaseAuth.instance.signOut();
          if (context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
        } else {
          Navigator.pop(context); // Close bottom sheet
          if (label == 'My Profile') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const MyProfileScreen()));
          } else if (label == 'Terms & Conditions') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const TermsAndConditionsScreen()));
          } else if (label == 'Feedback') {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const FeedbackBottomSheet(),
            );
          }
        }
      },
      horizontalTitleGap: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}

// ── MAP GRID PAINTER (subtle grid lines as map placeholder) ───────────────
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.0;

    // Horizontal lines
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vertical lines
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Fake road lines for map feel
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Horizontal roads
    canvas.drawLine(
        Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35), roadPaint);
    canvas.drawLine(
        Offset(0, size.height * 0.60), Offset(size.width, size.height * 0.60), roadPaint);

    // Vertical roads
    canvas.drawLine(
        Offset(size.width * 0.3, 0), Offset(size.width * 0.3, size.height), roadPaint);
    canvas.drawLine(
        Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), roadPaint);

    // Building blocks (placeholder rectangles)
    final blockPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final blockStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final blocks = [
      Rect.fromLTWH(size.width * 0.05, size.height * 0.10, size.width * 0.20, size.height * 0.18),
      Rect.fromLTWH(size.width * 0.35, size.height * 0.10, size.width * 0.28, size.height * 0.15),
      Rect.fromLTWH(size.width * 0.75, size.height * 0.08, size.width * 0.18, size.height * 0.20),
      Rect.fromLTWH(size.width * 0.05, size.height * 0.43, size.width * 0.18, size.height * 0.12),
      Rect.fromLTWH(size.width * 0.35, size.height * 0.43, size.width * 0.28, size.height * 0.12),
      Rect.fromLTWH(size.width * 0.75, size.height * 0.43, size.width * 0.18, size.height * 0.12),
      Rect.fromLTWH(size.width * 0.10, size.height * 0.68, size.width * 0.15, size.height * 0.18),
      Rect.fromLTWH(size.width * 0.35, size.height * 0.70, size.width * 0.28, size.height * 0.15),
      Rect.fromLTWH(size.width * 0.73, size.height * 0.68, size.width * 0.20, size.height * 0.18),
    ];

    for (final block in blocks) {
      canvas.drawRRect(RRect.fromRectAndRadius(block, const Radius.circular(4)), blockPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(block, const Radius.circular(4)), blockStroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
