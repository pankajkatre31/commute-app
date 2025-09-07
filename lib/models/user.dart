import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String department;
  final String designation;
  final String role;
  final Timestamp createdAt;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.department,
    required this.designation,
    required this.role,
    required this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> data, {required String uid}) {
    return AppUser(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      department: data['department'] ?? '',
      designation: data['designation'] ?? '',
      role: data['role'] ?? 'faculty',
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }
}
