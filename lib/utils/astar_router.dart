import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';

class PathNode {
  final LatLng point;
  final Map<PathNode, double> neighbors = {};

  PathNode(this.point);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathNode &&
          point.latitude == other.point.latitude &&
          point.longitude == other.point.longitude;

  @override
  int get hashCode => point.latitude.hashCode ^ point.longitude.hashCode;
}

class AStarRouter {
  final List<PathNode> nodes = [];

  void buildGraph(List<List<LatLng>> paths) {
    nodes.clear();
    final Map<String, PathNode> pointToNode = {};

    for (var path in paths) {
      PathNode? prevNode;
      for (var point in path) {
        // Round to 7 decimal places (~1cm precision) to handle floating point errors
        // and ensure nodes from different LineStrings connect correctly.
        final lat = double.parse(point.latitude.toStringAsFixed(7));
        final lng = double.parse(point.longitude.toStringAsFixed(7));
        final key = "$lat,$lng";
        
        final node = pointToNode.putIfAbsent(key, () {
          final newNode = PathNode(LatLng(lat, lng));
          nodes.add(newNode);
          return newNode;
        });

        if (prevNode != null) {
          final distance = const Distance().as(LengthUnit.Meter, prevNode.point, node.point);
          prevNode.neighbors[node] = distance;
          node.neighbors[prevNode] = distance;
        }
        prevNode = node;
      }
    }
  }

  List<LatLng>? findPath(LatLng start, LatLng end) {
    if (nodes.isEmpty) return null;

    final startNode = _findNearestNode(start);
    final endNode = _findNearestNode(end);

    if (startNode == null || endNode == null) return null;

    final Map<PathNode, PathNode?> cameFrom = {};
    final Map<PathNode, double> gScore = {for (var n in nodes) n: double.infinity};
    final Map<PathNode, double> fScore = {for (var n in nodes) n: double.infinity};

    gScore[startNode] = 0;
    fScore[startNode] = _heuristic(startNode.point, endNode.point);

    final openSet = PriorityQueue<PathNode>((a, b) => fScore[a]!.compareTo(fScore[b]!));
    openSet.add(startNode);

    while (openSet.isNotEmpty) {
      final current = openSet.removeFirst();

      if (current == endNode) {
        return _reconstructPath(cameFrom, current);
      }

      for (var neighborEntry in current.neighbors.entries) {
        final neighbor = neighborEntry.key;
        final weight = neighborEntry.value;
        final tentativeGScore = gScore[current]! + weight;

        if (tentativeGScore < gScore[neighbor]!) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeGScore;
          fScore[neighbor] = tentativeGScore + _heuristic(neighbor.point, endNode.point);
          if (!openSet.contains(neighbor)) {
            openSet.add(neighbor);
          }
        }
      }
    }

    return null;
  }

  PathNode? _findNearestNode(LatLng point) {
    PathNode? nearest;
    double minDistance = double.infinity;

    for (var node in nodes) {
      final dist = const Distance().as(LengthUnit.Meter, point, node.point);
      if (dist < minDistance) {
        minDistance = dist;
        nearest = node;
      }
    }
    return nearest;
  }

  double _heuristic(LatLng a, LatLng b) {
    return const Distance().as(LengthUnit.Meter, a, b);
  }

  List<LatLng> _reconstructPath(Map<PathNode, PathNode?> cameFrom, PathNode current) {
    final path = [current.point];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.insert(0, current.point);
    }
    return path;
  }
}
