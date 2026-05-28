import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'dart:convert';
import 'package:flutter/services.dart';
import '../utils/dijkstra_router.dart';
import '../models.dart';

// Floor identifiers: 0 = Ground, 1 = Floor 1, 2 = Floor 2, 3 = Floor 3, 4 = Floor 4
class IndoorMapWidget extends StatefulWidget {
  final int currentFloor;
  final LatLng? userLocation;
  final double heading;
  final Function(String name, LatLng centroid)? onRoomSelected;
  final Function(List<NavPoint> path)? onRouteCalculated;
  final String? highlightType;
  final bool isNavigating;

  const IndoorMapWidget({
    super.key,
    this.currentFloor = 0,
    this.userLocation,
    this.heading = 0,
    this.onRoomSelected,
    this.onRouteCalculated,
    this.highlightType,
    this.isNavigating = false,
  });

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
  LatLng? _destinationLocation;
  int? _destinationFloor;

  LatLng? _selectedRoomCentroid; // unique per-polygon identifier (centroid coords)
  String? _highlightType;   // active filter room type (null = no filter)
  double _currentZoom = 18.5;

  // Cache for GeoJSON data to avoid re-parsing
  final Map<int, Map<String, dynamic>> _geoJsonCache = {};

  // 🔴 University Building Center (Assam Don Bosco University, Azara)
  // Fine-tuned based on your specific GeoJSON coordinates
  static const LatLng _buildingCenter = LatLng(26.1297, 91.6197);

  // Router for pathfinding
  final DijkstraRouter _router = DijkstraRouter();
  List<NavPoint>? _currentFullRoute;

  @override
  void initState() {
    super.initState();
    _selectedFloor  = widget.currentFloor;
    _highlightType  = widget.highlightType;
    _loadFloorPlan(_selectedFloor);
    _initializeGlobalRouter();
  }

  Future<void> _initializeGlobalRouter() async {
    final Map<int, List<List<LatLng>>> allFloorPaths = {};
    final Map<int, List<TransitionPoint>> allTransitionPoints = {};

    for (int floor = 0; floor <= 4; floor++) {
      try {
        final String fileName = floor == 0 ? 'ground' : 'floor_$floor';
        final String data = await rootBundle.loadString('assets/geojson/$fileName.geojson');
        final geoJson = json.decode(data);
        _geoJsonCache[floor] = geoJson;

        final List<List<LatLng>> paths = [];
        final List<TransitionPoint> transitions = [];

        for (final feature in geoJson['features']) {
          final geometry = feature['geometry'];
          final props = feature['properties'];
          final type = (props['type'] ?? '').toString().toLowerCase();

          if (geometry['type'] == 'LineString' && (type == 'path' || type == 'corridor')) {
            final coords = geometry['coordinates'] as List;
            final points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
            paths.add(points);
          }
          
          if (type.contains('stair') || type.contains('lift') || type.contains('elevator')) {
            List<LatLng> points = [];
            if (geometry['type'] == 'Polygon') {
              final coords = geometry['coordinates'][0] as List;
              points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
            } else if (geometry['type'] == 'LineString') {
               final coords = geometry['coordinates'] as List;
               points = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
            }
            if (points.isNotEmpty) {
              final centroid = _calculateCentroid(points);
              final isLift = type.contains('lift') || type.contains('elevator');
              transitions.add(TransitionPoint(latitude: centroid.latitude, longitude: centroid.longitude, isLift: isLift));
            }
          }
        }
        allFloorPaths[floor] = paths;
        allTransitionPoints[floor] = transitions;
      } catch (e) {
        debugPrint('Error pre-loading floor $floor: $e');
      }
    }

    _router.buildGlobalGraph(allFloorPaths, allTransitionPoints);
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
    if (oldWidget.userLocation != widget.userLocation && widget.userLocation != null) {
      if (_currentFullRoute != null && _currentFullRoute!.isNotEmpty) {
        _handleLocationUpdate(widget.userLocation!);
      }
    }
  }

  // To avoid spamming recalculations when GPS jitters, we track the last recalculation time
  DateTime? _lastRecalculationTime;

