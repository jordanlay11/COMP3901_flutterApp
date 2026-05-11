import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  final Set<String> _seenDevices = {};
  bool _isScanning = false;
  bool _keepScanning = false;

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
    _keepScanning = true;

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final deviceId = r.device.remoteId.str;

        if (_seenDevices.contains(deviceId)) continue;
        _seenDevices.add(deviceId);

        final adv = r.advertisementData;
        if (adv.manufacturerData.isEmpty) continue;

        try {
          final bytes = adv.manufacturerData.values.first;
          final decoded = utf8.decode(bytes);
          final data = jsonDecode(decoded);

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

    while (_keepScanning) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      if (!_keepScanning) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // 🛑 Stop scanning
  Future<void> stopScan() async {
    if (!_isScanning) return;

    _keepScanning = false;
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }
}

final bleService = BleService();