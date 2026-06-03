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
}
