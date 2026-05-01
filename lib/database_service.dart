import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── USER DATA ─────────────────────────────────────────────────────────────

  Future<void> saveUser(UniUser user) async {
    await _db.collection('users').doc(user.id).set(user.toMap());
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  // ─── LOCATIONS & ROOMS ─────────────────────────────────────────────────────

  Future<void> saveLocation(UniLocation location) async {
    await _db.collection('locations').doc(location.lId).set(location.toMap());
  }

  // Retrieves all locations, including rooms (polymorphic)
  Stream<List<UniLocation>> streamLocations() {
    return _db.collection('locations').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => UniLocation.fromFirestore(doc)).toList());
  }

  // ─── PATHS ─────────────────────────────────────────────────────────────────

  Future<void> savePath(UniPath path) async {
    await _db.collection('paths').doc(path.pId.toString()).set(path.toMap());
  }

  Stream<List<UniPath>> streamPaths() {
    return _db.collection('paths').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => UniPath.fromFirestore(doc)).toList());
  }

  // ─── SPECIFIC QUERIES ──────────────────────────────────────────────────────

  // Example: Find a room by its number
  Future<Room?> findRoomByNumber(int roomNumber) async {
    final query = await _db
        .collection('locations')
        .where('isRoom', isEqualTo: true)
        .where('r_no', isEqualTo: roomNumber)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return UniLocation.fromFirestore(query.docs.first) as Room;
    }
    return null;
  }
}
