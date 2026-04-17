import 'dart:convert';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleAdvertising {
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  bool _isAdvertising = false;

  bool get isAdvertising => _isAdvertising;

  // 🔐 Permissions
  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();
  }

  // 📢 Start advertising
  Future<void> startAdvertising(Function(String) onStatus) async {
    if (_isAdvertising) return;

    await _requestPermissions();

    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();

      if (ip == null) {
        onStatus("No IP found");
        return;
      }

      final payload = jsonEncode({
        "ip": ip,
        "p": 8080,
      });

      final advertiseData = AdvertiseData(
        serviceUuid: "12345678-1234-1234-1234-123456789abc",
        manufacturerId: 1234,
        manufacturerData: utf8.encode(payload),
        includeDeviceName: true,
      );

      await _blePeripheral.start(advertiseData: advertiseData);

      _isAdvertising = true;
      onStatus("Advertising");
    } catch (_) {
      onStatus("Advertising failed");
    }
  }

  // 🛑 Stop advertising
  Future<void> stopAdvertising(Function(String) onStatus) async {
    if (!_isAdvertising) return;

    await _blePeripheral.stop();
    _isAdvertising = false;

    onStatus("Advertising stopped");
  }
}

final bleAdvertising = BleAdvertising();