import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
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
  bool _isFloorMenuOpen = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<IndoorMapWidgetState> _mapKey = GlobalKey<IndoorMapWidgetState>();

  // Compass and Connectivity
  double _heading = 0;
  bool _isOffline = false;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _compassSubscription;
  StreamSubscription<Position>? _positionSubscription;
  bool _isTrackingLocation = false;
  String? _selectedRoomName;
  LatLng? _selectedRoomCentroid;

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
      
      // If we lost focus, make sure the keyboard is hidden
      if (!hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    });
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
      }
    });

    // Simulate map/UI initialization
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _isInitializing = false);
        _getCurrentLocation(); // Automatically get location on startup
      }
    });
    _fetchUserName();
    _loadAllRoomsData();
    _loadRecentSearches();
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

          final String name = (properties['name'] ?? properties['roomNo'] ?? '').toString();
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
    _positionSubscription?.cancel();
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
      // 1. Accuracy Filtering: Get position with highest accuracy
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      );
      
      // 5. Filter out stale or low-accuracy data (> 35m error)
      if (position.accuracy > 35) {
        debugPrint("Initial location accuracy low: ${position.accuracy}m");
      }

      final LatLng newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _isFetchingLocation = false;
        _currentLocation = newLocation;
      });
      
      // Move map to the user's location
      _mapKey.currentState?.moveToLocation(newLocation, zoom: 19.0);

      if (!_isTrackingLocation) {
        _isTrackingLocation = true;
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0, // 4. Fused / Continuous updates for maximum smoothness
          ),
        ).listen((Position position) {
          if (mounted) {
            // 5. Accuracy Filtering: Ignore points with very high error margins
            if (position.accuracy > 35) return;

            setState(() {
              // 2. Exponential Moving Average Smoothing
              // weight: 0.3 (new), 0.7 (old) to reduce marker "jumping"
              if (_currentLocation == null) {
                _currentLocation = LatLng(position.latitude, position.longitude);
              } else {
                const double weight = 0.3;
                double lat = (position.latitude * weight) + (_currentLocation!.latitude * (1.0 - weight));
                double lng = (position.longitude * weight) + (_currentLocation!.longitude * (1.0 - weight));
                _currentLocation = LatLng(lat, lng);
              }
            });
          }
        });
      }

      _showLocationSnackbar('📍 Tracking live location...');
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

                            // 3. QR Code Anchors (Format: UNIMAP_LOC:lat,lng,floor)
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
                                  });
                                  
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

    return PopScope(
      canPop: !_isSearchFocused && _activeFilter == null && _selectedRoomName == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        setState(() {
          if (_isSearchFocused) {
            // 1. Close Search Overlay
            _isSearchFocused = false;
            _searchFocusNode.unfocus();
            _searchController.clear();
            _searchQuery = '';
            _mapKey.currentState?.setHighlight(null);
          } else if (_activeFilter != null) {
            // 2. Clear Active Filter
            _activeFilter = null;
            _mapKey.currentState?.setHighlight(null);
            _searchQuery = '';
            _searchController.clear();
          } else if (_selectedRoomName != null) {
            // 3. Clear Room Selection
            _selectedRoomName = null;
            _selectedRoomCentroid = null;
            _searchQuery = '';
            _searchController.clear();
          }
        });
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
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
                onRoomSelected: (name, centroid) {
                  setState(() {
                    _selectedRoomName = name;
                    _selectedRoomCentroid = centroid;
                  });
                },
              ),
            ),
          ),

          // ── 2. TOP SEARCH BAR (map mode) ────────────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: _buildSearchBar(context),
            ),

          // ── 1.5. FULL-SCREEN SEARCH OVERLAY ─────────────────────────────────
          if (_isSearchFocused)
            Positioned.fill(
              child: _buildSearchOverlay(context),
            ),

          // ── 3. COMPASS ─────────────────────────────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 140, // Moved higher
              right: 16,
              child: _buildCompass(),
            ),

          // ── 4. LOCATION BUTTON (bottom right) ──────────────────────────────
          if (!_isSearchFocused)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 64, // Moved higher
              right: 16,
              child: _buildLocationButton(),
            ),

          // ── 5. OFFLINE OVERLAY ─────────────────────────────────────────────
          if (_isOffline)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
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
          
          // ── 6. DIRECTIONS BUTTON ───────────────────────────────────────────
          if (!_isSearchFocused && _selectedRoomName != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: _buildDirectionsPanel(),
            ),

          // ── 7. FLOOR SELECTOR (Top Right - FAB Menu) ──────────────────────
          if (!_isSearchFocused)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              right: 16,
              child: _buildFloorFabMenu(),
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
        if (_isFloorMenuOpen)
          ...floors.map((floor) {
            bool isSelected = _selectedFloor == floor['value'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFloor = floor['value'] as int;
                    _isFloorMenuOpen = false;
                  });
                  _mapKey.currentState?.setFloor(floor['value'] as int);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF5B5FEF) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    floor['label'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF1E3A5F),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'googlesans',
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
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
                  color: Colors.black.withOpacity(0.2),
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
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.layers_outlined,
                        color: Color(0xFF1E3A5F),
                        size: 14,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompass() {
    return GestureDetector(
      onTap: () {
        // Reset map rotation to North
        _mapKey.currentState?.resetRotation();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Transform.rotate(
          angle: (_heading * (3.14159 / 180) * -1),
          child: const Icon(Icons.explore_rounded, color: Color(0xFFD9534F), size: 32),
        ),
      ),
    );
  }

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
      
      // 1. Exact Substring Match (Highest priority)
      if (roomNameLower.contains(queryLower) || roomTypeLower.contains(queryLower)) {
        score += 100;
        if (roomNameLower.startsWith(queryLower)) score += 50; // Bonus for starting with query
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
                    decoration: InputDecoration(
                      hintText: 'Search location',
                      hintStyle: TextStyle(
                        fontFamily: 'googlesans',
                        color: Colors.black.withOpacity(0.38),
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
                // Zero state: suggestion chips + recent searches
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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
        _searchController.text = label;
        setState(() {
          _searchQuery = label;
        });
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
            _selectedFloor = room.floor; // Update the floor selector
          });

          // Save to recent searches
          _saveRecentSearch(room.name);

          // Tell the map to jump to this room
          _mapKey.currentState?.selectAndFocusRoom(room.floor, room.name, room.centroid);
        },
      ),
    );
  }

  Widget _buildDirectionsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded, color: Color(0xFF6C63FF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedRoomName ?? '',
                      style: const TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Text(
                      'Assam Don Bosco University',
                      style: TextStyle(
                        fontFamily: 'googlesans',
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.black38),
                onPressed: () {
                  setState(() {
                    _selectedRoomName = null;
                    _selectedRoomCentroid = null;
                  });
                  _mapKey.currentState?.setRoute(null);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_selectedRoomCentroid != null) {
                  _mapKey.currentState?.showDirectionsTo(_selectedRoomCentroid!);
                }
              },
              icon: const Icon(Icons.directions_rounded, color: Colors.white),
              label: const Text(
                'Directions',
                style: TextStyle(
                  fontFamily: 'googlesans',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SEARCH BAR (map mode – tappable pill) ───────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    if (_isInitializing) {
      return const Skeleton(height: 52, borderRadius: 30);
    }
    return GestureDetector(
      onTap: () {
        setState(() => _isSearchFocused = true);
        // autofocus in overlay handles keyboard
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search_rounded, color: Colors.black54, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _searchQuery.isEmpty ? 'Search location' : _searchQuery,
                style: TextStyle(
                  fontFamily: 'googlesans',
                  fontSize: 20,
                  color: _searchQuery.isEmpty
                      ? Colors.black.withValues(alpha: 0.40)
                      : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // QR Scanner button
            GestureDetector(
              onTap: () => _showQrScanner(context),
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B5FEF).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFF5B5FEF),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Profile avatar
            GestureDetector(
              onTap: () => _showProfileMenu(context),
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
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
    return GestureDetector(
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
    );
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
  final String type;
  final int floor;
  final LatLng centroid;

  RoomSearchItem({
    required this.name,
    required this.type,
    required this.floor,
    required this.centroid,
  });
}
