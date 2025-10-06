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
import 'package:commute_app/models/commute_log.dart';
import 'package:commute_app/widgets/inline_map_tracker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; 

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


  LatLng? _start;
  LatLng? _end;
  List<LatLng> _routePoints = [];
  double? _distanceKm;
  bool _showTripDetails = false;
  bool _isTracking = false;
  int? _durationSeconds;


  DateTime? _tripStartTime;
  DateTime? _tripEndTime;


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

String? userFuelType;
try {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.userId;
  if (uid != null) {
    final profileSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final pd = profileSnap.data();
    if (pd != null && pd['vehicleFuelType'] != null) {
      userFuelType = (pd['vehicleFuelType'] as String).toLowerCase();
    }
  }
} catch (_) {
  userFuelType = null;
}


final logData = {
  'userId': widget.userId,
  'date': Timestamp.fromDate(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)),
  'mode': _selectedMode,
  'distanceKm': distanceKm,
  'productivityScore': productivityScore,
  'durationMinutes': _durationController.text.isNotEmpty ? int.tryParse(_durationController.text) : null,
  'durationSeconds': _durationSeconds,
  'cost': _costController.text.isNotEmpty ? double.tryParse(_costController.text) : null,
  'fatigueLevel': _fatigueController.text.isNotEmpty ? double.tryParse(_fatigueController.text) : null,
  'stressLevel': _stressController.text.isNotEmpty ? double.tryParse(_stressController.text) : null,
  'startLocation': _start != null ? {'lat': _start!.latitude, 'lng': _start!.longitude} : null,
  'endLocation': _end != null ? {'lat': _end!.latitude, 'lng': _end!.longitude} : null,
  'checkpoints': _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
  'distanceComputedKm': _distanceKm,
  'startTime': _start != null && _durationSeconds != null
      ? Timestamp.fromDate(DateTime.now().subtract(Duration(seconds: _durationSeconds!)))
      : null, 
  'endTime': _durationSeconds != null ? Timestamp.fromDate(DateTime.now()) : null, // prefer actual times if you have them
  'vehicleFuelType': userFuelType,
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
      _durationSeconds = null; 
      _tripStartTime = null;
      _tripEndTime = null;
    });
  }

  Future<void> _showTripReviewSheet({
    required LatLng start,
    required LatLng end,
    required List<LatLng> routePoints,
    required double distanceKm,
    required int durationSeconds,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    
    _distanceController.text = distanceKm.toStringAsFixed(2);

    final chosenMode = _selectedMode;
    
    final result = await showModalBottomSheet<Map<String, String>?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TripReviewSheet(
        chosenMode: chosenMode,
        distanceKm: distanceKm,
        durationSeconds: durationSeconds,
        startTime: startTime,
        endTime: endTime,
        initialProductivity: _productivityController.text,
        initialDurationText: _durationController.text,
        initialCost: _costController.text,
        initialFatigue: _fatigueController.text,
        initialStress: _stressController.text,
      ),
    );

    
    if (result != null && mounted) {
      setState(() {
        _selectedMode = chosenMode;
        _productivityController.text = result['productivity'] ?? '';
        _durationController.text = result['duration'] ?? '';
        _costController.text = result['cost'] ?? '';
        _fatigueController.text = result['fatigue'] ?? '';
        _stressController.text = result['stress'] ?? '';
        _distanceController.text = distanceKm.toStringAsFixed(2);

        
        _tripStartTime = startTime;
        _tripEndTime = endTime;
        _durationSeconds = durationSeconds;
      });

      await _submitLog();
    }
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

    
    query = FirebaseFirestore.instance.collection('commute_logs').orderBy('date', descending: true);

    

    if (!allUsers) {
      
      query = query.where('userId', isEqualTo: widget.userId);
    }

    
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

  Widget _buildAddLogTabWithTracker() {
    return Stack(
      children: [
        Column(
          children: [
            InlineMapTracker(
              height: 360,
              onTripStarted: () => setState(() {
                _isTracking = true;
                
                _tripStartTime = DateTime.now();
              }),
              onTripEnded: () => setState(() {
                _isTracking = false;
                
                _tripEndTime = DateTime.now();
              }),
              onRouteFinished: ({
                required LatLng start,
                required LatLng end,
                required List<LatLng> routePoints,
                required double distanceKm,
                required int durationSeconds,
                required DateTime startTime,
                required DateTime endTime,
              }) {
                setState(() {
                  _start = start;
                  _end = end;
                  _routePoints = routePoints;
                  _distanceKm = distanceKm;
                  _durationSeconds = durationSeconds;
                  _tripStartTime = startTime;
                  _tripEndTime = endTime;
                  _showTripDetails = true;
                  _isTracking = false;
                });

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddCommuteLogScreen(
                      startLat: start.latitude,
                      startLng: start.longitude,
                      endLat: end.latitude,
                      endLng: end.longitude,
                      routePoints: routePoints,
                      distanceKm: distanceKm,
                      durationSeconds: durationSeconds,
                      startTime: startTime,
                      endTime: endTime,
                      selectedMode: _selectedMode, 
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            
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
              'Person Dashboard',
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
        'durationSeconds',
        'startTime',
        'endTime',
        'cost',
        'fatigueLevel',
        'stressLevel',
        'createdAt',
      ],
    ];

    for (var log in logs) {
    
      DateTime createdAtDt;
      if (log.createdAt == null) {
        createdAtDt = DateTime.now();
      } else if (log.createdAt is DateTime) {
        createdAtDt = log.createdAt as DateTime;
      } else {
      
        try {
          createdAtDt = (log.createdAt as dynamic).toDate() as DateTime;
        } catch (_) {
          createdAtDt = DateTime.now();
        }
      }

      
      final DateTime? startDt = log.startTime;
      final DateTime? endDt = log.endTime;

      csvData.add([
        DateFormat('yyyy-MM-dd').format(log.date),
        log.mode,
        log.distanceKm,
        log.productivityScore,
        log.durationMinutes ?? '',
        log.durationSeconds ?? '',
        startDt != null ? startDt.toIso8601String() : '',
        endDt != null ? endDt.toIso8601String() : '',
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
    final totalDistance = logs.fold<double>(0, (sum, log) => sum + log.distanceKm);
    final totalProductivity = logs.fold<double>(0, (sum, log) => sum + log.productivityScore);
    final totalCost = logs.fold<double>(0, (sum, log) => sum + (log.cost ?? 0));
    final totalCarbon = logs.fold<double>(0, (sum, log) => sum + _calculateCarbonForLog(log));
    final totalFatigue = logs.fold<double>(0, (sum, log) => sum + (log.fatigueLevel ?? 0));
    final totalStress = logs.fold<double>(0, (sum, log) => sum + (log.stressLevel ?? 0));
    final totalPhysicalActivity = logs.fold<double>(0, (sum, log) => sum + (log.physicalActivity ?? 0));

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

    
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom + 96.0;

    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        children: [
          _KeyMetricsCard(stats: stats),
          const SizedBox(height: 16),
          _ProductivityChart(logs: logs),
          const SizedBox(height: 16),
          _ModeDistributionChart(logs: logs),
          const SizedBox(height: 16),
          _TrendAnalysisCard(logs: logs),
        ],
      ),
    );
  }
}

class _KeyMetricsCard extends StatelessWidget {
  final CommuteStats stats;

  const _KeyMetricsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    
    final screenWidth = MediaQuery.of(context).size.width;
    
    final horizontalGaps = 16.0 * 2 + 12.0;
    final tileWidth = (screenWidth - horizontalGaps) / 2;

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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(width: tileWidth, child: _MetricTile('Total Trips', '${stats.totalTrips}', Icons.trip_origin)),
                SizedBox(width: tileWidth, child: _MetricTile('Total Distance', '${stats.totalDistance.toStringAsFixed(1)} km', Icons.straighten)),
                SizedBox(width: tileWidth, child: _MetricTile('Avg Productivity', '${stats.avgProductivity.toStringAsFixed(1)}/10', Icons.trending_up)),
                SizedBox(width: tileWidth, child: _MetricTile('Total Cost', '₹${stats.totalCost.toStringAsFixed(0)}', Icons.currency_rupee)),
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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
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

  String _formatMaybe(dynamic val) {
    if (val == null) return '-';
    try {
      if (val is DateTime) return DateFormat('yyyy-MM-dd HH:mm:ss').format(val);
      if (val is Timestamp) return DateFormat('yyyy-MM-dd HH:mm:ss').format(val.toDate());
      return val.toString();
    } catch (e) {
      return val.toString();
    }
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
              if (log.durationSeconds != null)
                _DetailRow('Duration (sec)', '${log.durationSeconds} s'),
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
              _DetailRow('Start Time', _formatMaybe(log.startTime)),
              _DetailRow('End Time', _formatMaybe(log.endTime)),
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
class TripReviewSheet extends StatefulWidget {
  final String chosenMode;
  final double distanceKm;
  final int? durationSeconds;
  final DateTime? startTime;
  final DateTime? endTime;
  final String initialProductivity;
  final String initialDurationText;
  final String initialCost;
  final String initialFatigue;
  final String initialStress;

  const TripReviewSheet({
    Key? key,
    required this.chosenMode,
    required this.distanceKm,
    this.durationSeconds,
    this.startTime,
    this.endTime,
    this.initialProductivity = '',
    this.initialDurationText = '',
    this.initialCost = '',
    this.initialFatigue = '',
    this.initialStress = '',
  }) : super(key: key);

  @override
  State<TripReviewSheet> createState() => _TripReviewSheetState();
}

class _TripReviewSheetState extends State<TripReviewSheet> {
  late final TextEditingController tmpProductivity;
  late final TextEditingController tmpDuration;
  late final TextEditingController tmpCost;
  late final TextEditingController tmpFatigue;
  late final TextEditingController tmpStress;
  late final TextEditingController tmpMood;
  late final TextEditingController tmpTrack;
  late final TextEditingController tmpWeather;

  @override
  void initState() {
    super.initState();
    tmpProductivity = TextEditingController(text: widget.initialProductivity);
    tmpDuration = TextEditingController(text: widget.initialDurationText);
    tmpCost = TextEditingController(text: widget.initialCost);
    tmpFatigue = TextEditingController(text: widget.initialFatigue);
    tmpStress = TextEditingController(text: widget.initialStress);
    tmpMood = TextEditingController();
    tmpTrack = TextEditingController();
    tmpWeather = TextEditingController();

    if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
      tmpDuration.text = _formatSecondsToHms(widget.durationSeconds!);
    }
  }

  @override
  void dispose() {
    tmpProductivity.dispose();
    tmpDuration.dispose();
    tmpCost.dispose();
    tmpFatigue.dispose();
    tmpStress.dispose();
    tmpMood.dispose();
    tmpTrack.dispose();
    tmpWeather.dispose();
    super.dispose();
  }

  String _formatSecondsToHms(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _showCost =>
      (widget.chosenMode == 'motorbike' ||
          widget.chosenMode == 'car' ||
          widget.chosenMode == 'bus' ||
          widget.chosenMode == 'train' ||
          widget.chosenMode == 'other');

  bool get _showFatigueStress =>
      (widget.chosenMode == 'walk' ||
          widget.chosenMode == 'cycle' ||
          widget.chosenMode == 'motorbike' ||
          widget.chosenMode == 'car' ||
          widget.chosenMode == 'other');

  bool get _showWalkCycleExtras =>
      (widget.chosenMode == 'walk' || widget.chosenMode == 'cycle');

  @override
  Widget build(BuildContext context) {
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
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              Text('Trip review', style: GoogleFonts.poppins(textStyle: Theme.of(context).textTheme.titleLarge)),
              const SizedBox(height: 8),
              Text('Distance: ${widget.distanceKm.toStringAsFixed(2)} km', style: GoogleFonts.poppins()),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: modeColors[widget.chosenMode]?.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: modeColors[widget.chosenMode] ?? Colors.grey),
                    ),
                    child: Row(children: [
                      Icon(modeIcons[widget.chosenMode], color: modeColors[widget.chosenMode]),
                      const SizedBox(width: 8),
                      Text(widget.chosenMode.toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Text('Mode selected before trip', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
              const SizedBox(height: 18),

              // show start/end times (if provided)
              if (widget.startTime != null || widget.endTime != null) ...[
                if (widget.startTime != null)
                  Text('Start: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.startTime!)}', style: GoogleFonts.poppins()),
                if (widget.endTime != null)
                  Text('End: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.endTime!)}', style: GoogleFonts.poppins()),
                const SizedBox(height: 12),
              ],

              // Inputs (same as your sheet content — shortend here for brevity)
              Text('Productivity Score (0-10)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(controller: tmpProductivity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: 'e.g. 7.5', prefixIcon: Icon(Icons.trending_up))),
              const SizedBox(height: 12),

              Text('Duration (HH:MM:SS)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(controller: tmpDuration, readOnly: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.access_time))),
              const SizedBox(height: 12),

              if (_showCost) ...[
                Text('Cost (₹)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(controller: tmpCost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: 'e.g. 40.5', prefixIcon: Icon(Icons.currency_rupee))),
                const SizedBox(height: 12),
              ],

              if (_showWalkCycleExtras) ...[
                TextFormField(controller: tmpMood, decoration: const InputDecoration(hintText: 'e.g. Happy', prefixIcon: Icon(Icons.emoji_emotions_outlined))),
                const SizedBox(height: 12),
                TextFormField(controller: tmpTrack, decoration: const InputDecoration(hintText: 'e.g. river road', prefixIcon: Icon(Icons.alt_route_outlined))),
                const SizedBox(height: 12),
                TextFormField(controller: tmpWeather, decoration: const InputDecoration(hintText: 'e.g. Sunny', prefixIcon: Icon(Icons.wb_sunny_outlined))),
                const SizedBox(height: 12),
              ],

              if (_showFatigueStress) ...[
                const SizedBox(height: 8),
                Text('Fatigue (0 - 10)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: double.tryParse(tmpFatigue.text) ?? 0.0,
                        min: 0,
                        max: 10,
                        divisions: 20,
                        label: (double.tryParse(tmpFatigue.text) ?? 0.0).toStringAsFixed(1),
                        onChanged: (v) {
                          setState(() {
                            tmpFatigue.text = v.toStringAsFixed(1);
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: TextFormField(
                        controller: tmpFatigue,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Stress (0 - 10)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: double.tryParse(tmpStress.text) ?? 0.0,
                        min: 0,
                        max: 10,
                        divisions: 20,
                        label: (double.tryParse(tmpStress.text) ?? 0.0).toStringAsFixed(1),
                        onChanged: (v) {
                          setState(() {
                            tmpStress.text = v.toStringAsFixed(1);
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: TextFormField(
                        controller: tmpStress,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],


              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.of(context).pop(null); }, child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    // Return values as strings; parent will convert/set timestamps/durationSeconds from context
                    Navigator.of(context).pop(<String,String>{
                      'productivity': tmpProductivity.text,
                      'duration': tmpDuration.text,
                      'cost': tmpCost.text,
                      'fatigue': tmpFatigue.text,
                      'stress': tmpStress.text,
                      'mood': tmpMood.text,
                      'track': tmpTrack.text,
                      'weather': tmpWeather.text,
                    });
                  }, child: const Text('Save Log'))),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }
}
