import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiFingerprintService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    bool granted = statuses.values.every((status) => status.isGranted);
    return granted;
  }

  Future<Map<String, double>> collectWifiVector({int scanCount = 3}) async {
    Map<String, List<int>> rssiData = {};

    for (int i = 0; i < scanCount; i++) {
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canScan != CanStartScan.yes) {
        throw Exception("Cannot start WiFi scan: $canScan");
      }

      await WiFiScan.instance.startScan();
      
      // Wait for scan to complete (typically takes a few seconds)
      await Future.delayed(const Duration(seconds: 2));

      final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGetResults == CanGetScannedResults.yes) {
        final results = await WiFiScan.instance.getScannedResults();
        for (var network in results) {
          if (!rssiData.containsKey(network.bssid)) {
            rssiData[network.bssid] = [];
          }
          rssiData[network.bssid]!.add(network.level);
        }
      } else {
        throw Exception("Cannot get WiFi scan results: $canGetResults");
      }
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
