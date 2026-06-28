// ─────────────────────────────────────────────────────────────────────────────
// A* ROUTER  –  multi-floor indoor navigation
// ─────────────────────────────────────────────────────────────────────────────
// Builds a weighted undirected graph from per-floor path/corridor LineStrings
// and connects floors through staircase / lift transition points.
// Pathfinding uses A* algorithm.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import '../models.dart';

// ── Graph node ────────────────────────────────────────────────────────────────

class PathNode {
  final NavPoint navPoint;

  /// Adjacency list: neighbour → edge weight (metres, or floor-change penalty).
  final Map<PathNode, double> neighbors = {};
  
  bool isStair = false;
  bool isLift = false;

  PathNode(this.navPoint);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathNode && navPoint == other.navPoint;

  @override
  int get hashCode => navPoint.hashCode;
}

// ── Router ────────────────────────────────────────────────────────────────────

class AStarRouter {
  /// All nodes in the global graph (all floors combined).
  final List<PathNode> nodes = [];

  // ── Graph construction ────────────────────────────────────────────────────

  /// Builds the global navigation graph.
  ///
  /// [floorPaths]       – per-floor list of path polylines (corridor/path features).
  /// [transitionPoints] – per-floor centroids of staircases / lifts.
  void buildGlobalGraph(
    Map<int, List<List<LatLng>>> floorPaths,
    Map<int, List<TransitionPoint>> transitionPoints,
  ) {
    nodes.clear();
    final Map<String, PathNode> keyToNode = {};

    // Step 1 – Add path nodes per floor and connect adjacent points on each
    //          polyline with edges weighted by real-world distance.
    floorPaths.forEach((floor, paths) {
      for (final path in paths) {
        PathNode? prev;
        for (final point in path) {
          final lat = double.parse(point.latitude.toStringAsFixed(7));
          final lng = double.parse(point.longitude.toStringAsFixed(7));
          final key = '$floor|$lat|$lng';

          final node = keyToNode.putIfAbsent(key, () {
            final n = PathNode(NavPoint(latitude: lat, longitude: lng, floor: floor));
            nodes.add(n);
            return n;
          });

          if (prev != null) {
            final d = _metersBetween(
              LatLng(prev.navPoint.latitude, prev.navPoint.longitude),
              LatLng(node.navPoint.latitude, node.navPoint.longitude),
            );
            prev.neighbors[node] = d;
            node.neighbors[prev] = d;
          }
          prev = node;
        }
      }
    });

    // Step 1.5 - Bridge gaps between different path segments on the same floor
    // This fixes disconnected graphs caused by slight gaps in GeoJSON LineStrings.
    final Map<int, List<PathNode>> nodesByFloor = {};
    for (final node in nodes) {
      nodesByFloor.putIfAbsent(node.navPoint.floor, () => []).add(node);
    }
    
    nodesByFloor.forEach((floor, floorNodes) {
      for (int i = 0; i < floorNodes.length; i++) {
        final a = floorNodes[i];
        for (int j = i + 1; j < floorNodes.length; j++) {
          final b = floorNodes[j];
          if (!a.neighbors.containsKey(b)) {
            final d = _metersBetween(
              LatLng(a.navPoint.latitude, a.navPoint.longitude),
              LatLng(b.navPoint.latitude, b.navPoint.longitude),
            );
            if (d < 1.5) { // Snapping threshold: 1.5 meters
              a.neighbors[b] = d;
              b.neighbors[a] = d;
            }
          }
        }
      }
    });

    // Step 2 – Connect adjacent floors through staircase / lift nodes.
    _connectFloors(keyToNode, transitionPoints);
  }

  void _connectFloors(
    Map<String, PathNode> keyToNode,
    Map<int, List<TransitionPoint>> transitionPoints,
  ) {
    final floors = transitionPoints.keys.toList()..sort();

    for (int i = 0; i < floors.length - 1; i++) {
      final floorA = floors[i];
      final floorB = floors[i + 1];

      for (final pA in transitionPoints[floorA]!) {
        for (final pB in transitionPoints[floorB]!) {
          final latLngA = LatLng(pA.latitude, pA.longitude);
          final latLngB = LatLng(pB.latitude, pB.longitude);
          
          // Only pair transition points that share the same physical column
          // (staircase or lift shaft): must be within 2.5 m horizontally.
          if (_metersBetween(latLngA, latLngB) >= 2.5) continue;
          
          // Must be of the same type (lift to lift, stair to stair)
          if (pA.isLift != pB.isLift) continue;

          // ── Physical stair/lift node on floor A ──────────────────────────
          final keyA = 'T|$floorA|${pA.latitude}|${pA.longitude}';
          final stairA = keyToNode.putIfAbsent(keyA, () {
            final n = PathNode(NavPoint(
                latitude: pA.latitude, longitude: pA.longitude, floor: floorA));
            n.isLift = pA.isLift;
            n.isStair = !pA.isLift;
            nodes.add(n);
            return n;
          });

          // ── Physical stair/lift node on floor B ──────────────────────────
          final keyB = 'T|$floorB|${pB.latitude}|${pB.longitude}';
          final stairB = keyToNode.putIfAbsent(keyB, () {
            final n = PathNode(NavPoint(
                latitude: pB.latitude, longitude: pB.longitude, floor: floorB));
            n.isLift = pB.isLift;
            n.isStair = !pB.isLift;
            nodes.add(n);
            return n;
          });

          // ── Connect the nearest corridor node to the stair node (same floor)
          final corridorA = _nearestOnFloor(latLngA, floorA);
          if (corridorA != null) {
            final d = _metersBetween(latLngA,
                LatLng(corridorA.navPoint.latitude, corridorA.navPoint.longitude));
            corridorA.neighbors[stairA] = d;
            stairA.neighbors[corridorA] = d;
          }

          final corridorB = _nearestOnFloor(latLngB, floorB);
          if (corridorB != null) {
            final d = _metersBetween(latLngB,
                LatLng(corridorB.navPoint.latitude, corridorB.navPoint.longitude));
            corridorB.neighbors[stairB] = d;
            stairB.neighbors[corridorB] = d;
          }

          // ── Vertical edge: stair A ↔ stair B (floor-change penalty = 10 m)
          const double floorChangePenalty = 10.0;
          stairA.neighbors[stairB] = floorChangePenalty;
          stairB.neighbors[stairA] = floorChangePenalty;
        }
      }
    }
  }

