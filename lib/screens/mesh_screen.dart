import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/ble_advertising.dart';
import '../services/wifi_service.dart';
import '../services/api_service.dart';

class MeshScreen extends StatefulWidget {
  @override
  _MeshScreenState createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  List<String> foundDevices = [];
  List<String> connectedDevices = [];
  List<String> messages = [];
  List<String> logs = [];

  String status = "Idle";
  String messageInput = "";

  bool meshStarted = false;

  // 🚀 START FULL MESH
  void startMesh() async {
    if (meshStarted) return;

    meshStarted = true;

    setState(() {
      status = "Starting mesh...";
      logs.clear();
      foundDevices.clear();
      connectedDevices.clear();
    });

    await wifiService.startMesh(
      onMessage: (msg) {
        setState(() {
          messages.add("📥 $msg");
        });
      },

      onStatus: (msg) {
        setState(() {
          status = msg;
          logs.add(msg);
        });
      },

      onDeviceFound: (data) {
        final ip = data["ip"];

        if (ip != null && !foundDevices.contains(ip)) {
          setState(() {
            foundDevices.add(ip);
          });
        }
      },

      startAdvertising: () {
        bleAdvertising.startAdvertising((msg) {
          setState(() {
            logs.add("📢 $msg");
          });
        });
      },

      startScan: (callback) {
        bleService.startScan((data) {
          final ip = data["ip"];

          if (ip != null && !foundDevices.contains(ip)) {
            setState(() {
              foundDevices.add(ip);
            });
          }

          callback(data);

          // Track connections visually
          if (ip != null) {
            wifiService.connect(
              ip,
              (connectedIp) {
                if (!connectedDevices.contains(connectedIp)) {
                  setState(() {
                    connectedDevices.add(connectedIp);
                  });
                }
              },
              (msg) {
                setState(() {
                  messages.add("📥 $msg");
                });
              },
            );
          }


        });
      },
    );
  }

  // 📤 Send message
  void sendMessage() async {
    if (messageInput.isEmpty) return;

    final text = messageInput.trim();

    wifiService.sendMessage(text, "device");

    await ApiService.meshUpload([
    {
      "reportID": DateTime.now().millisecondsSinceEpoch.toString(),
      "report_type": "MESSAGE",
      "description": text,
      "latitude": 0,
      "longitude": 0,
      "urgency_level": "LOW",
      "sent_mode": "MESH",
      "created_at": DateTime.now().toIso8601String(),
      "ttl": 1
    }
  ]);

    setState(() {
      messages.add("📤 $text");
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
            // 🚀 Start Mesh Button
            ElevatedButton(
              onPressed: startMesh,
              child: Text("Start Mesh"),
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

            Divider(),

            // 📜 Logs (NEW — helps debugging mesh behavior)
            SizedBox(
              height: 100,
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (_, i) => Text(
                  logs[i],
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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