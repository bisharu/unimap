import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'dart:convert';
import 'package:flutter/services.dart';
import '../utils/astar_router.dart';

// Floor identifiers: 0 = Ground, 1 = Floor 1, 2 = Floor 2, 3 = Floor 3, 4 = Floor 4
class IndoorMapWidget extends StatefulWidget {
  final int currentFloor;
  final LatLng? userLocation;
  final double heading;
  final Function(String name, LatLng centroid)? onRoomSelected;

  const IndoorMapWidget({
    super.key,
    this.currentFloor = 0,
    this.userLocation,
    this.heading = 0,
    this.onRoomSelected,
    this.highlightType,
  });

  final String? highlightType; // room type to highlight when filter is active

  @override
  State<IndoorMapWidget> createState() => IndoorMapWidgetState();
}

class IndoorMapWidgetState extends State<IndoorMapWidget> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  List<Polygon> _roomPolygons = [];
  List<Marker> _roomMarkers = [];
  List<Polyline> _routePolylines = [];
  List<Polyline> _borderPolylines = [];
  int _selectedFloor = 0;
  String? _selectedRoomName;
  String? _highlightType;   // active filter room type (null = no filter)
  double _currentZoom = 18.5;

  // Cache for GeoJSON data to avoid re-parsing
  final Map<int, Map<String, dynamic>> _geoJsonCache = {};

  // 🔴 University Building Center (Assam Don Bosco University, Azara)
  // Fine-tuned based on your specific GeoJSON coordinates
  static const LatLng _buildingCenter = LatLng(26.1297, 91.6197);

  // Router for pathfinding
  final AStarRouter _router = AStarRouter();

  @override
  void initState() {
    super.initState();
    _selectedFloor  = widget.currentFloor;
    _highlightType  = widget.highlightType;
    _loadFloorPlan(_selectedFloor);
  }

  @override
  void didUpdateWidget(covariant IndoorMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentFloor != widget.currentFloor) {
      _selectedFloor = widget.currentFloor;
      _loadFloorPlan(_selectedFloor);
    }
    if (oldWidget.highlightType != widget.highlightType) {
      _highlightType = widget.highlightType;
      _updateMapObjects();
    }
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
    final List<Polyline> borderLines = [];
    final List<Map<String, dynamic>> potentialMarkers = [];
    final List<List<LatLng>> routingPaths = [];
    
    // De-cluttering: show labels at appropriate zoom
    final bool showLabels = _currentZoom > 19.0;
    
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
        if (coords.length >= 2) {
          points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        }
      }

      if (points.isNotEmpty) {
        final String type = (properties['type'] ?? 'other').toString().toLowerCase();
        if (geometry['type'] == 'LineString' && (type == 'path' || type == 'corridor')) {
          routingPaths.add(points);
        }

        final String name = (properties['name'] ?? properties['roomNo'] ?? '').toString();
        final bool isSelected = _selectedRoomName == name;
        final bool hasName = name.isNotEmpty && name != "null";
        
        final bool isFiltering = _highlightType != null;
        final bool typeMatches = isFiltering &&
            (type.contains(_highlightType!) || _highlightType!.contains(type));

        final Color baseColor = _getRoomColor(type);
        final Color fillColor;
        final Color borderColor;
        final double borderWidth;

        if (isSelected && hasName) {
          fillColor   = baseColor.withValues(alpha: 1.0);
          borderColor = Colors.white;
          borderWidth = 3.5;
        } else if (!isFiltering) {
          fillColor   = baseColor.withValues(alpha: 1.0);
          borderColor = baseColor.withValues(alpha: 1.0);
          borderWidth = hasName ? 1.0 : 1.5;
        } else if (typeMatches && hasName) {
          fillColor   = baseColor.withValues(alpha: 1.0);
          borderColor = Colors.white;
          borderWidth = 2.5;
        } else {
          fillColor   = baseColor.withValues(alpha: 0.3); // Increased from 0.15
          borderColor = baseColor.withValues(alpha: 0.4);
          borderWidth = 0.5;
        }

        if (type != 'path' && type != 'corridor') {
          if (hasName) {
            polygons.add(Polygon(
              points: points,
              color: fillColor,
              borderColor: borderColor,
              borderStrokeWidth: borderWidth,
              isFilled: true,
            ));
          } else {
            // Draw unnamed structural features as polylines to prevent unwanted
            // diagonal closure lines across the map.
            borderLines.add(Polyline(
              points: points,
              color: baseColor.withValues(alpha: 1.0), // Solid borders for structure
              strokeWidth: borderWidth,
            ));
          }
        }

        if (hasName && showLabels && (!isFiltering || typeMatches || isSelected)) {
          potentialMarkers.add({
            'point': _calculateCentroid(points),
            'name': name,
            'type': type,
            'isSelected': isSelected,
            'typeMatches': typeMatches,
            'priority': isSelected ? 3 : (typeMatches ? 2 : 1),
          });
        }
      }
    }
    
    // Sort by priority descending (Selected > Highlighted > Others)
    potentialMarkers.sort((a, b) => (b['priority'] as int).compareTo(a['priority'] as int));

    if (mounted) {
      setState(() {
        _roomPolygons = polygons;
        _borderPolylines = borderLines;
        _roomMarkers = _deconflictMarkers(potentialMarkers);
      });
      _router.buildGraph(routingPaths);
    }
  }

  List<Marker> _deconflictMarkers(List<Map<String, dynamic>> potentialMarkers) {
    final List<Marker> markers = [];
    final List<Rect> occupiedRects = [];
    
    for (var m in potentialMarkers) {
      final LatLng point = m['point'];
      final String name = m['name'];
      final String type = m['type'];
      
      // Calculate screen position
      final CustomPoint<double> pixel = _mapController.camera.project(point);
      
      // Vertical layout: wider and taller to allow full room names
      const double w = 100;
      const double h = 75;
      
      final Rect rect = Rect.fromCenter(
        center: Offset(pixel.x, pixel.y),
        width: w,
        height: h,
      );
      
      // Check for collisions
      bool hasCollision = false;
      for (var occupied in occupiedRects) {
        if (occupied.overlaps(rect)) {
          hasCollision = true;
          break;
        }
      }
      
      // Prominent markers (selected/filtered) have higher tolerance or are always shown
      if (!hasCollision || m['isSelected']) {
        markers.add(Marker(
          point: point,
          width: w,
          height: h,
          rotate: true,
          child: _buildMarkerWidget(name, type, m['isSelected']),
        ));
        occupiedRects.add(rect.inflate(4)); // Add some padding between labels
      }
    }
    return markers;
  }

  Widget _buildMarkerWidget(String name, String type, bool isSelected) {
    final Color categoryColor = _getRoomColor(type);
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon with circular background
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5B5FEF) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : categoryColor.withValues(alpha: 0.8),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              _getRoomIcon(type),
              size: isSelected ? 15 : 12,
              color: isSelected ? Colors.white : categoryColor,
            ),
          ),
          const SizedBox(height: 3),
          // Name label with white rectangular background
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
              border: isSelected 
                ? Border.all(color: const Color(0xFF5B5FEF), width: 2) 
                : Border.all(color: Colors.black12, width: 0.5),
            ),
            child: Text(
              name,
              style: TextStyle(
                fontSize: isSelected ? 12 : 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontFamily: 'googlesans',
                letterSpacing: -0.1,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: true,
            ),
          ),
        ],
      ),
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
      case 'refreshment area':
      case 'refreshmentarea':
        return Icons.restaurant_rounded;
      case 'waste segregation unit':
      case 'vermi composting tank':
        return Icons.recycling_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color _getRoomColor(String type) {
    // 🎨 Premium Vibrant Palette
    switch (type.trim().toLowerCase()) {
      case 'classroom':
      case 'class room':
        return const Color(0xFF3683ff);
      case 'lab':
      case 'laboratory':
        return const Color(0xFF525150);
      case 'office':
      case 'cabin':
        return const Color(0xFF61a8b0);
      case 'staff room':
      case 'staffroom':
        return const Color(0xFFB4C5DB);
      case 'washroom':
      case 'toilet':
        return const Color(0xFF000000);
      case 'cafeteria':
      case 'cafetria':
      case 'nescafe':
      case 'coffee lounge':
        return const Color(0xFF525150);
      case 'auditorium':
      case 'hall':
      case 'chall':
        return const Color(0xFFB4C5DB);
      case 'terrace':
        return const Color(0xFFECF0F1); 
      case 'nursing station':
      case 'infirmary':
        return const Color(0xFFE74C3C); 
      case 'common room':
      case 'guest house':
      case 'guesthouse':
        return const Color(0xFFBDC3C7); 
      case 'reception':
        return const Color(0xFF2980B9); 
      case 'green area':
      case 'atrium':
      case 'quadrangle':
      case 'park':
        return const Color(0xFF61b06f); 
      case 'refreshment area':
      case 'refreshmentarea':
        return const Color(0xFF525150);
      case 'waste segregation unit':
      case 'vermi composting tank':
        return const Color(0xFF7F8C8D);
      default:
        return const Color(0xFF34495E); 
    }
  }

  void setRoute(List<LatLng>? path) {
    if (mounted) {
      setState(() {
        if (path == null || path.isEmpty) {
          _routePolylines = [];
        } else {
          _routePolylines = [
            // 1. Path Glow / Outer Line
            Polyline(
              points: path,
              strokeWidth: 9.0,
              color: const Color(0xFF5B5FEF).withValues(alpha: 0.25),
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
            // 2. Main Path Line
            Polyline(
              points: path,
              strokeWidth: 4.5,
              color: const Color(0xFF5B5FEF),
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ];
        }
      });
    }
  }

  void showDirectionsTo(LatLng destination) {
    if (widget.userLocation == null) return;
    
    final path = _router.findPath(widget.userLocation!, destination);
    setRoute(path);
    
    if (path != null && path.isNotEmpty) {
      // Zoom out slightly to show the path if needed, or just keep focus
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

  void setFloor(int floor) {
    if (_selectedFloor != floor) {
      setState(() => _selectedFloor = floor);
      _loadFloorPlan(floor);
    }
  }

  /// Call from HomeScreen whenever the active filter changes.
  void setHighlight(String? type) {
    if (_highlightType != type) {
      _highlightType = type;
      _updateMapObjects();
      if (type != null) {
        // Delay slightly to ensure UI has updated or to provide a smoother transition
        Future.delayed(const Duration(milliseconds: 100), () {
          _zoomToFilteredRooms(type);
        });
      }
    }
  }

  void _zoomToFilteredRooms(String type) {
    final geoJson = _geoJsonCache[_selectedFloor];
    if (geoJson == null) return;

    final List<LatLng> allMatchingPoints = [];
    final String query = type.toLowerCase();
    
    for (final feature in geoJson['features']) {
      final properties = feature['properties'];
      final String roomType = (properties['type'] ?? '').toString().toLowerCase();
      final String roomName = (properties['name'] ?? properties['roomNo'] ?? '').toString().toLowerCase();
      
      if (roomType.contains(query) || query.contains(roomType) || roomName.contains(query)) {
        final geometry = feature['geometry'];
        if (geometry['type'] == 'Polygon') {
          final coords = geometry['coordinates'][0] as List;
          allMatchingPoints.addAll(coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())));
        }
      }
    }

    if (allMatchingPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(allMatchingPoints);
      
      // Use fitCamera for a smooth fit to all matching locations
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(100), // Generous padding to see surrounding context
          maxZoom: 21.0, // Don't zoom in too much for single rooms
        ),
      );
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
          if (widget.onRoomSelected != null) {
            widget.onRoomSelected!(name, _calculateCentroid(featurePoints));
          }
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
            // Google Satellite Imagery
            TileLayer(
              urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.example.unimap',
            ),
            
            // Indoor room polygons from GeoJSON
            PolygonLayer(polygons: _roomPolygons),
            PolylineLayer(polylines: _borderPolylines),
            PolylineLayer(polylines: _routePolylines),

            // 🏫 University Annotation (pointing to the building)
            MarkerLayer(
              markers: [
                Marker(
                  point: _buildingCenter,
                  width: 200,
                  height: 100,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
                          ],
                          border: Border.all(color: const Color(0xFF1E3A5F), width: 1),
                        ),
                        child: const Text(
                          "Assam Don Bosco University",
                          style: TextStyle(
                            fontFamily: 'googlesans',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF1E3A5F),
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Color(0xFF1E3A5F), size: 30),
                    ],
                  ),
                ),
              ],
            ),
            
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
      ],
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
                  color: const Color(0xFF4285F4).withValues(
                    alpha: 0.18 * (1.0 - (scale - 0.5) * 2),
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
              color: const Color(0xFF4285F4).withValues(alpha: 0.15),
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
                  color: const Color(0xFF4285F4).withValues(alpha: 0.4),
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
          const Color(0xFF4285F4).withValues(alpha: 0.75),
          const Color(0xFF4285F4).withValues(alpha: 0.0),
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