  // ── A* pathfinding ─────────────────────────────────────────────────────────

  /// Returns the shortest path from [start] to [end] as an ordered list of
  /// [NavPoint]s, or `null` if no path exists.
  List<NavPoint>? findPath(NavPoint start, NavPoint end, {bool accessibleRoute = false}) {
    if (nodes.isEmpty) return null;

    var startNode = _nearestOnFloor(
        LatLng(start.latitude, start.longitude), start.floor, excludeTransitions: true);
    startNode ??= _nearestOnFloor(LatLng(start.latitude, start.longitude), start.floor);
        
    var endNode = _nearestOnFloor(
        LatLng(end.latitude, end.longitude), end.floor, excludeTransitions: true);
    endNode ??= _nearestOnFloor(LatLng(end.latitude, end.longitude), end.floor);

    if (startNode == null || endNode == null) return null;
    if (startNode == endNode) return [startNode.navPoint];

    // gScore[node] = cost from startNode
    final Map<PathNode, double> gScore = {for (final n in nodes) n: double.infinity};
    // fScore[node] = gScore[node] + heuristic(node, endNode)
    final Map<PathNode, double> fScore = {for (final n in nodes) n: double.infinity};
    
    final Map<PathNode, PathNode?> prev = {};

    gScore[startNode] = 0.0;
    fScore[startNode] = _heuristic(startNode, endNode);

    // Min-heap keyed on current best fScore
    final pq = PriorityQueue<PathNode>((a, b) => fScore[a]!.compareTo(fScore[b]!));
    pq.add(startNode);

    while (pq.isNotEmpty) {
      final u = pq.removeFirst();

      // Early exit once we pop the destination
      if (u == endNode) break;

      final currentGScore = gScore[u]!;

      for (final entry in u.neighbors.entries) {
        final v = entry.key;
        final w = entry.value;
        
        // Prioritize accessible routing by adding a heavy penalty to staircases
        double adjustedW = w;
        if (accessibleRoute && v.isStair) {
          adjustedW += 10000.0;
        }
        
        final tentativeGScore = currentGScore + adjustedW;

        if (tentativeGScore < gScore[v]!) {
          prev[v] = u;
          gScore[v] = tentativeGScore;
          fScore[v] = tentativeGScore + _heuristic(v, endNode);
          
          // Re-insert with updated priority (Dart PriorityQueue doesn't
          // support decrease-key, so we remove+re-add).
          pq.remove(v);
          pq.add(v);
        }
      }
    }

    // Reconstruct path
    if (gScore[endNode] == double.infinity) return null; // unreachable

    final path = <NavPoint>[];
    PathNode? cur = endNode;
    while (cur != null) {
      path.insert(0, cur.navPoint);
      cur = prev[cur];
    }
    return path;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _heuristic(PathNode a, PathNode b) {
    double h = _metersBetween(
        LatLng(a.navPoint.latitude, a.navPoint.longitude),
        LatLng(b.navPoint.latitude, b.navPoint.longitude));
    h += (a.navPoint.floor - b.navPoint.floor).abs() * 10.0;
    return h;
  }

  /// Euclidean distance in metres between two lat/lng points.
  double _metersBetween(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  /// Nearest graph node on [floor] to [point], ignoring nodes from other floors.
  /// Returns `null` if no nodes exist on that floor.
  PathNode? _nearestOnFloor(LatLng point, int floor, {bool excludeTransitions = false}) {
    PathNode? nearest;
    double minDist = double.infinity;

    for (final node in nodes) {
      if (node.navPoint.floor != floor) continue;
      if (excludeTransitions && (node.isStair || node.isLift)) continue;

      final d = _metersBetween(
          point, LatLng(node.navPoint.latitude, node.navPoint.longitude));
      if (d < minDist) {
        minDist = d;
        nearest = node;
      }
    }
    return nearest;
  }
}
