import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

typedef OnRouteFinished = void Function({
  required LatLng start,
  required LatLng end,
  required List<LatLng> routePoints,
  required double distanceKm,
  required int durationSeconds,
  required DateTime startTime,
  required DateTime endTime,
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
    with AutomaticKeepAliveClientMixin<InlineMapTracker>, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  List<LatLng> _polylinePoints = [];
  bool isTracking = false;
  LatLng? startPos;
  LatLng? endPos;
  DateTime? startTime;
  DateTime? endTime;
  Duration _elapsed = Duration.zero;

  final _service = FlutterBackgroundService();

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(19.0760, 72.8777),
    zoom: 13,
  );

  StreamSubscription? _serviceSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen to background service update events
    _serviceSub = _service.on('update').listen((event) {
      if (event == null) return;

      try {
        if (event['type'] == 'time') {
          final seconds = (event['elapsed_seconds'] as num).toInt();
          if (mounted) {
            setState(() {
              _elapsed = Duration(seconds: seconds);
            });
          }
        }

        if (event['type'] == 'location') {
          final lat = (event['lat'] as num).toDouble();
          final lng = (event['lng'] as num).toDouble();
          final newPoint = LatLng(lat, lng);
          if (mounted) {
            setState(() {
              _polylinePoints.add(newPoint);
            });
            _mapController?.animateCamera(CameraUpdate.newLatLng(newPoint));
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('InlineMapTracker: error parsing service event: $e');
      }
    });

    _restoreTempRouteIfAny();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceSub?.cancel();
    _mapController?.dispose();
    _saveTempRouteIfNeeded();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveTempRouteIfNeeded();
    } else if (state == AppLifecycleState.resumed) {
      _restoreTempRouteIfAny();
    }
  }

  Future<void> _saveTempRouteIfNeeded() async {
    if (_polylinePoints.isEmpty && !isTracking) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/_tmp_route.json');
      final data = {
        'polyline': _polylinePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'start': startPos != null ? {'lat': startPos!.latitude, 'lng': startPos!.longitude} : null,
        'isTracking': isTracking,
        'elapsedSeconds': _elapsed.inSeconds,
        'startTime': startTime?.toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      if (kDebugMode) debugPrint('InlineMapTracker: failed to save tmp route: $e');
    }
  }

  Future<void> _restoreTempRouteIfAny() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/_tmp_route.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final data = jsonDecode(content);

      final poly = (data['polyline'] as List)
          .map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
          .toList();

      if (!mounted) return;
      setState(() {
        _polylinePoints = poly;
        if (data['start'] != null) {
          startPos = LatLng((data['start']['lat'] as num).toDouble(), (data['start']['lng'] as num).toDouble());
        }
        isTracking = data['isTracking'] == true;
        _elapsed = Duration(seconds: (data['elapsedSeconds'] as int?) ?? 0);
        if (data['startTime'] != null) {
          try {
            startTime = DateTime.parse(data['startTime'] as String);
          } catch (_) {}
        }
      });

      if (_polylinePoints.isNotEmpty && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(_polylinePoints.last));
      }

      await file.delete();
    } catch (e) {
      if (kDebugMode) debugPrint('InlineMapTracker: restore tmp route failed: $e');
    }
  }

  String _formatSecondsToHms(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formattedElapsed() {
    return _formatSecondsToHms(_elapsed.inSeconds);
  }

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

    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      startPos = LatLng(pos.latitude, pos.longitude);
      _polylinePoints = [startPos!];

      setState(() {
        isTracking = true;
        _elapsed = Duration.zero;
        startTime = DateTime.now();
        endTime = null;
      });

      // Ensure the background service is started before invoking commands.
      await _service.startService();
      // small delay to allow the service to set up listeners
      await Future.delayed(const Duration(milliseconds: 300));
      _service.invoke('startTracking');

      widget.onTripStarted?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start tracking: $e')));
      }
      setState(() {
        isTracking = false;
      });
    }
  }

  Future<void> _stopTracking() async {
    // compute end pos
    if (_polylinePoints.isNotEmpty) {
      endPos = _polylinePoints.last;
    } else if (startPos != null) {
      endPos = startPos;
    } else {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) endPos = LatLng(pos.latitude, pos.longitude);
      } catch (_) {}
    }

    // make sure service stops collecting
    try {
      _service.invoke('stopTracking');
    } catch (_) {}

    endTime = DateTime.now();
    final durationSeconds = _elapsed.inSeconds;

    // compute distance in meters using recorded points
    final double distanceMeters = _polylinePoints.asMap().entries.fold<double>(0.0, (acc, e) {
      if (e.key == 0) return 0.0;
      final prev = _polylinePoints[e.key - 1];
      final cur = e.value;
      return acc + Geolocator.distanceBetween(prev.latitude, prev.longitude, cur.latitude, cur.longitude);
    });
    final km = distanceMeters / 1000.0;

    setState(() {
      isTracking = false;
    });

    if (startPos != null && endPos != null && startTime != null && endTime != null) {
      widget.onRouteFinished(
        start: startPos!,
        end: endPos!,
        routePoints: _polylinePoints,
        distanceKm: km,
        durationSeconds: durationSeconds,
        startTime: startTime!,
        endTime: endTime!,
      );
    }

    widget.onTripEnded?.call();
  }

  Future<void> _centerToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final target = CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 16);
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(target));
    } catch (e) {
      if (kDebugMode) debugPrint("InlineMapTracker: Error getting location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // REQUIRED when using AutomaticKeepAliveClientMixin:
    // call super.build(context) and ignore the returned value.
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
              polylines: {
                if (_polylinePoints.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _polylinePoints,
                    width: 5,
                  ),
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
            ),
          ),
        ),

        // Live elapsed timer overlay (top-left)
        Positioned(
          top: 16,
          left: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _formattedElapsed(),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        // Center-to-current-location button (top-right)
        Positioned(
          top: 16,
          right: 24,
          child: FloatingActionButton.small(
            heroTag: 'centerBtn',
            onPressed: _centerToCurrentLocation,
            child: const Icon(Icons.my_location),
          ),
        ),

        // Buttons overlay (bottom)
        Positioned(
          bottom: 12,
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
