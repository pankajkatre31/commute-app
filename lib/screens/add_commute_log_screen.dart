// lib/screens/add_commute_log_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'; // optional helper

// ---------------- Score model + compute helper (top-level) ----------------

class _ScoreResult {
  final double stressRaw; // 0..100
  final int stress1to10;
  final double fatigueRaw; // 0..100
  final int fatigue1to10;
  final List<Map<String, dynamic>> stressContributors;
  final List<Map<String, dynamic>> fatigueContributors;

  _ScoreResult({
    required this.stressRaw,
    required this.stress1to10,
    required this.fatigueRaw,
    required this.fatigue1to10,
    required this.stressContributors,
    required this.fatigueContributors,
  });
}

double _clamp01(double v) => v.isFinite ? (v < 0 ? 0 : (v > 1 ? 1 : v)) : 0;

_ScoreResult computeCommuteScoreLocal({
  required double durationMin,
  double delayMin = 0,
  int stopCount = 0,
  double speedVar = 0,
  double crowdness = 0, // 0..1
  double weatherFactor = 0,
  double timeOfDayFactor = 1.0, // 1.0 normal, >1 rush
  bool calendarPressure = false,
  String mode = 'car',
  double sleepHours = 8,
  double priorFatigue = 0,
  double hrElev = 0,
  double stepsExertionNorm = 0,
  double? prevStressSmoothed,
  double? prevFatigueSmoothed,
  double smoothingAlpha = 0.3,
}) {
  final durationNorm = _clamp01(durationMin / 90.0);
  final delayNorm = _clamp01(delayMin / 60.0);
  final stopNorm = _clamp01(stopCount / 10.0);
  final speedVarNorm = _clamp01(speedVar / 0.8);
  final sleepDeficit = _clamp01((8.0 - sleepHours) / 8.0);
  final hrElevNorm = _clamp01(hrElev / 30.0);
  final timeOfDayNorm = _clamp01(timeOfDayFactor - 1.0);
  final crowdNorm = _clamp01(crowdness); // expect 0..1
  final weatherNorm = _clamp01(weatherFactor); // 0..1

  final modeMap = <String, List<double>>{
    'car': [0.6, 0.4],
    'bus': [0.7, 0.3],
    'train': [0.7, 0.3],
    'walk': [0.3, 0.5],
    'cycle': [0.5, 0.6],
    'motorbike': [0.5, 0.5],
    'other': [0.6, 0.4],
  };
  final modeFactors = modeMap.containsKey(mode) ? modeMap[mode]! : [0.6, 0.4];
  final modeStressFactor = modeFactors[0];
  final modeFatigueFactor = modeFactors[1];

  final w = {
    'duration': 0.16, 'delay': 0.16, 'stops': 0.10, 'speedVar': 0.10, 'crowd': 0.10,
    'weather': 0.18, 'timeOfDay': 0.08, 'calendar': 0.06, 'mode': 0.06
  };
  final v = {
    'duration': 0.18, 'sleep': 0.30, 'prior': 0.18, 'hr': 0.10, 'steps': 0.08, 'mode': 0.06
  };

  final stressFeatures = {
    'Duration': w['duration']! * durationNorm,
    'Delay': w['delay']! * delayNorm,
    'Stops': w['stops']! * stopNorm,
    'Speed variability': w['speedVar']! * speedVarNorm,
    'Crowdness': w['crowd']! * crowdNorm,
    'Weather': w['weather']! * weatherNorm,
    'Rush hour': w['timeOfDay']! * timeOfDayNorm,
    'Calendar pressure': w['calendar']! * (calendarPressure ? 1.0 : 0.0),
    'Mode': w['mode']! * modeStressFactor,
  };

  final fatigueFeatures = {
    'Duration': v['duration']! * durationNorm,
    'Sleep deficit': v['sleep']! * sleepDeficit,
    'Prior fatigue': v['prior']! * priorFatigue,
    'HR elevation': v['hr']! * hrElevNorm,
    'Physical exertion': v['steps']! * stepsExertionNorm,
    'Mode': v['mode']! * modeFatigueFactor,
  };

  double stressSum = stressFeatures.values.fold(0.0, (a, b) => a + b);
  double fatigueSum = fatigueFeatures.values.fold(0.0, (a, b) => a + b);

  double stressRaw = (stressSum * 100.0).clamp(0.0, 100.0);
  double fatigueRaw = (fatigueSum * 100.0).clamp(0.0, 100.0);

  if (prevStressSmoothed != null) {
    stressRaw = smoothingAlpha * stressRaw + (1 - smoothingAlpha) * prevStressSmoothed;
  }
  if (prevFatigueSmoothed != null) {
    fatigueRaw = smoothingAlpha * fatigueRaw + (1 - smoothingAlpha) * prevFatigueSmoothed;
  }

  int to1to10(double raw) => ((raw / 100.0) * 9.0 + 1.0).round().clamp(1, 10);

  var topS = stressFeatures.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  var topF = fatigueFeatures.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  final sTotal = stressFeatures.values.fold(0.0, (a, b) => a + b);
  final fTotal = fatigueFeatures.values.fold(0.0, (a, b) => a + b);

  final sContrib = topS.take(3).map((e) => {'name': e.key, 'pct': sTotal > 0 ? (e.value / sTotal * 100.0) : 0.0}).toList();
  final fContrib = topF.take(3).map((e) => {'name': e.key, 'pct': fTotal > 0 ? (e.value / fTotal * 100.0) : 0.0}).toList();

  return _ScoreResult(
    stressRaw: stressRaw,
    stress1to10: to1to10(stressRaw),
    fatigueRaw: fatigueRaw,
    fatigue1to10: to1to10(fatigueRaw),
    stressContributors: sContrib,
    fatigueContributors: fContrib,
  );
}

