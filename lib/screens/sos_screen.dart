import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/wifi_service.dart';
import 'dart:convert';
import '../services/api_service.dart';

class SosScreen extends StatefulWidget {
  @override
  _SosScreenState createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  String locationText = "Getting location...";
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
    isOnline = wifiService.isOnline;
    _connectivitySubscription = wifiService.connectivityStream.listen((online) {
      if (mounted) {
        setState(() {
          isOnline = online;
        });
      }
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

  Future<void> getLocation() async {
    await Geolocator.requestPermission();

    position = await Geolocator.getCurrentPosition();

    final placemarks = await placemarkFromCoordinates(
      position!.latitude,
      position!.longitude,
    );

    final place = placemarks.first;

    setState(() {
      locationText = "${place.street}, ${place.subLocality}, ${place.locality}, ${place.subAdministrativeArea}, ${place.administrativeArea}, ${place.postalCode}, ${place.country}";
    });
  }

  void sendSOS() async {
    final report = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "type": "SOS",
      "text": "Emergency Alert",
      "origin": "device",
      "hopCount": 0,
      "data": {
        "lat": position?.latitude,
        "lng": position?.longitude,
        "location": locationText,
      }
    };
  
  final msg = {
      "report_type": "OTHER",
      "description": "Emergency Alert",
      "latitude": position?.latitude,
      "longitude": position?.longitude,
      "urgency_level": "MEDIUM",
      "sent_mode": "INTERNET"
    };
    // Send direct to Flask backend
    try {
    await ApiService.reportIncident(msg);
  } catch (_) {}

    wifiService.sendMessage(jsonEncode(report), "device");
  }

  void startHold() {
    setState(() {
      holding = true;
      countdown = 3;
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          countdown--;
        });
        if (countdown <= 0) {
          timer.cancel();
          sendSOS();
          setState(() {
            holding = false;
          });
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("SOS Sent")));
        }
      }
    });
  }

  void stopHold() {
    setState(() {
      holding = false;
    });
    holdTimer?.cancel();
    countdownTimer?.cancel();
  }

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
                    isOnline ? 'Internet connected' : 'Offline - mesh fallback',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isOnline && wifiService.connectedPeers > 0) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.link,
                    size: 16,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${wifiService.connectedPeers} mesh peer${wifiService.connectedPeers == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            )
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
                    Icon(Icons.location_on, color: Colors.red),
                    Text(locationText),
                  ],
                ),
              ),
            ),

            Spacer(),

            // 🔴 SOS BUTTON
            GestureDetector(
              onTapDown: (_) => startHold(),
              onTapUp: (_) => stopHold(),
              onTapCancel: stopHold,
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
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
                    )
                  ],
                ),
                child: Center(
                  child: Text(
                    holding ? countdown.toString() : "HOLD\nSOS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: holding ? 48 : 22,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

            Spacer(),
          ],
        ),
      ),
    );
  }
}