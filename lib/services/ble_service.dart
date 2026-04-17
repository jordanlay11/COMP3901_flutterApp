import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  final Set<String> _seenDevices = {};
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  // 🔐 Request permissions
  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  // 🔍 Start scanning
  Future<void> startScan(Function(Map<String, dynamic>) onDeviceFound) async {
    if (_isScanning) return;

    await _requestPermissions();

    _seenDevices.clear();
    _isScanning = true;

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
    );

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final deviceId = r.device.remoteId.str;

        // 🚫 Skip duplicates
        if (_seenDevices.contains(deviceId)) continue;
        _seenDevices.add(deviceId);

        final adv = r.advertisementData;

        // 🔍 Only process devices with manufacturer data
        if (adv.manufacturerData.isEmpty) continue;

        try {
          final bytes = adv.manufacturerData.values.first;
          final decoded = utf8.decode(bytes);
          final data = jsonDecode(decoded);

          // ✅ Validate mesh payload
          if (data is Map<String, dynamic> &&
              data.containsKey("ip") &&
              data.containsKey("p")) {
            onDeviceFound(data);
          }
        } catch (_) {
          // Ignore non-mesh devices silently
        }
      }
    });
  }

  // 🛑 Stop scanning
  Future<void> stopScan() async {
    if (!_isScanning) return;

    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }
}

final bleService = BleService();