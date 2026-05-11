import 'dart:convert';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

import 'wifi_service.dart';

class BleAdvertising {
  final FlutterBlePeripheral _peripheral =
      FlutterBlePeripheral();

  bool _isAdvertising = false;

  bool get isAdvertising => _isAdvertising;

  // =========================
  // 🔐 REQUEST PERMISSIONS
  // =========================
  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();
  }

  // =========================
  // 📢 START ADVERTISING
  // =========================
  Future<void> startAdvertising(
    Function(String)? onStatus,
  ) async {
    if (_isAdvertising) return;

    await _requestPermissions();

    try {
      // 🌐 Get local IP
      final ip = await wifiService.getLocalIP();

      if (ip == null) {
        onStatus?.call("No network IP found");
        return;
      }

      // 📦 Mesh payload
      final payload = jsonEncode({
        "ip": ip,
        "p": 8080,
      });

      final advertiseData = AdvertiseData(
        includeDeviceName: true,
        manufacturerId: 1234,
        manufacturerData: utf8.encode(payload),
      );

      await _peripheral.start(
        advertiseData: advertiseData,
      );

      _isAdvertising = true;

      onStatus?.call("Advertising started");
    } catch (e) {
      onStatus?.call("Advertising failed");
    }
  }

  // =========================
  // 🛑 STOP ADVERTISING
  // =========================
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    try {
      await _peripheral.stop();

      _isAdvertising = false;
    } catch (_) {}
  }
}

final bleAdvertising = BleAdvertising();