  void _handleLocationUpdate(LatLng newLocation) {
    if (_currentFullRoute == null || _currentFullRoute!.isEmpty) return;
    
    // Only process points on the current floor where the user is
    final List<NavPoint> currentFloorRoute = _currentFullRoute!
        .where((p) => p.floor == widget.currentFloor)
        .toList();

    if (currentFloorRoute.isEmpty) return;

    double minDistance = double.infinity;
    int closestSegmentIndex = -1;

    // Find the closest segment on the current floor's path
    for (int i = 0; i < currentFloorRoute.length - 1; i++) {
      final p1 = LatLng(currentFloorRoute[i].latitude, currentFloorRoute[i].longitude);
      final p2 = LatLng(currentFloorRoute[i + 1].latitude, currentFloorRoute[i + 1].longitude);
      
      final projection = _projectPointOnSegment(newLocation, p1, p2);
      final dist = _distanceBetweenPoints(newLocation, projection);
      
      if (dist < minDistance) {
        minDistance = dist;
        closestSegmentIndex = i;
      }
    }

    // minDistance is roughly in degrees. Let's convert to meters.
    // 1 degree latitude ~ 111,320 meters
    final distanceInMeters = minDistance * 111320.0;
    
    // Threshold for deviation in meters
    const double deviationThreshold = 12.0;

    if (distanceInMeters > deviationThreshold) {
      // User deviated! Trigger recalculation (debounce by 3 seconds)
      final now = DateTime.now();
      if (_lastRecalculationTime == null || now.difference(_lastRecalculationTime!).inSeconds > 3) {
        _lastRecalculationTime = now;
        
        // Original destination is the last point in the full route
        final destPoint = _currentFullRoute!.last;
        final destination = LatLng(destPoint.latitude, destPoint.longitude);
        
        // Recalculate route
        showDirectionsTo(destination, destinationFloor: destPoint.floor);
      }
    } else if (closestSegmentIndex != -1) {
      // User is on track! Trim the route to start from their current location.
      // We rebuild the visible points to start exactly from where they are, 
      // continuing through the rest of the current floor's route.
      List<LatLng> trimmedPoints = [newLocation];
      for (int i = closestSegmentIndex + 1; i < currentFloorRoute.length; i++) {
        trimmedPoints.add(LatLng(currentFloorRoute[i].latitude, currentFloorRoute[i].longitude));
      }
      setRoute(trimmedPoints);
    }
  }

  LatLng _projectPointOnSegment(LatLng p, LatLng v, LatLng w) {
    final l2 = _distanceBetweenPointsSq(v, w);
    if (l2 == 0) return v;
    
    // Consider the line extending the segment, parameterized as v + t (w - v).
    // We find projection of point p onto the line. 
    // It falls where t = [(p-v) . (w-v)] / |w-v|^2
    var t = ((p.latitude - v.latitude) * (w.latitude - v.latitude) + 
             (p.longitude - v.longitude) * (w.longitude - v.longitude)) / l2;
             
    // Clamp t to [0, 1] to ensure it falls on the segment
    t = max(0, min(1, t));
    
    return LatLng(
      v.latitude + t * (w.latitude - v.latitude),
      v.longitude + t * (w.longitude - v.longitude)
    );
  }

  double _distanceBetweenPointsSq(LatLng p1, LatLng p2) {
    return pow(p1.latitude - p2.latitude, 2) + pow(p1.longitude - p2.longitude, 2).toDouble();
  }

