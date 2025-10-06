
import 'dart:async';
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart_plugin_registrant.dart';
import 'screens/faculty_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
const notificationChannelId = 'commute_tracker_foreground';

class ThemeController {
  static const _prefKey = 'is_dark_mode';
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(ThemeMode.light);

  
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_prefKey) ?? false;
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }


  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, mode == ThemeMode.dark);
  }

  
  static Future<void> toggleDark(bool enable) async {
    await setThemeMode(enable ? ThemeMode.dark : ThemeMode.light);
  }
}


// ================== BACKGROUND SERVICE LOGIC ==================
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}

  // 
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Commute Tracker",
      content: "Starting location service...",
    );
  }

  
  Future.microtask(() async {
    Timer? timer;
    StreamSubscription<Position>? positionStream;
    int elapsedSeconds = 0;

    
    service.on('startTracking').listen((event) {
    
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        elapsedSeconds++;
        service.invoke('update', {'type': 'time', 'elapsed_seconds': elapsedSeconds});
      });

      // start location updates
      try {
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 10,
        );
        positionStream?.cancel();
        positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
          service.invoke('update', {
            'type': 'location',
            'lat': position.latitude,
            'lng': position.longitude,
          });
        });
      } catch (e, st) {
        
        service.invoke('update', {'type': 'error', 'message': e.toString()});
      }

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "Commute Tracker",
          content: "Tracking location",
        );
      }
    });

    service.on('stopTracking').listen((event) {
      timer?.cancel();
      positionStream?.cancel();
      service.stopSelf();
    });

    
    service.invoke('ready', {'status': 'ok'});
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: false,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Commute Tracker',
      initialNotificationContent: 'Preparing to track commute...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      autoStart: false,
    ),
  );
}
// =============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();


  await ThemeController.init();


  if (Platform.isAndroid) {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          notificationChannelId,
          'Commute Tracker Service',
          description: 'Notifications for commute tracking',
          importance: Importance.low,
        ));
  }

  await initializeService();

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Commute Tracker',
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            textTheme: GoogleFonts.poppinsTextTheme(),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            textTheme: GoogleFonts.poppinsTextTheme(
              ThemeData(brightness: Brightness.dark).textTheme,
            ),
          ),
          home: const AuthWrapper(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            // add other named routes here if needed
          },
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
      },
    );
  }
}
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
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
            if (role == null || role.isEmpty) {
              return const RegisterScreen();
            }
            if (role == 'admin') {
              return const AdminDashboardScreen();
            } else {
              return FacultyDashboardScreen(userId: user.uid);
            }
          },
        );
      },
    );
  }

  Future<String?> _fetchUserRole(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final role = data['role'];
    return (role is String && role.isNotEmpty) ? role : null;
  }
}
