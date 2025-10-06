import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CommuteLog {
  final String? id;
  final String userId;
  final DateTime date;
  final String mode;
  final double distanceKm;
  final double productivityScore;

  
  final int? durationMinutes;
  final int? durationSeconds;

  
  final double? cost;

  
  final double totalCost;

  final Map<String, dynamic>? startLocation; 
  final Map<String, dynamic>? endLocation;
  final String? startAddress;
  final String? endAddress;
  final DateTime? startTime; 
  final DateTime? endTime; 

  
  final String? vehicleFuelType;

  
  final double fatigueLevel;
  final double stressLevel;

  final double? physicalActivity;
  final int? numberOfCommuters;
  final String? missedDeadlines;
  final List<Map<String, double>>? checkpoints; 
  final String? polyline; 

  
  final String weather;

  final Timestamp createdAt;

  CommuteLog({
    this.id,
    required this.userId,
    required this.date,
    required this.mode,
    required this.distanceKm,
    required this.productivityScore,
    this.durationMinutes,
    this.durationSeconds,
    this.cost,
    required this.totalCost,
    this.startLocation,
    this.endLocation,
    this.startAddress,
    this.endAddress,
    this.startTime,
    this.endTime,
    this.vehicleFuelType,
    this.fatigueLevel = 0.0,
    this.stressLevel = 0.0,
    this.physicalActivity,
    this.numberOfCommuters,
    this.missedDeadlines,
    this.checkpoints,
    this.polyline,
    required this.weather,
    required this.createdAt,
  });

  
  double? get durationMinutesDouble =>
      durationMinutes == null ? null : durationMinutes!.toDouble();

  
  static double estimateCo2Kg(double km, String mode, {String? vehicleFuelType}) {
    
    const Map<String, double> baseFactors = {
      'walk': 0.0,
      'cycle': 0.0,
      'motorbike': 0.113,
      'bus': 0.089,
      'train': 0.041,
      'other': 0.1,
    };

    final m = mode.toLowerCase();
    if (m == 'car') {
      
      const Map<String, double> carFuelFactors = {
        'petrol': 0.192,
        'diesel': 0.210,
        'cng': 0.120,
        'electric': 0.050, 
        'hybrid': 0.110,
        'other': 0.171,
      };
      final key = (vehicleFuelType ?? 'other').toLowerCase();
      final factor = carFuelFactors[key] ?? carFuelFactors['other']!;
      return factor * km;
    }

    final factor = baseFactors[m] ?? baseFactors['other']!;
    return factor * km;
  }


  double get carbonKg => CommuteLog.estimateCo2Kg(distanceKm, mode, vehicleFuelType: vehicleFuelType);

  
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

  
  factory CommuteLog.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    
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

    
    double _toDouble(dynamic v, {double fallback = 0.0}) {
      if (v == null) return fallback;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      if (v is num) return v.toDouble();
      return fallback;
    }

    int? _toIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v);
      if (v is num) return v.toInt();
      return null;
    }

    DateTime? _toDateTimeNullable(dynamic v) {
      if (v == null) return null;
      try {
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
        if (v is String) return DateTime.tryParse(v);
      } catch (_) {}
      return null;
    }

    
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

    
    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is Timestamp ? createdAtRaw : Timestamp.now();


    final parsedWeather = (data['weather'] as String?)?.trim() ?? 'Unknown';

    return CommuteLog(
      id: doc.id,
      userId: (data['userId'] ?? data['uid'] ?? '') as String,
      date: parsedDate,
      mode: (data['mode'] ?? 'other').toString(),
      distanceKm: _toDouble(data['distanceKm']),
      productivityScore: _toDouble(data['productivityScore']),
      durationMinutes: _toIntNullable(data['durationMinutes']),
      durationSeconds: _toIntNullable(data['durationSeconds']),
      cost: data['cost'] != null ? _toDouble(data['cost'], fallback: 0.0) : null,
      totalCost: data['totalCost'] != null
          ? _toDouble(data['totalCost'], fallback: 0.0)
          : (data['cost'] != null ? _toDouble(data['cost'], fallback: 0.0) : 0.0),
      startLocation: _mapFromDynamic(data['startLocation']),
      endLocation: _mapFromDynamic(data['endLocation']),
      startAddress: data['startAddress'] as String?,
      endAddress: data['endAddress'] as String?,
      startTime: _toDateTimeNullable(data['startTime']),
      endTime: _toDateTimeNullable(data['endTime']),
      vehicleFuelType: (data['vehicleFuelType'] as String?)?.toLowerCase(),
      fatigueLevel: _toDouble(data['fatigueLevel'], fallback: 0.0),
      stressLevel: _toDouble(data['stressLevel'], fallback: 0.0),
      physicalActivity:
          data['physicalActivity'] != null ? _toDouble(data['physicalActivity']) : null,
      numberOfCommuters: _toIntNullable(data['numberOfCommuters']),
      missedDeadlines: data['missedDeadlines'] as String?,
      checkpoints: parsedCheckpoints,
      polyline: data['polyline'] as String?,
      weather: parsedWeather,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'userId': userId,
      'date': Timestamp.fromDate(date),
      'mode': mode,
      'distanceKm': distanceKm,
      'productivityScore': productivityScore,
      'totalCost': totalCost,
      'weather': weather,
      'createdAt': createdAt,
    };

    if (durationMinutes != null) map['durationMinutes'] = durationMinutes;
    if (durationSeconds != null) map['durationSeconds'] = durationSeconds;
    if (cost != null) map['cost'] = cost;
    if (startLocation != null) map['startLocation'] = startLocation;
    if (endLocation != null) map['endLocation'] = endLocation;
    if (startAddress != null) map['startAddress'] = startAddress;
    if (endAddress != null) map['endAddress'] = endAddress;
    if (startTime != null) map['startTime'] = Timestamp.fromDate(startTime!);
    if (endTime != null) map['endTime'] = Timestamp.fromDate(endTime!);
    if (vehicleFuelType != null) map['vehicleFuelType'] = vehicleFuelType;
    map['fatigueLevel'] = fatigueLevel;
    map['stressLevel'] = stressLevel;

    if (physicalActivity != null) map['physicalActivity'] = physicalActivity;
    if (numberOfCommuters != null) map['numberOfCommuters'] = numberOfCommuters;
    if (missedDeadlines != null) map['missedDeadlines'] = missedDeadlines;
    if (checkpoints != null) map['checkpoints'] = checkpoints;
    if (polyline != null) map['polyline'] = polyline;

    return map;
  }
}