  double _distanceBetweenPoints(LatLng p1, LatLng p2) {
    return sqrt(_distanceBetweenPointsSq(p1, p2));
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

        final String rawName = (properties['name'] ?? '').toString();
        final String rawRoomNo = (properties['roomNo'] ?? '').toString().trim();
        final String name = rawName == 'null' ? '' : rawName;
        final String roomNo = rawRoomNo == 'null' ? '' : rawRoomNo;

        // Use name for display; fall back to roomNo for identity
        final String displayName = name.isNotEmpty ? name : roomNo;

        // Compute centroid once — used both for isSelected check and marker placement.
        // Centroid coordinates uniquely identify the polygon even when many features
        // share the same display name (e.g. multiple rooms all named "CLASSROOM").
        final LatLng featureCentroid = _calculateCentroid(points);
        final bool isSelected = _selectedRoomCentroid != null &&
            (featureCentroid.latitude  - _selectedRoomCentroid!.latitude).abs()  < 1e-6 &&
            (featureCentroid.longitude - _selectedRoomCentroid!.longitude).abs() < 1e-6;

        final bool hasExplicitName = name.isNotEmpty;
        final bool isStructuralType = type == 'other' || type == 'null' || type == '';
        final bool isPath = type == 'path' || type == 'corridor';

        // Treat as "hasName" only if it has an explicit name or a valid room type.
        // This prevents structural walls (which have only a roomNo) from being labeled on the map.
        final bool hasName = displayName.isNotEmpty && (hasExplicitName || (!isStructuralType && !isPath));
        
        final bool isFiltering = _highlightType != null;
        final String query = isFiltering ? _highlightType!.toLowerCase() : '';
        final bool typeMatches = isFiltering && _isMatch(query, type, displayName.toLowerCase(), roomNo.toLowerCase());

        // Category-based coloring with soft modern tones
        final Color baseColor = _getRoomColor(type);
        final Color fillColor;
        final Color borderColor;
        final double borderWidth;

        if (isSelected) {

          fillColor = baseColor.withValues(alpha: 0.85);

          borderColor = const Color(0xFF5B5FEF);

          borderWidth = 3.0;

        } else if (!isFiltering) {

          // Colored room interiors
          fillColor = baseColor.withValues(alpha: 0.75);

          // Neutral dark borders
          borderColor = const Color(0xFF424242);

          borderWidth = 1.5;

        } else if (typeMatches) {

          fillColor = baseColor.withValues(alpha: 0.9);

          borderColor = const Color(0xFF5B5FEF);

          borderWidth = 2.2;

        } else {

          fillColor = baseColor.withValues(alpha: 0.25);

          borderColor = const Color(0xFF757575);

          borderWidth = 1.0;
        }

        if (type != 'path' && type != 'corridor') {
          bool isClosed = false;
          if (points.length >= 3) {
            final double latDiff = (points.first.latitude - points.last.latitude).abs();
            final double lngDiff = (points.first.longitude - points.last.longitude).abs();
            isClosed = (latDiff < 1e-4 && lngDiff < 1e-4);
          }

          if (points.length >= 3 && (geometry['type'] == 'Polygon' || isClosed)) {
            polygons.add(Polygon(
              points: points,
              color: fillColor,
              borderColor: borderColor,
              borderStrokeWidth: borderWidth,
            ));
          } else {
            // For open LineStrings or unnamed structural features, use Polyline.
            borderLines.add(Polyline(
              points: points,
              color: isSelected ? const Color(0xFF5B5FEF) : borderColor.withValues(alpha: 0.8),
              strokeWidth: borderWidth,
            ));
          }
        }

        if (hasName && (showLabels || isSelected) && (!isFiltering || typeMatches || isSelected)) {
          potentialMarkers.add({
            'point': featureCentroid, // reuse already-computed centroid
            'name': displayName,
            'roomNo': roomNo,
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
      // No need to rebuild graph here, it's done once for all floors
    }
  }

  List<Marker> _deconflictMarkers(List<Map<String, dynamic>> potentialMarkers) {
    final List<Marker> markers = [];
    final List<Rect> occupiedRects = [];
    final bool bypassDeconfliction = _currentZoom >= 20.5;
    
    for (var m in potentialMarkers) {
      final LatLng point = m['point'];
      final String name = m['name'];
      final String roomNo = m['roomNo'] ?? '';
      final String type = m['type'];
      
      // Calculate screen position
      final Offset pixel = _mapController.camera.latLngToScreenOffset(point);
      
      // Vertical layout: wider and taller to allow full room names + room number
      const double w = 110;
      const double h = 85;
      
      final Rect rect = Rect.fromCenter(
        center: pixel,
        width: w,
        height: h,
      );
      
      // Check for collisions
      bool hasCollision = false;
      if (!bypassDeconfliction) {
        for (var occupied in occupiedRects) {
          if (occupied.overlaps(rect)) {
            hasCollision = true;
            break;
          }
        }
      }
      
      // Prominent markers (selected/filtered) have higher tolerance or are always shown
      if (bypassDeconfliction || !hasCollision || m['isSelected'] || m['typeMatches']) {
        Widget markerChild = _buildMarkerWidget(name, roomNo, type, m['isSelected'], isHighlighted: m['typeMatches']);
        
        // Shift Reception Area slightly to the left so it doesn't block the user location blue dot
        if (name.toLowerCase().contains('reception')) {
          markerChild = Transform.translate(
            offset: const Offset(-45, 0), // Move it left by 45 pixels
            child: markerChild,
          );
        }

        markers.add(Marker(
          point: point,
          width: w,
          height: h,
          rotate: true,
          child: markerChild,
        ));
        if (!bypassDeconfliction) {
          occupiedRects.add(rect.inflate(4)); // Add some padding between labels
        }
      }
    }
    return markers;
  }

  Widget _buildMarkerWidget(String name, String roomNo, String type, bool isSelected, {bool isHighlighted = false}) {
    final bool emphasize = isSelected || isHighlighted;
    final Color categoryColor = _getRoomColor(type);
    // Use a darker version of the category color for icons to ensure contrast
    final Color iconColor = emphasize ? Colors.white : HSLColor.fromColor(categoryColor).withLightness(0.4).toColor();
    final bool hasRoomNo = roomNo.isNotEmpty && roomNo != 'null' && !roomNo.startsWith('G');
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon with circular background
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: emphasize ? const Color(0xFF5B5FEF) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: emphasize ? Colors.white : iconColor.withValues(alpha: 0.8),
                width: emphasize ? 2 : 1,
              ),
            ),
            child: Icon(
              _getRoomIcon(type),
              size: emphasize ? 15 : 12,
              color: emphasize ? Colors.white : iconColor,
            ),
          ),
          const SizedBox(height: 3),
          // Name + Room Number label with white rectangular background
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: emphasize 
                ? Border.all(color: const Color(0xFF5B5FEF), width: 2) 
                : Border.all(color: Colors.black12, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Room name
                Text(
                  name,
                  style: TextStyle(
                    fontSize: emphasize ? 12 : 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontFamily: 'googlesans',
                    letterSpacing: -0.1,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
                // Room number (shown below the name)
                if (hasRoomNo) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Rm $roomNo',
                    style: TextStyle(
                      fontSize: emphasize ? 10 : 9,
                      fontWeight: FontWeight.w600,
                      color: emphasize ? const Color(0xFF5B5FEF) : Colors.black54,
                      fontFamily: 'googlesans',
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
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
    switch (type.trim().toLowerCase()) {
      case 'classroom':
      case 'class room':
      case 'seminar room':
        return Colors.yellow; // yellow

      case 'lab':
      case 'laboratory':
      case 'workshop':
        return const Color(0xFF1565C0); // Dark blue

      case 'office':
      case 'staff room':
        return const Color(0xFF9E9E9E); // Grey

      case 'washroom':
      case 'toilet':
        return const Color(0xFF2196F3); // Blue

      case 'cafeteria':
      case 'cafetria':
      case 'refreshment area':
        return const Color(0xFFFF9800); // Orange

      case 'nescafe':
        return const Color(0xFF795548); // Brown

      case 'auditorium':
      case 'hall':
      case 'chall':
      case 'conference hall':
        return const Color(0xFF4E342E); // Dark brown

      case 'faculty cabin':
      case 'cabin':
        return const Color(0xFF2E7D32); // Dark green

      case 'parking lot':
      case 'parking':
      case 'green area':
      case 'atrium':
      case 'quadrangle':
      case 'park':
        return const Color(0xFF4CAF50); // Green

      case 'coffee lounge':
        return const Color(0xFFFFFFFF); // White

      case 'gate':
      case 'main gate':
      case 'back gate':
      case 'entry':
      case 'exit':
        return const Color(0xFFF44336); // Red

      case 'library':
        return const Color(0xFF9FA8DA); // indigo

      case 'reception':
      case 'waiting area':
        return const Color(0xFF013220); //dark green

      case 'staircase':
      case 'stairs':
      case 'lift':
      case 'elevator':
        return Colors.black; // black

      default:
        return const Color(0xFFE0E0E0);
    }
  }


  void setRoute(List<LatLng>? path) {
    if (mounted) {
      setState(() {
        if (path == null || path.isEmpty) {
          _routePolylines = [];
          _destinationLocation = null;
          _destinationFloor = null;
        } else {
          final List<Polyline> polylines = [
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

          // 3. User Snap Dotted Line (Start)
          if (widget.userLocation != null) {
            final startLatLng = widget.userLocation!;
            final endLatLng = path.first;
            final distance = const Distance().as(LengthUnit.Meter, startLatLng, endLatLng);
            if (distance > 1.0) {
              polylines.addAll([
                // Outer dotted line (accent outline)
                Polyline(
                  points: [startLatLng, endLatLng],
                  strokeWidth: 8.0,
                  color: const Color(0xFF5B5FEF).withValues(alpha: 0.5),
                  pattern: const StrokePattern.dotted(spacingFactor: 1.8),
                  strokeCap: StrokeCap.round,
                ),
                // Inner dotted line (white core)
                Polyline(
                  points: [startLatLng, endLatLng],
                  strokeWidth: 4.5,
                  color: Colors.white,
                  pattern: const StrokePattern.dotted(spacingFactor: 1.8),
                  strokeCap: StrokeCap.round,
                ),
              ]);
            }
          }

          // 4. Destination Snap Dotted Line (End)
          if (_destinationLocation != null && _destinationFloor == _selectedFloor) {
            final startLatLng = path.last;
            final endLatLng = _destinationLocation!;
            final distance = const Distance().as(LengthUnit.Meter, startLatLng, endLatLng);
            if (distance > 1.0) {
              polylines.addAll([
                // Outer dotted line (accent outline)
                Polyline(
                  points: [startLatLng, endLatLng],
                  strokeWidth: 8.0,
                  color: const Color(0xFF5B5FEF).withValues(alpha: 0.5),
                  pattern: const StrokePattern.dotted(spacingFactor: 1.8),
                  strokeCap: StrokeCap.round,
                ),
                // Inner dotted line (white core)
                Polyline(
                  points: [startLatLng, endLatLng],
                  strokeWidth: 4.5,
                  color: Colors.white,
                  pattern: const StrokePattern.dotted(spacingFactor: 1.8),
                  strokeCap: StrokeCap.round,
                ),
              ]);
            }
          }

          _routePolylines = polylines;
        }
      });
    }
  }

  List<PathNode> get globalNodes => _router.nodes;

  void showDirectionsTo(LatLng destination, {int? destinationFloor, bool accessibleRoute = false}) {
    if (widget.userLocation == null) return;
    
    _destinationLocation = destination;
    _destinationFloor = destinationFloor ?? _selectedFloor;
    
    final start = NavPoint(
      latitude: widget.userLocation!.latitude,
      longitude: widget.userLocation!.longitude,
      floor: widget.currentFloor,
    );
    
    final end = NavPoint(
      latitude: destination.latitude,
      longitude: destination.longitude,
      floor: destinationFloor ?? _selectedFloor,
    );
    
    final path = _router.findPath(start, end, accessibleRoute: accessibleRoute);
    _currentFullRoute = path;
    _updateRouteLayer();

    if (widget.onRouteCalculated != null && path != null) {
      widget.onRouteCalculated!(path);
    }
  }

  void _updateRouteLayer() {
    if (_currentFullRoute == null || _currentFullRoute!.isEmpty) {
      setRoute(null);
      return;
    }

    final List<LatLng> visiblePoints = _currentFullRoute!
        .where((p) => p.floor == _selectedFloor)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    setRoute(visiblePoints.isNotEmpty ? visiblePoints : null);
    
    // Check if transition cues are needed
    _checkForFloorTransitions();
  }

  int? _getNextFloorInPath() {
    if (_currentFullRoute == null || _currentFullRoute!.isEmpty) return null;
    
    // Check if the current floor has ANY points. 
    // If we are currently NOT on the path, find the first floor that has path points.
    bool currentFloorHasPath = _currentFullRoute!.any((p) => p.floor == _selectedFloor);
    
    if (!currentFloorHasPath) {
       // Return the first floor that has path points
       return _currentFullRoute!.first.floor;
    }

    // If we are on the current floor, find the NEXT floor in sequence
    bool foundCurrent = false;
    for (var point in _currentFullRoute!) {
      if (point.floor == _selectedFloor) {
        foundCurrent = true;
      } else if (foundCurrent) {
        return point.floor;
      }
    }
    return null;
  }

  void _checkForFloorTransitions() {
    if (mounted) {
      setState(() {}); // Trigger rebuild to show/hide transition hints
    }
  }

  void resetRotation() {
    _mapController.rotate(0);
  }

  void rotateMapToHeading(double heading) {
    // In FlutterMap, 0 is North. If device points East (90), to make East point UP, 
    // the map needs to be rotated -90 or 270 degrees.
    double rotation = (360 - heading) % 360;
    _mapController.rotate(rotation);
  }

  void moveMapWithHeading(LatLng location, double heading) {
    double rotation = (360 - heading) % 360;
    _mapController.moveAndRotate(location, _mapController.camera.zoom, rotation);
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
      _selectedRoomCentroid = centroid;
      _highlightType = null; // clear filter so only this room is highlighted
      _loadFloorPlan(floor).then((_) {
        moveToLocation(centroid, zoom: 21.5);
      });
    } else {
      setState(() {
        _selectedRoomCentroid = centroid;
        _highlightType = null; // clear filter so only this room is highlighted
      });
      _updateMapObjects();
      moveToLocation(centroid, zoom: 21.5);
    }
  }

  void setFloor(int floor) {
    if (_selectedFloor != floor) {
      setState(() => _selectedFloor = floor);
      _loadFloorPlan(floor).then((_) {
        _updateRouteLayer(); // Refresh route for the new floor
      });
    }
  }

  bool _isMatch(String query, String roomType, String roomName, String roomNo) {
    if (query.isEmpty) return false;
    
    // 1. Exact Predefined Chip Mappings
    if (query == 'washrooms' && roomType == 'washroom') return true;
    if (query == 'faculty cabins' && roomType == 'cabin') return true;
    if (query == 'computer labs' && roomType == 'lab') return true;
    if (query == 'cafeteria' && roomType == 'cafeteria') return true;

    // 2. Strict Type Match (exact or simple plural)
    if (roomType.isNotEmpty) {
      if (roomType == query || roomType + 's' == query || query + 's' == roomType) return true;
      if (roomType.length > 4 && query.contains(roomType)) return true;
    }

    // 3. Name or Number Match
    if (roomName.isNotEmpty && roomName.contains(query)) return true;
    if (roomNo.isNotEmpty && roomNo.contains(query)) return true;

    return false;
  }

  bool hasLocationsOfType(String type) {
    final geoJson = _geoJsonCache[_selectedFloor];
    if (geoJson == null) return false;
    final String query = type.toLowerCase();
    for (final feature in geoJson['features']) {
      final properties = feature['properties'];
      final String roomType = (properties['type'] ?? '').toString().toLowerCase();
      final String rawName = (properties['name'] ?? '').toString().toLowerCase();
      final String roomNo = (properties['roomNo'] ?? '').toString().trim().toLowerCase();
      final String roomName = rawName.isNotEmpty && rawName != 'null' ? rawName : roomNo;
      
      if (_isMatch(query, roomType, roomName, roomNo)) return true;
    }
    return false;
  }

  /// Call from HomeScreen whenever the active filter changes.
  bool setHighlight(String? type) {
    bool hasMatches = true;
    if (type != null) {
      hasMatches = hasLocationsOfType(type);
    }
    
    if (_highlightType != type) {
      _highlightType = type;
      _updateMapObjects();
    }
    
    if (type != null && hasMatches) {
      // Delay slightly to ensure UI has updated or to provide a smoother transition
      Future.delayed(const Duration(milliseconds: 100), () {
        _zoomToFilteredRooms(type);
      });
    }
    return hasMatches;
  }

  void _zoomToFilteredRooms(String type) {
    final geoJson = _geoJsonCache[_selectedFloor];
    if (geoJson == null) return;

    final List<LatLng> allMatchingPoints = [];
    final String query = type.toLowerCase();
    
    for (final feature in geoJson['features']) {
      final properties = feature['properties'];
      final String roomType = (properties['type'] ?? '').toString().toLowerCase();
      final String rawName = (properties['name'] ?? '').toString().toLowerCase();
      final String roomNo = (properties['roomNo'] ?? '').toString().trim().toLowerCase();
      final String roomName = rawName.isNotEmpty && rawName != 'null' ? rawName : roomNo;
      
      if (_isMatch(query, roomType, roomName, roomNo)) {
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
          padding: const EdgeInsets.all(40), // Safe padding to see surrounding context
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
    LatLng? tappedCentroid;
    final geoJson = _geoJsonCache[_selectedFloor];

    if (geoJson != null) {
      for (final feature in geoJson['features']) {
        final geometry = feature['geometry'];
        final props = feature['properties'];
        final rawName = (props['name'] ?? '').toString();
        final rawRoomNo = (props['roomNo'] ?? '').toString().trim();
        final name = rawName.isNotEmpty && rawName != 'null' ? rawName : rawRoomNo;
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
          tappedCentroid = _calculateCentroid(featurePoints);
          break;
        }
      }
    }

    // Use centroid equality to detect a real selection change.
    // Name alone is not sufficient because many rooms share the same display name
    // (e.g. every classroom is named "CLASSROOM").
    final bool alreadySelected = _selectedRoomCentroid != null &&
        tappedCentroid != null &&
        (tappedCentroid.latitude  - _selectedRoomCentroid!.latitude).abs()  < 1e-6 &&
        (tappedCentroid.longitude - _selectedRoomCentroid!.longitude).abs() < 1e-6;

    if (!alreadySelected) {
      // Clear any active type-based filter so ONLY the tapped room is highlighted.
      _highlightType = null;
      setState(() {
        _selectedRoomCentroid = tappedCentroid; // unique identifier for this polygon
      });
      _updateMapObjects();

      // Notify parent after selection is fully resolved
      if (tappedRoomName != null && tappedCentroid != null && widget.onRoomSelected != null) {
        widget.onRoomSelected!(tappedRoomName, tappedCentroid);
      }
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
              final double oldZoom = _currentZoom;
              _currentZoom = pos.zoom;
              final bool crossedLabelThreshold = (oldZoom > 19.0) != (_currentZoom > 19.0);
              if ((_currentZoom - oldZoom).abs() > 0.05 || crossedLabelThreshold) {
                _updateMapObjects();
              }
                        },
          ),
          children: [
            // Google Satellite map style
            TileLayer(
              urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.example.unimap',
            ),
            
            // Indoor room polygons from GeoJSON
            PolygonLayer(polygons: _roomPolygons),
            PolylineLayer(polylines: _borderPolylines),
            PolylineLayer(polylines: _routePolylines),

            // 🏫 University Annotation (pointing to the building)
            if (_currentZoom <= 19.0)
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
                    child: UserLocationMarker(
                      heading: widget.heading,
                      isNavigating: widget.isNavigating,
                    ),
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
  final bool isNavigating;

  const UserLocationMarker({
    super.key,
    required this.heading,
    this.isNavigating = false,
  });

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
          // 1. Pulsing accuracy ring (always shown)
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

          if (widget.isNavigating)
            // Navigation mode: rotating caret ^ arrow
            Transform.rotate(
              angle: headingRad,
              child: const Icon(
                Icons.navigation_rounded,
                color: Color(0xFF4285F4),
                size: 32,
                shadows: [
                  Shadow(
                    color: Colors.white,
                    blurRadius: 6,
                  ),
                ],
              ),
            )
          else ...[
            // Default mode: static accuracy ring + blue dot
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4285F4).withValues(alpha: 0.15),
              ),
            ),
            // Center blue dot with white border
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
