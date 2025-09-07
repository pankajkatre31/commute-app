// faculty_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'add_commute_log_screen.dart';
import 'package:commute_app/screens/commute_map_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
// top of faculty_dashboard_screen.dart
import 'package:commute_app/models/commute_log.dart';
import 'package:commute_app/widgets/inline_map_tracker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // for LatLng

class CommuteStats {
  final int totalTrips;
  final double totalDistance;
  final double avgProductivity;
  final double totalCost;
  final double totalCarbon;
  final double avgFatigue;
  final double avgStress;
  final double avgPhysicalActivity;

  const CommuteStats({
    required this.totalTrips,
    required this.totalDistance,
    required this.avgProductivity,
    required this.totalCost,
    required this.totalCarbon,
    required this.avgFatigue,
    required this.avgStress,
    required this.avgPhysicalActivity,
  });
}

// ---------------------------------
// B. CONSTANTS & THEMES
// ---------------------------------

final Map<String, IconData> modeIcons = {
  'walk': Icons.directions_walk,
  'cycle': Icons.directions_bike,
  'motorbike': Icons.two_wheeler,
  'car': Icons.directions_car,
  'bus': Icons.directions_bus,
  'train': Icons.train,
  'other': Icons.more_horiz,
};

final Map<String, Color> modeColors = {
  'walk': Colors.green.shade600,
  'cycle': Colors.lightGreen.shade600,
  'motorbike': Colors.orange.shade600,
  'car': Colors.red.shade600,
  'bus': Colors.blue.shade600,
  'train': Colors.indigo.shade600,
  'other': Colors.grey.shade600,
};

// ---------------------------------
// C. WIDGET LOGIC & UI
// ---------------------------------

class FacultyDashboardScreen extends StatefulWidget {
  final String userId;
  const FacultyDashboardScreen({super.key, required this.userId});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _distanceController = TextEditingController();
  final _productivityController = TextEditingController();
  final _costController = TextEditingController();
  final _durationController = TextEditingController();
  final _fatigueController = TextEditingController();
  final _stressController = TextEditingController();

  String _selectedMode = 'walk';
  DateTime _selectedDate = DateTime.now();
  bool _isSubmitting = false;
  bool _showAdvancedFields = false;
  bool _screenLocked = false;
  String _dateRange = '30';
  String _modeFilter = 'all';
  DateTimeRange? _customDateRange;

  late TabController _tabController;
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;

  final List<String> _transportModes = [
    'walk',
    'cycle',
    'motorbike',
    'car',
    'bus',
    'train',
    'other',
  ];

