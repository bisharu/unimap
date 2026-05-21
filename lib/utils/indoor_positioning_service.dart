import 'dart:async';
import 'dart:math';

import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A lightweight indoor positioning service using step detection and
/// geomagnetic heading to fuse pedestrian dead reckoning (PDR) with
/// available sensor heading data.
class IndoorPositioningUpdate {
  final LatLng anchor;
  final LatLng estimatedLocation;
  final double heading;
  final int stepCount;
  final double offsetEast;
  final double offsetNorth;

  IndoorPositioningUpdate({
    required this.anchor,
    required this.estimatedLocation,
    required this.heading,
    required this.stepCount,
    required this.offsetEast,
    required this.offsetNorth,
  });
}

class IndoorPositioningService {
  final StreamController<IndoorPositioningUpdate> _updateController = StreamController.broadcast();

  Stream<IndoorPositioningUpdate> get updates => _updateController.stream;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  bool _running = false;
  LatLng? _anchor;
  double _heading = 0.0;
  double _magneticHeading = 0.0;
  double _offsetEast = 0.0;
  double _offsetNorth = 0.0;
  int _stepCount = 0;
  DateTime _lastStepDetected = DateTime.fromMillisecondsSinceEpoch(0);
  double _gravityEstimate = 9.81;
  double _lastLinearAcceleration = 0.0;

  static const double _defaultStepLength = 0.75;
  static const Duration _minStepInterval = Duration(milliseconds: 320);
  static const double _stepThreshold = 1.2;
  static const double _headingSmoothFactor = 0.18;
  static const double _gravitySmoothFactor = 0.12;

  bool get isRunning => _running;
  LatLng? get anchor => _anchor;
  double get heading => _heading;
  int get stepCount => _stepCount;

  void start({LatLng? anchorLocation}) {
    if (_running) return;
    _running = true;
    if (anchorLocation != null) {
      setAnchor(anchorLocation);
    }
    _subscribeToHeading();
    _subscribeToAcceleration();
    _subscribeToMagnetometer();
    _emitUpdate();
  }

  void stop() {
    _accelerometerSubscription?.cancel();
    _compassSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _compassSubscription = null;
    _magnetometerSubscription = null;
    _running = false;
  }

  void setAnchor(LatLng anchor) {
    _anchor = anchor;
    _offsetEast = 0.0;
    _offsetNorth = 0.0;
    _stepCount = 0;
    _lastStepDetected = DateTime.fromMillisecondsSinceEpoch(0);
    _gravityEstimate = 9.81;
    _lastLinearAcceleration = 0.0;
    _emitUpdate();
  }

  void updateWithGps(LatLng gpsLocation) {
    if (!_running || _anchor == null) return;
    setAnchor(gpsLocation);
  }

  void _subscribeToHeading() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      final newHeading = event.heading ?? _magneticHeading;
      if (newHeading.isNaN) return;
      _heading = _smoothHeading(_heading, newHeading);
      _emitUpdate();
    });
  }

  void _subscribeToMagnetometer() {
    _magnetometerSubscription = magnetometerEvents.listen((event) {
      final heading = _calculateMagneticHeading(event);
      if (!heading.isNaN) {
        _magneticHeading = heading;
      }
    });
  }

  void _subscribeToAcceleration() {
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      _handleStepDetection(event);
    });
  }

  double _calculateMagneticHeading(MagnetometerEvent event) {
    final headingRad = atan2(event.y, event.x);
    var headingDeg = headingRad * (180.0 / pi);
    if (headingDeg < 0) headingDeg += 360.0;
    return headingDeg;
  }

  void _handleStepDetection(AccelerometerEvent event) {
    final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    _gravityEstimate = (_gravitySmoothFactor * magnitude) + ((1.0 - _gravitySmoothFactor) * _gravityEstimate);

    final linearAcceleration = magnitude - _gravityEstimate;
    final filtered = (_lastLinearAcceleration * 0.9) + (linearAcceleration * 0.1);
    _lastLinearAcceleration = filtered;

    final bool isRising = filtered > _stepThreshold;
    final now = DateTime.now();

    if (isRising && now.difference(_lastStepDetected) > _minStepInterval) {
      _lastStepDetected = now;
      _stepCount += 1;
      _applyStepDisplacement(_defaultStepLength);
      _emitUpdate();
    }
  }

  void _applyStepDisplacement(double stepLength) {
    final headingRad = _degreesToRadians(_heading);
    _offsetEast += sin(headingRad) * stepLength;
    _offsetNorth += cos(headingRad) * stepLength;
  }

  double _smoothHeading(double current, double target) {
    final diff = ((target - current + 540) % 360) - 180;
    final smoothed = current + diff * _headingSmoothFactor;
    return (smoothed + 360) % 360;
  }

  LatLng _calculateEstimatedLocation() {
    if (_anchor == null) {
      throw StateError('Anchor location must be set before estimating position.');
    }
    return _translateOffset(_anchor!, _offsetEast, _offsetNorth);
  }

  void _emitUpdate() {
    if (_anchor == null) return;
    final estimatedLocation = _calculateEstimatedLocation();
    _updateController.add(IndoorPositioningUpdate(
      anchor: _anchor!,
      estimatedLocation: estimatedLocation,
      heading: _heading,
      stepCount: _stepCount,
      offsetEast: _offsetEast,
      offsetNorth: _offsetNorth,
    ));
  }

  static LatLng _translateOffset(LatLng anchor, double eastMeters, double northMeters) {
    final latitudeDelta = northMeters / 111320.0;
    final longitudeDelta = eastMeters / (111320.0 * cos(_degreesToRadians(anchor.latitude)));
    return LatLng(anchor.latitude + latitudeDelta, anchor.longitude + longitudeDelta);
  }

  static double _degreesToRadians(double degrees) => degrees * pi / 180.0;

  void dispose() {
    stop();
    _updateController.close();
  }
}
