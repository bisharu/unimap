import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiPositioningService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Local cache of the radio map
  List<Map<String, dynamic>> _radioMap = [];
  bool _isMapLoaded = false;

  // The penalty RSSI value for missing BSSIDs during distance calculation
  static const double _penaltyRssi = -95.0;

  /// Fetch the calibrated WiFi fingerprints from Firestore and cache them.
  Future<void> fetchRadioMap() async {
    try {
      final querySnapshot = await _firestore.collection('wifi_fingerprints').get();
      _radioMap = querySnapshot.docs.map((doc) {
        final data = doc.data();
        // Convert the dynamic vector map to Map<String, double>
        Map<String, double> vector = {};
        if (data['vector'] != null) {
          (data['vector'] as Map<String, dynamic>).forEach((key, value) {
            vector[key] = (value as num).toDouble();
          });
        }
        return {
          'roomName': data['roomName'],
          'vector': vector,
        };
      }).toList();
      _isMapLoaded = true;
    } catch (e) {
      print('Error fetching radio map: $e');
    }
  }

  /// Perform a single live WiFi scan and return the BSSID->RSSI vector.
  Future<Map<String, double>?> performLiveScan() async {
    try {
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: false);
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        // Give it a brief moment to gather results
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: false);
      if (canGetResults == CanGetScannedResults.yes) {
        final results = await WiFiScan.instance.getScannedResults();
        
        Map<String, double> liveVector = {};
        for (var network in results) {
          liveVector[network.bssid] = network.level.toDouble();
        }
        
        if (liveVector.isNotEmpty) {
          return liveVector;
        }
      }
    } catch (e) {
      print('Error during live WiFi scan: $e');
    }
    return null;
  }

  /// Compare the live vector against the cached radio map using Euclidean distance.
  /// Returns the estimated roomName, or null if no strong match is found.
  String? estimateLocation(Map<String, double> liveVector, {double maxDistanceThreshold = 40.0}) {
    if (!_isMapLoaded || _radioMap.isEmpty) return null;

    String? bestMatchRoom;
    double minDistance = double.infinity;

    for (var entry in _radioMap) {
      final String roomName = entry['roomName'];
      final Map<String, double> dbVector = entry['vector'];

      double distanceSquared = 0.0;
      
      // We need to look at all unique BSSIDs present in either the live vector or the db vector
      Set<String> allBssids = {...liveVector.keys, ...dbVector.keys};

      for (String bssid in allBssids) {
        double liveRssi = liveVector[bssid] ?? _penaltyRssi;
        double dbRssi = dbVector[bssid] ?? _penaltyRssi;

        distanceSquared += pow((liveRssi - dbRssi), 2);
      }

      double distance = sqrt(distanceSquared);

      if (distance < minDistance) {
        minDistance = distance;
        bestMatchRoom = roomName;
      }
    }

    // If the closest match is still too far (e.g. user is in the parking lot), return null
    if (minDistance <= maxDistanceThreshold) {
      return bestMatchRoom;
    }

    return null;
  }
}