const String GOOGLE_WEATHER_API_KEY = 'AIzaSyAW3A-mvsl84_XlTp4PtAfxTy7asMjmBrA';

class _CachedWeather {
  final double factor;
  final String label;
  final DateTime fetchedAt;
  _CachedWeather({required this.factor, required this.label, required this.fetchedAt});
}
final Map<String, _CachedWeather> _weatherCache = {};

String _coordsCacheKey(double lat, double lng, [int precision = 3]) {
  final factor = math.pow(10, precision);
  final latR = (lat * factor).round() / factor;
  final lngR = (lng * factor).round() / factor;
  return '${latR.toStringAsFixed(precision)},${lngR.toStringAsFixed(precision)}';
}

Future<Map<String, dynamic>> fetchWeatherFactor(double lat, double lng) async {
  const ttlMinutes = 15;
  final key = _coordsCacheKey(lat, lng, 3);
  final cached = _weatherCache[key];
  if (cached != null) {
    if (DateTime.now().difference(cached.fetchedAt).inMinutes < ttlMinutes) {
      return {'factor': cached.factor, 'label': cached.label, 'source': 'cache'};
    } else {
      _weatherCache.remove(key);
    }
  }

  final googleUrl = Uri.parse(
    'https://weather.googleapis.com/v1/currentConditions:lookup'
    '?key=$GOOGLE_WEATHER_API_KEY'
    '&location.latitude=${lat.toString()}'
    '&location.longitude=${lng.toString()}'
  );

  try {
    if (GOOGLE_WEATHER_API_KEY.trim().isNotEmpty) {
      final gResp = await http.get(googleUrl).timeout(const Duration(seconds: 10));
      if (gResp.statusCode == 200) {
        final gJson = jsonDecode(gResp.body) as Map<String, dynamic>;
        String label = '';
        try {
          label = (gJson['weatherCondition']?['description']?['text'] ?? '').toString();
        } catch (_) {}
        if (label.isEmpty) {
          label = (gJson['description'] ?? gJson['weather']?['description'] ?? '').toString();
        }
        double temp = 0.0;
        try {
          temp = (gJson['temperature']?['degrees'] ?? 0).toDouble();
        } catch (_) {}
        double windSpeedKph = 0.0;
        try {
          windSpeedKph = (gJson['wind']?['speed']?['value'] ?? 0).toDouble();
        } catch (_) {}
        int precipProb = 0;
        try {
          precipProb = (gJson['precipitation']?['probability']?['percent'] ?? 0) as int;
        } catch (_) {}
        int cloudCover = 0;
        try {
          cloudCover = (gJson['cloudCover'] ?? 0) as int;
        } catch (_) {}
        int thunderProb = 0;
        try {
          thunderProb = (gJson['thunderstormProbability'] ?? 0) as int;
        } catch (_) {}

        double factor = 0.0;
        final low = label.toLowerCase();
        if (low.contains('clear') || low.contains('sun')) factor = 0.0;
        else if (low.contains('partly') || low.contains('mostly')) factor = 0.1;
        else if (low.contains('cloud') || low.contains('overcast')) factor = 0.2;
        else if (low.contains('fog') || low.contains('mist')) factor = 0.25;
        else if (low.contains('drizzle') || low.contains('light rain')) factor = 0.45;
        else if (low.contains('rain') || precipProb >= 50) factor = 0.7;
        else if (low.contains('thunder') || thunderProb >= 40) factor = 1.0;
        else if (low.contains('snow') || low.contains('sleet') || low.contains('freezing')) factor = 0.9;
        else factor = 0.15;

        factor = (factor + (precipProb / 100.0) * 0.25).clamp(0.0, 1.0);
        if (windSpeedKph > 15.0) factor = (factor + 0.12).clamp(0.0, 1.0);
        else if (windSpeedKph > 8.0) factor = (factor + 0.06).clamp(0.0, 1.0);
        factor = (factor + (cloudCover / 100.0) * 0.05).clamp(0.0, 1.0);

        final sourceLabel = label.isNotEmpty ? label : 'Google Weather';
        _weatherCache[key] = _CachedWeather(factor: factor, label: sourceLabel, fetchedAt: DateTime.now());
        return {'factor': factor, 'label': sourceLabel, 'source': 'google'};
      } else {
        if (kDebugMode) {
          try {
            final msg = gResp.body;
            print('Google weather failed status: ${gResp.statusCode}');
            print('Response body: $msg');
          } catch (_) {}
        }
      }
    }
  } catch (e) {
    if (kDebugMode) print('Google weather error: $e');
  }

  // Fallback to Open-Meteo (no key)
  try {
    final omUrl = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${lat.toString()}&longitude=${lng.toString()}&current_weather=true'
    );
    final r = await http.get(omUrl).timeout(const Duration(seconds: 6));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final cw = j['current_weather'] as Map<String, dynamic>?;
      final int weatherCode = (cw?['weathercode'] ?? 0) as int;
      final double wind = (cw?['windspeed'] ?? 0).toDouble();
      String label = 'Open-Meteo';
      double factor = 0.2;
      if (weatherCode == 0) { label = 'Clear'; factor = 0.0; }
      else if (weatherCode == 1 || weatherCode == 2) { label = 'Partly cloudy'; factor = 0.1; }
      else if (weatherCode == 3) { label = 'Overcast'; factor = 0.2; }
      else if ((weatherCode >= 51 && weatherCode <= 57) || (weatherCode >= 80 && weatherCode <= 82)) { label = 'Rain'; factor = 0.6; }
      else if ((weatherCode >= 61 && weatherCode <= 67) || (weatherCode >= 95 && weatherCode <= 99)) { label = 'Heavy rain / thunder'; factor = 1.0; }
      else if (weatherCode >= 71 && weatherCode <= 77) { label = 'Snow'; factor = 0.9; }
      if (wind > 15.0) factor = (factor + 0.15).clamp(0.0, 1.0);

      _weatherCache[key] = _CachedWeather(factor: factor, label: label, fetchedAt: DateTime.now());
      return {'factor': factor, 'label': label, 'source': 'open-meteo'};
    }
  } catch (e) {
    if (kDebugMode) print('Open-Meteo fallback failed: $e');
  }

  _weatherCache[key] = _CachedWeather(factor: 0.2, label: 'Unknown', fetchedAt: DateTime.now());
  return {'factor': 0.2, 'label': 'Unknown', 'source': 'fallback'};
}

