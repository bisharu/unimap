import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'widgets/indoor_map_widget.dart';
import 'profile_screens.dart';
import 'profile_page.dart';
import 'skeleton.dart';
import 'filter_screen.dart';
import 'dart:ui' as ui;
import 'utils/directions_helper.dart';
import 'utils/indoor_positioning_service.dart';
import 'package:url_launcher/url_launcher.dart';
// import 'ai_assistant_screen.dart';
import 'package:geolocator/geolocator.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;
  String _searchQuery = '';
  List<RoomSearchItem> _allRooms = [];
  List<String> _recentSearches = [];
  FilterResult? _activeFilter;
  bool _isFetchingLocation = false;
  bool _isInitializing = true;
  String? _userName;
  LatLng? _currentLocation;
  int _selectedFloor = 0;
  int? _userPhysicalFloor;
  bool _isFloorMenuOpen = false;
  bool _didShowFloorMismatchWarning = false;
  bool _isQrAnchored = false; // true when location was set via QR scan
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<IndoorMapWidgetState> _mapKey = GlobalKey<IndoorMapWidgetState>();
  final IndoorPositioningService _indoorPositioningService = IndoorPositioningService();
  StreamSubscription<IndoorPositioningUpdate>? _indoorPositioningSubscription;
  bool _isIndoorFusionEnabled = false;
  int _indoorStepCount = 0;

  // Animated search placeholder
  static const List<String> _searchPlaceholders = [
    'Search Classrooms',
    'Search Washrooms',
    'Search Faculty Cabins',
    'Search Cafeteria',
    'Search Atrium',
    'Search Offices',
    'Search Infirmary',
    'Search Parking Lot',
  ];
  int _currentPlaceholderIndex = 0;
  double _placeholderOpacity = 1.0;
  Timer? _placeholderTimer;

  // Compass and Connectivity
  double _heading = 0;
  bool _isOffline = false;
  List<DirectionStep> _directionSteps = [];
  bool _isOrientationMode = false; // Tracks if compass/orientation mode is active
  LatLng? _lastOrientationLocation; // For tracking movement in orientation mode
  double _lastHeading = 0; // Previous heading to detect changes

  // Geofencing security state variables
  bool _geofenceBypass = false;
  int _devTapCount = 0;
  DateTime? _lastDevTap;
  bool _isGuestBlocked = true; // Block guests by default until GPS confirms they are inside
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _compassSubscription;
  String? _selectedRoomName;
  LatLng? _selectedRoomCentroid;
  int? _selectedRoomFloor;
  bool _isNavigating = false; // Tracks whether map routing is currently active

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      final hasFocus = _searchFocusNode.hasFocus;
      if (mounted) {
        setState(() {
          _isSearchFocused = hasFocus;
        });
      }
      if (hasFocus) {
        _stopPlaceholderAnimation();
        _checkFirstTimeQRGuide();
      } else {
        _startPlaceholderAnimation();
      }
    });
    _startPlaceholderAnimation();
    // Connectivity Check
    _checkInitialConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _updateConnectionStatus(results);
    });

    // Compass Listener
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _heading = event.heading ?? 0;
        });
        
        // If orientation mode is active and we have a current location, rotate and move the map
        if (_isOrientationMode && _currentLocation != null) {
          _handleOrientationMapMovement();
        }
      }
    });

    // Simulate map/UI initialization
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _isInitializing = false);
        _getCurrentLocation(); // Automatically get location on startup
        
        // As a fallback for guests, immediately check geofence gate
        _checkGuestGeofence();
      }
    });
    _fetchUserName();
    _loadAllRoomsData();
    _loadRecentSearches();
    _seedFacultyCabins(); // Self-healing background faculty seeder
  }

  static bool _hasShownQRPromptThisSession = false;

  Future<void> _checkFirstTimeQRGuide() async {
    if (_hasShownQRPromptThisSession || _isQrAnchored) return;

    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user?.isAnonymous ?? false;

    if (isGuest) {
      if (_currentLocation == null) return;
      if (!_isPointInCampusPolygon(_currentLocation!)) return;
    }

    _hasShownQRPromptThisSession = true;
    if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, size: 64, color: Color(0xFF6C63FF)),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome to UniMap!',
                        style: TextStyle(
                          fontFamily: 'googlesans',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'For the most precise positioning before you navigate, please scan a nearby location QR code!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'googlesans',
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Got it!', style: TextStyle(fontFamily: 'googlesans', fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          );
        },
      );
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _recentSearches = prefs.getStringList('recent_searches') ?? [];
      });
    }
  }

  Future<void> _saveRecentSearch(String roomName) async {
    if (roomName.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final List<String> updated = List.from(_recentSearches);
    
    // Remove if already exists to move it to the top
    updated.remove(roomName);
    updated.insert(0, roomName);
    
    // Keep only last 8 searches
    if (updated.length > 8) {
      updated.removeRange(8, updated.length);
    }
    
    await prefs.setStringList('recent_searches', updated);
    if (mounted) {
      setState(() {
        _recentSearches = updated;
      });
    }
  }

  Future<void> _removeRecentSearch(String roomName) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> updated = List.from(_recentSearches);
    updated.remove(roomName);
    
    await prefs.setStringList('recent_searches', updated);
    if (mounted) {
      setState(() {
        _recentSearches = updated;
      });
    }
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    bool isOffline = results.isEmpty || results.contains(ConnectivityResult.none);
    if (mounted && _isOffline != isOffline) {
      setState(() {
        _isOffline = isOffline;
      });
    }
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

  Future<void> _loadAllRoomsData() async {
    final List<RoomSearchItem> loadedRooms = [];
    final floors = {0: 'ground', 1: 'floor_1', 2: 'floor_2', 3: 'floor_3', 4: 'floor_4'};

    for (var entry in floors.entries) {
      final int floor = entry.key;
      final String fileName = entry.value;

      try {
        final String data = await rootBundle.loadString('assets/geojson/$fileName.geojson');
        final Map<String, dynamic> geoJson = json.decode(data);

        for (final feature in geoJson['features']) {
          final geometry = feature['geometry'];
          final properties = feature['properties'];

          if (geometry == null || geometry['coordinates'] == null) continue;

          List<LatLng> points = [];
          if (geometry['type'] == 'Polygon') {
            final coords = geometry['coordinates'][0] as List;
            points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
          } else if (geometry['type'] == 'LineString') {
            final coords = geometry['coordinates'] as List;
            if (coords.length > 3) {
              points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
            }
          }

          final String rawName = (properties['name'] ?? '').toString();
          final String roomNo = (properties['roomNo'] ?? '').toString().trim();
          final String name = rawName.isNotEmpty && rawName != 'null' ? rawName : roomNo;
          final String type = (properties['type'] ?? 'other').toString().toLowerCase();

          if (points.isNotEmpty && name.isNotEmpty && name != "null") {
            double lat = 0;
            double lng = 0;
            for (var p in points) {
              lat += p.latitude;
              lng += p.longitude;
            }
            final centroid = LatLng(lat / points.length, lng / points.length);

            loadedRooms.add(RoomSearchItem(
              name: name,
              roomNo: roomNo,
              type: type,
              floor: floor,
              centroid: centroid,
            ));
          }
        }
      } catch (e) {
        debugPrint('Error loading search data for $fileName: $e');
      }
    }

    if (mounted) {
      setState(() {
        _allRooms = loadedRooms;
      });
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
    _searchFocusNode.dispose();
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    _compassSubscription?.cancel();
    _placeholderTimer?.cancel();
    _indoorPositioningSubscription?.cancel();
    _indoorPositioningService.dispose();
    super.dispose();
  }

  // ── ANIMATED SEARCH PLACEHOLDER ──────────────────────────────────────────
  void _startPlaceholderAnimation() {
    _placeholderTimer?.cancel();
    _placeholderTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      // Fade out
      setState(() => _placeholderOpacity = 0.0);
      // After fade-out completes, switch text and fade back in
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _currentPlaceholderIndex =
              (_currentPlaceholderIndex + 1) % _searchPlaceholders.length;
          _placeholderOpacity = 1.0;
        });
      });
    });
  }

  void _stopPlaceholderAnimation() {
    _placeholderTimer?.cancel();
    _placeholderTimer = null;
  }

  Future<void> _getCurrentLocation() async {
    // If QR is the current anchor, warn the user first
    if (_isQrAnchored && _currentLocation != null) {
      _showGpsSwitchDialog();
      return;
    }
    await _fetchAndApplyGpsLocation();
  }

  void _showGpsSwitchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF0D2137)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(bottom: 20),
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
              // GPS icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gps_fixed_rounded, color: Colors.blue, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                "Switch to your real-time location?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'googlesans',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: const Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Note: GPS may fluctuate indoors and lack accuracy.',
                            style: TextStyle(
                              fontFamily: 'googlesans',
                              color: Colors.amber,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.thumb_up_rounded, color: Colors.greenAccent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recommended: Continue with current location for accuracy.',
                            style: TextStyle(
                              fontFamily: 'googlesans',
                              color: Colors.greenAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  // No button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        // Keep current QR location — just re-center on it
                        if (_currentLocation != null) {
                          _mapKey.currentState?.moveToLocation(_currentLocation!, zoom: 19.0);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Center(
                          child: Text(
                            'No',
                            style: TextStyle(
                              fontFamily: 'googlesans',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Yes button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _fetchAndApplyGpsLocation();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4285F4), Color(0xFF1565C0)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4285F4).withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Yes',
                            style: TextStyle(
                              fontFamily: 'googlesans',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
  }

  Future<void> _fetchAndApplyGpsLocation() async {
    setState(() => _isFetchingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationSnackbar('⚠️ Location services are disabled. Please enable GPS.');
        setState(() => _isFetchingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationSnackbar('⚠️ Location permission denied.');
          setState(() => _isFetchingLocation = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationSnackbar('⚠️ Location permission permanently denied. Enable it in Settings.');
        setState(() => _isFetchingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );

      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _isFetchingLocation = false;
        _currentLocation = newLocation;
        _isQrAnchored = false; // Now using live GPS, not QR
      });
      _mapKey.currentState?.moveToLocation(newLocation, zoom: 19.0);
      if (_isIndoorFusionEnabled) {
        _indoorPositioningService.updateWithGps(newLocation);
      }
      _showLocationSnackbar('📍 Location updated via GPS.');
      
      // Geofence check
      _checkGuestGeofence();
    } catch (e) {
      setState(() => _isFetchingLocation = false);
      _showLocationSnackbar('⚠️ Could not get GPS location. Try again.');
    }
  }

  void _handleOrientationMapMovement() {
    // Only proceed if orientation mode is active and we have locations
    if (!_isOrientationMode || _currentLocation == null || _lastOrientationLocation == null) {
      return;
    }

    // Calculate the heading change
    double headingChange = _heading - _lastHeading;
    
    // Normalize heading change to -180 to 180 range
    if (headingChange > 180) headingChange -= 360;
    if (headingChange < -180) headingChange += 360;

    // Only rotate map if heading changed significantly (more than 2 degrees)
    if (headingChange.abs() > 2) {
      _lastHeading = _heading;
      _mapKey.currentState?.moveMapWithHeading(_currentLocation!, _heading);
    }
  }

  void _toggleIndoorFusion() {
    if (_isIndoorFusionEnabled) {
      _indoorPositioningSubscription?.cancel();
      _indoorPositioningService.stop();
      setState(() {
        _isIndoorFusionEnabled = false;
        _indoorStepCount = 0;
      });
      _showLocationSnackbar('Indoor fusion disabled.');
      return;
    }

    if (_currentLocation == null) {
      _showLocationSnackbar('Anchor your location first before activating indoor fusion.');
      return;
    }

    _indoorPositioningSubscription?.cancel();
    _indoorPositioningService.setAnchor(_currentLocation!);
    _indoorPositioningService.start(anchorLocation: _currentLocation!);
    _indoorPositioningSubscription = _indoorPositioningService.updates.listen((update) {
      if (!mounted) return;
      setState(() {
        _indoorStepCount = update.stepCount;
        _heading = update.heading;
        _currentLocation = update.estimatedLocation;
      });
      _mapKey.currentState?.moveToLocation(update.estimatedLocation, zoom: 19.0);
    });

    setState(() {
      _isIndoorFusionEnabled = true;
    });
    _showLocationSnackbar('Indoor fusion enabled. Step-based position tracking started.');
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePage()),
    );
  }

  Future<void> _openFilterScreen(BuildContext context) async {
    _searchFocusNode.unfocus();
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _applyFilter(FilterResult result) {
    setState(() {
      _activeFilter = result;
      _searchQuery = result.displayLabel;
      _searchController.text = result.displayLabel;
      
      // Directly switch floors while using filters
      if (result.floor != null) {
        _selectedFloor = result.floor!;
        _mapKey.currentState?.setFloor(result.floor!);
      } else if (result.type != null) {
        final matchingRoom = _allRooms.firstWhere(
          (r) => r.type.toLowerCase().contains(result.type!),
          orElse: () => _allRooms.firstWhere((r) => r.floor == _selectedFloor, orElse: () => _allRooms.first),
        );
        
        if (matchingRoom.floor != _selectedFloor) {
          _selectedFloor = matchingRoom.floor;
          _mapKey.currentState?.setFloor(matchingRoom.floor);
        }
      }
    });
    // Highlight matching rooms on the map
    _mapKey.currentState?.setHighlight(result.type);
    // Re-focus so keyboard comes back
    if (mounted && _isSearchFocused) _searchFocusNode.requestFocus();
  }

  void _showQrScanner(BuildContext context) {
    final MobileScannerController scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D0D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scan QR Code',
                      style: TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      children: [
                        // Torch toggle
                        IconButton(
                          icon: ValueListenableBuilder(
                            valueListenable: scannerController,
                            builder: (ctx, state, _) => Icon(
                              state.torchState == TorchState.on
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              color: state.torchState == TorchState.on
                                  ? Colors.amber
                                  : Colors.white54,
                            ),
                          ),
                          onPressed: () => scannerController.toggleTorch(),
                        ),
                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          onPressed: () {
                            scannerController.dispose();
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Scanner viewport
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: MobileScanner(
                        controller: scannerController,
                        onDetect: (capture) {
                          final barcode = capture.barcodes.first;
                          final String? rawValue = barcode.rawValue;
                          if (rawValue != null && rawValue.isNotEmpty) {
                            scannerController.dispose();
                            Navigator.pop(ctx);

                            // 3. Dynamic QR Code Anchors (Format: UNIMAP_QR:id)
                            if (rawValue.startsWith("UNIMAP_QR:")) {
                              final qrId = rawValue.replaceFirst("UNIMAP_QR:", "");
                              _showLocationSnackbar('⏳ Fetching location details...');
                              FirebaseFirestore.instance
                                  .collection('qr_codes')
                                  .doc(qrId)
                                  .get()
                                  .then((doc) {
                                if (!mounted) return;
                                if (doc.exists && doc.data() != null) {
                                  final data = doc.data()!;
                                  try {
                                    final lat = (data['lat'] as num).toDouble();
                                    final lng = (data['lng'] as num).toDouble();
                                    final int floor = (data['floor'] as num?)?.toInt() ?? _selectedFloor;
                                    
                                    final anchorLoc = LatLng(lat, lng);
                                    setState(() {
                                      _currentLocation = anchorLoc;
                                      _selectedFloor = floor;
                                      _userPhysicalFloor = floor;
                                      _isQrAnchored = true;
                                    });
                                    if (_isIndoorFusionEnabled) {
                                      _indoorPositioningService.updateWithGps(anchorLoc);
                                    }
                                    _mapKey.currentState?.setFloor(floor);
                                    _mapKey.currentState?.moveToLocation(anchorLoc, zoom: 21.0);
                                    
                                    _showLocationSnackbar('📍 Location anchored to precise spot');
                                  } catch (e) {
                                    _showLocationSnackbar('⚠️ Invalid location data format in database.');
                                  }
                                } else {
                                  _showLocationSnackbar('⚠️ QR Code not found in database.');
                                }
                              }).catchError((error) {
                                if (!mounted) return;
                                _showLocationSnackbar('⚠️ Error fetching location. Please check internet.');
                                debugPrint("Error fetching dynamic QR: $error");
                              });
                              return;
                            }

                            // 4. Static QR Code Anchors (Format: UNIMAP_LOC:lat,lng,floor)
                            if (rawValue.startsWith("UNIMAP_LOC:")) {
                              try {
                                final parts = rawValue.replaceFirst("UNIMAP_LOC:", "").split(",");
                                if (parts.length >= 2) {
                                  final lat = double.parse(parts[0]);
                                  final lng = double.parse(parts[1]);
                                  final int floor = parts.length > 2 ? int.parse(parts[2]) : _selectedFloor;
                                  
                                  final anchorLoc = LatLng(lat, lng);
                                  setState(() {
                                    _currentLocation = anchorLoc;
                                    _selectedFloor = floor;
                                    _userPhysicalFloor = floor;
                                    _isQrAnchored = true; // Location set from QR
                                  });
                                  if (_isIndoorFusionEnabled) {
                                    _indoorPositioningService.updateWithGps(anchorLoc);
                                  }
                                  _mapKey.currentState?.setFloor(floor);
                                  _mapKey.currentState?.moveToLocation(anchorLoc, zoom: 21.0);
                                  
                                  _showLocationSnackbar('📍 Location anchored to precise spot');
                                  return;
                                }
                              } catch (e) {
                                debugPrint("Error parsing QR anchor: $e");
                              }
                            }

                            // Search for the scanned value on the map
                            setState(() {
                              _searchQuery = rawValue;
                              _searchController.text = rawValue;
                            });
                            // Attempt to find a matching room
                            final results = _performSemanticSearch(rawValue);
                            if (results.isNotEmpty) {
                              final room = results.first;
                              _mapKey.currentState?.selectAndFocusRoom(
                                room.floor, room.name, room.centroid);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.qr_code_scanner, color: Colors.white, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '📍 Navigating to ${room.name}',
                                          style: const TextStyle(fontFamily: 'googlesans', fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } else {
                              // Show raw value as a snackbar if no room matched
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Scanned: $rawValue',
                                          style: const TextStyle(fontFamily: 'googlesans', fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    // Scan frame overlay
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF5B5FEF), width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Point camera at a QR code',
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => scannerController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    // Ensure system bars remain transparent on this screen
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
    ));

    final bool hasSearchText = _searchQuery.isNotEmpty || _searchController.text.isNotEmpty;

    return PopScope(
      canPop: !_isSearchFocused && _activeFilter == null && _selectedRoomName == null && !_isNavigating && !hasSearchText && !_didShowFloorMismatchWarning,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        bool didPrompt = false;
        if (_didShowFloorMismatchWarning && _userPhysicalFloor != null) {
          _didShowFloorMismatchWarning = false;
          _selectedFloor = _userPhysicalFloor!;
          _mapKey.currentState?.setFloor(_userPhysicalFloor!);
          if (_currentLocation != null) {
            _mapKey.currentState?.moveToLocation(_currentLocation!, zoom: 19.0);
          }
          didPrompt = true;
        }

        setState(() {
          if (didPrompt) {
            _isSearchFocused = false;
            if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
            _searchController.clear();
            _searchQuery = '';
            _selectedRoomName = null;
            _selectedRoomCentroid = null;
            _selectedRoomFloor = null;
            _isNavigating = false;
            _directionSteps = [];
            _mapKey.currentState?.setRoute(null);
            _mapKey.currentState?.setHighlight(null);
          } else if (_isSearchFocused) {
            // 1. Close Search Overlay
            _isSearchFocused = false;
            if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
            _searchController.clear();
            _searchQuery = '';
            _mapKey.currentState?.setHighlight(null);
          } else if (_isNavigating) {
            // 2. Exit Map Navigation (clear active route path)
            _isNavigating = false;
            _directionSteps = [];
            _mapKey.currentState?.setRoute(null);
          } else if (_selectedRoomName != null) {
            // 3. Clear Room Selection
            _selectedRoomName = null;
            _selectedRoomCentroid = null;
            _searchQuery = '';
            _searchController.clear();
            _selectedRoomFloor = null;
          } else if (_activeFilter != null) {
            // 4. Clear Active Filter
            _activeFilter = null;
            _mapKey.currentState?.setHighlight(null);
            _searchQuery = '';
            _searchController.clear();
          } else if (hasSearchText) {
            // 5. Clear Search Bar text & results
            _searchQuery = '';
            _searchController.clear();
            _mapKey.currentState?.setHighlight(null);
          }
        });

        if (didPrompt) {
          _showFacilityPromptSheet();
        }
      },

      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        endDrawer: Drawer(
          width: MediaQuery.of(context).size.width * 0.85,
          child: FilterScreen(
            onResult: (result) {
              _scaffoldKey.currentState?.closeEndDrawer();
              _applyFilter(result);
            },
          ),
        ),
        body: Stack(
          children: [
          // ── 1. INDOOR MAP ──────────────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
              },
              behavior: HitTestBehavior.translucent,
              child: IndoorMapWidget(
                key: _mapKey,
                currentFloor: 0,
                userLocation: _currentLocation,
                heading: _heading,
                isNavigating: _isNavigating,
                onRoomSelected: (name, centroid) {
                  _checkFirstTimeQRGuide();
                  // Find the room to get its floor
                  final room = _allRooms.firstWhereOrNull((r) => r.name == name);
                  setState(() {
                    _selectedRoomName = name;
                    _selectedRoomCentroid = centroid;
                    _selectedRoomFloor = room?.floor;
                    _isNavigating = false; 
                    _directionSteps = [];
                  });
                },
                onRouteCalculated: (path) {
                  final nodes = _mapKey.currentState?.globalNodes ?? [];
                  setState(() {
                    _directionSteps = DirectionsHelper.generateDirections(path, nodes);
                  });
                },
              ),
            ),
          ),

          // ── 2. TOP SEARCH BAR (map mode) ────────────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 14,
              right: 14,
              child: _buildSearchBar(context),
            ),

          // ── 1.5. FULL-SCREEN SEARCH OVERLAY ─────────────────────────────────
          if (_isSearchFocused)
            Positioned.fill(
              child: _buildSearchOverlay(context),
            ),

          // ── 3. AI ICON BUTTON (above compass) ────────────────────────────
/*
          if (!_isSearchFocused)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 200,
              right: 16,
              child: _buildAiIconButton(),
            ),
*/

          // ── 3.5. COMPASS ───────────────────────────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.60,
              right: 16,
              child: _buildCompass(),
            ),

          // ── 3.6. INDOOR FUSION BUTTON (above compass)
          if (!_isSearchFocused)
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.60 + 64,
              right: 16,
              child: _buildIndoorFusionButton(),
            ),

          // ── 4. LOCATION BUTTON (bottom right) ──────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.60 - 75,
              right: 8,
              child: _buildLocationButton(),
            ),

          // ── 4.5. FLOOR SELECTOR (layers icon) ──────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.15,
              right: 16,
              child: _buildFloorFabMenu(),
            ),


          // ── 5. OFFLINE OVERLAY ─────────────────────────────────────────────
          if (_isOffline)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        "Internet Connection Required",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'googlesans',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Please turn on internet to view the map.",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontFamily: 'googlesans',
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _checkInitialConnectivity,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B5FEF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Retry", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // ── 5.5 GUEST BLOCKED OVERLAY ──────────────────────────────────────
          if (_isGuestBlocked)
            Positioned.fill(
              child: _buildGuestBlockedOverlay(),
            ),

          // ── 6. DIRECTIONS BUTTON ───────────────────────────────────────────
          if (!_isSearchFocused && _selectedRoomName != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: _buildDirectionsPanel(),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildFloorFabMenu() {
  final floors = [
    {'label': '4th Floor', 'value': 4},
    {'label': '3rd Floor', 'value': 3},
    {'label': '2nd Floor', 'value': 2},
    {'label': '1st Floor', 'value': 1},
    {'label': 'Ground Floor', 'value': 0},
  ];

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [

      // Floating Toggle Button
      GestureDetector(
        onTap: () {
          setState(() {
            _isFloorMenuOpen = !_isFloorMenuOpen;
          });
        },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _isFloorMenuOpen
              ? const Icon(Icons.close_rounded, color: Color(0xFF1E3A5F), size: 26)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _selectedFloor == 0 ? 'G' : _selectedFloor.toString(),
                      style: const TextStyle(
                        color: Color(0xFF1E3A5F),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        fontFamily: 'googlesans',
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.layers_outlined,
                      color: Color(0xFF1E3A5F),
                      size: 14,
                    ),
                  ],
                ),
        ),
      ),

      if (_isFloorMenuOpen)
        Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 255, maxWidth: 325),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF525150), Color(0xFF525150)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: floors.map((floor) {
                  final val = floor['value'] as int;
                  final label = (floor['label'] as String).toUpperCase();
                  final isSelected = _selectedFloor == val;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedFloor = val;
                          _isFloorMenuOpen = false;
                        });
                        _mapKey.currentState?.setFloor(val);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isSelected
                                ? [const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)]
                                : [const Color(0xFFDBD9CA), const Color(0xFFDBD9CA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            // Location Pin Icon
                            Container(
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.black87,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Floor Label
                            Expanded(
                              child: Center(
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    fontFamily: 'googlesans',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
    ],
  );
}

  Widget _buildCompass() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isOrientationMode = !_isOrientationMode;
          if (_isOrientationMode) {
            // Entering orientation mode: lock map to current heading
            _lastOrientationLocation = _currentLocation;
            _lastHeading = _heading;
            _mapKey.currentState?.rotateMapToHeading(_heading);
            _showLocationSnackbar('🧭 Orientation mode active - move your phone to navigate');
          } else {
            // Exiting orientation mode: reset rotation to North
            _mapKey.currentState?.resetRotation();
            _showLocationSnackbar('🧭 Orientation mode deactivated');
          }
        });
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _isOrientationMode ? const Color(0xFFD9534F) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _isOrientationMode 
                ? const Color(0xFFD9534F).withValues(alpha: 0.4) 
                : Colors.black.withValues(alpha: 0.1),
              blurRadius: _isOrientationMode ? 12 : 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Transform.rotate(
          angle: (_heading * (3.14159 / 180) * -1),
          child: Icon(
            Icons.explore_rounded, 
            color: _isOrientationMode ? Colors.white : const Color(0xFFD9534F), 
            size: 32
          ),
        ),
      ),
    );
  }

  /*
  // ── AI ICON FLOATING BUTTON ──────────────────────────────────────────────
  Widget _buildAiIconButton() {
    return GestureDetector(
      onTap: () => _openAiAssistant(context),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/images/aiIcon.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
  */

  /*
  // ── OPEN AI ASSISTANT ──────────────────────────────────────────────────────
  Future<void> _openAiAssistant(BuildContext context) async {
    // Unfocus any active search before navigating
    _searchFocusNode.unfocus();
    if (_isSearchFocused) {
      setState(() {
        _isSearchFocused = false;
        _searchQuery = '';
        _searchController.clear();
      });
    }

    // Navigate and receive the optional deep-link room back
    final RoomSearchItem? selectedRoom = await Navigator.push<RoomSearchItem>(
      context,
      MaterialPageRoute(
        builder: (_) => AIAssistantScreen(allRooms: _allRooms),
      ),
    );

    // If the user tapped "Show on Map" in the AI chat, focus that room
    if (selectedRoom != null && mounted) {
      setState(() {
        _selectedRoomName = selectedRoom.name;
        _selectedRoomCentroid = selectedRoom.centroid;
        _selectedRoomFloor = selectedRoom.floor;
        _selectedFloor = selectedRoom.floor;
        _searchQuery = selectedRoom.name;
        _searchController.text = selectedRoom.name;
        _isNavigating = false;
        _directionSteps = [];
      });
      _mapKey.currentState?.setFloor(selectedRoom.floor);
      _mapKey.currentState?.selectAndFocusRoom(
        selectedRoom.floor,
        selectedRoom.name,
        selectedRoom.centroid,
      );
      _showLocationSnackbar('📍 Showing ${selectedRoom.name} from AI Assistant');
    }
  }
  */

  // ── SEMANTIC SEARCH ENGINE ────────────────────────────────────────────────
  
  static const Map<String, List<String>> _semanticSynonyms = {
    'washroom': ['toilet', 'bathroom', 'restroom', 'pee', 'poop', 'wash', 'loo', 'men', 'women'],
    'cafeteria': ['food', 'eat', 'hungry', 'lunch', 'breakfast', 'snack', 'cafe', 'canteen', 'coffee', 'tea'],
    'library': ['book', 'read', 'study', 'quiet', 'issue'],
    'classroom': ['class', 'study', 'lecture', 'teach', 'room'],
    'lab': ['computer', 'science', 'experiment', 'practical', 'coding', 'programming'],
    'faculty cabin': ['teacher', 'sir', 'madam', 'staff', 'professor', 'hod', 'faculty', 'cabin', 'office'],
    'lift': ['elevator'],
    'staircase': ['stairs', 'climb', 'steps'],
    'gate': ['entry', 'exit', 'out', 'in', 'security'],
  };

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        int minCost = v1[j] + 1;
        if (v0[j + 1] + 1 < minCost) minCost = v0[j + 1] + 1;
        if (v0[j] + cost < minCost) minCost = v0[j] + cost;
        v1[j + 1] = minCost;
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  List<RoomSearchItem> _performSemanticSearch(String query) {
    if (query.trim().isEmpty) return [];
    
    final queryLower = query.trim().toLowerCase();
    final queryWords = queryLower.split(RegExp(r'\s+'));
    
    List<Map<String, dynamic>> scoredRooms = [];
    
    for (var room in _allRooms) {
      double score = 0;
      final roomNameLower = room.name.toLowerCase();
      final roomTypeLower = room.type.toLowerCase();
      final roomNoLower = room.roomNo.toLowerCase();
      
      // 1. Exact Substring Match (Highest priority)
      if (roomNameLower.contains(queryLower) || roomTypeLower.contains(queryLower)) {
        score += 100;
        if (roomNameLower.startsWith(queryLower)) score += 50; // Bonus for starting with query
      }
      
      // 1b. Room Number Match
      if (roomNoLower == queryLower) {
        score += 200; // Highest priority for exact room number match
      } else if (roomNoLower.contains(queryLower)) {
        score += 120;
      }
      
      // 2. Word-by-Word Analysis (Tokenization)
      for (var word in queryWords) {
        if (word.length < 2) continue; // Skip very short words
        
        // Check against name and type words
        final roomNameWords = roomNameLower.split(RegExp(r'\s+'));
        for (var rnWord in roomNameWords) {
          if (rnWord == word) {
            score += 20;
          } else if (rnWord.contains(word)) {
            score += 10;
          } else if (_levenshtein(word, rnWord) <= 2 && rnWord.length > 4) {
             score += 5; // Typo tolerance
          }
        }
        
        if (roomTypeLower.contains(word)) score += 15;
        
        // 3. Synonym / Semantic Expansion
        _semanticSynonyms.forEach((type, synonyms) {
          if (synonyms.contains(word)) {
            // If the query word is a synonym for this type, boost rooms of this type
            if (roomTypeLower.contains(type) || roomNameLower.contains(type)) {
              score += 30; // High score for semantic match
            }
          }
        });
      }
      
      if (score > 0) {
        scoredRooms.add({'room': room, 'score': score});
      }
    }
    
    // Sort by score descending
    scoredRooms.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    
    // Return top matching rooms
    return scoredRooms.map((e) => e['room'] as RoomSearchItem).toList();
  }

  // ── SEARCH OVERLAY (full-screen) ──────────────────────────────────────────
  Widget _buildSearchOverlay(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // Apply active filter on top of semantic search
    List<RoomSearchItem> searchResults;
    if (_searchQuery.isEmpty && _activeFilter == null) {
      searchResults = [];
    } else if (_activeFilter != null) {
      // Filter-driven results (ignore text query, filter by floor+type)
      searchResults = _allRooms.where((room) {
        final floorMatch = _activeFilter!.floor == null || room.floor == _activeFilter!.floor;
        final typeMatch  = _activeFilter!.type  == null || room.type.toLowerCase().contains(_activeFilter!.type!);
        return floorMatch && typeMatch;
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } else {
      searchResults = _performSemanticSearch(_searchQuery);
    }

    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── TOP BAR (status bar + search bar) ───────────────────────────────
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              top: statusBarHeight + 8,
              left: 8,
              right: 16,
              bottom: 8,
            ),
            child: Row(
              children: [
                // Back arrow
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87, size: 22),
                  onPressed: () {
                    _searchFocusNode.unfocus();
                    setState(() {
                      _isSearchFocused = false;
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                ),
                // Search text field
                Expanded(
                  child: TextField(
                    focusNode: _searchFocusNode,
                    controller: _searchController,
                    autofocus: true,
                    showCursor: true,
                    cursorColor: Colors.blueAccent,
                    decoration: InputDecoration(
                      // hintText: 'Search location',
                      hintStyle: TextStyle(
                        fontFamily: 'googlesans',
                        color: Colors.black.withValues(alpha: 0.38),
                        fontSize: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      suffixIcon: (_searchQuery.isNotEmpty || _activeFilter != null)
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.black45, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _activeFilter = null;
                                });
                                _mapKey.currentState?.setHighlight(null);
                              },
                            )
                          : null,
                    ),
                    cursorWidth: 2,
                    cursorHeight: 20,
                    cursorRadius: const Radius.circular(2),
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        if (_activeFilter != null) {
                          _activeFilter = null;
                          // Remove highlight when user types manually
                          _mapKey.currentState?.setHighlight(null);
                        }
                      });
                    },
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                ),
                // Filter icon
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: Colors.black87, size: 22),
                      onPressed: () => _openFilterScreen(context),
                    ),
                    if (_activeFilter != null)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6C63FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFEEEEEE)),

          // ── ACTIVE FILTER CHIP ───────────────────────────────────────────────
          if (_activeFilter != null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list_rounded, size: 14, color: Color(0xFF6C63FF)),
                        const SizedBox(width: 6),
                        Text(
                          _activeFilter!.displayLabel,
                          style: const TextStyle(
                            fontFamily: 'googlesans',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6C63FF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _activeFilter = null;
                              _searchQuery = '';
                              _searchController.clear();
                            });
                            _mapKey.currentState?.setHighlight(null);
                          },
                          child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF6C63FF)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── CONTENT AREA ─────────────────────────────────────────────────────
          Expanded(
            child: (_searchQuery.isEmpty && _activeFilter == null)
                // Zero state: AI banner + suggestion chips + recent searches
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
/*
                      // ── AI ASSISTANT BUTTON (between search and suggestions) ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: GestureDetector(
                          onTap: () => _openAiAssistant(context),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/images/aiButton.png',
                                width: double.infinity,
                                fit: BoxFit.fitWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
*/
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          'SUGGESTED SEARCHES',
                          style: TextStyle(
                            fontFamily: 'googlesans',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black45,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildSuggestionChip('Washrooms'),
                            _buildSuggestionChip('Faculty Cabins'),
                            _buildSuggestionChip('Computer Labs'),
                            _buildSuggestionChip('Cafeteria'),
                          ],
                        ),
                      ),
                      
                      if (_recentSearches.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                          child: Text(
                            'RECENT SEARCHES',
                            style: TextStyle(
                              fontFamily: 'googlesans',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black45,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _recentSearches.length,
                            itemBuilder: (context, index) {
                              final query = _recentSearches[index];
                              return ListTile(
                                leading: const Icon(Icons.history_rounded, color: Colors.black38, size: 20),
                                title: Text(
                                  query,
                                  style: const TextStyle(
                                    fontFamily: 'googlesans',
                                    fontSize: 14.5,
                                    color: Colors.black87,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.black26),
                                  onPressed: () => _removeRecentSearch(query),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                dense: true,
                                onTap: () {
                                  _searchController.text = query;
                                  setState(() {
                                    _searchQuery = query;
                                    _activeFilter = null; // clear filter when typing
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  )
                // Active filter or typing state: show results
                : searchResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 48, color: Colors.black12),
                            const SizedBox(height: 12),
                            Text(
                              _activeFilter != null
                                  ? 'No locations found for "${_activeFilter!.displayLabel}"'
                                  : 'No rooms found for "$_searchQuery"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'googlesans',
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 8,
                          bottom: keyboardHeight,
                        ),
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final room = searchResults[index];
                          final floorName = room.floor == 0 ? 'Ground floor' : 'Floor ${room.floor}';
                          return _buildSearchResultItem(
                            '${room.name}, $floorName',
                            room,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String label) {
    return GestureDetector(
      onTap: () {
        // Hide search overlay and clear focus
        FocusScope.of(context).unfocus();
        setState(() {
          _isSearchFocused = false;
          _searchQuery = label;
          _searchController.text = label;
        });

        // Save to recent searches
        _saveRecentSearch(label);

        // Tell the map to highlight this type of room
        final bool hasMatches = _mapKey.currentState?.setHighlight(label) ?? true;
        if (!hasMatches) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF6C63FF)),
                  SizedBox(width: 8),
                  Text('Not Found', style: TextStyle(fontFamily: 'googlesans', fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                'There are no $label on this floor.',
                style: const TextStyle(fontFamily: 'googlesans', fontSize: 15),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK', style: TextStyle(color: Color(0xFF6C63FF), fontFamily: 'googlesans', fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'googlesans',
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultItem(String title, RoomSearchItem room) {
    final bool hasRoomNo = room.roomNo.isNotEmpty && room.roomNo != 'null' && !room.roomNo.startsWith('G');
    final String subtitle = hasRoomNo ? 'Rm ${room.roomNo} · Floor ${room.floor == 0 ? 'G' : room.floor.toString()}' : 'Floor ${room.floor == 0 ? 'G' : room.floor.toString()}';
    
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.search_rounded, color: Colors.black45, size: 20),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'googlesans',
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'googlesans',
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
        trailing: const Icon(Icons.location_on_outlined, color: Colors.black87, size: 20),
        onTap: () {
          // Hide search overlay and clear focus
          FocusScope.of(context).unfocus();
          setState(() {
            _isSearchFocused = false;
            _searchQuery = room.name; // Keep the selected room name in the bar
            _searchController.text = room.name;
            _selectedRoomName = room.name;
            _selectedRoomCentroid = room.centroid;
            _selectedRoomFloor = room.floor;
            _selectedFloor = room.floor; // Update the floor selector
            _isNavigating = false; 
          });

          // Save to recent searches
          _saveRecentSearch(room.name);

          // Tell the map to jump to this room
          _mapKey.currentState?.selectAndFocusRoom(room.floor, room.name, room.centroid);
        },
      ),
    );
  }

  Future<void> _seedFacultyCabins() async {
    // A secure, structured map of Assam Don Bosco University faculty details keyed by cabin room number
    final Map<int, Map<String, String>> facultySeedData = {
      117: {
        'name': 'Dr. Pranab Das',
        'designation': 'Associate Professor & HOD',
        'dept': 'Dept. of Computer Science & Engineering',
        'email': 'pranab.das@dbuniversity.ac.in',
      },
      118: {
        'name': 'Prof. Sonia Sharma',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Computer Science & Engineering',
        'email': 'sonia.sharma@dbuniversity.ac.in',
      },
      119: {
        'name': 'Dr. Amit Barua',
        'designation': 'Associate Professor',
        'dept': 'Dept. of Electrical & Electronics',
        'email': 'amit.barua@dbuniversity.ac.in',
      },
      120: {
        'name': 'Prof. Sonia Sen',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Electronics & Communications',
        'email': 'sonia.sen@dbuniversity.ac.in',
      },
      121: {
        'name': 'Dr. Manas Jyoti',
        'designation': 'Professor',
        'dept': 'Dept. of Civil Engineering',
        'email': 'manas.jyoti@dbuniversity.ac.in',
      },
      122: {
        'name': 'Prof. Rishabh Dev',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Information Technology',
        'email': 'rishabh.dev@dbuniversity.ac.in',
      },
      217: {
        'name': 'Dr. Bobby Sharma',
        'designation': 'Associate Professor',
        'dept': 'Dept. of Computer Science & Engineering',
        'email': 'bobby.sharma@dbuniversity.ac.in',
      },
      218: {
        'name': 'Prof. Gyani Sharma',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Computer Applications',
        'email': 'gyani.sharma@dbuniversity.ac.in',
      },
      219: {
        'name': 'Prof. Vijay Prasad',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Computer Applications',
        'email': 'vijay.prasad@dbuniversity.ac.in',
      },
      220: {
        'name': 'Dr. Smriti Priya',
        'designation': 'Professor',
        'dept': 'Dept. of Civil Engineering',
        'email': 'smriti.priya@dbuniversity.ac.in',
      },
      221: {
        'name': 'Prof. Hemant Kalita',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Civil Engineering',
        'email': 'hemant.kalita@dbuniversity.ac.in',
      },
      317: {
        'name': 'Dr. Bikramjit Goswami',
        'designation': 'Associate Professor',
        'dept': 'Dept. of Electrical & Electronics',
        'email': 'bikramjit.goswami@dbuniversity.ac.in',
      },
      318: {
        'name': 'Prof. P. Joseph',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Electrical & Electronics',
        'email': 'joseph.p@dbuniversity.ac.in',
      },
      319: {
        'name': 'Dr. Sunandan Baruah',
        'designation': 'Professor & Dean',
        'dept': 'Dept. of Engineering & Technology',
        'email': 'sunandan.baruah@dbuniversity.ac.in',
      },
      320: {
        'name': 'Prof. Nupur Choudhury',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Electronics & Communications',
        'email': 'nupur.choudhury@dbuniversity.ac.in',
      },
      321: {
        'name': 'Dr. Shakuntala Laskar',
        'designation': 'Professor',
        'dept': 'Dept. of Electronics & Communications',
        'email': 'shakuntala.laskar@dbuniversity.ac.in',
      },
      322: {
        'name': 'Prof. Gitanjali Devi',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Humanities & Social Sciences',
        'email': 'gitanjali.devi@dbuniversity.ac.in',
      },
      324: {
        'name': 'Dr. Monmayuri Goswami',
        'designation': 'Associate Professor',
        'dept': 'Dept. of Basic Sciences',
        'email': 'monmayuri.goswami@dbuniversity.ac.in',
      },
      325: {
        'name': 'Prof. Subra Mukherjee',
        'designation': 'Assistant Professor',
        'dept': 'Dept. of Basic Sciences',
        'email': 'subra.mukherjee@dbuniversity.ac.in',
      },
    };

    try {
      // Query all rooms of type 'cabin' from the live Firestore locations collection
      final snapshot = await FirebaseFirestore.instance
          .collection('locations')
          .where('r_type', isEqualTo: 'cabin')
          .get();

      if (snapshot.docs.isEmpty) return;

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final int roomNo = data['r_no'] ?? 0;
        final String currentDescription = data['Description'] ?? '';

        // Only seed if the room matches a room number in our seed data
        if (facultySeedData.containsKey(roomNo)) {
          final fInfo = facultySeedData[roomNo]!;
          final String seedDescription = '${fInfo['name']}|${fInfo['designation']}|${fInfo['dept']}|${fInfo['email']}';

          // Self-Healing Protection: Only update if the current description is generic/fallback
          if (currentDescription.contains('Room FACULTY CABIN') || 
              currentDescription.contains('Room RESEARCH SCHOLAR') || 
              currentDescription.isEmpty) {
            
            batch.update(doc.reference, {
              'Description': seedDescription,
            });
            hasUpdates = true;
          }
        }
      }

      if (hasUpdates) {
        await batch.commit();
        debugPrint("🔍 [Faculty Seeder] Successfully seeded live Firestore cabin profiles!");
      } else {
        debugPrint("🔍 [Faculty Seeder] Live database is already seeded. Skipping updates.");
      }
    } catch (e) {
      debugPrint("🔍 [Faculty Seeder] Error seeding faculty cabins: $e");
    }
  }

  bool _isPointInCampusPolygon(LatLng point) {
    final List<LatLng> polygon = [
      const LatLng(26.129478442237748, 91.62074621851825),
      const LatLng(26.129214548306525, 91.62052824180157),
      const LatLng(26.12926349954137, 91.62006646474872),
      const LatLng(26.129362087991154, 91.61947453082043),
      const LatLng(26.129450433017126, 91.61910061352303),
      const LatLng(26.129539755861114, 91.61865594713322),
      const LatLng(26.129575514877217, 91.6186001697514),
      const LatLng(26.129811402579325, 91.61890885764142),
      const LatLng(26.129965670025573, 91.61907486973203),
      const LatLng(26.13005382162376, 91.61916070973427),
      const LatLng(26.130088212701303, 91.61929506221927),
      const LatLng(26.130082433522404, 91.61943533450788),
      const LatLng(26.130146676607925, 91.6194908899106),
      const LatLng(26.13018425785511, 91.61958583380742),
      const LatLng(26.130166612698567, 91.61969901904217),
      const LatLng(26.13012902818572, 91.61979800100573),
      const LatLng(26.130093784697685, 91.61988645572802),
      const LatLng(26.130007464022707, 91.62004778943809),
      const LatLng(26.129958587669208, 91.6201678939534),
      const LatLng(26.129876659118068, 91.62038983569859),
      const LatLng(26.129819775062682, 91.62055033451924),
      const LatLng(26.12974950809844, 91.6207540379922),
      const LatLng(26.129678723831073, 91.62087509200539),
    ];

    bool isInside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].longitude > point.longitude) != (polygon[j].longitude > point.longitude) &&
          point.latitude <
              (polygon[j].latitude - polygon[i].latitude) *
                      (point.longitude - polygon[i].longitude) /
                      (polygon[j].longitude - polygon[i].longitude) +
                  polygon[i].latitude) {
        isInside = !isInside;
      }
      j = i;
    }
    return isInside;
  }

  bool _checkGeofence() {
    if (_geofenceBypass) return true;
    if (_currentLocation == null) return false;
    return _isPointInCampusPolygon(_currentLocation!);
  }

  void _checkGuestGeofence() {
    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user?.isAnonymous ?? false;
    
    // Non-guests are never blocked
    if (!isGuest) {
      if (mounted) {
        setState(() => _isGuestBlocked = false);
      }
      return;
    }

    // Guests must pass the geofence check
    final bool allowed = _checkGeofence();
    if (mounted) {
      setState(() => _isGuestBlocked = !allowed);
    }
  }

  void _showAllStepsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Route Directions',
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: _directionSteps.isEmpty
                    ? const Center(child: Text("Calculating route directions..."))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: _directionSteps.length,
                        itemBuilder: (context, index) {
                          final step = _directionSteps[index];
                          final isLast = index == _directionSteps.length - 1;
                          final isFirst = index == 0;
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isFirst 
                                            ? const Color(0xFF6C63FF).withValues(alpha: 0.1) 
                                            : isLast 
                                                ? Colors.green.withValues(alpha: 0.1)
                                                : Colors.grey[100],
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        step.icon, 
                                        color: isFirst 
                                            ? const Color(0xFF6C63FF) 
                                            : isLast 
                                                ? Colors.green 
                                                : Colors.black54, 
                                        size: 18
                                      ),
                                    ),
                                    if (!isLast)
                                      Expanded(
                                        child: VerticalDivider(
                                          color: Colors.grey[300],
                                          thickness: 2,
                                          width: 32,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          step.instruction,
                                          style: TextStyle(
                                            fontFamily: 'googlesans',
                                            fontSize: 15,
                                            fontWeight: (isFirst || isLast) ? FontWeight.bold : FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        if (step.distance > 0) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'For ${step.distance.round()} m',
                                            style: const TextStyle(
                                              fontFamily: 'googlesans',
                                              fontSize: 12,
                                              color: Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startNavigation({required bool enableCompass}) {
    if (_selectedRoomCentroid == null) return;

    if (_userPhysicalFloor != null && _selectedRoomFloor != _userPhysicalFloor) {
      _didShowFloorMismatchWarning = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please move to Floor $_selectedRoomFloor and scan a nearby QR code to get directions.',
                  style: const TextStyle(fontFamily: 'googlesans', fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isNavigating = true;
      if (enableCompass) {
        _isOrientationMode = true;
        if (_currentLocation != null) {
          _lastOrientationLocation = _currentLocation;
        }
      }
    });
    
    _mapKey.currentState?.showDirectionsTo(
      _selectedRoomCentroid!,
      destinationFloor: _selectedRoomFloor,
    );
  }

  Widget _buildDirectionsPanel() {
    return _isNavigating ? _buildNavigationBar() : _buildRoomDetailSheet();
  }

  // ── GUEST BLOCKED OVERLAY ─────────────────────────────────────────────────
  Widget _buildGuestBlockedOverlay() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          color: Colors.white.withValues(alpha: 0.75),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  final now = DateTime.now();
                  if (_lastDevTap == null || now.difference(_lastDevTap!) < const Duration(seconds: 2)) {
                    _devTapCount++;
                  } else {
                    _devTapCount = 1;
                  }
                  _lastDevTap = now;
                  
                  if (_devTapCount >= 5) {
                    setState(() {
                      _geofenceBypass = true;
                      _isGuestBlocked = false;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Developer Mode Activated: Geofence Bypassed!'),
                        backgroundColor: Color(0xFF6C63FF),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_bad_rounded,
                    color: Colors.redAccent,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Campus Access Only',
                style: TextStyle(
                  fontFamily: 'googlesans',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'As a guest, map navigation is restricted. You must be physically inside the Assam Don Bosco University campus boundary to view the map.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'googlesans',
                  fontSize: 16,
                  height: 1.4,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _fetchAndApplyGpsLocation,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  label: const Text(
                    'Refresh Location',
                    style: TextStyle(
                      fontFamily: 'googlesans',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  FirebaseAuth.instance.signOut();
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.black54, size: 20),
                label: const Text(
                  'Exit Guest Session',
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── COMPACT NAV BAR (shown while route is active) ─────────────────────────
  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B5BDB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedRoomName ?? '',
                      style: const TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _selectedRoomFloor != null
                          ? 'Floor ${_selectedRoomFloor == 0 ? "Ground" : _selectedRoomFloor}'
                          : 'Assam Don Bosco University',
                      style: const TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showAllStepsBottomSheet,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3B5BDB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_rounded, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  _startNavigation(enableCompass: true);
                },
                icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 17),
                label: const Text(
                  'Start',
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B5BDB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isNavigating = false;
                  _directionSteps = [];
                });
                _mapKey.currentState?.setRoute(null);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                elevation: 0,
              ),
              child: const Text(
                'Exit Navigation',
                style: TextStyle(
                  fontFamily: 'googlesans',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FULL ROOM DETAIL SHEET ─────────────────────────────────────────────────
  Widget _buildRoomDetailSheet() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('locations')
            .where('L_name', isEqualTo: _selectedRoomName)
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          String description = '';
          String rType = '';
          int rNo = 0;
          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
            description = data['Description'] ?? '';
            rType = data['r_type'] ?? '';
            rNo = data['r_no'] ?? 0;
          }
          final isCabin = rType.toLowerCase() == 'cabin';
          final parts = description.split('|');
          final isFacultyProfile = isCabin && parts.length >= 4;

          final floorName = _selectedRoomFloor == null
              ? 'Unknown'
              : _selectedRoomFloor == 0
                  ? 'Ground'
                  : _selectedRoomFloor == 1
                      ? '1st Floor'
                      : _selectedRoomFloor == 2
                          ? '2nd Floor'
                          : _selectedRoomFloor == 3
                              ? '3rd Floor'
                              : 'Floor $_selectedRoomFloor';

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              // Title Section
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
                child: Row(
                  children: [
                    // Location Pin Icon (no blue circle container, as in mockup)
                    const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF2563EB),
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    
                    // Location Name Text (vibrant blue color, bold)
                    Expanded(
                      child: Text(
                        _selectedRoomName ?? '',
                        style: const TextStyle(
                          fontFamily: 'googlesans',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Styled X Close Button
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRoomName = null;
                          _selectedRoomCentroid = null;
                          _selectedRoomFloor = null;
                          _isNavigating = false;
                          _directionSteps = [];
                        });
                        _mapKey.currentState?.setRoute(null);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFCA5A5),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFFEF4444),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Room Details & Go Now Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Room Details Column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room no. ${rNo > 0 ? rNo : "-"}',
                          style: const TextStyle(
                            fontFamily: 'googlesans',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Floor : $floorName',
                          style: const TextStyle(
                            fontFamily: 'googlesans',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),

                    // "Go Now" Gradient Button
                    GestureDetector(
                      onTap: () {
                        _startNavigation(enableCompass: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Navigation arrow rotated to point northeast (top-right)
                            Transform.rotate(
                              angle: 0.785398, // 45 degrees in radians to point northeast
                              child: const Icon(
                                Icons.navigation_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Go Now',
                              style: TextStyle(
                                fontFamily: 'googlesans',
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              
              // Divider
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: Colors.black12),
              ),

              const SizedBox(height: 16),

              // Image Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB), // Sleek grey matching mockup
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: isFacultyProfile
                        ? _buildFacultyImageCard(parts)
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_outlined, color: Colors.grey[400], size: 36),
                                const SizedBox(height: 6),
                                Text(
                                  'IMAGE',
                                  style: TextStyle(
                                    fontFamily: 'googlesans',
                                    color: Colors.grey[500],
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedRoomName ?? '',
                                  style: TextStyle(
                                    fontFamily: 'googlesans',
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Description Section
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6), // Matches description block background
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Description',
                        style: TextStyle(
                          fontFamily: 'googlesans',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[500],
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (description.isNotEmpty && !isFacultyProfile)
                            ? description
                            : isFacultyProfile && parts.length > 2
                                ? '${parts[1]}, ${parts[2]}'
                                : 'No description available.',
                        style: TextStyle(
                          fontFamily: 'googlesans',
                          fontSize: 13.5,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFacultyImageCard(List<String> parts) {
    final fName = parts[0];
    final fDesignation = parts.length > 1 ? parts[1] : '';
    final fDept = parts.length > 2 ? parts[2] : '';
    final fEmail = parts.length > 3 ? parts[3] : '';
    String initials = '';
    final cleanName = fName.replaceAll('Dr. ', '').replaceAll('Prof. ', '').trim();
    final nameParts = cleanName.split(' ');
    if (nameParts.isNotEmpty) {
      initials += nameParts[0][0];
      if (nameParts.length > 1) initials += nameParts[1][0];
    }
    initials = initials.toUpperCase();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            child: Text(initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'googlesans')),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(fName,
                    style: const TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                if (fDesignation.isNotEmpty)
                  Text(fDesignation,
                      style: const TextStyle(
                          fontFamily: 'googlesans', fontSize: 12, color: Colors.white70)),
                if (fDept.isNotEmpty)
                  Text(fDept,
                      style: const TextStyle(
                          fontFamily: 'googlesans', fontSize: 11, color: Colors.white60),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (fEmail.isNotEmpty)
            GestureDetector(
              onTap: () async {
                final uri = Uri(
                    scheme: 'mailto',
                    path: fEmail,
                    queryParameters: {'subject': 'Inquiry from UniMap'});
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Icon(Icons.mail_rounded, color: Colors.white, size: 19),
              ),
            ),
        ],
      ),
    );
  }

  // ── SEARCH BAR (map mode – tappable pill) ───────────────────────────────────
  // Widget _buildSearchBar(BuildContext context) {
  //   if (_isInitializing) {
  //     return const Skeleton(height: 52, borderRadius: 30);
  //   }
  //   return GestureDetector(
  //     onTap: () {
  //       setState(() => _isSearchFocused = true);
  //       // autofocus in overlay handles keyboard
  //     },
  //     child: Container(
  //       height: 52,
  //       decoration: BoxDecoration(
  //         color: Colors.white,
  //         borderRadius: BorderRadius.circular(30),
  //         boxShadow: [
  //           BoxShadow(
  //             color: Colors.black.withValues(alpha: 0.10),
  //             blurRadius: 12,
  //             offset: const Offset(0, 4),
  //           ),
  //         ],
  //       ),
  //       child: Row(
  //         children: [
  //           const SizedBox(width: 16),
  //           const Icon(Icons.search_rounded, color: Colors.black54, size: 22),
  //           const SizedBox(width: 10),
  //           Expanded(
  //             child: Text(
  //               _searchQuery.isEmpty ? 'Search location' : _searchQuery,
  //               style: TextStyle(
  //                 fontFamily: 'googlesans',
  //                 fontSize: 20,
  //                 color: _searchQuery.isEmpty
  //                     ? Colors.black.withValues(alpha: 0.40)
  //                     : Colors.black87,
  //               ),
  //               overflow: TextOverflow.ellipsis,
  //             ),
  //           ),
  //           const SizedBox(width: 8),
  //           // QR Scanner button
  //           GestureDetector(
  //             onTap: () => _showQrScanner(context),
  //             child: Container(
  //               width: 36,
  //               height: 36,
  //               margin: const EdgeInsets.only(right: 4),
  //               decoration: BoxDecoration(
  //                 color: const Color(0xFF5B5FEF).withValues(alpha: 0.10),
  //                 shape: BoxShape.circle,
  //               ),
  //               child: const Icon(
  //                 Icons.qr_code_scanner_rounded,
  //                 color: Color(0xFF5B5FEF),
  //                 size: 20,
  //               ),
  //             ),
  //           ),
  //           const SizedBox(width: 4),
  //           // Profile avatar
  //           GestureDetector(
  //             onTap: () => _showProfileMenu(context),
  //             child: Container(
  //               width: 36,
  //               height: 36,
  //               margin: const EdgeInsets.only(right: 8),
  //               decoration: BoxDecoration(
  //                 color: Colors.black.withValues(alpha: 0.7),
  //                 shape: BoxShape.circle,
  //               ),
  //               child: Center(
  //                 child: Text(
  //                   _getUserInitial(),
  //                   style: const TextStyle(
  //                     color: Colors.white,
  //                     fontWeight: FontWeight.bold,
  //                     fontSize: 16,
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

Widget _buildSearchBar(BuildContext context) {
  final bool focused = _isSearchFocused;

  return GestureDetector(
    onTap: () {
      setState(() {
        _isSearchFocused = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        borderRadius: BorderRadius.circular(28),
      ),
      child: AnimatedRotatingBorder(
        borderRadius: 28,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              height: focused ? 56 : 52,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  width: 2,
                  // Neon gradient border
                  color: Colors.transparent,
                ),
              // gradient: const LinearGradient(
              //   colors: [Color(0xFFFF00FF), Color(0xFF00BFFF)], // pink → blue
              //   begin: Alignment.centerLeft,
              //   end: Alignment.centerRight,
              // ),
              boxShadow: [
                BoxShadow(
                  color: Colors.pinkAccent.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(-2, 0),
                ),
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Row(
              children: [
                // Search icon
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    // border: Border.all(color: Colors.black.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.search, color: Colors.black, size: 22),
                ),
                const SizedBox(width: 2),

                // Search label and query preview
                Expanded(
                  child: _searchQuery.isEmpty
                      ? AnimatedOpacity(
                          opacity: _placeholderOpacity,
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            _searchPlaceholders[_currentPlaceholderIndex],
                            style: TextStyle(
                              fontFamily: 'googlesans',
                              fontSize: 16,
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text(
                          _searchQuery,
                          style: const TextStyle(
                            fontFamily: 'googlesans',
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),

                // Clear button or QR/Profile actions
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black, size: 20),
                    onPressed: () {
                      bool didPrompt = false;
                      if (_didShowFloorMismatchWarning && _userPhysicalFloor != null) {
                        _didShowFloorMismatchWarning = false;
                        _selectedFloor = _userPhysicalFloor!;
                        _mapKey.currentState?.setFloor(_userPhysicalFloor!);
                        if (_currentLocation != null) {
                          _mapKey.currentState?.moveToLocation(_currentLocation!, zoom: 19.0);
                        }
                        didPrompt = true;
                      }

                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                        _selectedRoomName = null;
                        _selectedRoomCentroid = null;
                        _selectedRoomFloor = null;
                        _isNavigating = false;
                        _directionSteps = [];
                        _mapKey.currentState?.setRoute(null);
                        _mapKey.currentState?.setHighlight(null);
                      });

                      if (didPrompt) {
                        _showFacilityPromptSheet();
                      }
                    },
                  )
                else
                  Row(
                    children: [
                      // QR Scanner button
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: Colors.black, size: 25),
                        onPressed: () => _showQrScanner(context),
                      ),

                      // Profile icon button
                      Padding(
                        padding: const EdgeInsets.only(right: 0),
                        child: GestureDetector(
                          onTap: () => _showProfileMenu(context),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.blue.withValues(alpha: 0.2),
                            child: Text(
                              _getUserInitial(),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  // ── LOCATION BUTTON ───────────────────────────────────────────────────────
  Widget _buildLocationButton() {
    if (_isInitializing) {
      return const Skeleton(
        width: 60,
        height: 60,
        shape: BoxShape.circle,
      );
    }
    return GestureDetector(
      onTap: _isFetchingLocation ? null : _getCurrentLocation,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Glowing gradient ring (blur simulates halo from reference image) ──
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFF4FC3F7), // light blue
                    Color(0xFF9C27B0), // violet/purple
                    Color(0xFF00E5FF), // cyan / teal
                    Color(0xFF4FC3F7), // back to blue — seamless loop
                  ],
                ),
              ),
            ),
          ),
          // ── Dark inner button ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: _isFetchingLocation
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(
                      Icons.my_location_rounded,
                      color: Colors.blue,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndoorFusionButton() {
    return GestureDetector(
      onTap: _toggleIndoorFusion,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _isIndoorFusionEnabled ? const Color(0xFF1E8E3E) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: _isIndoorFusionEnabled ? const Color(0xFF0F6A26) : Colors.black12,
            width: 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              _isIndoorFusionEnabled ? Icons.track_changes_rounded : Icons.explore_rounded,
              color: _isIndoorFusionEnabled ? Colors.white : Colors.blue,
              size: 24,
            ),
            if (_isIndoorFusionEnabled && _indoorStepCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$_indoorStepCount',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFacilityPromptSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFB703), Color(0xFFFB8500)], // Vibrant yellow to orange
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Small top handle or close button
              Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(bottom: 24),
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
              const Text(
                "Looking for the nearest elevator or stairs?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'googlesans',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              // Option 1: Yes
              _buildOptionCard(
                title: "Yes",
                subtitle: "Find the quickest route between floors",
                icon: Icons.directions_run_rounded,
                iconColor: Colors.redAccent,
                iconBgColor: Colors.red.withValues(alpha: 0.15),
                onTap: () {
                  Navigator.pop(context);
                  _showFacilitySelectionSheet();
                },
              ),
              const SizedBox(height: 16),
              // Option 2: No
              _buildOptionCard(
                title: "No, choose manually",
                subtitle: "Dismiss and explore the map",
                icon: Icons.map_rounded,
                iconColor: Colors.blueAccent,
                iconBgColor: Colors.blue.withValues(alpha: 0.15),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFacilitySelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFB703), Color(0xFFFB8500)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(bottom: 24),
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
              const Text(
                "Choose:",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'googlesans',
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              // Lift
              _buildOptionCard(
                title: "Lift",
                subtitle: "Navigate to the nearest elevator",
                icon: Icons.elevator_rounded,
                iconColor: Colors.green,
                iconBgColor: Colors.green.withValues(alpha: 0.15),
                onTap: () {
                  Navigator.pop(context);
                  _routeToNearestFacility('lift');
                },
              ),
              const SizedBox(height: 16),
              // Staircase
              _buildOptionCard(
                title: "Staircase",
                subtitle: "Navigate to the nearest stairs",
                icon: Icons.stairs_rounded,
                iconColor: Colors.orange,
                iconBgColor: Colors.orange.withValues(alpha: 0.15),
                onTap: () {
                  Navigator.pop(context);
                  _routeToNearestFacility('staircase');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  void _routeToNearestFacility(String type) {
    if (_userPhysicalFloor == null || _currentLocation == null) return;

    RoomSearchItem? nearestFacility;
    double minDistance = double.infinity;
    const distanceCalculator = Distance();

    for (var room in _allRooms) {
      if (room.floor == _userPhysicalFloor && room.type.toLowerCase() == type) {
        double dist = distanceCalculator.as(LengthUnit.Meter, _currentLocation!, room.centroid);
        if (dist < minDistance) {
          minDistance = dist;
          nearestFacility = room;
        }
      }
    }

    if (nearestFacility != null) {
      setState(() {
        _searchQuery = nearestFacility!.name;
        _searchController.text = nearestFacility.name;
        _selectedRoomName = nearestFacility.name;
        _selectedRoomCentroid = nearestFacility.centroid;
        _selectedRoomFloor = nearestFacility.floor;
        _isNavigating = true;
        _isOrientationMode = true;
        _lastOrientationLocation = _currentLocation;
      });
      _mapKey.currentState?.selectAndFocusRoom(nearestFacility.floor, nearestFacility.name, nearestFacility.centroid);
      _mapKey.currentState?.showDirectionsTo(
        nearestFacility.centroid,
        destinationFloor: nearestFacility.floor,
      );
    }
  }
}

// ── PROFILE BOTTOM SHEET ──────────────────────────────────────────────────
class _ProfileBottomSheet extends StatefulWidget {
  final VoidCallback onSubScreenClosed;
  const _ProfileBottomSheet({required this.onSubScreenClosed});

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
    
    // Req 6: Show User ID instead of email
    String displayId = "Timed Session (30s)";
    if (!isGuest && user?.email != null) {
      displayId = user!.email!.split('@')[0].toUpperCase();
    }

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
                              displayId,
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
              _menuItem(Icons.lock_reset_rounded, 'Change Password', context),
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
          
          Widget targetScreen;
          if (label == 'Change Password') {
            targetScreen = const PasswordChangeScreen();
          } else if (label == 'Terms & Conditions') {
            targetScreen = const TermsAndConditionsScreen();
          } else if (label == 'Feedback') {
            targetScreen = const FeedbackBottomSheet();
          } else {
            return;
          }

          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
          
          // Req 3: Re-open profile menu when sub-screen is closed
          widget.onSubScreenClosed();
        }
      },
      horizontalTitleGap: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}

class RoomSearchItem {
  final String name;
  final String roomNo;
  final String type;
  final int floor;
  final LatLng centroid;

  RoomSearchItem({
    required this.name,
    this.roomNo = '',
    required this.type,
    required this.floor,
    required this.centroid,
  });
}

class AnimatedRotatingBorder extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  const AnimatedRotatingBorder({super.key, required this.child, this.borderRadius = 28});

  @override
  State<AnimatedRotatingBorder> createState() => _AnimatedRotatingBorderState();
}

class _AnimatedRotatingBorderState extends State<AnimatedRotatingBorder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(2.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: SweepGradient(
              colors: const [Colors.green, Colors.red, Colors.blue, Colors.green],
              stops: const [0.0, 0.33, 0.66, 1.0],
              transform: GradientRotation(_controller.value * 2 * 3.1415926535),
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
