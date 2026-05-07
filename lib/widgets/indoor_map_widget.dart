import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'dart:convert';
import 'package:flutter/services.dart';

// Floor identifiers: 0 = Ground, 1 = Floor 1, 2 = Floor 2, 3 = Floor 3, 4 = Floor 4
class IndoorMapWidget extends StatefulWidget {
  final int currentFloor;
  final LatLng? userLocation;
  final double heading;

  const IndoorMapWidget({
    super.key,
    this.currentFloor = 0,
    this.userLocation,
    this.heading = 0,
  });

  @override
  State<IndoorMapWidget> createState() => IndoorMapWidgetState();
}

class IndoorMapWidgetState extends State<IndoorMapWidget> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  List<Polygon> _roomPolygons = [];
  List<Marker> _roomMarkers = [];
  int _selectedFloor = 0;
  String? _selectedRoomName;
  double _currentZoom = 18.5;

  // Cache for GeoJSON data to avoid re-parsing
  final Map<int, Map<String, dynamic>> _geoJsonCache = {};

  // 🔴 University Building Center (Assam Don Bosco University, Azara)
  // Fine-tuned based on your specific GeoJSON coordinates
  static const LatLng _buildingCenter = LatLng(26.1297, 91.6197);

  @override
  void initState() {
    super.initState();
    _selectedFloor = widget.currentFloor; // 0=Ground, 1,2,3,4 for upper floors
    _loadFloorPlan(_selectedFloor);
  }

  Future<void> _loadFloorPlan(int floor) async {
    try {
      if (!_geoJsonCache.containsKey(floor)) {
        final String fileName = floor == 0 ? 'ground' : 'floor_$floor';
        final String data = await rootBundle.loadString('assets/geojson/$fileName.geojson');
        _geoJsonCache[floor] = json.decode(data);
      }
      
      _updateMapObjects();
    } catch (e) {
      debugPrint('Error loading floor plan: $e');
      setState(() {
        _roomPolygons = [];
        _roomMarkers = [];
      });
    }
  }

  void _updateMapObjects() {
    final geoJson = _geoJsonCache[_selectedFloor];
    if (geoJson == null) return;

    final List<Polygon> polygons = [];
    final List<Marker> markers = [];
    
    // Only show markers/labels if zoomed in enough to avoid clutter and lag
    final bool showLabels = _currentZoom > 19.2;
    
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

      if (points.isNotEmpty) {
        final String type = (properties['type'] ?? 'other').toString().toLowerCase();
        final String name = (properties['name'] ?? properties['roomNo'] ?? '').toString();
        final bool isSelected = _selectedRoomName == name;
        
        if (name.isNotEmpty && name != "null") {
          polygons.add(Polygon(
            points: points,
            color: isSelected 
              ? _getRoomColor(type).withOpacity(0.85) 
              : _getRoomColor(type).withOpacity(0.5),
            borderColor: isSelected ? Colors.white : _getRoomColor(type).withOpacity(0.7),
            borderStrokeWidth: isSelected ? 3.5 : 1.0,
            isFilled: true,
          ));

          if (showLabels) {
            final centroid = _calculateCentroid(points);
            markers.add(Marker(
              point: centroid,
              width: 100,
              height: 50,
              rotate: true, // ✅ Labels stay upright during map rotation (safe: only shown when zoomed in)
              child: _buildMarkerWidget(name, type, isSelected),
            ));
          }
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _roomPolygons = polygons;
        _roomMarkers = markers;
      });
    }
  }

  Widget _buildMarkerWidget(String name, String type, bool isSelected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _getRoomIcon(type),
          size: isSelected ? 16 : 12,
          color: Colors.white.withOpacity(0.9),
        ),
        const SizedBox(height: 1),
        Flexible(
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isSelected ? 12.0 : 10.0,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isSelected ? Colors.amberAccent : Colors.white, // Highlight color
              fontFamily: 'googlesans',
              shadows: const [
                Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    );
  }

  LatLng _calculateCentroid(List<LatLng> points) {
    double lat = 0;
    double lng = 0;
    for (var point in points) {
      lat += point.latitude;
      lng += point.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  IconData _getRoomIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'classroom':
      case 'class room':
        return Icons.school_rounded;
      case 'lab':
      case 'laboratory':
        return Icons.science_rounded;
      case 'office':
      case 'cabin':
        return Icons.work_rounded;
      case 'washroom':
      case 'toilet':
        return Icons.wc_rounded;
      case 'staircase':
      case 'stairs':
        return Icons.stairs_rounded;
      case 'lift':
        return Icons.elevator_rounded;
      case 'cafeteria':
      case 'cafetria':
      case 'coffee lounge':
        return Icons.restaurant_rounded;
      case 'library':
        return Icons.local_library_rounded;
      case 'atrium':
      case 'quadrangle':
      case 'green area':
      case 'park':
        return Icons.park_rounded;
      case 'store':
      case 'shop':
      case 'stationary':
        return Icons.shopping_bag_rounded;
      case 'gate':
      case 'entry':
      case 'exit':
        return Icons.meeting_room_rounded;
      case 'parking':
      case 'parking lot':
        return Icons.local_parking_rounded;
      case 'chapel':
      case 'prayer room':
        return Icons.church_rounded;
      case 'workshop':
      case 'workshiop': // typo in geojson
        return Icons.build_circle_rounded;
      case 'auditorium':
      case 'hall':
      case 'chall':
      case 'conference hall':
        return Icons.theater_comedy_rounded;
      case 'terrace':
      case 'balcony':
        return Icons.wb_sunny_rounded;
      case 'nursing station':
      case 'infirmary':
        return Icons.medical_services_rounded;
      case 'common room':
      case 'guest house':
      case 'guesthouse':
        return Icons.house_rounded;
      case 'reception':
      case 'waiting area':
        return Icons.desk_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color _getRoomColor(String type) {
    // 🎨 Premium Vibrant Palette
    switch (type.trim().toLowerCase()) {
      case 'classroom':
      case 'class room':
        return const Color(0xFF3498DB); // Bright Blue
      case 'lab':
      case 'laboratory':
        return const Color(0xFF2ECC71); // Emerald Green
      case 'office':
      case 'cabin':
        return const Color(0xFFE67E22); // Carrot Orange
      case 'washroom':
      case 'toilet':
        return const Color(0xFF9B59B6); // Amethyst Purple
      case 'staircase':
      case 'stairs':
      case 'lift':
        return const Color(0xFF95A5A6); // Concrete Grey
      case 'cafeteria':
      case 'cafetria':
      case 'coffee lounge':
        return const Color(0xFFF1C40F); // Sun Flower Yellow
      case 'library':
        return const Color(0xFF1ABC9C); // Turquoise
      case 'atrium':
      case 'quadrangle':
      case 'green area':
        return const Color(0xFF27AE60); // Nephritis Green
      case 'store':
      case 'shop':
      case 'stationary':
        return const Color(0xFFD35400); // Pumpkin
      case 'gate':
        return const Color(0xFFC0392B); // Pomegranate Red
      case 'parking':
        return const Color(0xFF7F8C8D); // Asbestos Grey
      case 'chapel':
        return const Color(0xFFF1C40F); // Sun Flower
      case 'workshop':
      case 'workshiop':
        return const Color(0xFF16A085); // Green Sea
      case 'auditorium':
      case 'hall':
      case 'chall':
        return const Color(0xFF8E44AD); // Wisteria Purple
      case 'terrace':
        return const Color(0xFFECF0F1); // Clouds (Light grey)
      case 'nursing station':
      case 'infirmary':
        return const Color(0xFFE74C3C); // Alizarin Red
      case 'common room':
      case 'guest house':
      case 'guesthouse':
        return const Color(0xFFBDC3C7); // Silver
      case 'reception':
        return const Color(0xFF2980B9); // Belize Hole Blue
      default:
        return const Color(0xFF34495E); // Wet Asphalt
    }
  }

  void resetRotation() {
    _mapController.rotate(0);
  }

  void moveToLocation(LatLng destLocation, {double? zoom}) {
    final destZoom = zoom ?? _mapController.camera.zoom;
    
    final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude, 
        end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude, 
        end: destLocation.longitude);
    final zoomTween = Tween<double>(
        begin: _mapController.camera.zoom, 
        end: destZoom);

    var controller = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);
    
    Animation<double> animation = CurvedAnimation(
        parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  void selectAndFocusRoom(int floor, String roomName, LatLng centroid) {
    if (_selectedFloor != floor) {
      _selectedFloor = floor;
      _selectedRoomName = roomName;
      _loadFloorPlan(floor).then((_) {
        moveToLocation(centroid, zoom: 21.5);
      });
    } else {
      setState(() {
        _selectedRoomName = roomName;
      });
      _updateMapObjects();
      moveToLocation(centroid, zoom: 21.5);
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      var j = (i + 1) % polygon.length;
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        intersections++;
      }
    }
    return (intersections % 2 != 0);
  }

  void _handleMapTap(LatLng point) {
    String? tappedRoomName;
    final geoJson = _geoJsonCache[_selectedFloor];
    
    if (geoJson != null) {
      for (final feature in geoJson['features']) {
        final geometry = feature['geometry'];
        final props = feature['properties'];
        final name = (props['name'] ?? props['roomNo'] ?? '').toString();
        if (name.isEmpty || name == "null") continue;

        List<LatLng> featurePoints = [];
        if (geometry['type'] == 'Polygon') {
          final coords = geometry['coordinates'][0] as List;
          featurePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        } else if (geometry['type'] == 'LineString' && (geometry['coordinates'] as List).length > 3) {
          final coords = geometry['coordinates'] as List;
          featurePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        }

        if (featurePoints.isNotEmpty && _isPointInPolygon(point, featurePoints)) {
          tappedRoomName = name;
          break;
        }
      }
    }

    if (tappedRoomName != _selectedRoomName) {
      setState(() {
        _selectedRoomName = tappedRoomName;
      });
      _updateMapObjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _buildingCenter,
            initialZoom: 18.5,
            minZoom: 17.0,
            maxZoom: 22.0,
            onTap: (_, point) => _handleMapTap(point),
            onPositionChanged: (pos, hasGesture) {
              if (pos.zoom != null && (pos.zoom! - _currentZoom).abs() > 0.1) {
                _currentZoom = pos.zoom!;
                _updateMapObjects();
              }
            },
          ),
          children: [
            // Google Hybrid Satellite tiles (Satellite + Labels)
            Opacity(
              opacity: 0.75,
              child: TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.example.unimap',
              ),
            ),
            
            // Indoor room polygons from GeoJSON
            PolygonLayer(polygons: _roomPolygons),
            
            // User Location Marker (Google Maps style)
            if (widget.userLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.userLocation!,
                    width: 90,
                    height: 90,
                    rotate: true, // Always upright on screen
                    child: UserLocationMarker(heading: widget.heading),
                  ),
                ],
              ),

            // 📍 Room POI Markers (Icons + Names)
            MarkerLayer(markers: _roomMarkers),
          ],
        ),
        
        // Floor selector overlay (placed top right)
        Positioned(
          top: 110,
          right: 16,
          child: _buildFloorSelector(),
        ),
      ],
    );
  }

  Widget _buildFloorSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedFloor,
          icon: const Icon(Icons.layers_outlined, color: Color(0xFF1E3A5F), size: 20),
          elevation: 16,
          style: const TextStyle(
            color: Color(0xFF1E3A5F),
            fontWeight: FontWeight.w600,
            fontSize: 15,
            fontFamily: 'googlesans',
          ),
          borderRadius: BorderRadius.circular(16),
          dropdownColor: Colors.white.withOpacity(0.98),
          onChanged: (int? newValue) {
            if (newValue != null) {
              setState(() => _selectedFloor = newValue);
              _loadFloorPlan(newValue);
            }
          },
          items: [
            {'label': 'Ground Floor', 'value': 0},
            {'label': '1st Floor', 'value': 1},
            {'label': '2nd Floor', 'value': 2},
            {'label': '3rd Floor', 'value': 3},
            {'label': '4th Floor', 'value': 4},
          ].map<DropdownMenuItem<int>>((item) {
            return DropdownMenuItem<int>(
              value: item['value'] as int,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(item['label'] as String),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GOOGLE MAPS-STYLE USER LOCATION MARKER
// ─────────────────────────────────────────────────────────────────────────────

class UserLocationMarker extends StatefulWidget {
  final double heading; // degrees, 0 = North

  const UserLocationMarker({super.key, required this.heading});

  @override
  State<UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double headingRad = widget.heading * (3.14159265 / 180);

    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Pulsing accuracy ring
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final scale = _pulseAnimation.value;
              return Container(
                width: 80 * scale,
                height: 80 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4285F4).withOpacity(
                    0.18 * (1.0 - (scale - 0.5) * 2),
                  ),
                ),
              );
            },
          ),

          // 2. Static semi-transparent accuracy circle
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4285F4).withOpacity(0.15),
            ),
          ),

          // 3. Directional heading cone (rotates with compass)
          Transform.rotate(
            angle: headingRad,
            child: CustomPaint(
              size: const Size(90, 90),
              painter: _HeadingArrowPainter(),
            ),
          ),

          // 4. Center blue dot with white border
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4285F4).withOpacity(0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a translucent heading cone pointing upward (North = 0°).
class _HeadingArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF4285F4).withOpacity(0.75),
          const Color(0xFF4285F4).withOpacity(0.0),
        ],
        stops: const [0.0, 1.0],
        center: Alignment.center,
        radius: 0.55,
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2))
      ..style = PaintingStyle.fill;

    // Cone pointing upward from center
    final path = Path()
      ..moveTo(center.dx, center.dy - 9)
      ..lineTo(center.dx - 15, center.dy + 12)
      ..lineTo(center.dx, center.dy + 3)
      ..lineTo(center.dx + 15, center.dy + 12)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