  // --- ADDED: route/tracking state used by InlineMapTracker ---
  LatLng? _start;
  LatLng? _end;
  List<LatLng> _routePoints = [];
  double? _distanceKm;
  bool _showTripDetails = false;
  bool _isTracking = false;
  int? _durationSeconds;
// helper to format seconds -> HH:MM:SS
String _formatSecondsToHms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );

    _tabController.addListener(() {
      if (_tabController.index == 0) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    });

    _fabAnimationController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fabAnimationController.dispose();
    _distanceController.dispose();
    _productivityController.dispose();
    _costController.dispose();
    _durationController.dispose();
    _fatigueController.dispose();
    _stressController.dispose();
    super.dispose();
  }

  Future<void> _submitLog() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

  try {
  // Basic sanity checks
  if (_distanceController.text.trim().isEmpty) {
    _showErrorMessage('Please provide distance before saving the log.');
    return;
  }
  if (_productivityController.text.trim().isEmpty) {
    _showErrorMessage('Please provide a productivity score before saving the log.');
    return;
  }

  final distanceKm = double.tryParse(_distanceController.text);
  final productivityScore = double.tryParse(_productivityController.text);

  if (distanceKm == null || productivityScore == null) {
    _showErrorMessage('Distance or productivity score is invalid.');
    return;
  }

  final logData = {
    'userId': widget.userId,
    'date': Timestamp.fromDate(
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
    ),
    'mode': _selectedMode,
    'distanceKm': distanceKm,
    'productivityScore': productivityScore,
    'durationMinutes':
        _durationController.text.isNotEmpty ? int.tryParse(_durationController.text) : null,
    'durationSeconds': _durationSeconds, // authoritative exact seconds (may be null)
    'cost': _costController.text.isNotEmpty ? double.tryParse(_costController.text) : null,
    'fatigueLevel':
        _fatigueController.text.isNotEmpty ? double.tryParse(_fatigueController.text) : null,
    'stressLevel':
        _stressController.text.isNotEmpty ? double.tryParse(_stressController.text) : null,
    'startLocation': _start != null ? {'lat': _start!.latitude, 'lng': _start!.longitude} : null,
    'endLocation': _end != null ? {'lat': _end!.latitude, 'lng': _end!.longitude} : null,
    'checkpoints': _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    'distanceComputedKm': _distanceKm,
    'createdAt': FieldValue.serverTimestamp(),
  };


      await FirebaseFirestore.instance.collection('commute_logs').add(logData);
      _showSuccessMessage('Commute log saved successfully!');
      _resetForm();
    } catch (e) {
      _showErrorMessage('Failed to save log: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
void _resetForm() {
  _distanceController.clear();
  _productivityController.clear();
  _costController.clear();
  _durationController.clear();
  _fatigueController.clear();
  _stressController.clear();
  setState(() {
    _selectedMode = 'walk';
    _selectedDate = DateTime.now();
    _showAdvancedFields = false;
    _start = null;
    _end = null;
    _routePoints = [];
    _distanceKm = null;
    _showTripDetails = false;
    _durationSeconds = null; // reset authoritative seconds
  });
}

Future<void> _showTripReviewSheet({
  required LatLng start,
  required LatLng end,
  required List<LatLng> routePoints,
  required double distanceKm,
  
}) async {
  // Pre-fill distance
  _distanceController.text = distanceKm.toStringAsFixed(2);

  // Local controllers for the sheet (start with main controllers' values)
  final TextEditingController tmpProductivity = TextEditingController(text: _productivityController.text);
  final TextEditingController tmpDuration = TextEditingController(text: _durationController.text);
  final TextEditingController tmpCost = TextEditingController(text: _costController.text);
  final TextEditingController tmpFatigue = TextEditingController(text: _fatigueController.text);
  final TextEditingController tmpStress = TextEditingController(text: _stressController.text);

  // New controllers for the walk/cycle extra questions
  final TextEditingController tmpMood = TextEditingController();
  final TextEditingController tmpTrack = TextEditingController();
  final TextEditingController tmpWeather = TextEditingController();

  // Use the mode that was selected BEFORE starting the trip (from your screen state)
  String chosenMode = _selectedMode;

  // Field visibility helpers
  bool showCost() =>
      (chosenMode == 'motorbike' || chosenMode == 'car' || chosenMode == 'bus' || chosenMode == 'train' || chosenMode == 'other');
  bool showFatigueStress() =>
      (chosenMode == 'walk' || chosenMode == 'cycle' || chosenMode == 'motorbike' || chosenMode == 'car' || chosenMode == 'other');
  bool showDuration() => true;
  bool showProductivity() => true;
  bool showWalkCycleExtras() => (chosenMode == 'walk' || chosenMode == 'cycle');

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Trip review', style: GoogleFonts.poppins(textStyle: Theme.of(context).textTheme.titleLarge)),
                const SizedBox(height: 8),
                Text('Distance: ${distanceKm.toStringAsFixed(2)} km', style: GoogleFonts.poppins()),
                const SizedBox(height: 12),

                // Show chosen mode (no chips to change it)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: modeColors[chosenMode]?.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: modeColors[chosenMode] ?? Colors.grey),
                      ),
                      child: Row(
                        children: [
                          Icon(modeIcons[chosenMode], color: modeColors[chosenMode]),
                          const SizedBox(width: 8),
                          Text(chosenMode.toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Mode selected before trip', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),

                const SizedBox(height: 18),

                StatefulBuilder(builder: (context, setModalState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showProductivity()) ...[
                        Text('Productivity Score (0-10)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpProductivity,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 7.5',
                            prefixIcon: Icon(Icons.trending_up),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
      if (showDuration()) ...[
  Text('Duration (HH:MM:SS)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
  const SizedBox(height: 6),
  TextFormField(
    controller: TextEditingController(
      text: _durationSeconds != null
          ? _formatSecondsToHms(_durationSeconds!)
          : (tmpDuration.text.isNotEmpty ? tmpDuration.text : ''),
    ),
    readOnly: true,
    decoration: const InputDecoration(
      prefixIcon: Icon(Icons.access_time),
    ),
  ),
  const SizedBox(height: 12),
],
                      if (showCost()) ...[
                        Text('Cost (₹)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpCost,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 40.5',
                            prefixIcon: Icon(Icons.currency_rupee),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (showWalkCycleExtras()) ...[
                        // Mood
                        Text('How was your mood?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpMood,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Happy, calm, stressed',
                            prefixIcon: Icon(Icons.emoji_emotions_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Track (route description)
                        Text('What was the track?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpTrack,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Short route via river road, lots of traffic',
                            prefixIcon: Icon(Icons.alt_route_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Weather
                        Text('How was the weather?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpWeather,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Sunny, cloudy, rainy',
                            prefixIcon: Icon(Icons.wb_sunny_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (showFatigueStress()) ...[
                        Text('Fatigue Level (0-10)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpFatigue,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 3.0',
                            prefixIcon: Icon(Icons.battery_alert),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text('Stress Level (0-10)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: tmpStress,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 2.0',
                            prefixIcon: Icon(Icons.psychology),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context); // cancel
                              },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                // copy modal values back to screen-level controllers/state
                                setState(() {
                                  _selectedMode = chosenMode;
                                  _productivityController.text = tmpProductivity.text;
                                  _durationController.text = tmpDuration.text;
                                  _costController.text = tmpCost.text;
                                  _fatigueController.text = tmpFatigue.text;
                                  _stressController.text = tmpStress.text;
                                  _distanceController.text = distanceKm.toStringAsFixed(2);

                                  // store walk/cycle extras into new state fields (or reuse controllers)
                                  // We'll reuse controllers by saving text into them (or you may add dedicated variables)
                                });
 // dispose temporary controllers
  tmpProductivity.dispose();
  tmpDuration.dispose();
  tmpCost.dispose();
  tmpFatigue.dispose();
  tmpStress.dispose();
  tmpMood.dispose();
  tmpTrack.dispose();
  tmpWeather.dispose();

  Navigator.pop(context);
  await _submitLog();
},
                                // Optionally save extras into Firestore via _submitLog
                                // To save mood/track/weather, update _submitLog to include these fields
                                
                              child: const Text('Save Log'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      );
    },
  );
}



  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        _showErrorMessage('Failed to sign out: ${e.toString()}');
      }
    }
  }

  Stream<List<CommuteLog>> _getLogsStream({bool allUsers = false}) {
    Query<Map<String, dynamic>> query;

    // if you saved logs in 'commute_logs' as a flat collection:
    query = FirebaseFirestore.instance.collection('commute_logs').orderBy('date', descending: true);

    // If you saved logs under users/{uid}/trips, use collectionGroup:
    // query = FirebaseFirestore.instance.collectionGroup('trips').orderBy('date', descending: true);

    if (!allUsers) {
      // show only current user's logs
      query = query.where('userId', isEqualTo: widget.userId);
    }

    // date range / custom range filtering
    if (_customDateRange != null) {
      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_customDateRange!.start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_customDateRange!.end));
    } else if (_dateRange != 'all') {
      final days = int.tryParse(_dateRange) ?? 30;
      final startDate = DateTime.now().subtract(Duration(days: days));
      query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }

    return query.snapshots().map((snapshot) {
      print('DEBUG: commute_logs snapshot count: ${snapshot.docs.length}');
      var logs = snapshot.docs.map((doc) => CommuteLog.fromFirestore(doc)).toList();
      if (_modeFilter != 'all') {
        logs = logs.where((log) => log.mode == _modeFilter).toList();
      }
      return logs;
    });
  }

  // -----------------------
  // New helper that composes InlineMapTracker + add form
// Replace the whole _buildAddLogTabWithTracker() with this:
Widget _buildAddLogTabWithTracker() {
  return Stack(
    children: [
      Column(
        children: [
    InlineMapTracker(
  height: 300,
  onTripStarted: () {
    setState(() {
      _isTracking = true;
      _screenLocked = false;
    });
  },
  onTripEnded: () {
    setState(() {
      _isTracking = false;
      _screenLocked = false;
    });
  },
  onRouteFinished: ({
    required LatLng start,
    required LatLng end,
    required List<LatLng> routePoints,
    required double distanceKm,
    required int durationSeconds,
  }) {
    // save authoritative values into state
    setState(() {
      _start = start;
      _end = end;
      _routePoints = routePoints;
      _distanceKm = distanceKm;
      _showTripDetails = true;
      _isTracking = false;
      _durationSeconds = durationSeconds; // <-- set state field (not local var)
    });

    // fill distance controller (display in km)
    _distanceController.text = distanceKm.toStringAsFixed(2);

    // optional: put numeric seconds in durationController for backward compatibility (not editable authoritative)
    _durationController.text = durationSeconds.toString();

    // show review modal (it will display read-only HH:MM:SS from _durationSeconds)
    _showTripReviewSheet(
      start: start,
      end: end,
      routePoints: routePoints,
      distanceKm: distanceKm,
    );
  },
),


          const SizedBox(height: 12),

          // The inputs/form area below the map
          Expanded(
            child: AbsorbPointer(
              // AbsorbPointer here will block the form when _screenLocked is true.
              absorbing: _screenLocked,
              child: _AddLogTab(
                formKey: _formKey,
                distanceController: _distanceController,
                productivityController: _productivityController,
                costController: _costController,
                durationController: _durationController,
                fatigueController: _fatigueController,
                stressController: _stressController,
                selectedMode: _selectedMode,
                onModeChanged: (mode) => setState(() => _selectedMode = mode),
                selectedDate: _selectedDate,
                onDateSelected: (date) => setState(() => _selectedDate = date),
                showAdvancedFields: _showAdvancedFields,
                onToggleAdvanced: (value) => setState(() => _showAdvancedFields = value),
                transportModes: _transportModes,
              ),
            ),
          ),
        ],
      ),

      // Dim overlay when screen is locked — placed before lock button so lock still receives taps
      if (_screenLocked)
        const Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.black54,
          ),
        ),

      // Lock/Unlock button: shown only when tracking
      if (_isTracking)
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: "lockBtn",
            backgroundColor: _screenLocked ? Colors.red : Colors.green,
            onPressed: () {
              debugPrint('Lock FAB tapped — toggling _screenLocked (was: $_screenLocked)');
              setState(() => _screenLocked = !_screenLocked);
            },
            child: Icon(_screenLocked ? Icons.lock : Icons.lock_open),
          ),
        ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Faculty Dashboard',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            Text(
              'Welcome back!',
              style: GoogleFonts.poppins(
                textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Export Data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        userId: widget.userId,
                        userEmail: FirebaseAuth.instance.currentUser?.email,
                      ),
                    ),
                  );
                  break;
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                  break;
                case 'signout':
                  _signOut();
                  break;
                case 'export':
                  _exportData();
                  break;
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.poppins(),
          tabs: const [
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Add Log'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Analytics'),
            Tab(icon: Icon(Icons.eco_outlined), text: 'Sustainability'),
            Tab(icon: Icon(Icons.list_alt), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAddLogTabWithTracker(),
          _buildAnalyticsTab(),
          _buildSustainabilityTab(),
          _buildHistoryTab(),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimation,
        child: FloatingActionButton.extended(
          onPressed: _isSubmitting ? null : _submitLog,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_isSubmitting ? 'Saving...' : 'Save Log'),
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return StreamBuilder<List<CommuteLog>>(
      stream: _getLogsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return const _EmptyState(
            icon: Icons.analytics_outlined,
            title: 'No data available',
            subtitle: 'Start logging your commutes to see analytics',
          );
        }
        return _AnalyticsContent(logs: logs);
      },
    );
  }

  Widget _buildSustainabilityTab() {
    return StreamBuilder<List<CommuteLog>>(
      stream: _getLogsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return const _EmptyState(
            icon: Icons.eco_outlined,
            title: 'No sustainability data',
            subtitle: 'Log your commutes to track environmental impact',
          );
        }
        return _SustainabilityContent(logs: logs);
      },
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        _HistoryFilters(
          dateRange: _dateRange,
          onDateRangeChanged: (value) => setState(() => _dateRange = value ?? _dateRange),
          modeFilter: _modeFilter,
          onModeFilterChanged: (value) => setState(() => _modeFilter = value ?? _modeFilter),
          transportModes: _transportModes,
        ),
        Expanded(
          child: StreamBuilder<List<CommuteLog>>(
            stream: _getLogsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return const _EmptyState(
                  icon: Icons.history,
                  title: 'No commute history',
                  subtitle: 'Your logged commutes will appear here',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _LogTile(
                  log: logs[index],
                  onTap: () => _showLogDetails(logs[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showLogDetails(CommuteLog log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _LogDetailsSheet(log: log, onDelete: _deleteLog),
    );
  }

  Future<void> _deleteLog(CommuteLog log) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Log'),
        content: const Text(
          'Are you sure you want to delete this commute log?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true && log.id != null) {
      try {
        await FirebaseFirestore.instance.collection('commute_logs').doc(log.id!).delete();
        _showSuccessMessage('Log deleted successfully');
      } catch (e) {
        _showErrorMessage('Failed to delete log: ${e.toString()}');
      }
    }
  }

  Future<void> _exportData() async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      _showErrorMessage('Permission to access storage was denied.');
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting data...')));

      final logs = await _getLogsStream().first;
      if (logs.isEmpty) {
        _showSuccessMessage('No data to export.');
        return;
      }

      List<List<dynamic>> csvData = [
        [
          'date',
          'mode',
          'distanceKm',
          'productivityScore',
          'durationMinutes',
          'cost',
          'fatigueLevel',
          'stressLevel',
          'createdAt',
        ],
      ];
      for (var log in logs) {
        // compute a safe createdAt DateTime for export
DateTime createdAtDt;
if (log.createdAt == null) {
  createdAtDt = DateTime.now();
} else if (log.createdAt is DateTime) {
  createdAtDt = log.createdAt as DateTime;
} else {
  // Firestore Timestamp -> convert
  try {
    createdAtDt = (log.createdAt as dynamic).toDate() as DateTime;
  } catch (_) {
    createdAtDt = DateTime.now();
  }
}
csvData.add([
  DateFormat('yyyy-MM-dd').format(log.date),
  log.mode,
  log.distanceKm,
  log.productivityScore,
  log.durationMinutes ?? '',
  log.cost ?? '',
  log.fatigueLevel ?? '',
  log.stressLevel ?? '',
  DateFormat('yyyy-MM-ddTHH:mm:ss').format(createdAtDt),
]);
      }

      String csv = const ListToCsvConverter().convert(csvData);
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;
      final file = File('$path/commute_logs.csv');
      await file.writeAsString(csv);
      _showSuccessMessage('Data exported to ${file.path}');
    } catch (e) {
      _showErrorMessage('Export failed: ${e.toString()}');
    }
  }
}

// ---------------------------------
// D. REUSABLE WIDGETS
// ---------------------------------

class _AddLogTab extends StatelessWidget {
  const _AddLogTab({
    required this.formKey,
    required this.distanceController,
    required this.productivityController,
    required this.costController,
    required this.durationController,
    required this.fatigueController,
    required this.stressController,
    required this.selectedMode,
    required this.onModeChanged,
    required this.selectedDate,
    required this.onDateSelected,
    required this.showAdvancedFields,
    required this.onToggleAdvanced,
    required this.transportModes,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController distanceController;
  final TextEditingController productivityController;
  final TextEditingController costController;
  final TextEditingController durationController;
  final TextEditingController fatigueController;
  final TextEditingController stressController;
  final String selectedMode;
  final void Function(String) onModeChanged;
  final DateTime selectedDate;
  final void Function(DateTime) onDateSelected;
  final bool showAdvancedFields;
  final void Function(bool) onToggleAdvanced;
  final List<String> transportModes;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transport Mode',
                    style: GoogleFonts.poppins(
                      textStyle: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: transportModes.map((mode) {
                      final isSelected = selectedMode == mode;
                      return FilterChip(
                        selected: isSelected,
                        label: Text(mode.toUpperCase()),
                        avatar: Icon(
                          modeIcons[mode],
                          size: 18,
                          color: isSelected ? Colors.white : modeColors[mode],
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            onModeChanged(mode);
                          }
                        },
                        selectedColor: modeColors[mode],
                        checkmarkColor: Colors.white,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Additional Details'),
                  subtitle: const Text('Optional fields for detailed tracking'),
                  trailing: Switch(
                    value: showAdvancedFields,
                    onChanged: onToggleAdvanced,
                  ),
                ),
                if (showAdvancedFields)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Divider(),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: durationController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duration (minutes)',
                            prefixIcon: Icon(Icons.access_time),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: costController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cost (₹)',
                            prefixIcon: Icon(Icons.currency_rupee),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: fatigueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Fatigue Level (0-10)',
                            prefixIcon: Icon(Icons.battery_alert),
                            helperText: '0 = No fatigue, 10 = Extremely tired',
                          ),
                          validator: (value) {
                            if (value?.isNotEmpty == true) {
                              final level = double.tryParse(value!);
                              if (level == null || level < 0 || level > 10) {
                                return 'Enter a level between 0 and 10';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: stressController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Stress Level (0-10)',
                            prefixIcon: Icon(Icons.psychology),
                            helperText: '0 = No stress, 10 = Extremely stressed',
                          ),
                          validator: (value) {
                            if (value?.isNotEmpty == true) {
                              final level = double.tryParse(value!);
                              if (level == null || level < 0 || level > 10) {
                                return 'Enter a level between 0 and 10';
                              }
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  final List<CommuteLog> logs;

  const _AnalyticsContent({required this.logs});

  CommuteStats _calculateStats(List<CommuteLog> logs) {
    if (logs.isEmpty) {
      return const CommuteStats(
        totalTrips: 0,
        totalDistance: 0,
        avgProductivity: 0,
        totalCost: 0,
        totalCarbon: 0,
        avgFatigue: 0,
        avgStress: 0,
        avgPhysicalActivity: 0,
      );
    }
    final totalDistance = logs.fold<double>(
      0,
      (sum, log) => sum + log.distanceKm,
    );
    final totalProductivity = logs.fold<double>(
      0,
      (sum, log) => sum + log.productivityScore,
    );
    final totalCost = logs.fold<double>(0, (sum, log) => sum + (log.cost ?? 0));
    final totalCarbon = logs.fold<double>(
      0,
      (sum, log) => sum + _calculateCarbonForLog(log),
    );
    final totalFatigue = logs.fold<double>(
      0,
      (sum, log) => sum + (log.fatigueLevel ?? 0),
    );
    final totalStress = logs.fold<double>(
      0,
      (sum, log) => sum + (log.stressLevel ?? 0),
    );
    final totalPhysicalActivity = logs.fold<double>(
      0,
      (sum, log) => sum + (log.physicalActivity ?? 0),
    );

    return CommuteStats(
      totalTrips: logs.length,
      totalDistance: totalDistance,
      avgProductivity: totalProductivity / logs.length,
      totalCost: totalCost,
      totalCarbon: totalCarbon,
      avgFatigue: totalFatigue / logs.length,
      avgStress: totalStress / logs.length,
      avgPhysicalActivity: totalPhysicalActivity / logs.length,
    );
  }

  double _calculateCarbonForLog(CommuteLog log) {
    const Map<String, double> emissionFactors = {
      'walk': 0.0,
      'cycle': 0.0,
      'motorbike': 0.113,
      'car': 0.171,
      'bus': 0.089,
      'train': 0.041,
      'other': 0.1,
    };
    return (emissionFactors[log.mode] ?? 0.1) * log.distanceKm;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats(logs);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KeyMetricsCard(stats: stats),
        const SizedBox(height: 16),
        _ProductivityChart(logs: logs),
        const SizedBox(height: 16),
        _ModeDistributionChart(logs: logs),
        const SizedBox(height: 16),
        _TrendAnalysisCard(logs: logs),
      ],
    );
  }
}

class _KeyMetricsCard extends StatelessWidget {
  final CommuteStats stats;

  const _KeyMetricsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key Metrics',
              style: GoogleFonts.poppins(
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _MetricTile(
                  'Total Trips',
                  '${stats.totalTrips}',
                  Icons.trip_origin,
                ),
                _MetricTile(
                  'Total Distance',
                  '${stats.totalDistance.toStringAsFixed(1)} km',
                  Icons.straighten,
                ),
                _MetricTile(
                  'Avg Productivity',
                  '${stats.avgProductivity.toStringAsFixed(1)}/10',
                  Icons.trending_up,
                ),
                _MetricTile(
                  'Total Cost',
                  '₹${stats.totalCost.toStringAsFixed(0)}',
                  Icons.currency_rupee,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricTile(this.title, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    textStyle: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductivityChart extends StatelessWidget {
  final List<CommuteLog> logs;

  const _ProductivityChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.length < 2) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productivity Trend',
              style: GoogleFonts.poppins(
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget:
                            (value, meta) => Text(value.toInt().toString()),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < logs.length) {
                            return Text(
                              DateFormat('dd/MM').format(logs[index].date),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: logs.length.toDouble() - 1,
                  minY: 0,
                  maxY: 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots:
                          logs.asMap().entries.map((entry) {
                            return FlSpot(
                              entry.key.toDouble(),
                              entry.value.productivityScore,
                            );
                          }).toList(),
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeDistributionChart extends StatelessWidget {
  final List<CommuteLog> logs;

  const _ModeDistributionChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    final modeStats = <String, int>{};
    for (final log in logs) {
      modeStats[log.mode] = (modeStats[log.mode] ?? 0) + 1;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transport Mode Distribution',
              style: GoogleFonts.poppins(
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections:
                      modeStats.entries.map((entry) {
                        final percentage = (entry.value / logs.length) * 100;
                        return PieChartSectionData(
                          color: modeColors[entry.key] ?? Colors.grey,
                          value: entry.value.toDouble(),
                          title: '${percentage.toStringAsFixed(1)}%',
                          radius: 60,
                          titleStyle: GoogleFonts.poppins(
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children:
                  modeStats.entries.map((entry) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: modeColors[entry.key],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('${entry.key}: ${entry.value}'),
                      ],
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendAnalysisCard extends StatelessWidget {
  final List<CommuteLog> logs;

  const _TrendAnalysisCard({required this.logs});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final thisWeekLogs =
        logs.where((log) => log.date.isAfter(weekStart)).toList();

    final lastWeekStart = now.subtract(Duration(days: now.weekday + 6));
    final lastWeekEnd = now.subtract(Duration(days: now.weekday));
    final lastWeekLogs =
        logs
            .where(
              (log) =>
                  log.date.isAfter(lastWeekStart) &&
                  log.date.isBefore(lastWeekEnd),
            )
            .toList();

    final thisWeekAvg =
        thisWeekLogs.isEmpty
            ? 0.0
            : thisWeekLogs
                    .map((l) => l.productivityScore)
                    .reduce((a, b) => a + b) /
                thisWeekLogs.length;
    final lastWeekAvg =
        lastWeekLogs.isEmpty
            ? 0.0
            : lastWeekLogs
                    .map((l) => l.productivityScore)
                    .reduce((a, b) => a + b) /
                lastWeekLogs.length;

    final trend = thisWeekAvg - lastWeekAvg;
    final trendIcon =
        trend > 0
            ? Icons.trending_up
            : trend < 0
            ? Icons.trending_down
            : Icons.trending_flat;
    final trendColor =
        trend > 0
            ? Colors.green
            : trend < 0
            ? Colors.red
            : Colors.grey;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Trend Analysis',
              style: GoogleFonts.poppins(
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TrendTile(
                    'This Week',
                    thisWeekAvg.toStringAsFixed(1),
                    '${thisWeekLogs.length} trips',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TrendTile(
                    'Last Week',
                    lastWeekAvg.toStringAsFixed(1),
                    '${lastWeekLogs.length} trips',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: trendColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Icon(trendIcon, color: trendColor, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          '${trend.abs().toStringAsFixed(1)}',
                          style: GoogleFonts.poppins(
                            textStyle: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: trendColor,
                            ),
                          ),
                        ),
                        Text(
                          'Change',
                          style: GoogleFonts.poppins(
                            textStyle: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _TrendTile(this.title, this.value, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.poppins(
              textStyle: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              textStyle: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SustainabilityContent extends StatelessWidget {
  final List<CommuteLog> logs;

  const _SustainabilityContent({required this.logs});

  double _calculateCarbonFootprint(List<CommuteLog> logs) {
    return logs.fold<double>(
      0,
      (sum, log) => sum + _calculateCarbonForLog(log),
    );
  }

  double _calculateCarbonForLog(CommuteLog log) {
    const Map<String, double> emissionFactors = {
      'walk': 0.0,
      'cycle': 0.0,
      'motorbike': 0.113,
      'car': 0.171,
      'bus': 0.089,
      'train': 0.041,
      'other': 0.1,
    };
    return (emissionFactors[log.mode] ?? 0.1) * log.distanceKm;
  }

  @override
  Widget build(BuildContext context) {
    final carbonFootprint = _calculateCarbonFootprint(logs);
    final carbonByMode = <String, double>{};
    for (final log in logs) {
      final carbon = _calculateCarbonForLog(log);
      carbonByMode[log.mode] = (carbonByMode[log.mode] ?? 0) + carbon;
    }
    final suggestions = <String>[];
    final carLogs = logs.where((l) => l.mode == 'car').length;
    final walkCycleLogs =
        logs.where((l) => l.mode == 'walk' || l.mode == 'cycle').length;
    if (carLogs > walkCycleLogs) {
      suggestions.add('Consider walking or cycling for short distances');
    }
    final publicTransportLogs =
        logs.where((l) => l.mode == 'bus' || l.mode == 'train').length;
    if (publicTransportLogs < carLogs) {
      suggestions.add('Use public transport to reduce carbon footprint');
    }
    if (suggestions.isEmpty) {
      suggestions.add('Great job! You\'re making eco-friendly choices');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.eco, size: 48, color: Colors.green[700]),
                const SizedBox(height: 12),
                Text(
                  'Carbon Footprint',
                  style: GoogleFonts.poppins(
                    textStyle: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${carbonFootprint.toStringAsFixed(2)} kg CO₂',
                  style: GoogleFonts.poppins(
                    textStyle: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total emissions from commuting',
                  style: GoogleFonts.poppins(
                    textStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.green[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Eco-friendly Suggestions',
                      style: GoogleFonts.poppins(
                        textStyle: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: Colors.green[700]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...suggestions.map(
                  (suggestion) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(suggestion, style: GoogleFonts.poppins()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Carbon Footprint by Transport Mode',
                  style: GoogleFonts.poppins(
                    textStyle: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 16),
                ...carbonByMode.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          modeIcons[entry.key],
                          color: modeColors[entry.key],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.key.toUpperCase(),
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                        Text(
                          '${entry.value.toStringAsFixed(2)} kg CO₂',
                          style: GoogleFonts.poppins(
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryFilters extends StatelessWidget {
  const _HistoryFilters({
    required this.dateRange,
    required this.onDateRangeChanged,
    required this.modeFilter,
    required this.onModeFilterChanged,
    required this.transportModes,
  });

  final String dateRange;
  final void Function(String?) onDateRangeChanged;
  final String modeFilter;
  final void Function(String?) onModeFilterChanged;
  final List<String> transportModes;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // each control tries to use ~48% on narrow screens, or 260 on wide screens
    final controlWidth = width >= 600 ? 260.0 : (width * 0.48);

    return Padding(
      padding: const EdgeInsets.all(16),
      // Wrap lets controls flow to next line instead of overflowing
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: controlWidth,
            child: DropdownButtonFormField<String>(
              isExpanded: true, // important so the button can shrink
              value: dateRange,
              decoration: const InputDecoration(
                labelText: 'Date Range',
                prefixIcon: Icon(Icons.date_range),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: '7', child: Text('Last 7 days')),
                DropdownMenuItem(value: '30', child: Text('Last 30 days')),
                DropdownMenuItem(value: '90', child: Text('Last 3 months')),
                DropdownMenuItem(value: 'all', child: Text('All time')),
              ],
              onChanged: onDateRangeChanged,
            ),
          ),
          SizedBox(
            width: controlWidth,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: modeFilter,
              decoration: const InputDecoration(
                labelText: 'Transport Mode',
                prefixIcon: Icon(Icons.directions),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All modes')),
                ...transportModes.map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(mode.toUpperCase()),
                  ),
                ),
              ],
              onChanged: onModeFilterChanged,
            ),
          ),
          // optional small actions — constrained so they never force overflow
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, maxWidth: 80),
            child: ElevatedButton(
              onPressed: () {},
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.onTap});

  final CommuteLog log;
  final VoidCallback onTap;

  double _calculateCarbonForLog(CommuteLog log) {
    const Map<String, double> emissionFactors = {
      'walk': 0.0,
      'cycle': 0.0,
      'motorbike': 0.113,
      'car': 0.171,
      'bus': 0.089,
      'train': 0.041,
      'other': 0.1,
    };
    return (emissionFactors[log.mode] ?? 0.1) * log.distanceKm;
  }

  @override
  Widget build(BuildContext context) {
    final carbon = _calculateCarbonForLog(log);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: modeColors[log.mode]?.withOpacity(0.1),
          child: Icon(modeIcons[log.mode], color: modeColors[log.mode]),
        ),
        title: Text(
          '${log.mode.toUpperCase()} • ${log.distanceKm.toStringAsFixed(1)} km',
          style: GoogleFonts.poppins(
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy').format(log.date)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.eco, size: 12, color: Colors.green[600]),
                const SizedBox(width: 4),
                Text(
                  '${carbon.toStringAsFixed(2)} kg CO₂',
                  style: GoogleFonts.poppins(
                    textStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.green[600],
                    ),
                  ),
                ),
                if (log.cost != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.currency_rupee, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '₹${log.cost!.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(
                      textStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Productivity',
              style: GoogleFonts.poppins(
                textStyle: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
            Text(
              '${log.productivityScore.toStringAsFixed(1)}/10',
              style: GoogleFonts.poppins(
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogDetailsSheet extends StatelessWidget {
  final CommuteLog log;
  final void Function(CommuteLog) onDelete;

  const _LogDetailsSheet({required this.log, required this.onDelete});

  double _calculateCarbonForLog(CommuteLog log) {
    const Map<String, double> emissionFactors = {
      'walk': 0.0,
      'cycle': 0.0,
      'motorbike': 0.113,
      'car': 0.171,
      'bus': 0.089,
      'train': 0.041,
      'other': 0.1,
    };
    return (emissionFactors[log.mode] ?? 0.1) * log.distanceKm;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder:
          (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: modeColors[log.mode]?.withOpacity(0.1),
                    child: Icon(
                      modeIcons[log.mode],
                      color: modeColors[log.mode],
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.mode.toUpperCase(),
                          style: GoogleFonts.poppins(
                            textStyle: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, MMM dd, yyyy').format(log.date),
                          style: GoogleFonts.poppins(
                            textStyle: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _DetailRow('Distance', '${log.distanceKm.toStringAsFixed(1)} km'),
              _DetailRow(
                'Productivity Score',
                '${log.productivityScore.toStringAsFixed(1)}/10',
              ),
              _DetailRow(
                'Carbon Footprint',
                '${_calculateCarbonForLog(log).toStringAsFixed(2)} kg CO₂',
              ),
              if (log.durationMinutes != null)
                _DetailRow('Duration', '${log.durationMinutes} minutes'),
              if (log.cost != null)
                _DetailRow('Cost', '₹${log.cost!.toStringAsFixed(2)}'),
              if (log.fatigueLevel != null)
                _DetailRow(
                  'Fatigue Level',
                  '${log.fatigueLevel!.toStringAsFixed(1)}/10',
                ),
              if (log.stressLevel != null)
                _DetailRow(
                  'Stress Level',
                  '${log.stressLevel!.toStringAsFixed(1)}/10',
                ),
              if (log.startAddress != null)
                _DetailRow('Start Address', log.startAddress!),
              if (log.endAddress != null)
                _DetailRow('End Address', log.endAddress!),
              const SizedBox(height: 24),
                          Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        // open map screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => CommuteMapScreen(log: log),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('View Map'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onDelete(log);
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
    );
  }
}
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final labelMax = width >= 600 ? 200.0 : (width * 0.35); // adapt to screen size

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: labelMax),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                textStyle: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                textStyle: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.poppins(
              textStyle: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              textStyle: TextStyle(color: Colors.grey[600]),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
