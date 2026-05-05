import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/wifi_service.dart';
import 'dart:convert';
import '../services/api_service.dart';

class ReportScreen extends StatefulWidget {
  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController descController = TextEditingController();
  String locationText = "Getting location...";
  Position? position;

  File? image;

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
      locationText = "${place.street}, ${place.country}";
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
        "image": image?.path // simple reference (can upgrade later)
      }
    };

    final msg = {
      "report_type": "GENERAL",
      "description": descController.text,
      "latitude": position?.latitude,
      "longitude": position?.longitude,
      "urgency_level": "MEDIUM",
      "sent_mode": "INTERNET"
    };

    try{
      final response = await ApiService.reportIncident(msg);
      print("Backend Response: $response");
    } catch (e) {
      print("Error sending report: $e");
    }

    wifiService.sendMessage(jsonEncode(report), "device");

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Report Sent")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Submit Report")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 📍 Location
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.location_on),
                Text(locationText),
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