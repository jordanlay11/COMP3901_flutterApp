import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  void startScan(Function(Map<String, dynamic>) onDeviceFound) async {
    await requestPermissions(); // permissions
    print("🔍 Starting BLE scan...");

    // Start scan
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
    );

    // Listen to results
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final name = r.device.platformName;

         print("📡 Found device: $name");
        if (name.contains("MESH_NODE")) {
          print("📡 Found mesh device: $name");

          try {
            final manufacturerData = r.advertisementData.manufacturerData;

            if (manufacturerData.isNotEmpty) {
              final bytes = manufacturerData.values.first;
              final decoded = utf8.decode(bytes);
              final jsonData = jsonDecode(decoded);

              print("📦 Data: $jsonData");

              onDeviceFound(jsonData);
            }
          } catch (e) {
            print("❌ Parse error: $e");
          }
        }
      }
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    print("🛑 Scan stopped");
  }
}

Future<void> requestPermissions() async {
  print("🔐 Requesting permissions...");

  await [
    Permission.location,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  print("✅ Permissions requested");
}

final bleService = BleService();