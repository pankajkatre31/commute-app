import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // YYYY-MM-DD (UTC) for easy grouping
  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Unique trip id so multiple trips in a day don't overwrite
  String newTripId(String userId) {
    final short = const Uuid().v4().split('-').first; // e.g. 'a1b2c3'
    return '${userId}_${_today()}_$short';
  }

  /// Save commute + performance in one doc (no cross-collection join needed)
  Future<void> logCommuteAndPerformance({
    required String userId,
    required Map<String, dynamic> commuteData,
    required Map<String, dynamic> perfData,
  }) async {
    final tripId = newTripId(userId);
    final tripRef = _db.collection('users').doc(userId).collection('trips').doc(tripId);

    await _db.runTransaction((tx) async {
      tx.set(tripRef, {
        'uid': userId,
        'date': _today(), // <- field name is 'date' (no underscore)
        'createdAt': FieldValue.serverTimestamp(),
        'commute': commuteData,        // e.g. start/end, polyline, distance
        'performance': perfData,       // e.g. avg speed, duration, etc.
      });
    });
  }

  /// If you start a trip first and fill later, use this
  Future<void> upsertTrip({
    required String userId,
    required String tripId,
    Map<String, dynamic>? commute,
    Map<String, dynamic>? performance,
    Map<String, dynamic>? extra,
  }) async {
    final tripRef = _db.collection('users').doc(userId).collection('trips').doc(tripId);
    await tripRef.set({
      'uid': userId,
      if (commute != null) 'commute': commute,
      if (performance != null) 'performance': performance,
      if (extra != null) ...?extra,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Current user's trips (latest first)
  Stream<List<Map<String, dynamic>>> getMyCommuteHistory(String userId) {
    return _db
        .collection('users').doc(userId).collection('trips')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// All trips across all users (admin/faculty)
  Stream<List<Map<String, dynamic>>> getAllCommuteHistory() {
    return _db
        .collectionGroup('trips')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)}).toList());
  }

  Future<AppUser?> getUserProfile(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.data()!, uid: userId);
  }

  Stream<List<AppUser>> getAllUsers() {
    return _db.collection('users').snapshots().map(
      (s) => s.docs.map((d) => AppUser.fromMap(d.data(), uid: d.id)).toList(),
    );
  }
}
