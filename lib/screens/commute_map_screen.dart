import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class CommuteMapScreen extends StatefulWidget {
  final dynamic log; 
  
  final String? googleApiKey;

  const CommuteMapScreen({Key? key, required this.log, this.googleApiKey}) : super(key: key);

  @override
  State<CommuteMapScreen> createState() => _CommuteMapScreenState();
}

class _CommuteMapScreenState extends State<CommuteMapScreen> {
  GoogleMapController? _mapController;
  String _mapStyle = '';
  List<LatLng> _routePoints = [];

  // raw storage (theme applied in build)
  final List<LatLng> _rawPolylinePoints = [];
  final Set<Marker> _rawMarkers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMapStyleAndRoute());
  }

  // Helper to safely read a field from dynamic `log`.
  dynamic _getField(String key, [dynamic from]) {
    final log = from ?? widget.log;
    if (log == null) return null;
    if (log is Map) {
      return log[key];
    }
    try {
      final dyn = log as dynamic;
      switch (key) {
        case 'polyline':
          return dyn.polyline;
        case 'checkpoints':
          return dyn.checkpoints;
        case 'startLocation':
          return dyn.startLocation;
        case 'endLocation':
          return dyn.endLocation;
        case 'startAddress':
          return dyn.startAddress;
        case 'endAddress':
          return dyn.endAddress;
        default:
          break;
      }
      try {
        final maybeMap = dyn.toJson();
        if (maybeMap is Map && maybeMap.containsKey(key)) return maybeMap[key];
      } catch (_) {}
    } catch (_) {}
    return null;
  }

  /// Call Google Directions API to get a route polyline between origin and destination.
  Future<List<LatLng>> _fetchRouteFromDirections({
    required LatLng origin,
    required LatLng destination,
    String mode = 'driving',
  }) async {
    final String apiKey = widget.googleApiKey ?? const String.fromEnvironment('AIzaSyC9ih7LRAdbHqCPS1pLkoKpFga6mwUAKio');
    if (apiKey.isEmpty) {
      debugPrint('Google Maps API key is empty. Provide googleApiKey to CommuteMapScreen or set fromEnvironment.');
      return [];
    }

    final originStr = '${origin.latitude},${origin.longitude}';
    final destStr = '${destination.latitude},${destination.longitude}';

    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': originStr,
        'destination': destStr,
        'mode': mode,
        'key': apiKey,
        'alternatives': 'false',
      },
    );

    try {
      final resp = await http.get(url);
      if (resp.statusCode != 200) {
        debugPrint('Directions API failed: ${resp.statusCode} ${resp.body}');
        return [];
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final status = (body['status'] ?? '').toString().toLowerCase();
      if (status != 'ok') {
        debugPrint('Directions API status: ${body['status']} - ${body['error_message'] ?? ''}');
        return [];
      }

      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return [];

      final route0 = routes.first as Map<String, dynamic>;
      final overview = route0['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overview?['points'] as String?;

      if (encoded == null || encoded.isEmpty) return [];

      final decoded = decodePolyline(encoded, accuracyExponent: 5);
      final List<LatLng> points = [];
      for (final p in decoded) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          // google_polyline_algorithm returns [lat, lng]
          points.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
      return points;
    } catch (e) {
      debugPrint('Directions API exception: $e');
      return [];
    }
  }

  Future<void> _loadMapStyleAndRoute() async {
    final style = await _getMapStyle();
    List<LatLng> route = _getRouteFromLog(widget.log);

    // If no polyline/checkpoints but have start & end, fetch Directions
    if (route.isEmpty) {
      final s = _getField('startLocation');
      final e = _getField('endLocation');

      LatLng? _extract(dynamic obj) {
        if (obj is LatLng) return obj;
        if (obj is Map) {
          final lat = obj['lat'] ?? obj['latitude'];
          final lng = obj['lng'] ?? obj['longitude'];
          if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
        }
        return null;
      }

      final sLatLng = _extract(s);
      final eLatLng = _extract(e);
      if (sLatLng != null && eLatLng != null) {
        final fetched = await _fetchRouteFromDirections(origin: sLatLng, destination: eLatLng, mode: 'driving');
        if (fetched.isNotEmpty) route = fetched;
      }
    }

    if (!mounted) return;
    _rawPolylinePoints
      ..clear()
      ..addAll(route);

    // create markers (start & end)
    _rawMarkers.clear();
    if (route.isNotEmpty) {
      final start = route.first;
      final end = route.last;
      _rawMarkers.add(Marker(
        markerId: const MarkerId('start'),
        position: start,
        infoWindow: const InfoWindow(title: 'Start'),
      ));
      _rawMarkers.add(Marker(
        markerId: const MarkerId('end'),
        position: end,
        infoWindow: const InfoWindow(title: 'End'),
      ));
    }

    setState(() {
      _mapStyle = style;
      _routePoints = route;
    });

    if (_mapController != null && _routePoints.isNotEmpty) {
      await _fitMapToRoute();
    }
  }

  Future<String> _getMapStyle() async {
    if (!mounted) return '';
    // Theme.of(context) is safe here because called after frame callback
    if (Theme.of(context).brightness == Brightness.dark) {
      try {
        return await rootBundle.loadString('assets/map_style_dark.json');
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  /// Probes the `log` for a route.
  List<LatLng> _getRouteFromLog([dynamic log]) {
    final source = log ?? widget.log;
    final List<LatLng> points = [];

    // 1) Try encoded polyline
    final poly = _getField('polyline', source);
    if (poly != null) {
      // If it's an encoded string
      if (poly is String && poly.isNotEmpty) {
        try {
          final decoded = decodePolyline(poly, accuracyExponent: 5);
          for (final p in decoded) {
            if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
              points.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
            }
          }
          if (points.isNotEmpty) return points;
        } catch (e) {
          debugPrint('Polyline decode failed: $e');
        }
      }

      // If poly might be already a List of coords
      if (poly is List && poly.isNotEmpty) {
        for (final item in poly) {
          if (item is LatLng) {
            points.add(item);
            continue;
          }
          if (item is List && item.length >= 2 && item[0] is num && item[1] is num) {
            points.add(LatLng((item[0] as num).toDouble(), (item[1] as num).toDouble()));
            continue;
          }
          if (item is Map) {
            final lat = item['lat'] ?? item['latitude'];
            final lng = item['lng'] ?? item['longitude'];
            if (lat is num && lng is num) {
              points.add(LatLng(lat.toDouble(), lng.toDouble()));
              continue;
            }
          }
        }
        if (points.isNotEmpty) return points;
      }
    }

    // 2) Try checkpoints
    final cps = _getField('checkpoints', source);
    if (cps is List && cps.isNotEmpty) {
      for (final cp in cps) {
        // a) LatLng instance
        if (cp is LatLng) {
          points.add(cp);
          continue;
        }

        // b) Map with numeric lat/lng keys
        if (cp is Map) {
          final dynamic latVal = cp['lat'] ?? cp['latitude'];
          final dynamic lngVal = cp['lng'] ?? cp['longitude'];
          if (latVal is num && lngVal is num) {
            points.add(LatLng(latVal.toDouble(), lngVal.toDouble()));
            continue;
          }

          // latLng nested as map or list
          final latLngCandidate = cp['latLng'] ?? cp['location'] ?? cp['point'];
          if (latLngCandidate is Map) {
            final nLat = latLngCandidate['lat'] ?? latLngCandidate['latitude'];
            final nLng = latLngCandidate['lng'] ?? latLngCandidate['longitude'];
            if (nLat is num && nLng is num) {
              points.add(LatLng(nLat.toDouble(), nLng.toDouble()));
              continue;
            }
          } else if (latLngCandidate is List && latLngCandidate.length >= 2 && latLngCandidate[0] is num && latLngCandidate[1] is num) {
            points.add(LatLng((latLngCandidate[0] as num).toDouble(), (latLngCandidate[1] as num).toDouble()));
            continue;
          }
        }

        // c) List like [lat, lng]
        if (cp is List && cp.length >= 2 && cp[0] is num && cp[1] is num) {
          points.add(LatLng((cp[0] as num).toDouble(), (cp[1] as num).toDouble()));
          continue;
        }

        // d) Dynamic object with lat/lng getters
        try {
          final dyn = cp as dynamic;
          final dynLat = dyn.lat ?? dyn.latitude;
          final dynLng = dyn.lng ?? dyn.longitude;
          if (dynLat is num && dynLng is num) {
            points.add(LatLng(dynLat.toDouble(), dynLng.toDouble()));
            continue;
          }
        } catch (_) {
          // ignore unknown shape
        }
      }
      if (points.isNotEmpty) return points;
    }

    // 3) Fallback to startLocation & endLocation
    final sLoc = _getField('startLocation', source);
    final eLoc = _getField('endLocation', source);

    LatLng? _extractLatLng(dynamic obj) {
      if (obj == null) return null;
      if (obj is LatLng) return obj;
      if (obj is Map) {
        final latVal = obj['lat'] ?? obj['latitude'];
        final lngVal = obj['lng'] ?? obj['longitude'];
        if (latVal is num && lngVal is num) return LatLng(latVal.toDouble(), lngVal.toDouble());

        final ll = obj['latLng'] ?? obj['location'] ?? obj['point'];
        if (ll is List && ll.length >= 2 && ll[0] is num && ll[1] is num) {
          return LatLng((ll[0] as num).toDouble(), (ll[1] as num).toDouble());
        }
        if (ll is Map) {
          final nLat = ll['lat'] ?? ll['latitude'];
          final nLng = ll['lng'] ?? ll['longitude'];
          if (nLat is num && nLng is num) return LatLng(nLat.toDouble(), nLng.toDouble());
        }
      }

      // try dynamic getters
      try {
        final dyn = obj as dynamic;
        final dynLat = dyn.lat ?? dyn.latitude;
        final dynLng = dyn.lng ?? dyn.longitude;
        if (dynLat is num && dynLng is num) return LatLng(dynLat.toDouble(), dynLng.toDouble());
      } catch (_) {}
      return null;
    }

    final sLatLng = _extractLatLng(sLoc);
    final eLatLng = _extractLatLng(eLoc);
    if (sLatLng != null) points.add(sLatLng);
    if (eLatLng != null) points.add(eLatLng);
    if (points.isNotEmpty) return points;

    return [];
  }

  Future<void> _fitMapToRoute({double padding = 50.0}) async {
    if (_mapController == null || _routePoints.isEmpty) return;
    if (_routePoints.length == 1) {
      await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_routePoints.first, 15));
      return;
    }

    double minLat = _routePoints.first.latitude;
    double maxLat = minLat;
    double minLng = _routePoints.first.longitude;
    double maxLng = minLng;

    for (final p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    try {
      await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    } catch (e) {
      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(center, 13));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Convert raw polyline points into a themed Polyline
    final Set<Polyline> themedPolylines = {};
    if (_rawPolylinePoints.length >= 2) {
      themedPolylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: List<LatLng>.from(_rawPolylinePoints),
        width: 5,
        color: theme.colorScheme.primary,
      ));
    }

    final markers = Set<Marker>.from(_rawMarkers);

    return Scaffold(
      appBar: AppBar(title: const Text('Commute Route')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _routePoints.isNotEmpty ? _routePoints.first : const LatLng(19.0760, 72.8777),
          zoom: 12,
        ),
        onMapCreated: (controller) async {
          _mapController = controller;
          if (_mapStyle.isNotEmpty && mounted) {
            try {
              await _mapController!.setMapStyle(_mapStyle);
            } catch (e) {
              debugPrint('setMapStyle failed: $e');
            }
          }
          if (_routePoints.isNotEmpty) {
            await _fitMapToRoute();
          }
        },
        polylines: themedPolylines,
        markers: markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}