// ---------------- End weather helpers ----------------

class AddCommuteLogScreen extends StatefulWidget {
  // incoming optional trip data from InlineMapTracker / FacultyDashboard
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final List<LatLng>? routePoints;
  final double? distanceKm;
  final int? durationSeconds;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? selectedMode;

  const AddCommuteLogScreen({
    Key? key,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.routePoints,
    this.distanceKm,
    this.durationSeconds,
    this.startTime,
    this.endTime,
    this.selectedMode,
  }) : super(key: key);

  @override
  State<AddCommuteLogScreen> createState() => _AddCommuteLogScreenState();
}

enum _MarkerType { start, end, none }

class _AddCommuteLogScreenState extends State<AddCommuteLogScreen> {
  GoogleMapController? _mapController;
  final _formKey = GlobalKey<FormState>();

  LatLng? _start;
  LatLng? _end;
  double? _distanceKm;
  String _startAddress = '';
  String _endAddress = '';

  List<LatLng> _routePoints = [];
  _MarkerType _selectedMarker = _MarkerType.none;

  String _selectedMode = 'car';
  final TextEditingController _moodController = TextEditingController();
  final TextEditingController _trackController = TextEditingController();

  // recording timestamps kept inside state
  DateTime? _recordingStartTime;
  DateTime? _recordingEndTime;

  // NEW: keep last computed results and previous smoothed values
  _ScoreResult? _lastScoreResult;
  double _prevStressSmoothed = 0.0;
  double _prevFatigueSmoothed = 0.0;

  // NEW controllers for transit-specific fields (bus/train)
  final TextEditingController _fareController = TextEditingController();
  final TextEditingController _crowdingController = TextEditingController();
  String _punctuality = 'On time';
  final TextEditingController _boardingController = TextEditingController();
  final TextEditingController _alightingController = TextEditingController();
  final TextEditingController _transfersController = TextEditingController();
  final TextEditingController _accessibilityController = TextEditingController();
  bool _hadSeat = false;

  // auto-detected weather label (shown to user in UI)
  String _autoWeatherLabel = '';
  String _autoWeatherSource = '';

  final List<String> _transportModes = [
    'walk',
    'cycle',
    'motorbike',
    'car',
    'bus',
    'train',
    'other',
  ];

  final Map<String, double> _emissionFactors = {
    'walk': 0.0,
    'cycle': 0.0,
    'motorbike': 0.113,
    'car': 0.171,
    'bus': 0.089,
    'train': 0.041,
    'other': 0.1,
  };

  // Recording state
  StreamSubscription<Position>? _positionSubscription;
  final List<LatLng> _recordedPoints = [];
  bool _isRecording = false;
  int _distanceFilterMeters = 8;

  // API keys (keep secure in production)
  static const String ROADS_API_KEY = 'AIzaSyDL99lwWWUuVOdj0zpOgld5x1xvkDWgU5c';
  static const String DIRECTIONS_API_KEY = 'AIzaSyCeDPReJb0Lr0WEaMWnCRmTfqr5p5EiBfk';

