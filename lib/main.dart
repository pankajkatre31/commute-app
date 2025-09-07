import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'screens/faculty_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const AuthWrapper());
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commute Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),

      // Declarative navigation based on auth + Firestore profile
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnap) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Not logged in → LoginScreen
          if (!authSnap.hasData) {
            return const LoginScreen();
          }

          final user = authSnap.data!;
          return FutureBuilder<String?>(
            future: _fetchUserRole(user.uid),
            builder: (context, roleSnap) {
              if (roleSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final role = roleSnap.data;

              // If no profile doc or missing role → RegisterScreen
              if (role == null || role.isEmpty) {
                return const RegisterScreen();
              }

              // Route by role
              if (role == 'admin') {
                return const AdminDashboardScreen();
              } else {
                return FacultyDashboardScreen(userId: user.uid);
              }
            },
          );
        },
      ),

      // Named routes for auth screens
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
      },

      // Safety for accidental direct hits to dashboards
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/admin':
            {
              final current = FirebaseAuth.instance.currentUser;
              if (current == null) {
                return MaterialPageRoute(builder: (_) => const LoginScreen());
              }
              return MaterialPageRoute(
                builder: (_) => const AdminDashboardScreen(),
              );
            }
          case '/faculty':
            {
              final current = FirebaseAuth.instance.currentUser;
              if (current == null) {
                return MaterialPageRoute(builder: (_) => const LoginScreen());
              }
              return MaterialPageRoute(
                builder: (_) => FacultyDashboardScreen(userId: current.uid),
              );
            }
        }
        return null;
      },
    );
  }

  Future<String?> _fetchUserRole(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final role = data['role'];
    return (role is String && role.isNotEmpty) ? role : null;
  }
}
