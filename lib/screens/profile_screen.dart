import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/commute_log.dart';
import '../models/commute_stats.dart';
import 'package:commute_app/screens/vehicle_settings_screen.dart';
class ProfileScreen extends StatefulWidget {
  final String userId;
  final String? userEmail;

  const ProfileScreen({super.key, required this.userId, this.userEmail});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isEditing = false;

  // --- NEW: fuel type state + options ---
  final List<String> _fuelOptions = ['petrol', 'diesel', 'cng', 'electric', 'hybrid', 'other'];
  String? _selectedFuelType;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _nameController.text = FirebaseAuth.instance.currentUser?.displayName ?? '';

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
    );

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });

    // load saved profile (including vehicleFuelType)
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }
Future<void> _loadProfile() async {
  if (!mounted) return;
  setState(() {
    _isLoadingProfile = true;
  });

  try {
    // Prefer the authenticated user's uid to avoid mismatches.
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final uid = authUid ?? widget.userId;
    if (uid == null) {
      debugPrint('ProfileScreen._loadProfile: no uid available');
      setState(() => _isLoadingProfile = false);
      return;
    }

    debugPrint('ProfileScreen._loadProfile: reading users/$uid');
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      debugPrint('ProfileScreen._loadProfile: users/$uid does not exist');
    }

    final data = doc.data();
    if (mounted) {
      setState(() {
        _selectedFuelType = data != null && data['vehicleFuelType'] != null
            ? (data['vehicleFuelType'] as String).toLowerCase()
            : null;

        // if displayName missing in auth, fallback to profile doc
        if ((FirebaseAuth.instance.currentUser?.displayName ?? '').isEmpty &&
            data != null &&
            data['displayName'] != null) {
          _nameController.text = data['displayName'] as String;
        }

        _isLoadingProfile = false;
      });
    }

    // debug: print the doc contents to console
    debugPrint('Profile doc for $uid -> ${data ?? '<empty>'}');
  } catch (e, st) {
    debugPrint('ProfileScreen._loadProfile ERROR: $e\n$st');
    if (mounted) setState(() => _isLoadingProfile = false);
  }
}
void _showSnack(String message, {bool isError = false}) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(isError ? Icons.error : Icons.check_circle, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: GoogleFonts.poppins())),
        ],
      ),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
