// helpers/commute_score.dart
class CommuteScoreResult {
  final double stressRaw; 
  final int stress1to10;
  final double fatigueRaw; 
  final int fatigue1to10;
  final List<Map<String, dynamic>> stressContributors; 
  final List<Map<String, dynamic>> fatigueContributors;

  CommuteScoreResult({
    required this.stressRaw,
    required this.stress1to10,
    required this.fatigueRaw,
    required this.fatigue1to10,
    required this.stressContributors,
    required this.fatigueContributors,
  });
}

double _clamp01(double v) => v.isFinite ? (v < 0 ? 0 : (v > 1 ? 1 : v)) : 0;

CommuteScoreResult computeCommuteScore({
  required double durationMin,
  double delayMin = 0,
  int stopCount = 0,
  double speedVar = 0,
  double crowdness = 0,
  double weatherFactor = 0,
  double timeOfDayFactor = 1.0,
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
  // Normalizers
  final durationNorm = _clamp01(durationMin / 90.0);
  final delayNorm = _clamp01(delayMin / 60.0);
  final stopNorm = _clamp01(stopCount / 10.0);
  final speedVarNorm = _clamp01(speedVar / 0.8);
  final sleepDeficit = _clamp01((8.0 - sleepHours) / 8.0);
  final hrElevNorm = _clamp01(hrElev / 30.0);
  final timeOfDayNorm = _clamp01(timeOfDayFactor - 1.0);

  final modeMap = <String, List<double>>{
    'car': [0.6, 0.4],
    'bus': [0.7, 0.3],
    'train': [0.7, 0.3],
    'walk': [0.3, 0.5],
    'bike': [0.5, 0.6],
    'ride': [0.8, 0.4],
  };
  final modeFactors = modeMap.containsKey(mode) ? modeMap[mode]! : [0.6, 0.4];
  final modeStressFactor = modeFactors[0];
  final modeFatigueFactor = modeFactors[1];

  // weights
  final w = {
    'duration': 0.18, 'delay': 0.18, 'stops': 0.10, 'speedVar': 0.12, 'crowd': 0.12,
    'weather': 0.08, 'timeOfDay': 0.08, 'calendar': 0.06, 'mode': 0.08
  };
  final v = {
    'duration': 0.20, 'sleep': 0.30, 'prior': 0.20, 'hr': 0.15, 'steps': 0.10, 'mode': 0.05
  };

  
  final stressFeatures = {
    'Duration': w['duration']! * durationNorm,
    'Delay': w['delay']! * delayNorm,
    'Stops': w['stops']! * stopNorm,
    'Speed variability': w['speedVar']! * speedVarNorm,
    'Crowdness': w['crowd']! * crowdness,
    'Weather': w['weather']! * weatherFactor,
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

  // smoothing
  if (prevStressSmoothed != null) {
    stressRaw = smoothingAlpha * stressRaw + (1 - smoothingAlpha) * prevStressSmoothed;
  }
  if (prevFatigueSmoothed != null) {
    fatigueRaw = smoothingAlpha * fatigueRaw + (1 - smoothingAlpha) * prevFatigueSmoothed;
  }

  int to1to10(double raw) => ((raw / 100.0) * 9.0 + 1.0).round().clamp(1, 10);

  
  List<Map<String, dynamic>> topStress = stressFeatures.entries
    .map((e) => {'name': e.key, 'value': e.value})
    .toList()
    ..sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
  List<Map<String, dynamic>> topFatigue = fatigueFeatures.entries
    .map((e) => {'name': e.key, 'value': e.value})
    .toList()
    ..sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));

  
  double stressTotal = stressFeatures.values.fold(0.0, (a, b) => a + b);
  double fatigueTotal = fatigueFeatures.values.fold(0.0, (a, b) => a + b);

  List<Map<String, dynamic>> sContrib = topStress.take(3).map((m) {
    final pct = stressTotal > 0 ? (m['value'] as double) / stressTotal * 100.0 : 0.0;
    return {'name': m['name'], 'pct': pct};
  }).toList();

  List<Map<String, dynamic>> fContrib = topFatigue.take(3).map((m) {
    final pct = fatigueTotal > 0 ? (m['value'] as double) / fatigueTotal * 100.0 : 0.0;
    return {'name': m['name'], 'pct': pct};
  }).toList();

  return CommuteScoreResult(
    stressRaw: stressRaw,
    stress1to10: to1to10(stressRaw),
    fatigueRaw: fatigueRaw,
    fatigue1to10: to1to10(fatigueRaw),
    stressContributors: sContrib,
    fatigueContributors: fContrib,
  );
}
