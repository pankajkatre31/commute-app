// lib/models/commute_stats.dart

import 'package:flutter/foundation.dart';

@immutable
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

  CommuteStats copyWith({
    int? totalTrips,
    double? totalDistance,
    double? avgProductivity,
    double? totalCost,
    double? totalCarbon,
    double? avgFatigue,
    double? avgStress,
    double? avgPhysicalActivity,
  }) {
    return CommuteStats(
      totalTrips: totalTrips ?? this.totalTrips,
      totalDistance: totalDistance ?? this.totalDistance,
      avgProductivity: avgProductivity ?? this.avgProductivity,
      totalCost: totalCost ?? this.totalCost,
      totalCarbon: totalCarbon ?? this.totalCarbon,
      avgFatigue: avgFatigue ?? this.avgFatigue,
      avgStress: avgStress ?? this.avgStress,
      avgPhysicalActivity: avgPhysicalActivity ?? this.avgPhysicalActivity,
    );
  }

  Map<String, dynamic> toJson() => {
        'totalTrips': totalTrips,
        'totalDistance': totalDistance,
        'avgProductivity': avgProductivity,
        'totalCost': totalCost,
        'totalCarbon': totalCarbon,
        'avgFatigue': avgFatigue,
        'avgStress': avgStress,
        'avgPhysicalActivity': avgPhysicalActivity,
      };

  factory CommuteStats.fromJson(Map<String, dynamic> json) => CommuteStats(
        totalTrips: (json['totalTrips'] ?? 0) as int,
        totalDistance: (json['totalDistance'] ?? 0.0).toDouble(),
        avgProductivity: (json['avgProductivity'] ?? 0.0).toDouble(),
        totalCost: (json['totalCost'] ?? 0.0).toDouble(),
        totalCarbon: (json['totalCarbon'] ?? 0.0).toDouble(),
        avgFatigue: (json['avgFatigue'] ?? 0.0).toDouble(),
        avgStress: (json['avgStress'] ?? 0.0).toDouble(),
        avgPhysicalActivity:
            (json['avgPhysicalActivity'] ?? 0.0).toDouble(),
      );

  @override
  String toString() {
    return 'CommuteStats(totalTrips: $totalTrips, totalDistance: $totalDistance, avgProductivity: $avgProductivity, totalCost: $totalCost, totalCarbon: $totalCarbon, avgFatigue: $avgFatigue, avgStress: $avgStress, avgPhysicalActivity: $avgPhysicalActivity)';
  }
}
