import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiFingerprintService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> requestPermissions() async {
    try {
      final status = await Permission.location.request();
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, double>> collectWifiVector({int scanCount = 3}) async {
    Map<String, List<int>> rssiData = {};

    for (int i = 0; i < scanCount; i++) {
      try {
        final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
        if (canScan == CanStartScan.yes) {
          await WiFiScan.instance.startScan();
          // Wait for scan to complete
          await Future.delayed(const Duration(seconds: 2));
        } else {
          // If rate limited or not supported, wait a bit and try to get cached results
          await Future.delayed(const Duration(seconds: 1));
        }

        final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
        if (canGetResults == CanGetScannedResults.yes) {
          final results = await WiFiScan.instance.getScannedResults();
          for (var network in results) {
            if (!rssiData.containsKey(network.bssid)) {
              rssiData[network.bssid] = [];
            }
            rssiData[network.bssid]!.add(network.level);
          }
        }
      } catch (e) {
        // Ignore individual scan errors, continue to the next scan attempt
      }
    }

    if (rssiData.isEmpty) {
      throw Exception("No WiFi networks found. Check if location services are enabled.");
    }

    // Average the RSSI values
    Map<String, double> averagedVector = {};
    rssiData.forEach((bssid, levels) {
      double average = levels.reduce((a, b) => a + b) / levels.length;
      averagedVector[bssid] = average;
    });

    return averagedVector;
  }

  Future<void> saveFingerprint(String roomName, Map<String, double> vector) async {
    await _firestore.collection('wifi_fingerprints').add({
      'roomName': roomName,
      'timestamp': FieldValue.serverTimestamp(),
      'vector': vector,
    });
  }
}
