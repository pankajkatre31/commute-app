// lib/models/commute_log.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CommuteLog {
  final String? id;
  final String userId;
  final DateTime date;
  final String mode;
  final double distanceKm;
  final double productivityScore;
  final int? durationMinutes; // kept as int (minutes)
  final double? cost;
  final Map<String, dynamic>? startLocation; // {'lat':..., 'lng':...}
  final Map<String, dynamic>? endLocation;
  final String? startAddress;
  final String? endAddress;
  final double? fatigueLevel;
  final double? stressLevel;
  final double? physicalActivity;
  final int? numberOfCommuters;
  final String? missedDeadlines;
  final List<Map<String, double>>? checkpoints; // [{'lat':..,'lng':..}, ...]
  final String? polyline; // encoded polyline
  final Timestamp createdAt;

  CommuteLog({
    this.id,
    required this.userId,
    required this.date,
    required this.mode,
    required this.distanceKm,
    required this.productivityScore,
    this.durationMinutes,
    this.cost,
    this.startLocation,
    this.endLocation,
    this.startAddress,
    this.endAddress,
    this.fatigueLevel,
    this.stressLevel,
    this.physicalActivity,
    this.numberOfCommuters,
    this.missedDeadlines,
    this.checkpoints,
    this.polyline,
    required this.createdAt,
  });

  /// Convenience: duration as double (null if not provided).
  double? get durationMinutesDouble =>
      durationMinutes == null ? null : durationMinutes!.toDouble();

  /// ✅ Automatically calculated CO₂ emissions
  double get carbonKg => _estimateCo2Kg(distanceKm, mode);

  /// Helper for carbon calculation
  static double _estimateCo2Kg(double km, String mode) {
    const Map<String, double> emissionFactors = {
      'walk': 0.0,
      'cycle': 0.0,
      'motorbike': 0.113,
      'car': 0.171,
      'bus': 0.089,
      'train': 0.041,
      'other': 0.1,
    };
    final key = mode.toLowerCase();
    return (emissionFactors[key] ?? 0.1) * km;
  }

  /// --- UI helpers used by admin/dashboard screens ---
  /// Move these out of the model if you want a purer data layer.
  static const Map<String, Color> modeColors = {
    'walk': Color(0xFF4CAF50),
    'cycle': Color(0xFF26A69A),
    'motorbike': Color(0xFFFFA000),
    'car': Color(0xFF1976D2),
    'bus': Color(0xFF7B1FA2),
    'train': Color(0xFF9C27B0),
    'other': Color(0xFF607D8B),
  };

  static const Map<String, IconData> modeIcons = {
    'walk': Icons.directions_walk,
    'cycle': Icons.directions_bike,
    'motorbike': Icons.motorcycle,
    'car': Icons.directions_car,
    'bus': Icons.directions_bus,
    'train': Icons.train,
    'other': Icons.travel_explore,
  };

  /// Robust factory parsing Firestore document (handles Timestamp / num / String)
  factory CommuteLog.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    // Parse date (Timestamp, int (msEpoch), or ISO string)
    DateTime parsedDate;
    final rawDate = data['date'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    // helper to convert num -> double safely
    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      if (v is num) return v.toDouble();
      return 0.0;
    }

    int? _toIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v);
      if (v is num) return v.toInt();
      return null;
    }

    // parse checkpoints if present (handle List<Map> or List of dynamic maps)
    List<Map<String, double>>? parsedCheckpoints;
    if (data['checkpoints'] is List) {
      final rawList = List.from(data['checkpoints']);
      parsedCheckpoints = rawList.map<Map<String, double>?>((item) {
        if (item is Map) {
          final lat = (item['lat'] is num) ? (item['lat'] as num).toDouble() : null;
          final lng = (item['lng'] is num) ? (item['lng'] as num).toDouble() : null;
          if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
        }
        return null;
      }).whereType<Map<String, double>>().toList();
      if (parsedCheckpoints.isEmpty) parsedCheckpoints = null;
    }

    Map<String, dynamic>? _mapFromDynamic(dynamic m) {
      if (m == null) return null;
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m);
      return null;
    }

    return CommuteLog(
      id: doc.id,
      userId: (data['userId'] ?? data['uid'] ?? '') as String,
      date: parsedDate,
      mode: (data['mode'] ?? 'other').toString(),
      distanceKm: _toDouble(data['distanceKm']),
      productivityScore: _toDouble(data['productivityScore']),
      durationMinutes: _toIntNullable(data['durationMinutes']),
      cost: data['cost'] != null ? _toDouble(data['cost']) : null,
      startLocation: _mapFromDynamic(data['startLocation']),
      endLocation: _mapFromDynamic(data['endLocation']),
      startAddress: data['startAddress'] as String?,
      endAddress: data['endAddress'] as String?,
      fatigueLevel:
          data['fatigueLevel'] != null ? _toDouble(data['fatigueLevel']) : null,
      stressLevel:
          data['stressLevel'] != null ? _toDouble(data['stressLevel']) : null,
      physicalActivity:
          data['physicalActivity'] != null ? _toDouble(data['physicalActivity']) : null,
      numberOfCommuters: _toIntNullable(data['numberOfCommuters']),
      missedDeadlines: data['missedDeadlines'] as String?,
      checkpoints: parsedCheckpoints,
      polyline: data['polyline'] as String?,
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (userId != null) 'userId': userId,
      'date': Timestamp.fromDate(date),
      'mode': mode,
      'distanceKm': distanceKm,
      'productivityScore': productivityScore,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (cost != null) 'cost': cost,
      if (startLocation != null) 'startLocation': startLocation,
      if (endLocation != null) 'endLocation': endLocation,
      if (startAddress != null) 'startAddress': startAddress,
      if (endAddress != null) 'endAddress': endAddress,
      if (fatigueLevel != null) 'fatigueLevel': fatigueLevel,
      if (stressLevel != null) 'stressLevel': stressLevel,
      if (physicalActivity != null) 'physicalActivity': physicalActivity,
      if (numberOfCommuters != null) 'numberOfCommuters': numberOfCommuters,
      if (missedDeadlines != null) 'missedDeadlines': missedDeadlines,
      if (checkpoints != null) 'checkpoints': checkpoints,
      if (polyline != null) 'polyline': polyline,
      'createdAt': createdAt,
    };
  }
}
