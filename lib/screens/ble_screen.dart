import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/ble_advertising.dart';
import '../services/wifi_service.dart';

class BleScreen extends StatefulWidget {
  @override
  _BleScreenState createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  List<String> devices = [];

  void startScan() {
  bleService.startScan((data) {
    print("📦 BLE Data: $data");

    final ip = data["ip"];

    if (ip != null) {
      wifiService.connect(ip); // 🔥 AUTO CONNECT
    }

    setState(() {
      devices.add(data.toString());
    });
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  appBar: AppBar(title: const Text("BLE Mesh Discovery")),
  body: Column(
    children: [
      ElevatedButton(
        onPressed: startScan,
        child: const Text("Start Scan"),
      ),
      ElevatedButton(
        onPressed: () {
          bleAdvertising.startAdvertising();
        },
        child: const Text("Start Advertising"),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: devices.length,
          itemBuilder: (context, index) {
            return ListTile(title: Text(devices[index]));
          },
        ),
      ),
    ],
  ),
);

  }
}