Future<void> _updateProfile() async {
  // If the name form is present, validate it; otherwise skip validation.
  final formState = _formKey.currentState;
  if (formState != null) {
    if (!formState.validate()) return;
    // optionally save: formState.save();
  }

  // disable editing UI immediately
  setState(() => _isEditing = false);

  try {
    final user = FirebaseAuth.instance.currentUser;
    final authUid = user?.uid;
    final uid = authUid ?? widget.userId;

    if (uid == null) {
      _showSnack('Unable to save profile (no user id)', isError: true);
      return;
    }

    // Try to update the Auth displayName if an auth user exists
    if (user != null) {
      try {
        // NOTE: updateProfile may be deprecated on some SDKs; keep this best-effort.
        await user.updateProfile(displayName: _nameController.text.trim());
        await user.reload();
      } catch (e) {
        debugPrint('Profile: failed to update auth displayName (non-fatal): $e');
      }
    }

    // Prepare payload for Firestore (merge so we don't overwrite other fields)
    final payload = <String, dynamic>{
      'displayName': _nameController.text.trim(),
      if (_selectedFuelType != null) 'vehicleFuelType': _selectedFuelType,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    debugPrint('ProfileScreen._updateProfile: writing users/$uid -> $payload');

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await docRef.set(payload, SetOptions(merge: true));

    // Re-read to confirm write and update UI
    final fresh = await docRef.get();
    final freshData = fresh.data();
    debugPrint('ProfileScreen._updateProfile: saved. freshData=$freshData');

    if (mounted) {
      setState(() {
        _selectedFuelType = freshData != null && freshData['vehicleFuelType'] != null
            ? (freshData['vehicleFuelType'] as String).toLowerCase()
            : _selectedFuelType;
        // Also sync name from saved doc if auth wasn't updated
        if ((FirebaseAuth.instance.currentUser?.displayName ?? '').isEmpty &&
            freshData != null &&
            freshData['displayName'] != null) {
          _nameController.text = freshData['displayName'] as String;
        }
      });

      _showSnack('Profile updated successfully', isError: false);
    }
  } catch (e, st) {
    debugPrint('ProfileScreen._updateProfile ERROR: $e\n$st');
    if (mounted) _showSnack('Failed to update profile: $e', isError: true);
  }
}

  Stream<List<CommuteLog>> _getLogsStream() {
    return FirebaseFirestore.instance
        .collection('commute_logs')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CommuteLog.fromFirestore(doc)).toList();
    });
  }

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
    // Prefer model's estimate if available and supports vehicleFuelType
    try {
      // If your CommuteLog provides an estimate method / getter, use it:
      return log.carbonKg;
    } catch (_) {
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(), builder: (context, userSnapshot) {
        final user = userSnapshot.data;
        return CustomScrollView(
          slivers: [
            _buildSliverAppBar(user),
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      _buildProfileCard(user),
                      const SizedBox(height: 20),
                      _buildAccountDetails(),
                      const SizedBox(height: 20),
                      _buildCommuteInsights(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSliverAppBar(User? user) {
    return SliverAppBar(
      expandedHeight: 280,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.8),
                Theme.of(context).colorScheme.secondary.withOpacity(0.6),
                Theme.of(context).colorScheme.tertiary.withOpacity(0.4),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                _buildAnimatedAvatar(),
                const SizedBox(height: 20),
                _buildNameSection(user),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedAvatar() {
    return Hero(
      tag: 'profile_avatar',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: 50,
          backgroundColor: Colors.white,
          child: CircleAvatar(
            radius: 46,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              size: 50,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameSection(User? user) {
    return Column(
      children: [
        if (_isEditing) ...[
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: TextFormField(
                controller: _nameController,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  hintStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(
                icon: Icons.check,
                onPressed: _updateProfile,
                color: Colors.green,
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                icon: Icons.close,
                onPressed: () => setState(() => _isEditing = false),
                color: Colors.red,
              ),
            ],
          ),
        ] else ...[
          GestureDetector(
            onTap: () => setState(() => _isEditing = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text
                        : 'Tap to add name',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              'Member since ${DateFormat('MMM yyyy').format(user?.metadata.creationTime ?? DateTime.now())}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildProfileCard(User? user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 8,
        shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              ],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_circle,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Profile Overview',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildProfileMetric(
                'Account Status',
                'Active',
                Icons.verified_user,
                Colors.green,
              ),
              const SizedBox(height: 16),
              _buildProfileMetric(
                'Account Type',
                'Faculty Member',
                Icons.school,
                Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              _buildProfileMetric(
                'Last Active',
                'Today',
                Icons.access_time,
                Colors.orange,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_forward_ios, color: color, size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountDetails() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 6,
        shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Account Details',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailCard(
                icon: Icons.fingerprint,
                label: 'User ID',
                value: widget.userId,
                color: Colors.purple,
              ),
              const SizedBox(height: 16),
              _buildDetailCard(
                icon: Icons.email_outlined,
                label: 'Email Address',
                value: widget.userEmail ?? 'Not provided',
                color: Colors.blue,
              ),
              const SizedBox(height: 16),

               
if (_isLoadingProfile)
  const Center(child: CircularProgressIndicator())
else
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Vehicle / Fuel Type',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 8),

  
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_gas_station, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedFuelType != null ? _selectedFuelType!.toUpperCase() : 'Not set',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 12),

      
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
          onPressed: () async {
  final result = await Navigator.push<String?>(
    context,
    MaterialPageRoute(builder: (_) => const VehicleSettingsScreen()),
  );

  if (!mounted) return;

  if (result != null && result.isNotEmpty) {
    setState(() {
      _selectedFuelType = result.toLowerCase();
    });
  } else {
    
    await _loadProfile();
  }
},

              icon: const Icon(Icons.car_rental),
              label: Text('Manage Vehicles', style: GoogleFonts.poppins()),
            ),
          ),
        ],
      ),
    ],

  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.copy, color: color.withOpacity(0.6), size: 18),
        ],
      ),
    );
  }

  Widget _buildCommuteInsights() {
    return StreamBuilder<List<CommuteLog>>(
      stream: _getLogsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }
        if (snapshot.hasError) {
          return _buildErrorCard(snapshot.error.toString());
        }

        final logs = snapshot.data ?? [];
        final stats = _calculateStats(logs);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            elevation: 8,
            shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.3),
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.analytics,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Commute Analytics',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Your travel insights & metrics',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (logs.isEmpty)
                    _buildEmptyState()
                  else ...[
                    _buildStatsGrid(stats),
                    const SizedBox(height: 20),
                    _buildQuickInsights(stats, logs),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsGrid(CommuteStats stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                '${stats.totalTrips}',
                'Total Trips',
                Icons.directions_walk,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                '${stats.totalDistance.toStringAsFixed(1)} km',
                'Distance',
                Icons.straighten,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                '₹${stats.totalCost.toStringAsFixed(0)}',
                'Total Cost',
                Icons.currency_rupee,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                '${stats.totalCarbon.toStringAsFixed(1)} kg',
                'CO₂ Footprint',
                Icons.eco,
                Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                '${stats.avgProductivity.toStringAsFixed(1)}/10',
                'Avg Productivity',
                Icons.trending_up,
                Colors.purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                '${stats.avgStress.toStringAsFixed(1)}/10',
                'Avg Stress',
                Icons.psychology,
                Colors.indigo,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInsights(CommuteStats stats, List<CommuteLog> logs) {
    final recentLogs = logs.take(7).toList();
    final weeklyDistance = recentLogs.fold<double>(
      0,
      (sum, log) => sum + log.distanceKm,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: Theme.of(context).colorScheme.tertiary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Insights',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInsightRow(
            'This week you traveled ${weeklyDistance.toStringAsFixed(1)} km',
            Icons.route,
          ),
          _buildInsightRow(
            'Your carbon savings: ${_calculateSavings(stats)} kg CO₂',
            Icons.eco,
          ),
          _buildInsightRow(
            'Most productive mode: ${_getMostProductiveMode(logs)}',
            Icons.star,
          ),
        ],
      ),
    );
  }

  Widget _buildInsightRow(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.tertiary.withOpacity(0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _calculateSavings(CommuteStats stats) {
    // Assume average car usage and calculate savings
    final carEmissions = stats.totalDistance * 0.171;
    final actualEmissions = stats.totalCarbon;
    final savings = carEmissions - actualEmissions;
    return savings.toStringAsFixed(1);
  }

  String _getMostProductiveMode(List<CommuteLog> logs) {
    if (logs.isEmpty) return 'None';

    final modeProductivity = <String, List<double>>{};
    for (final log in logs) {
      modeProductivity.putIfAbsent(log.mode, () => []).add(log.productivityScore);
    }

    String bestMode = 'None';
    double bestAvg = 0;

    for (final entry in modeProductivity.entries) {
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      if (avg > bestAvg) {
        bestAvg = avg;
        bestMode = entry.key;
      }
    }

    return bestMode.capitalize();
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_walk,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Commute Data Yet',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start logging your commutes to see detailed analytics and insights here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.add),
            label: Text(
              'Log First Commute',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading your analytics...',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                'Unable to Load Data',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.red[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please check your connection and try again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Extension to capitalize strings
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1).toLowerCase();
  }
}
