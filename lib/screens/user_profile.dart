// lib/models/user_profile.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String role;
  final bool isActive;
  final String? displayName;

  UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.isActive,
    this.displayName,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return UserProfile(
      uid: doc.id,
      email: (d['email'] as String?) ?? 'N/A',
      role: (d['role'] as String?) ?? 'user',
      isActive: (d['is_active'] as bool?) ?? true,
      displayName: d['displayName'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'role': role,
        'is_active': isActive,
        if (displayName != null) 'displayName': displayName,
      };
}
