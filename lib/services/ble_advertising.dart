import 'dart:convert';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:network_info_plus/network_info_plus.dart';

class BleAdvertising {
  final flutterBlePeripheral = FlutterBlePeripheral();

  Future<void> startAdvertising() async {
    try {
      print("📢 Starting BLE advertising...");

      // Get local IP
      final info = NetworkInfo();
      final ip = await info.getWifiIP();

      if (ip == null) {
        print("❌ No IP found");
        return;
      }

      final payload = jsonEncode({
        "ip": ip,
        "p": 8080,
      });

      print("📦 Advertising payload: $payload");

      final advertiseData = AdvertiseData(
        serviceUuid: "12345678-1234-1234-1234-123456789abc",
        manufacturerId: 1234,
        manufacturerData: utf8.encode(payload),
      );

      await flutterBlePeripheral.start(
        advertiseData: advertiseData,
      );

      print("✅ Advertising started");
    } catch (e) {
      print("❌ Advertising error: $e");
    }
  }

  Future<void> stopAdvertising() async {
    await flutterBlePeripheral.stop();
    print("🛑 Advertising stopped");
  }
}

final bleAdvertising = BleAdvertising();