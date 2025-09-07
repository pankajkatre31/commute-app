// add_commute_log_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'; // add at top of file
class AddCommuteLogScreen extends StatefulWidget {
  const AddCommuteLogScreen({super.key});

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
  final TextEditingController _productivityController = TextEditingController();
  final TextEditingController _moodController = TextEditingController();
  final TextEditingController _trackController = TextEditingController();
  String? _weather; // dropdown selection
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

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
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

  Future<void> _handleMapTap(LatLng tappedPoint) async {
    // Only proceed if a marker type is selected
    if (_selectedMarker == _MarkerType.none) {
      return;
    }

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
        _recalculateDistance();
      });
    } else if (_selectedMarker == _MarkerType.end) {
      setState(() {
        _end = tappedPoint;
        _endAddress = address;
        _selectedMarker = _MarkerType.none;
        _recalculateDistance();
      });
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
  }

  Future<void> _setCurrentAsEnd() async {
    final pos = await Geolocator.getCurrentPosition();
    final address = await _getAddress(pos);
    setState(() {
      _end = LatLng(pos.latitude, pos.longitude);
      _endAddress = address;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(_end!));
    _recalculateDistance();
  }

  Future<String> _getAddress(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return '${p.street}, ${p.locality}, ${p.administrativeArea}';
      }
    } catch (e) {
      print('Error during geocoding: $e');
    }
    return 'Unknown Location';
  }

  Future<List<LatLng>> _getRoutePolyline(LatLng start, LatLng end) async {
    // Replace with your Google Maps API Key
    const apiKey = "AIzaSyC9ih7LRAdbHqCPS1pLkoKpFga6mwUAKioAIzaSyC9ih7LRAdbHqCPS1pLkoKpFga6mwUAKio";

    final mode = _selectedMode == 'car' ? 'driving' : _selectedMode;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${start.latitude},${start.longitude}'
      '&destination=${end.latitude},${end.longitude}'
      '&mode=$mode'
      '&key=$apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['routes'].isNotEmpty) {
        final points = data['routes'][0]['overview_polyline']['points'];
        return _decodePolyline(points);
      }
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

  void _recalculateDistance() async {
    if (_start != null && _end != null) {
      final route = await _getRoutePolyline(_start!, _end!);
      setState(() {
        _routePoints = route;
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
          _distanceKm =
              Geolocator.distanceBetween(
                _start!.latitude,
                _start!.longitude,
                _end!.latitude,
                _end!.longitude,
              ) /
              1000;
        }
      });
    } else {
      setState(() {
        _distanceKm = null;
        _routePoints.clear();
      });
    }
  }


Future<void> _saveLog() async {
  if (!_formKey.currentState!.validate()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please correct form errors.')),
    );
    return;
  }
  if (_start == null || _end == null || _distanceKm == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please set start and end points.')),
    );
    return;
  }

  final uid = FirebaseAuth.instance.currentUser!.uid;

  // Prepare checkpoints array
  final checkpoints = _routePoints.map((p) => {
    'lat': p.latitude,
    'lng': p.longitude,
  }).toList();

  // Encoded polyline
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
    'checkpoints': checkpoints,     // full array
    'polyline': encoded,            // compact encoded polyline
    'createdAt': FieldValue.serverTimestamp()
  };

  // add optional fields
  if (_selectedMode == 'walk' || _selectedMode == 'cycle') {
    docData['mood'] = _moodController.text;
    docData['track'] = _trackController.text;
    docData['weather'] = _weather;
  } else {
    docData['productivityScore'] = double.parse(_productivityController.text);
  }

  try {
    // Option A: top-level collection
    await FirebaseFirestore.instance.collection('commute_logs').add(docData);

    // Option B: if you want to nest under the user:
    // await FirebaseFirestore.instance
    //   .collection('users')
    //   .doc(uid)
    //   .collection('trips')
    //   .add(docData);

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
/// Encodes a list of LatLng into Google encoded polyline string.
/// Implementation follows the Google polyline algorithm.
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

@override
void dispose() {
  _productivityController.dispose();
  _moodController.dispose();
  _trackController.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
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
                        onPressed: _setCurrentAsStart,
                        icon: const Icon(Icons.my_location),
                        label: const Text('My Location Start'),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.extended(
                        heroTag: 'endCurrentBtn',
                        onPressed: _setCurrentAsEnd,
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Distance:',
                      style: GoogleFonts.poppins(
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                    Text(
                      _distanceKm != null
                          ? '${_distanceKm!.toStringAsFixed(2)} km'
                          : 'N/A',
                      style: GoogleFonts.poppins(
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CO₂ Estimate:',
                      style: GoogleFonts.poppins(
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                    Text(
                      _distanceKm != null
                          ? '${(_distanceKm! * (_emissionFactors[_selectedMode] ?? 0.1)).toStringAsFixed(2)} kg'
                          : 'N/A',
                      style: GoogleFonts.poppins(
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
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
                    });
                  },
                ),
                const SizedBox(height: 12),

                /// 🔄 Conditional Section
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
                  DropdownButtonFormField<String>(
                    value: _weather,
                    decoration: const InputDecoration(
                      labelText: 'How was the weather?',
                      prefixIcon: Icon(Icons.wb_sunny),
                    ),
                    items: ['Sunny', 'Cloudy', 'Rainy', 'Windy']
                        .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                        .toList(),
                    onChanged: (val) => setState(() => _weather = val),
                    validator: (value) =>
                        value == null ? 'Please select weather' : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _productivityController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Productivity Score (0-10)',
                      prefixIcon: Icon(Icons.trending_up),
                    ),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Productivity score is required';
                      }
                      final score = double.tryParse(value!);
                      if (score == null || score < 0 || score > 10) {
                        return 'Enter a score between 0 and 10';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
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
          ),
        ),
      ],
    ),
  );
}

}