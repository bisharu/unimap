import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'models.dart';

/// Function to read local GeoJSON room data and upload it to Firestore
/// using the Room model defined in models.dart.
/// Uses batch writes for much faster uploads (up to 500 docs per batch).
Future<void> uploadRoomsToFirestore() async {
  final floors = {0: 'ground', 1: 'floor_1', 2: 'floor_2', 3: 'floor_3', 4: 'floor_4'};
  final firestore = FirebaseFirestore.instance;

  int totalRoomsUploaded = 0;

  // Collect all room data first, then batch-write
  WriteBatch batch = firestore.batch();
  int batchCount = 0;

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
          
          final centroidLat = lat / points.length;
          final centroidLng = lng / points.length;
          
          // Create a unique ID for the document
          final roomId = "room_${floor}_${name.replaceAll(RegExp(r'\s+'), '_')}";

          // Create the Room object using the class diagram model
          final room = Room(
            lId: roomId,
            lName: name,
            x: centroidLat, // Using latitude for X
            y: centroidLng, // Using longitude for Y
            description: properties['description'] ?? 'Room $name on floor $floor',
            rNo: int.tryParse(name.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
            rType: type,
            capacity: properties['capacity'] ?? 0,
            floorNo: floor,
          );

          // Add to batch instead of individual writes
          batch.set(firestore.collection('locations').doc(roomId), room.toMap());
          batchCount++;
          totalRoomsUploaded++;

          // Firestore batch limit is 500 operations
          if (batchCount >= 450) {
            await batch.commit();
            debugPrint("Committed batch of $batchCount rooms.");
            batch = firestore.batch();
            batchCount = 0;
          }
        }
      }
      debugPrint("Processed $fileName data.");
    } catch (e) {
      debugPrint('Error processing data for $fileName: $e');
    }
  }

  // Commit any remaining documents
  if (batchCount > 0) {
    await batch.commit();
    debugPrint("Committed final batch of $batchCount rooms.");
  }
  
  debugPrint("Completed uploading! Total rooms pushed: $totalRoomsUploaded");
}
