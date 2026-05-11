import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/mesh_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:permission_handler/permission_handler.dart';

class ReportScreen extends StatefulWidget {
  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController descController = TextEditingController();
  String locationText = 'Getting location...';
  Position? position;

  File? image;
  bool isOnline = false;
  bool isLocating = false;
  late StreamSubscription<bool> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    isOnline = meshService.isOnline;
    _connectivitySubscription =
        meshService.connectivityStream.listen((online) {
      if (mounted) setState(() => isOnline = online);
    });
    refreshLocation();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    descController.dispose();
    super.dispose();
  }

  // =========================
  // 📍 LOCATION
  // =========================
  Future<void> refreshLocation() async {
    if (!mounted) return;
    setState(() {
      isLocating = true;
      locationText = 'Refreshing location...';
    });

    try {
      await getLocation();
    } catch (e) {
      if (mounted) setState(() => locationText = 'Location unavailable');
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  Future<void> getLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      setState(() => locationText = 'Location permission denied');
      return;
    }

    // Best accuracy for geocoding
    position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    try {
      final placemarks = await placemarkFromCoordinates(
        position!.latitude,
        position!.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Filter out null, empty, and generic "Unnamed Road" values
        bool isUseful(String? s) =>
            s != null &&
            s.isNotEmpty &&
            !s.toLowerCase().contains('unnamed');

        final parts = [
          if (isUseful(place.street)) place.street,
          if (isUseful(place.subLocality)) place.subLocality,
          if (isUseful(place.locality)) place.locality,
          if (isUseful(place.subAdministrativeArea)) place.subAdministrativeArea,
          if (isUseful(place.administrativeArea)) place.administrativeArea,
          if (isUseful(place.country)) place.country,
        ];

        if (parts.isNotEmpty) {
          setState(() => locationText = parts.join(', '));
          return;
        }
      }
    } catch (_) {}

    // Fallback: raw coordinates if geocoding fails or returns nothing useful
    setState(() {
      locationText =
          '${position!.latitude.toStringAsFixed(5)}, '
          '${position!.longitude.toStringAsFixed(5)}';
    });
  }

  // =========================
  // 🖼️ PICK IMAGE
  // =========================
  Future<void> pickImage() async {
    // Android 13+ system photo picker needs no permission — launch directly.
    // For Android 12 and below, request storage as a courtesy but don't block.
    await Permission.storage.request();

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => image = File(picked.path));
  }

  // =========================
  // 📤 SEND REPORT
  // =========================
  void sendReport() async {
    if (descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a description before submitting.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final deviceId = await AuthService.getDeviceId();

    // API-formatted payload
    final msg = {
      'report_type': 'OTHER',
      'description': descController.text,
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'urgency_level': 'MEDIUM',
      'sent_mode': isOnline ? 'INTERNET' : 'MESH',
      'device_id': deviceId,
    };

    // Mesh envelope (used if offline)
    final meshMessage = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': 'REPORT',
      'origin': 'device',
      'hopCount': 0,
      'device_id': deviceId,
      'payload': msg,
      'data': {
        'description': descController.text,
        'location': locationText,
        'lat': position?.latitude,
        'lng': position?.longitude,
        'image': image?.path,
      },
    };

    if (isOnline) {
      // ── ONLINE PATH (unchanged) ──────────────────────────
      try {
        final response = await ApiService.reportIncident(msg);

        final reportData = response is Map ? response['report'] : null;
        final reportId = reportData is Map
            ? (reportData['reportid'] ??
                    reportData['reportID'] ??
                    reportData['report_id'])
                ?.toString()
            : null;

        if (image != null && reportId != null) {
          try {
            await ApiService.uploadReportPhoto(reportId, image!);
            _snack('Report and photo uploaded successfully.', Colors.green);
          } catch (e) {
            // Photo failed — still relay via mesh as fallback
            await meshService.sendPayload(
              meshMessage: meshMessage,
              apiPayload: msg,
            );
            _snack(
              'Report created, but photo upload failed. Saved to mesh.',
              Colors.orange,
            );
          }
        } else {
          _snack('Report submitted to the server.', Colors.green);
        }
      } catch (e) {
        // Full request failed — fall back to mesh
        await meshService.sendPayload(
          meshMessage: meshMessage,
          apiPayload: msg,
        );
        _snack(
          'Unable to reach server. Report saved to mesh and will retry when online.',
          Colors.orange,
        );
      }
    } else {
      // ── OFFLINE PATH — mesh only ──────────────────────────
      await meshService.sendPayload(
        meshMessage: meshMessage,
        apiPayload: msg,
      );
      _snack(
        'No internet. Report queued to mesh for delivery.',
        Colors.orange,
      );
    }
  }

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  // =========================
  // 🎨 BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Submit Report'),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  size: 16,
                  color: isOnline ? Colors.greenAccent : Colors.yellowAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isOnline
                        ? 'Internet connected'
                        : 'Offline - mesh fallback',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isOnline && meshService.connectedPeers > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.link, size: 16, color: Colors.cyanAccent),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${meshService.connectedPeers} mesh '
                      'peer${meshService.connectedPeers == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 📍 Location row
            Row(
              children: [
                const Icon(Icons.location_on),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locationText,
                    style: const TextStyle(color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: isLocating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: isLocating ? null : refreshLocation,
                ),
              ],
            ),

            TextField(
              controller: descController,
              decoration:
                  const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: pickImage,
              child: const Text('Attach Image'),
            ),

            if (image != null) Image.file(image!, height: 100),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: sendReport,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}