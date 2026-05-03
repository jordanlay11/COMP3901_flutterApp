import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/wifi_service.dart';
import 'dart:convert';

class SosScreen extends StatefulWidget {
  @override
  _SosScreenState createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  String locationText = "Getting location...";
  Position? position;

  Timer? holdTimer;
  bool holding = false;

  @override
  void initState() {
    super.initState();
    getLocation();
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
      locationText = "${place.locality}, ${place.country}";
    });
  }

  void sendSOS() {
    final msg = {
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

    wifiService.sendMessage(jsonEncode(msg), "device");
  }

  void startHold() {
    holding = true;

    holdTimer = Timer(Duration(seconds: 3), () {
      if (holding) {
        sendSOS();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("SOS Sent")));
      }
    });
  }

  void stopHold() {
    holding = false;
    holdTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
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
                    "HOLD\nSOS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
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