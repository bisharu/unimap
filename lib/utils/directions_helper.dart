import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models.dart';
import 'astar_router.dart';

class DirectionStep {
  final String instruction;
  final IconData icon;
  final double distance;
  final int floor;

  DirectionStep({
    required this.instruction,
    required this.icon,
    required this.distance,
    required this.floor,
  });
}

class DirectionsHelper {
  /// Translates a raw list of [NavPoint]s into high-level human written steps.
  static List<DirectionStep> generateDirections(List<NavPoint> path, List<PathNode> allNodes) {
    final List<DirectionStep> steps = [];
    if (path.isEmpty) return steps;
    
    if (path.length == 1) {
      steps.add(DirectionStep(
        instruction: "You have arrived at your destination.",
        icon: Icons.check_circle_rounded,
        distance: 0.0,
        floor: path.first.floor,
      ));
      return steps;
    }

    // Helper to identify transition node properties (stairs/lifts)
    PathNode? findNode(NavPoint p) {
      for (final n in allNodes) {
        if ((n.navPoint.latitude - p.latitude).abs() < 1e-6 &&
            (n.navPoint.longitude - p.longitude).abs() < 1e-6 &&
            n.navPoint.floor == p.floor) {
          return n;
        }
      }
      return null;
    }

    double segmentDistance = 0.0;
    int currentFloor = path.first.floor;

    int i = 0;
    while (i < path.length - 1) {
      final pCurr = path[i];
      final pNext = path[i + 1];

      // ── 1. DETECT FLOOR CHANGE ─────────────────────────────────────────────
      if (pCurr.floor != pNext.floor) {
        // Flush any accumulated straight walking distance before changing floors
        if (segmentDistance > 1.0) {
          steps.add(DirectionStep(
            instruction: "Walk straight for ${segmentDistance.round()} meters",
            icon: Icons.arrow_upward_rounded,
            distance: segmentDistance,
            floor: currentFloor,
          ));
          segmentDistance = 0.0;
        }

        final node = findNode(pCurr) ?? findNode(pNext);
        final bool isLift = node?.isLift ?? false;
        final bool isStair = node?.isStair ?? false;

        String facility = "stairs or lift";
        IconData transitionIcon = Icons.swap_vert_rounded;
        
        if (isLift) {
          facility = "lift";
          transitionIcon = Icons.elevator_rounded;
        } else if (isStair) {
          facility = "stairs";
          transitionIcon = Icons.stairs_rounded;
        }

        final direction = pNext.floor > pCurr.floor ? "up" : "down";
        steps.add(DirectionStep(
          instruction: "Take the $facility $direction to Floor ${pNext.floor}",
          icon: transitionIcon,
          distance: 0.0,
          floor: pCurr.floor,
        ));

        currentFloor = pNext.floor;
        i++;
        continue;
      }

      // ── 2. ACCUMULATE DISTANCE ─────────────────────────────────────────────
      final d = const Distance().as(
        LengthUnit.Meter,
        LatLng(pCurr.latitude, pCurr.longitude),
        LatLng(pNext.latitude, pNext.longitude),
      );
      segmentDistance += d;

      // ── 3. DETECT ANGLE TURNS AT NEXT NODE ──────────────────────────────────
      if (i < path.length - 2) {
        final pNextNext = path[i + 2];

        // If a floor transition is about to occur next, flush current segment first
        if (pNext.floor != pNextNext.floor) {
          steps.add(DirectionStep(
            instruction: "Walk straight for ${segmentDistance.round()} meters",
            icon: Icons.arrow_upward_rounded,
            distance: segmentDistance,
            floor: currentFloor,
          ));
          segmentDistance = 0.0;
          i++;
          continue;
        }

        // Calculate segment 1 bearing (pCurr -> pNext)
        final double dy1 = pNext.latitude - pCurr.latitude;
        final double dx1 = (pNext.longitude - pCurr.longitude) * cos(pCurr.latitude * pi / 180);
        final double bearing1 = atan2(dy1, dx1) * 180 / pi;

        // Calculate segment 2 bearing (pNext -> pNextNext)
        final double dy2 = pNextNext.latitude - pNext.latitude;
        final double dx2 = (pNextNext.longitude - pNext.longitude) * cos(pNext.latitude * pi / 180);
        final double bearing2 = atan2(dy2, dx2) * 180 / pi;

        // Calculate bearing difference, normalized to [-180, 180]
        double diff = (bearing2 - bearing1 + 180) % 360 - 180;
        if (diff < -180) diff += 360;

        // Turn threshold: change in heading of > 25 degrees
        if (diff.abs() > 25.0) {
          if (segmentDistance > 1.0) {
            steps.add(DirectionStep(
              instruction: "Walk straight for ${segmentDistance.round()} meters",
              icon: Icons.arrow_upward_rounded,
              distance: segmentDistance,
              floor: currentFloor,
            ));
            segmentDistance = 0.0;
          }

          if (diff > 25.0 && diff < 155.0) {
            steps.add(DirectionStep(
              instruction: "Turn right",
              icon: Icons.turn_right_rounded,
              distance: 0.0,
              floor: currentFloor,
            ));
          } else if (diff < -25.0 && diff > -155.0) {
            steps.add(DirectionStep(
              instruction: "Turn left",
              icon: Icons.turn_left_rounded,
              distance: 0.0,
              floor: currentFloor,
            ));
          } else if (diff.abs() >= 155.0) {
            steps.add(DirectionStep(
              instruction: "Make a U-turn",
              icon: Icons.u_turn_right_rounded,
              distance: 0.0,
              floor: currentFloor,
            ));
          }
        }
      }

      i++;
    }

    // Flush any remaining accumulated straight distance
    if (segmentDistance > 1.0) {
      steps.add(DirectionStep(
        instruction: "Walk straight for ${segmentDistance.round()} meters",
        icon: Icons.arrow_upward_rounded,
        distance: segmentDistance,
        floor: currentFloor,
      ));
    }

    // Final Arrival step
    steps.add(DirectionStep(
      instruction: "Arrive at your destination.",
      icon: Icons.check_circle_rounded,
      distance: 0.0,
      floor: path.last.floor,
    ));

    return steps;
  }
}
