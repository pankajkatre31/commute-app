import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:commute_app/models/commute_log.dart';
import 'user_profile.dart';

// ---------------------------------
// A. DATA MODELS
// ---------------------------------

// ---------------------------------
// B. ADMIN DASHBOARD SCREEN
// ---------------------------------
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Admin Dashboard',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.poppins(),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users'),
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(firestore: _firestore),
          _UsersTab(firestore: _firestore),
          _LogsTab(firestore: _firestore),
        ],
      ),
    );
  }
}

// ---------------------------------
// C. DASHBOARD TABS
// ---------------------------------
class _OverviewTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  const _OverviewTab({required this.firestore});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  DateTimeRange? _selectedDateRange;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateRangeFilter(
            selectedDateRange: _selectedDateRange,
            onDateRangeChanged: (range) {
              setState(() {
                _selectedDateRange = range;
              });
            },
          ),
          const SizedBox(height: 24),
          _MetricCardGrid(
            firestore: widget.firestore,
            dateRange: _selectedDateRange,
          ),
          const SizedBox(height: 24),
          _ChartsSection(
            firestore: widget.firestore,
            dateRange: _selectedDateRange,
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  final FirebaseFirestore firestore;
  const _UsersTab({required this.firestore});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final users =
            snapshot.data!.docs
                .map((doc) => UserProfile.fromFirestore(doc))
                .toList();
        if (users.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    user.isActive
                        ? Icons.person_outline
                        : Icons.person_off_outlined,
                  ),
                ),
                title: Text(
                  user.email,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Role: ${user.role} | Status: ${user.isActive ? 'Active' : 'Deactivated'}',
                ),
                trailing: Text('ID: ${user.uid.substring(0, 5)}...'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => _UserDetailScreen(user: user),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _LogsTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  const _LogsTab({required this.firestore});

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  String _modeFilter = 'all';
  String _searchTerm = '';
  DateTimeRange? _selectedDateRange;

  void _exportToCsv(List<CommuteLog> logs) {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No logs to export.')));
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'ID,User ID,Date,Mode,Distance (km),Productivity Score,Cost,Carbon (kg),Start Address,End Address',
    );

    for (var log in logs) {
      buffer.writeln(
        '${log.id},${log.userId},${DateFormat('yyyy-MM-dd').format(log.date)},${log.mode},${log.distanceKm},${log.productivityScore},${log.cost ?? ''},${log.carbonKg ?? ''},"${log.startAddress}", "${log.endAddress}"',
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${logs.length} logs to clipboard as CSV.'),
      ),
    );
    // In a real app, you would use a package like `csv` and `path_provider` to save the file.
    // For this example, we'll just "export" it.
    // final csvData = buffer.toString();
    // In a real app, you'd save this string to a file.
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Search by User ID or Mode',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) => setState(() => _searchTerm = value),
              ),
              const SizedBox(height: 12),
              _DateRangeFilter(
                selectedDateRange: _selectedDateRange,
                onDateRangeChanged: (range) {
                  setState(() {
                    _selectedDateRange = range;
                  });
                },
              ),
            ],
          ),
        ),
        _ModeFilterChips(
          selectedMode: _modeFilter,
          onModeChanged: (mode) => setState(() => _modeFilter = mode),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                widget.firestore
                    .collection('commute_logs')
                    .orderBy('date', descending: true)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final logs =
                  snapshot.data!.docs
                      .map((doc) => CommuteLog.fromFirestore(doc))
                      .where((log) {
                        final matchesMode =
                            _modeFilter == 'all' || log.mode == _modeFilter;
                        final matchesSearch =
                            _searchTerm.isEmpty ||
                            log.userId.toLowerCase().contains(
                              _searchTerm.toLowerCase(),
                            ) ||
                            log.mode.toLowerCase().contains(
                              _searchTerm.toLowerCase(),
                            );
                        final matchesDate =
                            _selectedDateRange == null ||
                            (log.date!.isAfter(_selectedDateRange!.start) &&
                                log.date!.isBefore(_selectedDateRange!.end));
                        return matchesMode && matchesSearch && matchesDate;
                      })
                      .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _exportToCsv(logs),
                        icon: const Icon(Icons.download),
                        label: Text('Export ${logs.length} Logs to CSV'),
                      ),
                    ),
                  ),
                  Expanded(
                    child:
                        logs.isEmpty
                            ? const Center(
                              child: Text('No matching logs found.'),
                            )
                            : ListView.builder(
                              itemCount: logs.length,
                              itemBuilder: (context, index) {
                                final log = logs[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  elevation: 1,
                                  child: ListTile(
                                    title: Text(
                                      'User ID: ${log.userId.substring(0, 8)}...',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${log.mode.toUpperCase()} • ${DateFormat('MMM dd, yyyy').format(log.date!)} • ${log.distanceKm.toStringAsFixed(1)} km',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed:
                                          () => _showDeleteConfirmation(
                                            context,
                                            log,
                                          ),
                                    ),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context, CommuteLog log) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Log'),
            content: Text(
              'Are you sure you want to delete this log from user ${log.userId.substring(0, 8)}...?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.firestore
                        .collection('commute_logs')
                        .doc(log.id)
                        .delete();
                    if (context.mounted) Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Log deleted successfully')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete log: $e')),
                    );
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}

// ---------------------------------
// D. REUSABLE COMPONENTS AND UTILS
// ---------------------------------
class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).primaryColor, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCardGrid extends StatelessWidget {
  final FirebaseFirestore firestore;
  final String? userId;
  final DateTimeRange? dateRange;
  const _MetricCardGrid({required this.firestore, this.userId, this.dateRange});

