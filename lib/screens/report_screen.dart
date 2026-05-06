import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/wifi_service.dart';

class ReportScreen extends StatefulWidget {
  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController descController = TextEditingController();
  String locationText = "Getting location...";
  Position? position;

  File? image;
  bool isOnline = false;
  bool isLocating = false;
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
    refreshLocation();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    descController.dispose();
    super.dispose();
  }

  Future<void> refreshLocation() async {
    if (!mounted) return;

    setState(() {
      isLocating = true;
      locationText = 'Refreshing location...';
    });

    try {
      await getLocation();
    } catch (e) {
      if (mounted) {
        setState(() {
          locationText = 'Location unavailable';
        });
      }
      print('Location error: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLocating = false;
        });
      }
    }
  }

  Future<void> getLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      setState(() {
        locationText = 'Location permission denied';
      });
      return;
    }

    position = await Geolocator.getCurrentPosition();

    final placemarks = await placemarkFromCoordinates(
      position!.latitude,
      position!.longitude,
    );

    if (placemarks.isEmpty) {
      setState(() {
        locationText = 'Location unavailable';
      });
      return;
    }

    final place = placemarks.first;

    setState(() {
      locationText = "${place.street ?? ''}${place.street != null ? ', ' : ''}${place.locality ?? ''}${place.locality != null ? ', ' : ''}${place.country ?? ''}";
    });
  }

  Future<void> pickImage() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() {
        image = File(picked.path);
      });
    }
  }

  void sendReport() async {
    final report = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "type": "REPORT",
      "origin": "device",
      "hopCount": 0,
      "data": {
        "description": descController.text,
        "location": locationText,
        "lat": position?.latitude,
        "lng": position?.longitude,
        "image": image?.path,
      }
    };

    final msg = {
      "report_type": "OTHER",
      "description": descController.text,
      "latitude": position?.latitude,
      "longitude": position?.longitude,
      "urgency_level": "MEDIUM",
      "sent_mode": isOnline ? "INTERNET" : "MESH"
    };

    if (descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a description before submitting.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (isOnline) {
      try {
        final response = await ApiService.reportIncident(msg);
        print("Backend Response: $response");

        final reportData = response is Map ? response['report'] : null;
        final reportId = reportData is Map
            ? (reportData['reportid'] ?? reportData['reportID'] ?? reportData['report_id'])?.toString()
            : null;

        if (image != null && reportId != null) {
          try {
            final photoResponse = await ApiService.uploadReportPhoto(reportId, image!);
            print('Photo upload response: $photoResponse');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Report and photo uploaded successfully.'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e, stackTrace) {
            wifiService.sendMessage(jsonEncode(report), "device");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Report created, but photo upload failed. Report saved to mesh.'),
                backgroundColor: Colors.orange,
              ),
            );
            print("Photo upload error: $e");
            print(stackTrace);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report submitted to the server.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e, stackTrace) {
        wifiService.sendMessage(jsonEncode(report), "device");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Unable to send to backend. Report saved to mesh and will retry when online.'),
            backgroundColor: Colors.orange,
          ),
        );
        print("Error sending report: $e");
        print(stackTrace);
      }
    } else {
      wifiService.sendMessage(jsonEncode(report), "device");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No internet connection. Report queued to mesh for delivery.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

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
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 📍 Location
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: isLocating ? null : refreshLocation,
                ),
              ],
            ),

            TextField(
              controller: descController,
              decoration: InputDecoration(labelText: "Description"),
              maxLines: 3,
            ),

            SizedBox(height: 10),

            ElevatedButton(
              onPressed: pickImage,
              child: Text("Attach Image"),
            ),

            if (image != null)
              Image.file(image!, height: 100),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: sendReport,
              child: Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }
}