import 'package:cloud_firestore/cloud_firestore.dart';

class PerfLog {
  final String uid;
  final String date;
  final int productivity;
  final int fatigue;
  final int stress;
  final double hoursOnCampus;
  final Timestamp createdAt;

  PerfLog({
    required this.uid,
    required this.date,
    required this.productivity,
    required this.fatigue,
    required this.stress,
    required this.hoursOnCampus,
    required this.createdAt,
  });

  factory PerfLog.fromMap(Map<String, dynamic> data) {
    return PerfLog(
      uid: data['uid'] ?? '',
      date: data['date'] ?? '',
      productivity: (data['productivity'] ?? 0),
      fatigue: (data['fatigue'] ?? 0),
      stress: (data['stress'] ?? 0),
      hoursOnCampus: (data['hoursOnCampus'] ?? 0).toDouble(),
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }
}
