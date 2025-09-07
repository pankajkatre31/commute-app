// lib/widgets/inline_map_tracker.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

/// Note: OnRouteFinished now includes durationSeconds so parent can save duration.
typedef OnRouteFinished = void Function({
  required LatLng start,
  required LatLng end,
  required List<LatLng> routePoints,
  required double distanceKm,
  required int durationSeconds,
});

class InlineMapTracker extends StatefulWidget {
  final double height;
  final OnRouteFinished onRouteFinished;

  final VoidCallback? onTripStarted;
  final VoidCallback? onTripEnded;

  const InlineMapTracker({
    Key? key,
    this.height = 360,
    required this.onRouteFinished,
    this.onTripStarted,
    this.onTripEnded,
  }) : super(key: key);

  @override
  _InlineMapTrackerState createState() => _InlineMapTrackerState();
}

class _InlineMapTrackerState extends State<InlineMapTracker>
    with
        AutomaticKeepAliveClientMixin<InlineMapTracker>,
        WidgetsBindingObserver {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posSub;
  List<LatLng> _polylinePoints = [];
  bool isTracking = false;
  LatLng? startPos;
  LatLng? endPos;

  // Timer/elapsed
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  static final CameraPosition _initialCamera = CameraPosition(
    target: LatLng(19.0760, 72.8777),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreTempRouteIfAny();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _posSub?.cancel();
    _mapController?.dispose();
    _saveTempRouteIfNeeded();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveTempRouteIfNeeded();
    } else if (state == AppLifecycleState.resumed) {
      _restoreTempRouteIfAny();
    }
  }

  Future<void> _saveTempRouteIfNeeded() async {
    if (_polylinePoints.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/_tmp_route.json');
      final data = {
        'polyline': _polylinePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'start': startPos != null ? {'lat': startPos!.latitude, 'lng': startPos!.longitude} : null,
        'end': endPos != null ? {'lat': endPos!.latitude, 'lng': endPos!.longitude} : null,
        'isTracking': isTracking,
        'elapsedSeconds': _elapsed.inSeconds,
      };
      await file.writeAsString(jsonEncode(data));
      debugPrint('InlineMapTracker: saved temp route (${_polylinePoints.length} pts, elapsed=${_elapsed.inSeconds}s)');
    } catch (e) {
      debugPrint('InlineMapTracker: Failed to save temp route: $e');
    }
  }

  Future<void> _restoreTempRouteIfAny() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/_tmp_route.json');
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final data = jsonDecode(content);
      final poly = (data['polyline'] as List).map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble())).toList();

      if (!mounted) return;
      setState(() {
        _polylinePoints = poly;
        if (data['start'] != null) {
          startPos = LatLng((data['start']['lat'] as num).toDouble(), (data['start']['lng'] as num).toDouble());
        }
        if (data['end'] != null) {
          endPos = LatLng((data['end']['lat'] as num).toDouble(), (data['end']['lng'] as num).toDouble());
        }
        isTracking = data['isTracking'] == true;
        _elapsed = Duration(seconds: (data['elapsedSeconds'] as int?) ?? 0);
      });

      if (isTracking) {
        // resume timer if tracking was active
        _startTimer();
      }

      if (_polylinePoints.isNotEmpty && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(_polylinePoints.last));
      }

      try {
        await file.delete();
      } catch (_) {}
      debugPrint('InlineMapTracker: restored temp route (${_polylinePoints.length} pts, elapsed=${_elapsed.inSeconds}s)');
    } catch (e) {
      debugPrint('InlineMapTracker: No temp route to restore or failed: $e');
    }
  }

  // ---------- Timer helpers ----------
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _elapsed += const Duration(seconds: 1);
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

// inside _InlineMapTrackerState

// helper in the state: add this method to format seconds
String _formatSecondsToHms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
}
String _formattedElapsed() {
  return _formatSecondsToHms(_elapsed.inSeconds);
}



  // --------- Tracking ----------
  Future<void> _startTracking() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required to track route.')),
        );
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    startPos = LatLng(pos.latitude, pos.longitude);
    _polylinePoints = [startPos!];

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 6,
      ),
    ).listen((Position p) {
      final latLng = LatLng(p.latitude, p.longitude);
      setState(() {
        _polylinePoints.add(latLng);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
    });

    setState(() {
      isTracking = true;
      _elapsed = Duration.zero; // reset timer on start
    });

    _startTimer();

    // remove old checkpoint if present
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/_tmp_route.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}

    widget.onTripStarted?.call();
  }

  Future<void> _stopTracking() async {
    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    endPos = LatLng(pos.latitude, pos.longitude);
    _polylinePoints.add(endPos!);

    await _posSub?.cancel();
    _posSub = null;

    // stop timer and capture elapsed
    _stopTimer();
    final durationSeconds = _elapsed.inSeconds;

    final double distanceMeters = _polylinePoints.asMap().entries.fold<double>(0.0, (acc, e) {
      if (e.key == 0) return 0.0;
      final prev = _polylinePoints[e.key - 1];
      final cur = _polylinePoints[e.key];
      return acc + Geolocator.distanceBetween(prev.latitude, prev.longitude, cur.latitude, cur.longitude);
    });

    final km = distanceMeters / 1000.0;

    setState(() {
      isTracking = false;
    });

    if (startPos != null && endPos != null) {
      widget.onRouteFinished(
  start: startPos!,
  end: endPos!,
  routePoints: _polylinePoints,
  distanceKm: km,
  durationSeconds: _elapsed.inSeconds, // EXACT integer seconds
);

    }

    // delete checkpoint
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/_tmp_route.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}

    widget.onTripEnded?.call();
  }

  Future<void> _centerToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final target = CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 16);
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(target));
    } catch (e) {
      debugPrint("InlineMapTracker: Error getting location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Container(
          height: widget.height,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black12)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GoogleMap(
              initialCameraPosition: _initialCamera,
              onMapCreated: (c) {
                _mapController = c;
                if (_polylinePoints.isNotEmpty) {
                  _mapController!.animateCamera(CameraUpdate.newLatLng(_polylinePoints.last));
                }
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              polylines: {
                if (_polylinePoints.isNotEmpty)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _polylinePoints,
                    width: 5,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              },
            ),
          ),
        ),

        // Elapsed timer display (top-left)
        if (isTracking)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _formattedElapsed(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

        // My location button (top-right)
        Positioned(
          top: 16,
          right: 16,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 3,
            child: IconButton(
              icon: const Icon(Icons.my_location, color: Colors.black87),
              onPressed: _centerToCurrentLocation,
            ),
          ),
        ),

        // Controls overlay (Start / End)
        Positioned(
          bottom: 18,
          left: 12,
          right: 12,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(isTracking ? 'Tracking...' : 'Start Trip'),
                  onPressed: isTracking ? null : _startTracking,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('End Trip'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isTracking ? Colors.red : Colors.grey,
                  ),
                  onPressed: isTracking ? _stopTracking : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