  // Local duration (formatted) if parent provided seconds
  String? _formattedDuration;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _populateFromWidget();
    _loadUserPrevSmoothed();
  }

  Future<void> _loadUserPrevSmoothed() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        setState(() {
          _prevStressSmoothed = (data['prevStressSmoothed'] ?? 0).toDouble();
          _prevFatigueSmoothed = (data['prevFatigueSmoothed'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      if (kDebugMode) print('Failed to load prev smoothed: $e');
    }
  }

  Future<void> _populateFromWidget() async {
    if (widget.selectedMode != null && widget.selectedMode!.isNotEmpty) {
      _selectedMode = widget.selectedMode!;
    }

    if (widget.startLat != null && widget.startLng != null) {
      _start = LatLng(widget.startLat!, widget.startLng!);
      try {
        final placemarks = await placemarkFromCoordinates(_start!.latitude, _start!.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _startAddress = '${p.street ?? ''}, ${p.locality ?? ''}, ${p.administrativeArea ?? ''}';
        }
      } catch (e) {
        if (kDebugMode) print('Reverse geocode start failed: $e');
      }
    }
    if (widget.endLat != null && widget.endLng != null) {
      _end = LatLng(widget.endLat!, widget.endLng!);
      try {
        final placemarks = await placemarkFromCoordinates(_end!.latitude, _end!.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _endAddress = '${p.street ?? ''}, ${p.locality ?? ''}, ${p.administrativeArea ?? ''}';
        }
      } catch (e) {
        if (kDebugMode) print('Reverse geocode end failed: $e');
      }
    }

    if (widget.routePoints != null && widget.routePoints!.isNotEmpty) {
      _routePoints = List<LatLng>.from(widget.routePoints!);
    }
    if (widget.distanceKm != null) {
      _distanceKm = widget.distanceKm;
    }

    if (widget.durationSeconds != null) {
      _formattedDuration = _formatSecondsToHms(widget.durationSeconds!);
    }

    if (_start != null && _end != null && (_routePoints.isEmpty || _distanceKm == null)) {
      try {
        await _recalculateDistance();
      } catch (_) {}
    }

    if ((_distanceKm == null || _distanceKm == 0.0) && _start != null && _end != null) {
      final directMeters = Geolocator.distanceBetween(_start!.latitude, _start!.longitude, _end!.latitude, _end!.longitude);
      _distanceKm = double.parse((directMeters / 1000.0).toStringAsFixed(3));
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
        }
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied.'),
          ),
        );
      }
      return;
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _moodController.dispose();
    _trackController.dispose();
    _fareController.dispose();
    _crowdingController.dispose();
    _boardingController.dispose();
    _alightingController.dispose();
    _transfersController.dispose();
    _accessibilityController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // Markers & polylines
  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_start != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _start!,
          infoWindow: InfoWindow(
            title: 'Start Location',
            snippet: _startAddress,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }
    if (_end != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _end!,
          infoWindow: InfoWindow(title: 'End Location', snippet: _endAddress),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> get _polylines {
    if (_routePoints.isNotEmpty) {
      return {
        Polyline(
          polylineId: const PolylineId('route'),
          color: Theme.of(context).colorScheme.primary,
          width: 5,
          points: _routePoints,
        ),
      };
    }
    return {};
  }

  // Map tap handler
  Future<void> _handleMapTap(LatLng tappedPoint) async {
    if (_selectedMarker == _MarkerType.none) return;

    final position = Position(
      latitude: tappedPoint.latitude,
      longitude: tappedPoint.longitude,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );

    final address = await _getAddress(position);

    if (_selectedMarker == _MarkerType.start) {
      setState(() {
        _start = tappedPoint;
        _startAddress = address;
        _selectedMarker = _MarkerType.none;
      });
      await _recalculateDistance();
    } else if (_selectedMarker == _MarkerType.end) {
      setState(() {
        _end = tappedPoint;
        _endAddress = address;
        _selectedMarker = _MarkerType.none;
      });
      await _recalculateDistance();
    }
  }

  Future<void> _setCurrentAsStart() async {
    final pos = await Geolocator.getCurrentPosition();
    final address = await _getAddress(pos);
    setState(() {
      _start = LatLng(pos.latitude, pos.longitude);
      _startAddress = address;
      _routePoints.clear();
      _distanceKm = null;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(_start!));
    await _recalculateDistance();
  }

  Future<void> _setCurrentAsEnd() async {
    final pos = await Geolocator.getCurrentPosition();
    final address = await _getAddress(pos);
    setState(() {
      _end = LatLng(pos.latitude, pos.longitude);
      _endAddress = address;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(_end!));
    await _recalculateDistance();
  }

  Future<String> _getAddress(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return '${p.street ?? ''}, ${p.locality ?? ''}, ${p.administrativeArea ?? ''}';
      }
    } catch (e) {
      if (kDebugMode) print('Error during geocoding: $e');
    }
    return 'Unknown Location';
  }

  Future<List<LatLng>> _getRoutePolyline(LatLng start, LatLng end) async {
    const apiKey = DIRECTIONS_API_KEY;
    final mode = _selectedMode == 'car' ? 'driving' : _selectedMode;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${start.latitude},${start.longitude}'
      '&destination=${end.latitude},${end.longitude}'
      '&mode=$mode'
      '&key=$apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final points = data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(points);
        }
      } else {
        if (kDebugMode) print('Directions API failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) print('Directions API error: $e');
    }
    return [];
  }

  List<LatLng> _decodePolyline(String polyline) {
    final List<LatLng> points = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Future<void> _recalculateDistance() async {
    if (_start != null && _end != null) {
      final route = await _getRoutePolyline(_start!, _end!);
      setState(() {
        _routePoints = route;
      });

      if (_routePoints.isNotEmpty) {
        double totalDistance = 0.0;
        for (int i = 0; i < _routePoints.length - 1; i++) {
          totalDistance += Geolocator.distanceBetween(
            _routePoints[i].latitude,
            _routePoints[i].longitude,
            _routePoints[i + 1].latitude,
            _routePoints[i + 1].longitude,
          );
        }
        _distanceKm = totalDistance / 1000;
      } else {
        final meters = Geolocator.distanceBetween(_start!.latitude, _start!.longitude, _end!.latitude, _end!.longitude);
        _distanceKm = meters / 1000.0;
      }
    } else {
      setState(() {
        _distanceKm = null;
        _routePoints.clear();
      });
    }
  }

  // Recording helpers
  Future<void> startRecording() async {
    await _checkLocationPermission();
    _recordedPoints.clear();
    setState(() {
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingEndTime = null;
    });

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: _distanceFilterMeters,
    );

    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position pos) {
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _recordedPoints.add(p);
        _routePoints = List<LatLng>.from(_recordedPoints);
      });
    });
  }

  Future<void> stopRecording() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    setState(() {
      _isRecording = false;
      _recordingEndTime = DateTime.now();
    });
  }

  double _computeDistanceFromPoints(List<LatLng> pts) {
    if (pts.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += Geolocator.distanceBetween(
        pts[i].latitude, pts[i].longitude,
        pts[i+1].latitude, pts[i+1].longitude,
      );
    }
    return total / 1000.0; // km
  }

  // Roads API snapping helpers
  Future<List<LatLng>> _snapToRoadsChunk(List<LatLng> rawPoints, String apiKey) async {
    if (rawPoints.isEmpty) return [];
    final path = rawPoints.map((p) => '${p.latitude},${p.longitude}').join('|');
    final url = Uri.parse('https://roads.googleapis.com/v1/snapToRoads?path=$path&interpolate=true&key=$apiKey');

    try {
      final resp = await http.get(url);
      if (resp.statusCode != 200) {
        if (kDebugMode) print('snapToRoads failed: ${resp.statusCode} ${resp.body}');
        return [];
      }
      final data = jsonDecode(resp.body);
      final List<LatLng> snapped = [];
      if (data['snappedPoints'] != null) {
        for (final sp in data['snappedPoints']) {
          final loc = sp['location'];
          snapped.add(LatLng((loc['latitude'] as num).toDouble(), (loc['longitude'] as num).toDouble()));
        }
      }
      return snapped;
    } catch (e) {
      if (kDebugMode) print('snapToRoads error: $e');
      return [];
    }
  }

  Future<List<LatLng>> _snapLargePointList(List<LatLng> points, String apiKey) async {
    if (points.isEmpty) return [];
    if (points.length <= 100) return _snapToRoadsChunk(points, apiKey);

    final List<LatLng> merged = [];
    const int chunkSize = 100;
    for (int i = 0; i < points.length; i += (chunkSize - 1)) {
      final end = (i + chunkSize) > points.length ? points.length : (i + chunkSize);
      final sub = points.sublist(i, end);
      final snapped = await _snapToRoadsChunk(sub, apiKey);
      if (snapped.isEmpty) continue;
      if (merged.isNotEmpty &&
          merged.last.latitude == snapped.first.latitude &&
          merged.last.longitude == snapped.first.longitude) {
        merged.addAll(snapped.skip(1));
      } else {
        merged.addAll(snapped);
      }
    }
    return merged;
  }

  // Save log (include trip start/end timestamps if available)
  Future<void> _saveLog() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct form errors.')),
      );
      return;
    }

    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set start and end points.')),
      );
      return;
    }

    if (_isRecording) {
      await stopRecording();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    List<LatLng> routeToSave = [];
    if (_recordedPoints.isNotEmpty) {
      if (ROADS_API_KEY.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ROADS_API_KEY missing — falling back to Directions API')));
        routeToSave = await _getRoutePolyline(_start!, _end!);
      } else {
        final snapped = await _snapLargePointList(_recordedPoints, ROADS_API_KEY);
        if (snapped.isNotEmpty) {
          routeToSave = snapped;
        } else {
          routeToSave = await _getRoutePolyline(_start!, _end!);
        }
      }
    } else if (_routePoints.isNotEmpty) {
      routeToSave = _routePoints;
    } else {
      routeToSave = await _getRoutePolyline(_start!, _end!);
    }

    double computedDistance = _computeDistanceFromPoints(routeToSave);
    if ((computedDistance == 0.0 || computedDistance.isNaN) && _start != null && _end != null) {
      final meters = Geolocator.distanceBetween(_start!.latitude, _start!.longitude, _end!.latitude, _end!.longitude);
      computedDistance = meters / 1000.0;
    }

    setState(() {
      _routePoints = routeToSave;
      _distanceKm = (computedDistance > 0.0) ? computedDistance : _distanceKm;
    });

    if (_distanceKm == null || _distanceKm == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine route distance.')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final checkpoints = _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    final encoded = encodePolyline(_routePoints.cast<LatLng>());

    final docData = <String, dynamic>{
      'userId': uid,
      'date': FieldValue.serverTimestamp(),
      'mode': _selectedMode,
      'distanceKm': _distanceKm,
      'startLocation': {'lat': _start!.latitude, 'lng': _start!.longitude},
      'endLocation': {'lat': _end!.latitude, 'lng': _end!.longitude},
      'startAddress': _startAddress,
      'endAddress': _endAddress,
      'checkpoints': checkpoints,
      'polyline': encoded,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // include timestamps: prefer widget-supplied, then recording timestamps, else now
    DateTime startTs = widget.startTime ?? _recordingStartTime ?? DateTime.now();
    DateTime endTs = widget.endTime ?? _recordingEndTime ?? DateTime.now();

    docData['tripStart'] = Timestamp.fromDate(startTs);
    docData['tripEnd'] = Timestamp.fromDate(endTs);

    if (widget.durationSeconds != null) {
      docData['durationSeconds'] = widget.durationSeconds;
    } else {
      final durationSecs = endTs.difference(startTs).inSeconds;
      if (durationSecs > 0) docData['durationSeconds'] = durationSecs;
    }

    // optional fields for walk/cycle
    if (_selectedMode == 'walk' || _selectedMode == 'cycle') {
      docData['mood'] = _moodController.text;
      docData['track'] = _trackController.text;
    } else if (_selectedMode == 'bus' || _selectedMode == 'train') {
      final fare = double.tryParse(_fareController.text);
      if (fare != null) docData['farePaid'] = fare;

      final crowd = double.tryParse(_crowdingController.text);
      if (crowd != null) {
        docData['crowdingLevel'] = crowd.clamp(0.0, 10.0);
      }

      docData['punctuality'] = _punctuality;
      if (_boardingController.text.isNotEmpty) docData['boardingStop'] = _boardingController.text;
      if (_alightingController.text.isNotEmpty) docData['alightingStop'] = _alightingController.text;

      final transfers = int.tryParse(_transfersController.text);
      if (transfers != null) docData['transfers'] = transfers;

      if (_accessibilityController.text.isNotEmpty) docData['accessibilityIssues'] = _accessibilityController.text;

      docData['hadSeat'] = _hadSeat;
    } else {
      // productivity removed per request — if you'd like to store it optionally, add a non-required input
    }

    // ---------- AUTOMATIC compute of fatigue & stress before saving ----------
    double durationMin = 0;
    if (widget.durationSeconds != null) {
      durationMin = widget.durationSeconds! / 60.0;
    } else if (widget.startTime != null && widget.endTime != null) {
      durationMin = widget.endTime!.difference(widget.startTime!).inMinutes.toDouble();
    } else if (_distanceKm != null) {
      durationMin = (_distanceKm! / 30.0) * 60.0; // fallback estimate
    }

    // weather factor: auto-detect for walk/cycle/car/motorbike; else neutral but still saved
    double weatherFactor = 0.0;
    try {
      if (['walk', 'cycle', 'car', 'motorbike'].contains(_selectedMode)) {
        if (_start != null) {
          final w = await fetchWeatherFactor(_start!.latitude, _start!.longitude);
          weatherFactor = (w['factor'] as double);
          docData['weatherAuto'] = {'label': w['label'], 'source': w['source']};
          setState(() {
            _autoWeatherLabel = w['label'] as String;
            _autoWeatherSource = w['source'] as String;
          });
        } else if (_routePoints.isNotEmpty) {
          final mid = _routePoints[_routePoints.length ~/ 2];
          final w = await fetchWeatherFactor(mid.latitude, mid.longitude);
          weatherFactor = (w['factor'] as double);
          docData['weatherAuto'] = {'label': w['label'], 'source': w['source']};
          setState(() {
            _autoWeatherLabel = w['label'] as String;
            _autoWeatherSource = w['source'] as String;
          });
        } else {
          weatherFactor = 0.2;
        }
      } else {
        if (_start != null) {
          final w = await fetchWeatherFactor(_start!.latitude, _start!.longitude);
          docData['weatherAuto'] = {'label': w['label'], 'source': w['source']};
        }
        weatherFactor = 0.2;
      }
    } catch (e) {
      if (kDebugMode) print('Weather fetch failed on save: $e');
      weatherFactor = 0.2;
    }

    double crowdnessNorm = 0.0;
    if ((_selectedMode == 'bus' || _selectedMode == 'train') && _crowdingController.text.isNotEmpty) {
      final c = double.tryParse(_crowdingController.text) ?? 0.0;
      crowdnessNorm = _clamp01(c / 10.0);
    }

    double speedVar = 0.0;

    final computed = computeCommuteScoreLocal(
      durationMin: durationMin,
      delayMin: 0,
      stopCount: 0,
      speedVar: speedVar,
      crowdness: crowdnessNorm,
      weatherFactor: weatherFactor,
      timeOfDayFactor: 1.0,
      calendarPressure: false,
      mode: _selectedMode,
      sleepHours: 8,
      priorFatigue: 0,
      hrElev: 0,
      stepsExertionNorm: 0,
      prevStressSmoothed: _prevStressSmoothed,
      prevFatigueSmoothed: _prevFatigueSmoothed,
    );

    // save computed values to the commute doc
    docData['stressRaw'] = computed.stressRaw;
    docData['stress1to10'] = computed.stress1to10;
    docData['fatigueRaw'] = computed.fatigueRaw;
    docData['fatigue1to10'] = computed.fatigue1to10;
    docData['stressContributors'] = computed.stressContributors;
    docData['fatigueContributors'] = computed.fatigueContributors;

    try {
      await FirebaseFirestore.instance.collection('commute_logs').add(docData);

      // update user's prev smoothed values for next smoothing
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'prevStressSmoothed': computed.stressRaw,
        'prevFatigueSmoothed': computed.fatigueRaw,
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commute log saved successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save log: ${e.toString()}')),
      );
    }
  }

  // encode polyline
  String encodePolyline(List<LatLng> points) {
    int _encodeSigned(int value) {
      value = value < 0 ? ~(value << 1) : (value << 1);
      return value;
    }

    StringBuffer result = StringBuffer();
    int lastLat = 0;
    int lastLng = 0;

    for (final p in points) {
      int lat = (p.latitude * 1e5).round();
      int lng = (p.longitude * 1e5).round();

      int dLat = lat - lastLat;
      int dLng = lng - lastLng;

      lastLat = lat;
      lastLng = lng;

      for (var v in [dLat, dLng]) {
        int value = _encodeSigned(v);
        while (value >= 0x20) {
          int next = (0x20 | (value & 0x1f)) + 63;
          result.writeCharCode(next);
          value >>= 5;
        }
        result.writeCharCode(value + 63);
      }
    }
    return result.toString();
  }

  Future<String> _getMapStyle() async {
    if (Theme.of(context).brightness == Brightness.dark) {
      return await rootBundle.loadString('assets/map_style_dark.json');
    }
    return '[]';
  }

  String _formatSecondsToHms(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // --- UI helpers for score preview card ------------------------------------------------------
  Widget _scoreCardWidget(String title, int score, double raw, List<Map<String, dynamic>> contributors) {
    Color color;
    if (score <= 3) color = Colors.green;
    else if (score <= 6) color = Colors.orange;
    else color = Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color,
              child: Text(score.toString(), style: const TextStyle(fontSize: 20, color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Raw: ${raw.toStringAsFixed(1)} / 100'),
                  const SizedBox(height: 6),
                  ...contributors.map((c) => Text('${c['name']}: ${c['pct'].toStringAsFixed(0)}%')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _computePreviewScores() async {
    double durationMin = 0;
    if (widget.durationSeconds != null) {
      durationMin = widget.durationSeconds! / 60.0;
    } else if (widget.startTime != null && widget.endTime != null) {
      durationMin = widget.endTime!.difference(widget.startTime!).inMinutes.toDouble();
    } else if (_distanceKm != null) {
      durationMin = (_distanceKm! / 30.0) * 60.0;
    }

    double crowdnessNorm = 0.0;
    if ((_selectedMode == 'bus' || _selectedMode == 'train') && _crowdingController.text.isNotEmpty) {
      final c = double.tryParse(_crowdingController.text) ?? 0.0;
      crowdnessNorm = _clamp01(c / 10.0);
    }

    double speedVarNorm = 0.0;

    // weather: auto-detect for walk/cycle/car/motorbike (and show label)
    double weatherFactor = 0.0;
    String weatherLabel = '';
    if (['walk', 'cycle', 'car', 'motorbike'].contains(_selectedMode)) {
      try {
        if (_start != null) {
          final w = await fetchWeatherFactor(_start!.latitude, _start!.longitude);
          weatherFactor = (w['factor'] as double);
          weatherLabel = (w['label'] as String);
          setState(() {
            _autoWeatherLabel = weatherLabel;
            _autoWeatherSource = w['source'] as String;
          });
        } else if (_routePoints.isNotEmpty) {
          final mid = _routePoints[_routePoints.length ~/ 2];
          final w = await fetchWeatherFactor(mid.latitude, mid.longitude);
          weatherFactor = (w['factor'] as double);
          weatherLabel = (w['label'] as String);
          setState(() {
            _autoWeatherLabel = weatherLabel;
            _autoWeatherSource = w['source'] as String;
          });
        } else {
          weatherFactor = 0.2;
        }
      } catch (e) {
        if (kDebugMode) print('Weather preview fetch failed: $e');
        weatherFactor = 0.2;
      }
    }

    final result = computeCommuteScoreLocal(
      durationMin: durationMin,
      delayMin: 0,
      stopCount: 0,
      speedVar: speedVarNorm,
      crowdness: crowdnessNorm,
      weatherFactor: weatherFactor,
      timeOfDayFactor: 1.0,
      calendarPressure: false,
      mode: _selectedMode,
      sleepHours: 8,
      priorFatigue: 0,
      hrElev: 0,
      stepsExertionNorm: 0,
      prevStressSmoothed: _prevStressSmoothed,
      prevFatigueSmoothed: _prevFatigueSmoothed,
    );

    setState(() {
      _lastScoreResult = result;
      if (weatherLabel.isNotEmpty) _autoWeatherLabel = weatherLabel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hideBottomButtons = _start != null && _end != null && _routePoints.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Commute Log')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FutureBuilder(
                  future: _getMapStyle(),
                  builder: (context, snapshot) {
                    return GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: LatLng(19.0760, 72.8777),
                        zoom: 14,
                      ),
                      onMapCreated: (c) {
                        _mapController = c;
                        if (snapshot.hasData) {
                          _mapController?.setMapStyle(snapshot.data!);
                        }
                        if (_routePoints.isNotEmpty) {
                          try {
                            _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_boundsFromLatLngList(_routePoints), 80));
                          } catch (_) {}
                        } else if (_end != null) {
                          _mapController?.animateCamera(CameraUpdate.newLatLng(_end!));
                        } else if (_start != null) {
                          _mapController?.animateCamera(CameraUpdate.newLatLng(_start!));
                        }
                      },
                      markers: _markers,
                      polylines: _polylines,
                      myLocationEnabled: true,
                      onTap: _handleMapTap,
                    );
                  },
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: AnimatedOpacity(
                    opacity: _selectedMarker != _MarkerType.none ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: _selectedMarker == _MarkerType.none,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _selectedMarker == _MarkerType.start
                              ? 'Tap on the map to set the start point.'
                              : 'Tap on the map to set the end point.',
                          style: GoogleFonts.poppins(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),

                if (!hideBottomButtons)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          FloatingActionButton.extended(
                            heroTag: 'startCurrentBtn',
                            onPressed: _start != null ? null : _setCurrentAsStart,
                            icon: const Icon(Icons.my_location),
                            label: const Text('My Location Start'),
                          ),
                          const SizedBox(width: 8),
                          FloatingActionButton.extended(
                            heroTag: 'endCurrentBtn',
                            onPressed: _end != null ? null : _setCurrentAsEnd,
                            icon: const Icon(Icons.my_location),
                            label: const Text('My Location End'),
                          ),
                          const SizedBox(width: 8),
                          FloatingActionButton.extended(
                            heroTag: 'tapBtn',
                            onPressed: () {
                              setState(() {
                                _selectedMarker = _selectedMarker == _MarkerType.none
                                    ? _MarkerType.start
                                    : _MarkerType.none;
                              });
                              if (_selectedMarker != _MarkerType.none) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tap on the map to set location.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.pin_drop),
                            label: const Text('Set by Tap'),
                          ),
                          const SizedBox(width: 8),
                          FloatingActionButton.extended(
                            heroTag: 'recordBtn',
                            onPressed: () async {
                              if (!_isRecording) {
                                await startRecording();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording started')));
                              } else {
                                await stopRecording();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording stopped')));
                                if (_recordedPoints.isNotEmpty) {
                                  _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
                                    _boundsFromLatLngList(_recordedPoints),
                                    80,
                                  ));
                                }
                              }
                            },
                            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                            label: Text(_isRecording ? 'Stop' : 'Start'),
                            backgroundColor: _isRecording ? Colors.red : Colors.green,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (widget.startTime != null || widget.endTime != null || _formattedDuration != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Trip Start:', style: GoogleFonts.poppins()),
                            Text(widget.startTime != null ? widget.startTime!.toLocal().toString() : 'N/A', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Trip End:', style: GoogleFonts.poppins()),
                            Text(widget.endTime != null ? widget.endTime!.toLocal().toString() : 'N/A', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_formattedDuration != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Duration:', style: GoogleFonts.poppins()),
                              Text(_formattedDuration!, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        const SizedBox(height: 12),
                      ],

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Distance:',
                            style: GoogleFonts.poppins(textStyle: const TextStyle(fontSize: 16)),
                          ),
                          Text(
                            _distanceKm != null ? '${_distanceKm!.toStringAsFixed(2)} km' : 'N/A',
                            style: GoogleFonts.poppins(textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CO₂ Estimate:',
                            style: GoogleFonts.poppins(textStyle: const TextStyle(fontSize: 16)),
                          ),
                          Text(
                            _distanceKm != null ? '${(_distanceKm! * (_emissionFactors[_selectedMode] ?? 0.1)).toStringAsFixed(2)} kg' : 'N/A',
                            style: GoogleFonts.poppins(textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedMode,
                        decoration: const InputDecoration(
                          labelText: 'Transport Mode',
                          prefixIcon: Icon(Icons.directions_transit),
                        ),
                        items: _transportModes.map((mode) {
                          return DropdownMenuItem(
                            value: mode,
                            child: Text(mode.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedMode = value!;
                            if (!(_selectedMode == 'bus' || _selectedMode == 'train')) {
                              _fareController.clear();
                              _crowdingController.clear();
                              _punctuality = 'On time';
                              _boardingController.clear();
                              _alightingController.clear();
                              _transfersController.clear();
                              _accessibilityController.clear();
                              _hadSeat = false;
                            }
                            _lastScoreResult = null;
                            _autoWeatherLabel = '';
                            _autoWeatherSource = '';
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      /// Conditional Section
                      if (_selectedMode == 'walk' || _selectedMode == 'cycle') ...[
                        TextFormField(
                          controller: _moodController,
                          decoration: const InputDecoration(
                            labelText: 'How was your mood?',
                            prefixIcon: Icon(Icons.emoji_emotions),
                          ),
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Please enter your mood';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _trackController,
                          decoration: const InputDecoration(
                            labelText: 'What was the track?',
                            prefixIcon: Icon(Icons.alt_route),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _autoWeatherLabel.isNotEmpty ? 'Weather: $_autoWeatherLabel' : 'Weather: (auto-detected on Preview/Save)',
                                style: GoogleFonts.poppins(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                await _computePreviewScores();
                              },
                              child: const Text('Refresh weather & preview'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ] else if (_selectedMode == 'bus' || _selectedMode == 'train') ...[
                        TextFormField(
                          controller: _fareController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Fare Paid (e.g., 25.50)',
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return null; // optional
                            }
                            final f = double.tryParse(value);
                            if (f == null || f < 0) return 'Enter a valid fare';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Crowding (0 - 10)', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: double.tryParse(_crowdingController.text) ?? 0.0,
                                min: 0,
                                max: 10,
                                divisions: 20,
                                label: (double.tryParse(_crowdingController.text) ?? 0.0).toStringAsFixed(1),
                                onChanged: (v) {
                                  setState(() {
                                    _crowdingController.text = v.toStringAsFixed(1);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextFormField(
                                controller: _crowdingController,
                                textAlign: TextAlign.center,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(hintText: '0.0'),
                                validator: (value) {
                                  if (value == null || value.isEmpty) return null;
                                  final d = double.tryParse(value);
                                  if (d == null || d < 0 || d > 10) return '0-10';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: _punctuality,
                          decoration: const InputDecoration(
                            labelText: 'Punctuality',
                            prefixIcon: Icon(Icons.access_time),
                          ),
                          items: ['On time', 'Slightly late', 'Very late']
                              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                              .toList(),
                          onChanged: (val) => setState(() => _punctuality = val ?? 'On time'),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _boardingController,
                          decoration: const InputDecoration(
                            labelText: 'Boarding Stop (optional)',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _alightingController,
                          decoration: const InputDecoration(
                            labelText: 'Alighting Stop (optional)',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _transfersController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Transfers (count)',
                            prefixIcon: Icon(Icons.swap_horiz),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return null;
                            final v = int.tryParse(value);
                            if (v == null || v < 0) return 'Enter a valid number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _accessibilityController,
                          decoration: const InputDecoration(
                            labelText: 'Accessibility issues (optional)',
                            prefixIcon: Icon(Icons.accessible),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Checkbox(
                              value: _hadSeat,
                              onChanged: (v) => setState(() => _hadSeat = v ?? false),
                            ),
                            const SizedBox(width: 8),
                            Text('Had a seat during the trip', style: GoogleFonts.poppins()),
                          ],
                        ),
                      ] else ...[
                        // car, motorbike, other: no productivity input per request
                        const SizedBox.shrink(),
                      ],

                      const SizedBox(height: 16),

                      // ---------- AUTOMATIC fatigue/stress display ----------
                      if (_lastScoreResult != null) ...[
                        _scoreCardWidget('Stress', _lastScoreResult!.stress1to10, _lastScoreResult!.stressRaw, _lastScoreResult!.stressContributors),
                        const SizedBox(height: 8),
                        _scoreCardWidget('Fatigue', _lastScoreResult!.fatigue1to10, _lastScoreResult!.fatigueRaw, _lastScoreResult!.fatigueContributors),
                        const SizedBox(height: 8),
                        if (_autoWeatherLabel.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Detected weather: $_autoWeatherLabel (source: $_autoWeatherSource)', style: GoogleFonts.poppins(fontSize: 13)),
                          ),
                        const SizedBox(height: 12),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Stress & fatigue are auto-calculated when you Save the commute. Tap "Refresh weather & preview" to see predicted values before saving.',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await _computePreviewScores();
                              },
                              child: const Text('Preview score'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _saveLog,
                              icon: const Icon(Icons.save),
                              label: const Text('Save Commute'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    assert(list.isNotEmpty);
    double x0 = list.first.latitude;
    double x1 = list.first.latitude;
    double y0 = list.first.longitude;
    double y1 = list.first.longitude;
    for (LatLng latLng in list) {
      if (latLng.latitude > x1) x1 = latLng.latitude;
      if (latLng.latitude < x0) x0 = latLng.latitude;
      if (latLng.longitude > y1) y1 = latLng.longitude;
      if (latLng.longitude < y0) y0 = latLng.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(x0, y0),
      northeast: LatLng(x1, y1),
    );
  }
}
