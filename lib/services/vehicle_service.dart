// lib/services/vehicle_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleService {
  final String uid;
  VehicleService(this.uid);

  CollectionReference<Map<String, dynamic>> get vehiclesRef =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('vehicles');

  /// Returns default vehicle doc data (Map) or null.
  Future<Map<String, dynamic>?> getDefaultVehicle() async {
    // 1) try vehicles subcollection
    final q = await vehiclesRef.where('isDefault', isEqualTo: true).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.data();

    // 2) fallback to shallow user doc fields
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = userDoc.data();
    if (data == null) return null;

    // If user doc contains vehicle-like fields, map them into vehicle shape
    if (data.containsKey('vehicleFuelType') || data.containsKey('mileageKmPerLitre') || data.containsKey('defaultFuelPrice')) {
      return {
        'name': data['vehicleName'] ?? 'My vehicle',
        'type': data['vehicleFuelType'] ?? data['vehicleType'] ?? 'petrol',
        'mileageKmPerLitre': data['mileageKmPerLitre'] ?? 0.0,
        'defaultFuelPrice': data['defaultFuelPrice'] ?? 0.0,
        'isDefault': true,
      };
    }
    return null;
  }
}
