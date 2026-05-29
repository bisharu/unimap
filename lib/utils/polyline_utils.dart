import 'dart:math';
import 'package:latlong2/latlong.dart';

// ── Polyline Utilities ────────────────────────────────────────────────────────
// Pure functions for route-snapped dot movement.
// ─────────────────────────────────────────────────────────────────────────────

const Distance _dist = Distance();

/// Total arc-length of [poly] in metres.
double polylineLength(List<LatLng> poly) {
  double total = 0.0;
  for (int i = 0; i < poly.length - 1; i++) {
    total += _dist.as(LengthUnit.Meter, poly[i], poly[i + 1]);
  }
  return total;
}

/// Returns the coordinate that is exactly [meters] along [poly] from its
/// first point. Clamps to the last point if [meters] exceeds total length.
LatLng interpolateAlong(List<LatLng> poly, double meters) {
  if (poly.isEmpty) throw ArgumentError('poly must not be empty');
  if (poly.length == 1 || meters <= 0) return poly.first;

  double remaining = meters;
  for (int i = 0; i < poly.length - 1; i++) {
    final segLen = _dist.as(LengthUnit.Meter, poly[i], poly[i + 1]);
    if (remaining <= segLen) {
      final t = segLen == 0 ? 0.0 : remaining / segLen;
      return LatLng(
        poly[i].latitude  + (poly[i + 1].latitude  - poly[i].latitude)  * t,
        poly[i].longitude + (poly[i + 1].longitude - poly[i].longitude) * t,
      );
    }
    remaining -= segLen;
  }
  return poly.last;
}

/// Splits [poly] at the point that is [distanceFromStart] metres along it.
/// Returns `(traveled, remaining)`.
(List<LatLng>, List<LatLng>) splitPolyline(List<LatLng> poly, double distanceFromStart) {
  if (poly.isEmpty) return (<LatLng>[], <LatLng>[]);
  if (distanceFromStart <= 0) return (<LatLng>[], List.of(poly));

  final List<LatLng> traveled = [];
  double remaining = distanceFromStart;

  for (int i = 0; i < poly.length - 1; i++) {
    traveled.add(poly[i]);
    final segLen = _dist.as(LengthUnit.Meter, poly[i], poly[i + 1]);
    if (remaining <= segLen) {
      final t = segLen == 0 ? 0.0 : remaining / segLen;
      final splitPoint = LatLng(
        poly[i].latitude  + (poly[i + 1].latitude  - poly[i].latitude)  * t,
        poly[i].longitude + (poly[i + 1].longitude - poly[i].longitude) * t,
      );
      traveled.add(splitPoint);
      final List<LatLng> ahead = [splitPoint, ...poly.sublist(i + 1)];
      return (traveled, ahead);
    }
    remaining -= segLen;
  }
  // Reached end
  return (List.of(poly), <LatLng>[poly.last]);
}

/// Distance in metres from [point] to the nearest location on any segment of
/// [poly], and also returns the cumulative distance along the polyline to that
/// nearest point.
({double distToLine, double distAlongLine, LatLng nearest}) nearestOnPolyline(
    LatLng point, List<LatLng> poly) {
  if (poly.isEmpty) throw ArgumentError('poly must not be empty');
  if (poly.length == 1) {
    return (
      distToLine: _dist.as(LengthUnit.Meter, point, poly.first),
      distAlongLine: 0.0,
      nearest: poly.first,
    );
  }

  double bestDist = double.infinity;
  double bestAlong = 0.0;
  LatLng bestPoint = poly.first;
  double cumulativeLen = 0.0;

  for (int i = 0; i < poly.length - 1; i++) {
    final a = poly[i];
    final b = poly[i + 1];
    final segLen = _dist.as(LengthUnit.Meter, a, b);

    final closest = _closestPointOnSegment(point, a, b);
    final d = _dist.as(LengthUnit.Meter, point, closest);
    final alongSeg = _dist.as(LengthUnit.Meter, a, closest);

    if (d < bestDist) {
      bestDist = d;
      bestAlong = cumulativeLen + alongSeg;
      bestPoint = closest;
    }
    cumulativeLen += segLen;
  }
  return (distToLine: bestDist, distAlongLine: bestAlong, nearest: bestPoint);
}

/// Compass bearing (0–360°) from [a] to [b].
double bearingBetween(LatLng a, LatLng b) {
  final lat1 = _toRad(a.latitude);
  final lat2 = _toRad(b.latitude);
  final dLng = _toRad(b.longitude - a.longitude);
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

// ── Private helpers ───────────────────────────────────────────────────────────

double _toRad(double deg) => deg * pi / 180;

/// Closest point on segment [a]–[b] to [p] (in lat/lng space).
LatLng _closestPointOnSegment(LatLng p, LatLng a, LatLng b) {
  final dx = b.longitude - a.longitude;
  final dy = b.latitude  - a.latitude;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) return a;
  double t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  return LatLng(a.latitude + t * dy, a.longitude + t * dx);
}
