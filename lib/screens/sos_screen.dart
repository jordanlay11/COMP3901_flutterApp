import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/mesh_service.dart'; // ← replaces wifi_service

class SosScreen extends StatefulWidget {
  @override
  _SosScreenState createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  String locationText = 'Getting location...';
  Position? position;

  Timer? holdTimer;
  Timer? countdownTimer;
  bool holding = false;
  int countdown = 3;
  bool isOnline = false;
  late StreamSubscription<bool> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    isOnline = meshService.isOnline;
    _connectivitySubscription =
        meshService.connectivityStream.listen((online) {
      if (mounted) setState(() => isOnline = online);
    });
    getLocation();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    holdTimer?.cancel();
    countdownTimer?.cancel();
    super.dispose();
  }

  // =========================
  // 📍 LOCATION
  // =========================
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

    setState(() {
      locationText =
          '${position!.latitude.toStringAsFixed(5)}, '
          '${position!.longitude.toStringAsFixed(5)}';
    });
  }

  // =========================
  // 🆘 SEND SOS
  // =========================
  Future<String> sendSOS() async {
    final deviceId = await AuthService.getDeviceId();

    // API-formatted payload
    final msg = {
      'report_type': 'OTHER',
      'description': 'Emergency Alert',
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'urgency_level': 'HIGH',
      'sent_mode': isOnline ? 'INTERNET' : 'MESH',
      'device_id': deviceId,
    };

    // Mesh envelope
    final meshMessage = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': 'SOS',
      'text': 'Emergency Alert',
      'origin': 'device',
      'hopCount': 0,
      'payload': msg,
      'data': {
        'lat': position?.latitude,
        'lng': position?.longitude,
        'location': locationText,
      },
    };

    bool serverSent = false;

    if (isOnline) {
      try {
        await ApiService.reportIncident(msg);
        serverSent = true;
      } catch (e) {
        // Server failed — fall through to mesh
      }
    }

    // Always send via mesh too (relay to any nearby peer)
    await meshService.sendPayload(
      meshMessage: meshMessage,
      apiPayload: msg,
    );

    return serverSent ? 'server' : 'mesh';
  }

  // =========================
  // ⏱️ HOLD LOGIC
  // =========================
  void startHold() {
    setState(() {
      holding = true;
      countdown = 3;
    });

    countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      setState(() => countdown--);

      if (countdown <= 0) {
        timer.cancel();
        final destination = await sendSOS();
        if (mounted) {
          setState(() => holding = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                destination == 'server'
                    ? 'SOS sent to server (mesh broadcast also sent).'
                    : 'SOS queued to mesh — will upload when online.',
              ),
            ),
          );
        }
      }
    });
  }

  void stopHold() {
    setState(() => holding = false);
    holdTimer?.cancel();
    countdownTimer?.cancel();
  }

  // =========================
  // 🎨 BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SOS Emergency'),
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
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isOnline && meshService.connectedPeers > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.link,
                      size: 16, color: Colors.cyanAccent),
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
      body: SafeArea(
        child: Column(
          children: [
            // 📍 Location
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        locationText,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // 🔴 SOS BUTTON
            GestureDetector(
              onTapDown: (_) => startHold(),
              onTapUp: (_) => stopHold(),
              onTapCancel: stopHold,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.6),
                      blurRadius: 30,
                      spreadRadius: holding ? 20 : 5,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    holding ? countdown.toString() : 'HOLD\nSOS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: holding ? 48 : 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}