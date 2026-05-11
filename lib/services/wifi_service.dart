import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';


class WifiService {
  ServerSocket? _server;

  final List<Socket> _clients = [];
  final Set<String> _connectedIPs = {};
  final Set<String> _seenMessages = {};
  final List<Map<String, dynamic>> _messageQueue = [];

  bool _serverRunning = false;

  static const int PORT = 8080;
  static const int MAX_HOPS = 5;

  bool get isServerRunning => _serverRunning;

  List<String> get connectedDevices => _connectedIPs.toList();

  // ── Mesh state ─────────────────────────────────────────────
  bool meshStarted = false;
  bool isHost = false;
  bool isOnline = false;

  // ── Peer count (used by report/SOS screens) ────────────────
  int _connectedPeers = 0;
  int get connectedPeers => _connectedPeers;

  // ── Logs ───────────────────────────────────────────────────
  List<String> logs = [];

  // ── Queues ─────────────────────────────────────────────────
  List<Map<String, dynamic>> queuedMessages = [];
  List<Map<String, dynamic>> localStoredMessages = [];

  int get meshQueueLength => queuedMessages.length;
  int get queuedLocalMessages => localStoredMessages.length;

  // ── Connectivity stream ────────────────────────────────────
  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectivityStream => _connectivityController.stream;

  // =========================
  // 🚀 START MESH
  // Orchestrates BLE peripheral + central + TCP server.
  // Called from app_container or MeshScreen.
  // =========================
  Future<void> startMesh({
    required Function(String) onMessage,
    required Function(String) onStatus,
    required Function(Map<String, dynamic>) onDeviceFound,
    required Function() startAdvertising,
    required Function(Function(Map<String, dynamic>)) startScan,
  }) async {
    if (meshStarted) return;
    meshStarted = true;

    onStatus('Starting mesh...');

    // Monitor internet connectivity
    Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      isOnline = online;
      _connectivityController.add(online);
      onStatus(online ? '🌐 Internet connected' : '📡 Offline — mesh mode');
    });

    final current = await Connectivity().checkConnectivity();
    isOnline = current != ConnectivityResult.none;
    _connectivityController.add(isOnline);

    // Start TCP server (host role)
    await startServer(
      onMessage,
      (ip) {
        _connectedPeers++;
        onStatus('Client connected: $ip');
      },
      (ip) {
        if (_connectedPeers > 0) _connectedPeers--;
        onStatus('Client disconnected: $ip');
      },
    );
    isHost = true;
    onStatus('TCP server started on port $PORT');

    // Start BLE advertising so others can find us
    startAdvertising();

    // Start BLE scanning so we can find others
    startScan((data) {
      onDeviceFound(data);
      final ip = data['ip'] as String?;
      if (ip != null) {
        connect(
          ip,
          (connectedIp) {
            _connectedPeers++;
            onStatus('Connected to peer: $connectedIp');
          },
          (disconnectedIp) {
            if (_connectedPeers > 0) _connectedPeers--;
            onStatus('Peer disconnected: $disconnectedIp');
          },
          onMessage,
        );
      }
    });

    onStatus('Mesh started');
  }

  // =========================
  // 🚀 START SERVER
  // =========================
  Future<void> startServer(
    Function(String) onMessage,
    Function(String)? onClientConnected,
    Function(String)? onClientDisconnected,
  ) async {
    if (_serverRunning) return;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, PORT);
      _serverRunning = true;

      _server!.listen((socket) {
        final ip = socket.remoteAddress.address;

        if (_connectedIPs.contains(ip)) {
          socket.destroy();
          return;
        }

        _clients.add(socket);
        _connectedIPs.add(ip);
        onClientConnected?.call(ip);
        _flushQueue();

        socket.listen(
          (data) => _handleIncomingMessage(data, socket, onMessage),
          onDone: () {
            _clients.remove(socket);
            _connectedIPs.remove(ip);
            onClientDisconnected?.call(ip);
          },
          onError: (_) {
            _clients.remove(socket);
            _connectedIPs.remove(ip);
            onClientDisconnected?.call(ip);
          },
        );
      });
    } catch (_) {}
  }

  // =========================
  // 🔗 CONNECT TO HOST
  // =========================
  Future<bool> connect(
    String ip,
    Function(String)? onConnected,
    Function(String)? onDisconnected,
    Function(String)? onMessage,
  ) async {
    if (_connectedIPs.contains(ip)) return true;

    try {
      final socket = await Socket.connect(ip, PORT,
          timeout: const Duration(seconds: 5));

      _clients.add(socket);
      _connectedIPs.add(ip);
      onConnected?.call(ip);
      _flushQueue();

      socket.listen(
        (data) => _handleIncomingMessage(data, socket, onMessage),
        onDone: () {
          _clients.remove(socket);
          _connectedIPs.remove(ip);
          onDisconnected?.call(ip);
        },
        onError: (_) {
          _clients.remove(socket);
          _connectedIPs.remove(ip);
          onDisconnected?.call(ip);
        },
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // =========================
  // 📩 HANDLE INCOMING MESSAGE
  // =========================
  void _handleIncomingMessage(
    List<int> data,
    Socket sender,
    Function(String)? onMessage,
  ) {
    try {
      final decoded = utf8.decode(data);
      final msg = jsonDecode(decoded);
      final id = msg['id'];

      if (_seenMessages.contains(id)) return;
      _seenMessages.add(id);

      int hop = msg['hopCount'] ?? 0;
      if (hop >= MAX_HOPS) return;

      final text = msg['text'] ?? '';
      onMessage?.call('$text (hop: $hop)');

      msg['hopCount'] = hop + 1;
      final updated = jsonEncode(msg);

      for (final client in _clients) {
        if (client == sender) continue;
        client.write(updated);
      }
    } catch (_) {}
  }

  // =========================
  // 📤 SEND MESSAGE
  // [payload] is the API-formatted object stored for upload.
  // =========================
  Future<void> sendMessage(
    String text,
    String senderId, {
    Map<String, dynamic>? payload,
  }) async {
    final msg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'sender': senderId,
      'text': text,
      'hopCount': 0,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Store API payload for later upload if provided
    if (payload != null) {
      localStoredMessages.add(payload);
    }

    final encoded = jsonEncode(msg);

    if (_clients.isEmpty) {
      _messageQueue.add(msg);
      queuedMessages.add(msg);
      return;
    }

    for (final client in _clients) {
      try {
        client.write(encoded);
      } catch (_) {}
    }
  }

  // =========================
  // 📤 FLUSH QUEUE
  // =========================
  void _flushQueue() {
    if (_clients.isEmpty) return;

    for (final msg in _messageQueue) {
      final encoded = jsonEncode(msg);
      for (final client in _clients) {
        try {
          client.write(encoded);
        } catch (_) {}
      }
    }

    _messageQueue.clear();
    queuedMessages.clear();
  }

  // =========================
  // 🌐 GET LOCAL IP
  // =========================
  Future<String?> getLocalIP() async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP != null) return wifiIP;

      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // =========================
  // 🛑 STOP SERVER
  // =========================
  Future<void> stopServer() async {
    try {
      for (final client in _clients) {
        await client.close();
      }
      _clients.clear();
      _connectedIPs.clear();
      await _server?.close();
      _serverRunning = false;
    } catch (_) {}
  }
}

final wifiService = WifiService();