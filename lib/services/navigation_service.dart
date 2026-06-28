import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../utils/polyline_utils.dart' as pu;

// ─────────────────────────────────────────────────────────────────────────────
// NavigationState — immutable snapshot delivered to the UI
// ─────────────────────────────────────────────────────────────────────────────

class NavigationState {
  /// The dot's current position, snapped to the route polyline.
  final LatLng currentPosition;

  /// Grey portion — already walked.
  final List<LatLng> traveledPolyline;

  /// Blue portion — still ahead.
  final List<LatLng> remainingPolyline;

  /// True once the dot reaches within [NavigationService.arrivalThresholdM]
  /// of the final waypoint.
  final bool hasArrived;

  /// The last QR-scanned position (used by Recenter).
  final LatLng? lastAnchor;

  /// Total cumulative distance walked along the route in metres.
  final double distanceWalkedM;

  const NavigationState({
    required this.currentPosition,
    required this.traveledPolyline,
    required this.remainingPolyline,
    this.hasArrived = false,
    this.lastAnchor,
    this.distanceWalkedM = 0,
  });

  NavigationState copyWith({
    LatLng? currentPosition,
    List<LatLng>? traveledPolyline,
    List<LatLng>? remainingPolyline,
    bool? hasArrived,
    LatLng? lastAnchor,
    double? distanceWalkedM,
  }) {
    return NavigationState(
      currentPosition:  currentPosition  ?? this.currentPosition,
      traveledPolyline: traveledPolyline ?? this.traveledPolyline,
      remainingPolyline: remainingPolyline ?? this.remainingPolyline,
      hasArrived:       hasArrived       ?? this.hasArrived,
      lastAnchor:       lastAnchor       ?? this.lastAnchor,
      distanceWalkedM:  distanceWalkedM  ?? this.distanceWalkedM,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NavigationService
// ─────────────────────────────────────────────────────────────────────────────

class NavigationService {
  // ── Public state ────────────────────────────────────────────────────────────
  final ValueNotifier<NavigationState?> state = ValueNotifier(null);

  // ── Configuration ───────────────────────────────────────────────────────────

  /// Step length in metres per detected footstep.
  static const double stepLengthM = 0.70;

  /// Minimum interval between two consecutive detected steps. (Lowered to allow faster walking)
  static const Duration minStepInterval = Duration(milliseconds: 250);

  /// Acceleration magnitude delta required to register as a step. (Lowered to catch softer steps)
  static const double stepThreshold = 0.8;

  /// How aggressively the low-pass gravity filter follows raw magnitude (0–1).
  static const double gravitySmoothFactor = 0.15;

  /// Smoothing factor for compass heading (0 = no change, 1 = instant). (Increased for faster heading updates)
  static const double headingSmoothFactor = 0.5;

  /// Dot must be within this many metres of the final waypoint to trigger arrival.
  static const double arrivalThresholdM = 3.0;

  /// Maximum heading deviation from route segment bearing to allow step advance. (Widened to be more forgiving)
  static const double headingToleranceDeg = 65.0;

  // ── Private state ───────────────────────────────────────────────────────────
  List<LatLng> _fullRoute = [];
  double _distanceWalkedM = 0.0;
  double _heading = 0.0;
  double _gravityEstimate = 9.81;
  double _lastLinearAccel = 0.0;
  DateTime _lastStepTime = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<CompassEvent>? _compassSub;

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Starts navigation along [routePolyline] from [startPosition].
  /// Snaps [startPosition] to the nearest point on the polyline automatically.
  void startNavigation(List<LatLng> routePolyline, LatLng startPosition) {
    if (routePolyline.length < 2) return;
    
    // Prepend the actual user position so the route starts exactly where they are.
    // This stops the blue dot from "jumping" to the nearest pre-defined graph node.
    if (routePolyline.first != startPosition) {
      routePolyline.insert(0, startPosition);
    }
    
    _fullRoute = routePolyline;

    // Snap start position to polyline (will now perfectly snap to 0 distance)
    final snap = pu.nearestOnPolyline(startPosition, _fullRoute);
    _distanceWalkedM = snap.distAlongLine;

    _emitState(anchor: startPosition);
    _subscribeCompass();
    _subscribeAccelerometer();
  }

  /// Call this whenever a QR code is scanned mid-navigation.
  /// Snaps the dot to the nearest polyline point to [qrPosition] and
  /// resets the last anchor for Recenter.
  void applyQrAnchor(LatLng qrPosition) {
    if (_fullRoute.isEmpty) return;
    final snap = pu.nearestOnPolyline(qrPosition, _fullRoute);
    _distanceWalkedM = snap.distAlongLine;
    _emitState(anchor: qrPosition);
  }



  /// Stops all sensors and clears state.
  void stopNavigation() {
    _accelSub?.cancel();
    _compassSub?.cancel();
    _accelSub = null;
    _compassSub = null;
    _fullRoute = [];
    _distanceWalkedM = 0;
    state.value = null;
  }

  void dispose() {
    stopNavigation();
    state.dispose();
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  void _subscribeCompass() {
    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen((event) {
      final h = event.heading;
      if (h == null || h.isNaN) return;
      // Smooth heading
      final diff = ((h - _heading + 540) % 360) - 180;
      _heading = (_heading + diff * headingSmoothFactor + 360) % 360;
    });
  }

  void _subscribeAccelerometer() {
    _accelSub?.cancel();
    _accelSub = accelerometerEvents.listen(_handleAccelerometer);
  }

  void _handleAccelerometer(AccelerometerEvent e) {
    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    // Low-pass gravity estimate
    _gravityEstimate = gravitySmoothFactor * magnitude +
        (1 - gravitySmoothFactor) * _gravityEstimate;

    // Linear (vertical) acceleration
    final linear = magnitude - _gravityEstimate;

    // Smooth it to kill noise
    _lastLinearAccel = _lastLinearAccel * 0.85 + linear * 0.15;

    final now = DateTime.now();
    if (_lastLinearAccel > stepThreshold &&
        now.difference(_lastStepTime) > minStepInterval) {
      _lastStepTime = now;
      _tryAdvanceDot(stepLengthM);
    }
  }

  void _tryAdvanceDot(double meters) {
    if (_fullRoute.isEmpty) return;
    if (state.value?.hasArrived == true) return;

    // Heading guard — only advance if we are facing the route direction ±45°
    if (!_headingMatchesRoute()) return;

    _distanceWalkedM += meters;

    // Clamp to route length
    final totalLen = pu.polylineLength(_fullRoute);
    if (_distanceWalkedM >= totalLen) {
      _distanceWalkedM = totalLen;
      _emitState(arrived: true);
      return;
    }

    _emitState();
  }

  bool _headingMatchesRoute() {
    if (_fullRoute.length < 2) return true;
    // Find current segment
    double remaining = _distanceWalkedM;
    for (int i = 0; i < _fullRoute.length - 1; i++) {
      final segLen = const Distance().as(
          LengthUnit.Meter, _fullRoute[i], _fullRoute[i + 1]);
      if (remaining <= segLen) {
        final segBearing =
            pu.bearingBetween(_fullRoute[i], _fullRoute[i + 1]);
        final diff = ((_heading - segBearing + 540) % 360) - 180;
        
        // Look-ahead Proximity Waypoint Check (Radius of Acceptance)
        final double distanceToSegmentEnd = segLen - remaining;
        if (distanceToSegmentEnd < 2.5 && i < _fullRoute.length - 2) {
          final nextSegBearing =
              pu.bearingBetween(_fullRoute[i + 1], _fullRoute[i + 2]);
          final nextDiff = ((_heading - nextSegBearing + 540) % 360) - 180;
          
          // If they are facing the direction of the next leg, they are cutting the corner.
          if (nextDiff.abs() <= headingToleranceDeg) {
            // Automatically snap their progress to the start of the next segment!
            _distanceWalkedM += distanceToSegmentEnd;
            return true;
          }
        }

        return diff.abs() <= headingToleranceDeg;
      }
      remaining -= segLen;
    }
    return true;
  }

  void _emitState({LatLng? anchor, bool arrived = false}) {
    if (_fullRoute.isEmpty) return;

    final pos = pu.interpolateAlong(_fullRoute, _distanceWalkedM);
    final split = pu.splitPolyline(_fullRoute, _distanceWalkedM);

    // Check arrival by distance to last waypoint
    final distToEnd = const Distance()
        .as(LengthUnit.Meter, pos, _fullRoute.last);
    final isArrived = arrived || distToEnd <= arrivalThresholdM;

    final prev = state.value;
    state.value = NavigationState(
      currentPosition:  pos,
      traveledPolyline: split.$1,
      remainingPolyline: split.$2,
      hasArrived:       isArrived,
      lastAnchor:       anchor ?? prev?.lastAnchor,
      distanceWalkedM:  _distanceWalkedM,
    );
  }
}
