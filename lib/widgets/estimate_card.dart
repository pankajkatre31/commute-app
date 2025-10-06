import 'package:flutter/material.dart';
import '../services/cost_calculator.dart';


class EstimateCard extends StatelessWidget {
final double distanceKm;
final double mileage;
final double fuelPrice;
final double parking;
final double tolls;
final double maintenancePerKm;
final double insuranceDaily;


const EstimateCard({
Key? key,
required this.distanceKm,
required this.mileage,
required this.fuelPrice,
this.parking = 0.0,
this.tolls = 0.0,
this.maintenancePerKm = 0.0,
this.insuranceDaily = 0.0,
}) : super(key: key);


@override
Widget build(BuildContext context) {
final breakdown = CostCalculator.computeBreakdown(
distanceKm: distanceKm,
mileageKmPerLitre: mileage,
fuelPricePerLitre: fuelPrice,
parkingPerDay: parking,
tollsPerDay: tolls,
maintenancePerKm: maintenancePerKm,
insuranceDaily: insuranceDaily,
);


return Card(
child: Padding(
padding: const EdgeInsets.all(12.0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text('Estimate', style: Theme.of(context).textTheme.subtitle1),
const SizedBox(height: 8),
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Text('Fuel'),
Text('₹${breakdown['fuel']!.toStringAsFixed(2)}'),
]),
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Text('Parking'),
Text('₹${breakdown['parking']!.toStringAsFixed(2)}'),
]),
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Text('Tolls'),
Text('₹${breakdown['tolls']!.toStringAsFixed(2)}'),
]),
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Text('Maintenance'),
Text('₹${breakdown['maintenance']!.toStringAsFixed(2)}'),
]),
const Divider(),
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
Text('₹${breakdown['total']!.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold)),
]),
],
),
),
);
}
}