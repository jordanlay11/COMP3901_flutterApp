import 'dart:convert';
import 'dart:io';

class WifiService {
  ServerSocket? server;
  List<Socket> clients = [];
  Set<String> seenMessages = {};

  // 🚀 Start server
  Future<void> startServer(Function(String) onMessage) async {
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 8080);
      print("🚀 Server started on port 8080");

      server!.listen((socket) {
        print("🟢 Client connected: ${socket.remoteAddress}");

        clients.add(socket);

        socket.listen((data) {
          final msgStr = utf8.decode(data);

          try {
            final msg = jsonDecode(msgStr);

            if (seenMessages.contains(msg["id"])) {
              print("♻️ Duplicate ignored");
              return;
            }

            seenMessages.add(msg["id"]);

            print("📥 Received: ${msg["text"]}");

            onMessage(msg["text"]);

            // 🔁 Relay
            for (var c in clients) {
              if (c != socket) {
                c.write(msgStr);
              }
            }
          } catch (e) {
            print("❌ Parse error: $e");
          }
        });

        socket.done.then((_) {
          print("🔴 Client disconnected");
          clients.remove(socket);
        });
      });
    } catch (e) {
      print("❌ Server error: $e");
    }
  }

  // 🔗 Connect
  Future<void> connect(String ip) async {
    try {
      print("🔗 Connecting to $ip...");

      final socket = await Socket.connect(ip, 8080);

      clients.add(socket);

      print("✅ Connected to $ip");

      socket.listen((data) {
        final msg = utf8.decode(data);
        print("📥 Received (client): $msg");
      });
    } catch (e) {
      print("❌ Connection error: $e");
    }
  }

  // 📤 Send message
  void sendMessage(String text) {
    final msg = jsonEncode({
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "text": text,
    });

    print("📤 Sending: $text");

    for (var c in clients) {
      c.write(msg);
    }
  }
}

final wifiService = WifiService();