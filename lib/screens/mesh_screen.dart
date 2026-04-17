import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/ble_advertising.dart';
import '../services/wifi_service.dart';

class MeshScreen extends StatefulWidget {
  @override
  _MeshScreenState createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  List<String> foundDevices = [];
  List<String> connectedDevices = [];
  List<String> messages = [];

  String status = "Idle";
  String messageInput = "";

  // 🔍 Scan
  void startScan() async {
    setState(() {
      status = "Scanning...";
    });

    await bleService.startScan((data) {
      final ip = data["ip"];

      if (ip != null && !foundDevices.contains(ip)) {
        setState(() {
          foundDevices.add(ip);
        });
      }

      if (ip != null) {
        wifiService.connect(ip, (connectedIp) {
          if (!connectedDevices.contains(connectedIp)) {
            setState(() {
              connectedDevices.add(connectedIp);
            });
          }
        });
      }
    });

    setState(() {
      status = "Scan complete";
    });
  }

  // 📢 Advertise
  void startAdvertising() {
    bleAdvertising.startAdvertising((msg) {
      setState(() {
        status = msg;
      });
    });
  }

  // 🚀 Server
  void startServer() {
    wifiService.startServer((msg) {
      setState(() {
        messages.add("📥 $msg");
      });
    });

    setState(() {
      status = "Server running";
    });
  }

  // 📤 Send message
  void sendMessage() {
    if (messageInput.isEmpty) return;

    wifiService.sendMessage(messageInput, "device");

    setState(() {
      messages.add("📤 $messageInput");
      messageInput = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Mesh Network")),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // 🔘 Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: startAdvertising,
                  child: Text("Advertise"),
                ),
                ElevatedButton(
                  onPressed: startScan,
                  child: Text("Scan"),
                ),
                ElevatedButton(
                  onPressed: startServer,
                  child: Text("Server"),
                ),
              ],
            ),

            SizedBox(height: 10),

            // 📢 Status
            Text("Status: $status"),

            Divider(),

            // 📡 Found Devices
            Text("📡 Found Devices"),
            SizedBox(
              height: 70,
              child: ListView.builder(
                itemCount: foundDevices.length,
                itemBuilder: (_, i) => Text(foundDevices[i]),
              ),
            ),

            Divider(),

            // 🔗 Connected Devices
            Text("🔗 Connected Devices"),
            SizedBox(
              height: 70,
              child: ListView.builder(
                itemCount: connectedDevices.length,
                itemBuilder: (_, i) =>
                    Text("Connected: ${connectedDevices[i]}"),
              ),
            ),

            Divider(),

            // 💬 Messages
            Text("💬 Messages"),
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (_, i) => Text(messages[i]),
              ),
            ),

            // ✍️ Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => messageInput = val,
                    decoration: InputDecoration(
                      hintText: "Enter message",
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: sendMessage,
                  child: Text("Send"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}