import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class WifiService {
  ServerSocket? _server;
  final List<Socket> _clients = [];

  final Set<String> _seenMessages = {};
  final Set<String> _connectedIPs = {};

  final List<Map<String, dynamic>> _messageQueue = [];
  final List<Map<String, dynamic>> _localStorage = [];

  bool _serverRunning = false;
  bool _isOnline = false;
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();

  bool isHost = false;
  bool meshStarted = false;

  bool hasConnections() {
    return _clients.isNotEmpty;
  }

  int get connectedPeers => _clients.length;

  bool get isOnline => _isOnline;

  Stream<bool> get connectivityStream => _connectivityController.stream;

  final int MAX_HOPS = 5;

  bool get isServerRunning => _serverRunning;

  WifiService() {
    _monitorInternet();
  }

  // 🌐 Monitor internet
  void _monitorInternet() {
    Connectivity().checkConnectivity().then((results) => _updateOnlineStatus(results));

    Connectivity().onConnectivityChanged.listen(_updateOnlineStatus);
  }

  void _updateOnlineStatus(List<ConnectivityResult> results) {
    final nowOnline = results.any((result) => result != ConnectivityResult.none);
    final wasOnline = _isOnline;

    _isOnline = nowOnline;
    _connectivityController.add(_isOnline);

    if (nowOnline && !wasOnline) {
      _uploadStoredMessages();
    }
  }

  // Start mesh
  Future<void> startMesh({
  required Function(String) onMessage,
  required Function(String) onStatus,
  required Function(Map<String, dynamic>) onDeviceFound,
  required Function startAdvertising,
  required Function startScan,
}) async {
  if (meshStarted) return;
  meshStarted = true;

  onStatus("🚀 Starting mesh...");

  // 1️⃣ Start server (your existing logic)
  await startServer(onMessage);

  // 2️⃣ Start BLE advertising
  startAdvertising();
  onStatus("📡 Advertising started");

  // 3️⃣ Start scanning → AUTO CONNECT 
  startScan((data) {
    final ip = data["ip"];
    final port = data["p"];

    onStatus("🔍 Found device: $ip");

    if (ip != null) {
    connect(
      ip,
      (connectedIp) {
        onStatus("✅ Connected to $connectedIp");
      },
      (msg) {
        onStatus("📥 $msg");
      },
    );
  }
  });

  // 4️⃣ Wait to discover peers
  await Future.delayed(const Duration(seconds: 6));

  // 5️⃣ Decide role
  if (!hasConnections()) {
    isHost = true;

    onStatus("⚠️ No peers found");
    onStatus("📶 Enable hotspot to become mesh host");
  } else {
    isHost = false;
    onStatus("🟢 Connected to mesh (client mode)");
  }
}

  // 🚀 Start server
  Future<void> startServer(Function(String) onMessage) async {
    if (_serverRunning) return;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 8080);
      _serverRunning = true;

      _server!.listen((socket) {
        final ip = socket.remoteAddress.address;

        _clients.add(socket);
        _connectedIPs.add(ip);

        _flushQueue();

        socket.listen((data) {
          final msgStr = utf8.decode(data);

          try {
            final msg = jsonDecode(msgStr);
            final id = msg["id"];

            if (_seenMessages.contains(id)) return;
            _seenMessages.add(id);

            int hop = msg["hopCount"] ?? 0;
            if (hop >= MAX_HOPS) return;

            // 💾 Store locally
            _storeMessage(msg);

            final text = msg["text"];
            onMessage("$text (hop: $hop)");

            msg["hopCount"] = hop + 1;
            final updated = jsonEncode(msg);

            for (var c in _clients) {
              if (c != socket) {
                c.write(updated);
              }
            }
          } catch (_) {}
        });

        socket.done.then((_) {
          _clients.remove(socket);
          _connectedIPs.remove(ip);
        });
      });
    } catch (_) {}
  }

  // 🔗 Connect
  Future<void> connect(String ip, Function(String)? onConnected, Function(String)? onMessage) async {
  if (_connectedIPs.contains(ip)) return;

  try {
    final socket = await Socket.connect(ip, 8080);

    _clients.add(socket);
    _connectedIPs.add(ip);

    if (onConnected != null) {
      onConnected(ip);
    }

    _flushQueue();

    socket.listen((data) {
      final msgStr = utf8.decode(data);

      try {
        final msg = jsonDecode(msgStr);
        final id = msg["id"];

        if (_seenMessages.contains(id)) return;
        _seenMessages.add(id);

        int hop = msg["hopCount"] ?? 0;
        if (hop >= MAX_HOPS) return;

        // 💾 Store locally
        _storeMessage(msg);

        // ✅ 🔥 ADD THIS LINE
        if (onMessage != null) {
          final text = msg["text"];
          onMessage("$text (hop: $hop)");
        }

        msg["hopCount"] = hop + 1;
        final updated = jsonEncode(msg);

        for (var c in _clients) {
          if (c != socket) {
            c.write(updated);
          }
        }
      } catch (_) {}
    });
  } catch (_) {}
}


  // 📤 Send message
  void sendMessage(String text, String origin) {
    final msg = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "text": text,
      "origin": origin,
      "hopCount": 0,
      "uploaded": false,
    };

    _storeMessage(msg);

    if (_clients.isEmpty) {
      _messageQueue.add(msg);
      return;
    }

    final encoded = jsonEncode(msg);

    for (var c in _clients) {
      c.write(encoded);
    }
  }

  // 💾 Store message locally
  void _storeMessage(Map<String, dynamic> msg) {
    final exists =
        _localStorage.any((m) => m["id"] == msg["id"]);

    if (!exists) {
      _localStorage.add(msg);
    }
  }

  // 🔁 Flush queued messages
  void _flushQueue() {
    if (_clients.isEmpty || _messageQueue.isEmpty) return;

    for (var msg in _messageQueue) {
      final encoded = jsonEncode(msg);

      for (var c in _clients) {
        c.write(encoded);
      }
    }

    _messageQueue.clear();
  }

  // 🌐 Upload messages
  Future<void> _uploadStoredMessages() async {
    for (var msg in _localStorage) {
      if (msg["uploaded"] == true) continue;

      try {
        // 🔥 Replace with YOUR backend URL
        final response = await http.post(
          Uri.parse("https://your-server.com/api/report"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(msg),
        );

        if (response.statusCode == 200) {
          msg["uploaded"] = true;
        }
      } catch (_) {}
    }
  }

  // 🛑 Stop server
  Future<void> stopServer() async {
    await _server?.close();
    _serverRunning = false;
    _clients.clear();
    _connectedIPs.clear();
    _seenMessages.clear();
    _messageQueue.clear();
    _localStorage.clear();
  }
}

final wifiService = WifiService();