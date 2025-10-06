class CostCalculator {
static double computeFuelCost({
required double distanceKm,
required double mileageKmPerLitre,
required double fuelPricePerLitre,
}) {
if (mileageKmPerLitre <= 0) return 0.0;
final litres = distanceKm / mileageKmPerLitre;
final cost = litres * fuelPricePerLitre;
return double.parse(cost.toStringAsFixed(2));
}


static Map<String, double> computeBreakdown({
required double distanceKm,
required double mileageKmPerLitre,
required double fuelPricePerLitre,
double parkingPerDay = 0.0,
double tollsPerDay = 0.0,
double maintenancePerKm = 0.0,
double insuranceDaily = 0.0,
double depreciationDaily = 0.0,
}) {
final fuel = computeFuelCost(
distanceKm: distanceKm,
mileageKmPerLitre: mileageKmPerLitre,
fuelPricePerLitre: fuelPricePerLitre);
final maintenance = maintenancePerKm * distanceKm;
final total = fuel + parkingPerDay + tollsPerDay + maintenance + insuranceDaily + depreciationDaily;
return {
'fuel': double.parse(fuel.toStringAsFixed(2)),
'parking': double.parse(parkingPerDay.toStringAsFixed(2)),
'tolls': double.parse(tollsPerDay.toStringAsFixed(2)),
'maintenance': double.parse(maintenance.toStringAsFixed(2)),
'insurance': double.parse(insuranceDaily.toStringAsFixed(2)),
'depreciation': double.parse(depreciationDaily.toStringAsFixed(2)),
'total': double.parse(total.toStringAsFixed(2)),
};
}
}