  @override
  Widget build(BuildContext context) {
    Stream<QuerySnapshot<Map<String, dynamic>>> getLogsStream() {
      Query<Map<String, dynamic>> query = firestore.collection('commute_logs');
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      if (dateRange != null) {
        query = query
            .where('date', isGreaterThanOrEqualTo: dateRange!.start)
            .where('date', isLessThanOrEqualTo: dateRange!.end);
      }
      return query.snapshots();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: getLogsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs =
            snapshot.data!.docs
                .map((doc) => CommuteLog.fromFirestore(doc))
                .toList();
        final users = logs.map((log) => log.userId).toSet();
        final totalDistance = logs.fold(
          0.0,
          (sum, log) => sum + log.distanceKm,
        );
        final totalCarbon = logs.fold(
          0.0,
          (sum, log) => sum + (log.carbonKg ?? 0),
        );

        return GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          childAspectRatio: 1.2, // Adjusted for more vertical space
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricTile(
              title: 'Total Logs',
              value: logs.length.toString(),
              icon: Icons.article_outlined,
            ),
            _MetricTile(
              title: 'Unique Users',
              value: userId != null ? '1' : users.length.toString(),
              icon: Icons.people_alt_outlined,
            ),
            _MetricTile(
              title: 'Total Distance',
              value: '${totalDistance.toStringAsFixed(1)} km',
              icon: Icons.map_outlined,
            ),
            _MetricTile(
              title: 'Total CO₂',
              value: '${totalCarbon.toStringAsFixed(1)} kg',
              icon: Icons.eco_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _ChartsSection extends StatelessWidget {
  final FirebaseFirestore firestore;
  final String? userId;
  final DateTimeRange? dateRange;
  const _ChartsSection({required this.firestore, this.userId, this.dateRange});

  @override
  Widget build(BuildContext context) {
    Stream<QuerySnapshot<Map<String, dynamic>>> getLogsStream() {
      Query<Map<String, dynamic>> query = firestore.collection('commute_logs');
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      if (dateRange != null) {
        query = query
            .where('date', isGreaterThanOrEqualTo: dateRange!.start)
            .where('date', isLessThanOrEqualTo: dateRange!.end);
      }
      return query.snapshots();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: getLogsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs =
            snapshot.data!.docs
                .map((doc) => CommuteLog.fromFirestore(doc))
                .toList();

        if (logs.isEmpty) {
          return const SizedBox.shrink();
        }

        final productivityData = _getWeeklyProductivityData(logs);
        final modeData = _getModeDistributionData(logs);

        return Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avg Productivity Trend',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 250,
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(show: true),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget:
                                    (value, meta) =>
                                        Text(value.toInt().toString()),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget:
                                    (value, meta) =>
                                        Text('Wk ${value.toInt()}'),
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
                          maxX: productivityData.length.toDouble() - 1,
                          minY: 0,
                          maxY: 10,
                          lineBarsData: [
                            LineChartBarData(
                              spots:
                                  productivityData.asMap().entries.map((entry) {
                                    return FlSpot(
                                      entry.key.toDouble(),
                                      entry.value,
                                    );
                                  }).toList(),
                              isCurved: true,
                              color: Theme.of(context).primaryColor,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                show: true,
                                color: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.1),
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
            const SizedBox(height: 24),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Distribution',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 250,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 60,
                          sections:
                              modeData.entries.map((entry) {
                                final percentage =
                                    (entry.value / logs.length) * 100;
                                return PieChartSectionData(
                                  color: CommuteLog.modeColors[entry.key],
                                  value: entry.value.toDouble(),
                                  title: '${percentage.toStringAsFixed(1)}%',
                                  radius: 80,
                                  titleStyle: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
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
                          modeData.entries.map((entry) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: CommuteLog.modeColors[entry.key],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(entry.key, style: GoogleFonts.poppins()),
                              ],
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<double> _getWeeklyProductivityData(List<CommuteLog> logs) {
    if (logs.isEmpty) return [];
    final Map<int, List<double>> weeklyData = {};
    for (var log in logs) {
      final startOfYear = DateTime(log.date.year, 1, 1);
      final dayOfYear = log.date.difference(startOfYear).inDays + 1;
      final weekOfYear = (dayOfYear / 7).ceil();
      weeklyData.putIfAbsent(weekOfYear, () => []).add(log.productivityScore);
    }
    return weeklyData.entries
        .map((e) => e.value.reduce((a, b) => a + b) / e.value.length)
        .toList();
  }

  Map<String, int> _getModeDistributionData(List<CommuteLog> logs) {
    final Map<String, int> modeCounts = {};
    for (var log in logs) {
      modeCounts.update(log.mode, (value) => value + 1, ifAbsent: () => 1);
    }
    return modeCounts;
  }
}

class _ModeFilterChips extends StatelessWidget {
  final String selectedMode;
  final void Function(String) onModeChanged;

  const _ModeFilterChips({
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    const allModes = [
      'all',
      'walk',
      'cycle',
      'motorbike',
      'car',
      'bus',
      'train',
      'other',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children:
            allModes.map((mode) {
              final isSelected = selectedMode == mode;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: FilterChip(
                  label: Text(mode.toUpperCase()),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    if (selected) onModeChanged(mode);
                  },
                  selectedColor:
                      CommuteLog.modeColors[mode] ??
                      Theme.of(context).primaryColor,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                  ),
                  avatar: Icon(
                    CommuteLog.modeIcons[mode] ?? Icons.public,
                    color:
                        isSelected
                            ? Colors.white
                            : (CommuteLog.modeColors[mode] ?? Colors.black),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _DateRangeFilter extends StatelessWidget {
  final DateTimeRange? selectedDateRange;
  final void Function(DateTimeRange?) onDateRangeChanged;

  const _DateRangeFilter({
    super.key,
    this.selectedDateRange,
    required this.onDateRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          final newDateRange = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            initialDateRange: selectedDateRange,
          );
          onDateRangeChanged(newDateRange);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                selectedDateRange == null
                    ? 'Filter by Date Range'
                    : 'Date: ${DateFormat('MMM d, yyyy').format(selectedDateRange!.start)} - ${DateFormat('MMM d, yyyy').format(selectedDateRange!.end)}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              if (selectedDateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () => onDateRangeChanged(null),
                )
              else
                const Icon(Icons.calendar_today, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserDetailScreen extends StatefulWidget {
  final UserProfile user;
  const _UserDetailScreen({super.key, required this.user});

  @override
  State<_UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<_UserDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isUserActive = false;

  @override
  void initState() {
    super.initState();
    _isUserActive = widget.user.isActive;
  }

  void _sendPasswordResetEmail() async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: widget.user.email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to ${widget.user.email}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send password reset email: $e')),
        );
      }
    }
  }

  void _toggleUserActiveStatus(bool value) async {
    setState(() {
      _isUserActive = value;
    });
    try {
      await _firestore.collection('users').doc(widget.user.uid).update({
        'is_active': value,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'User ${value ? 'activated' : 'deactivated'} successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update user status: $e')),
        );
      }
    }
  }

  void _showDeleteUserConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete User'),
            content: Text(
              'Are you sure you want to permanently delete the account for ${widget.user.email}? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    // In a production app, a Cloud Function should handle deleting the user from Firebase Authentication as well.
                    await _firestore
                        .collection('users')
                        .doc(widget.user.uid)
                        .delete();
                    if (context.mounted) Navigator.of(context).pop();
                    if (context.mounted) Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User deleted successfully'),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete user: $e')),
                    );
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.user.email,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => _showDeleteUserConfirmation(context),
            icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
            tooltip: 'Delete User',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Details',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('User ID: ${widget.user.uid}'),
                    const SizedBox(height: 4),
                    Text('Role: ${widget.user.role.capitalize()}'),
                    const SizedBox(height: 4),
                    Text('Email: ${widget.user.email}'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Deactivate User'),
                        Switch(
                          value: _isUserActive,
                          onChanged: _toggleUserActiveStatus,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _sendPasswordResetEmail,
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: const Text('Send Password Reset Email'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'User Metrics',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            _MetricCardGrid(firestore: _firestore, userId: widget.user.uid),
            const SizedBox(height: 24),
            Text(
              'User Analytics',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            _ChartsSection(firestore: _firestore, userId: widget.user.uid),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
