// lib/screens/vehicle_settings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VehicleSettingsScreen extends StatefulWidget {
  const VehicleSettingsScreen({Key? key}) : super(key: key);

  @override
  State<VehicleSettingsScreen> createState() => _VehicleSettingsScreenState();
}

class _VehicleSettingsScreenState extends State<VehicleSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController(); // km/l
  final _fuelPriceCtrl = TextEditingController(); // ₹/l
  final _maintenanceCtrl = TextEditingController();
  String _type = 'petrol';
  bool _isSaving = false;
  String? _editingDocId; // null => creating

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mileageCtrl.dispose();
    _fuelPriceCtrl.dispose();
    _maintenanceCtrl.dispose();
    super.dispose();
  }

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _vehiclesRef =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('vehicles');

  Future<void> _saveVehicle() async {
  if (!_formKey.currentState!.validate()) return;
  setState(() => _isSaving = true);

  final data = {
    'name': _nameCtrl.text.trim(),
    'type': _type,
    'mileageKmPerLitre': double.tryParse(_mileageCtrl.text) ?? 0.0,
    'defaultFuelPrice': double.tryParse(_fuelPriceCtrl.text) ?? 0.0,
    'maintenancePerKm': double.tryParse(_maintenanceCtrl.text) ?? 0.0,
    'isDefault': false,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  try {
    if (_editingDocId == null) {
      final docRef = await _vehiclesRef.add({...data, 'createdAt': FieldValue.serverTimestamp()});
      debugPrint('Vehicle added: ${docRef.id}');
    } else {
      await _vehiclesRef.doc(_editingDocId).set(data, SetOptions(merge: true));
      debugPrint('Vehicle updated: $_editingDocId');
    }

    // reset form
    _clearForm();

    // Success feedback
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle saved')));

    // Return the selected fuel type to the caller (ProfileScreen expects this).
    // This will close VehicleSettingsScreen and pass the fuel type back.
    Navigator.pop(context, _type);
  } catch (e) {
    debugPrint('Vehicle save error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to save vehicle: $e')),
    );
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}


  void _clearForm() {
    _nameCtrl.clear();
    _mileageCtrl.clear();
    _fuelPriceCtrl.clear();
    _maintenanceCtrl.clear();
    _type = 'petrol';
    _editingDocId = null;
  }

  Future<void> _deleteVehicle(String docId) async {
    try {
      await _vehiclesRef.doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle deleted')));
    } catch (e) {
      debugPrint('deleteVehicle error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

// Replace your existing _setDefault with this.
Future<void> _setDefault(String docId, String vehicleType) async {
  setState(() => _isSaving = true);
  try {
    final batch = FirebaseFirestore.instance.batch();
    final coll = _vehiclesRef;
    final snap = await coll.get();
    for (final d in snap.docs) {
      batch.update(d.reference, {'isDefault': d.id == docId});
    }
    await batch.commit();

    // ALSO update the user document with the selected vehicle fuel type (and optionally defaultVehicleId)
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userDocRef.set({
      'vehicleFuelType': (vehicleType ?? '').toString().toLowerCase(),
      'defaultVehicleId': docId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Default vehicle set')));

    // If this screen was opened by ProfileScreen and is awaiting a result,
    // return the chosen vehicleType so caller can immediately update UI.
    // This will close the VehicleSettingsScreen.
    Navigator.pop(context, (vehicleType ?? '').toString().toLowerCase());
  } catch (e) {
    debugPrint('setDefault error: $e');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to set default: $e')));
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}


  void _startEdit(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    _editingDocId = doc.id;
    _nameCtrl.text = (data['name'] ?? '') as String;
    _type = (data['type'] ?? 'petrol') as String;
    _mileageCtrl.text = (data['mileageKmPerLitre'] ?? 0).toString();
    _fuelPriceCtrl.text = (data['defaultFuelPrice'] ?? 0).toString();
    _maintenanceCtrl.text = (data['maintenancePerKm'] ?? 0).toString();
    setState(() {});
    // scroll to form (optional)
  }

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vehicles')),
        body: const Center(child: Text('Please sign in')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Settings')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // list of vehicles
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _vehiclesRef.orderBy('isDefault', descending: true).snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                  final docs = snap.data?.docs ?? [];
                  return ListView(
                    children: [
                      if (docs.isEmpty)
                        const ListTile(title: Text('No vehicles yet — add one below')),
                      ...docs.map((d) {
                        final data = d.data();
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text((data['name'] ?? 'V').toString()[0])),
                            title: Text(data['name'] ?? 'Unnamed'),
                            subtitle: Text('${(data['type'] ?? '')} • ${((data['mileageKmPerLitre'] ?? 0)).toString()} km/l'),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                if (data['isDefault'] == true) Chip(label: const Text('Default')),
                                IconButton(icon: const Icon(Icons.edit), onPressed: () => _startEdit(d)),
                                IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteVehicle(d.id)),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'setDefault') _setDefault(d.id, (data['type'] ?? 'petrol').toString());
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'setDefault', child: Text('Set as default')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
              ),
            ),

            // form to add/edit
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Text((_editingDocId == null) ? 'Add vehicle' : 'Edit vehicle', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name (eg. Car, Bike)'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _type,
                              items: const [
                                DropdownMenuItem(value: 'petrol', child: Text('Petrol')),
                                DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
                                DropdownMenuItem(value: 'cng', child: Text('CNG')),
                                DropdownMenuItem(value: 'electric', child: Text('Electric')),
                                DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
                                DropdownMenuItem(value: 'other', child: Text('Other')),
                              ],
                              onChanged: (v) => setState(() => _type = v ?? 'petrol'),
                              decoration: const InputDecoration(labelText: 'Fuel type'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: TextFormField(controller: _mileageCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Mileage (km/l)'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter mileage' : null)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextFormField(controller: _fuelPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fuel price (per litre)'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter price' : null)),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: _maintenanceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maintenance per km (optional)'))),
                      ]),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveVehicle,
                              icon: Icon(_isSaving ? Icons.hourglass_empty : Icons.save),
                              label: Text(_isSaving ? 'Saving...' : ((_editingDocId == null) ? 'Add Vehicle' : 'Save Changes')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_editingDocId != null)
                            TextButton(onPressed: _clearForm, child: const Text('Cancel')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
