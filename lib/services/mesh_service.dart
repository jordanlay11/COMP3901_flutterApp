import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_service.dart';
import 'auth_service.dart';

// ============================================================
// 🕸️ MESH SERVICE
//
// Role assignment: DYNAMIC (scan-first)
//   1. On start, scan for an existing host for up to
//      kRoleDecisionTimeout seconds.
//   2. If a host is found → become CLIENT and connect.
//   3. If no host found → become HOST.
//   4. Every kRescanInterval seconds, if peer count drops
//      to 0, tear down current role and rescan so devices
//      can reconnect after going out of range.
// ============================================================

enum MeshRole { searching, host, client }

/// How long to scan before deciding to become host (seconds).
const int kRoleDecisionTimeout = 15;

/// How often to check if peers dropped and rescan (seconds).
const int kRescanInterval = 30;

class MeshService {
  bool _started = false;
  bool _isHost = false;
  MeshRole meshRole = MeshRole.searching;

  bool isOnline = false;
  String? _deviceId;

  // ── flutter_p2p_connection instances ──────────────────────
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;

  // ── Peer tracking ──────────────────────────────────────────
  final Set<String> _connectedPeers = {};
  int get connectedPeers => _connectedPeers.length;

  final Set<String> _scannedDevices = {};
  int _lastLoggedPeerCount = -1;

  // ── Upload queue ───────────────────────────────────────────
  final List<Map<String, dynamic>> _uploadQueue = [];
  int get uploadQueueLength => _uploadQueue.length;

  // ── BLE outbox (messages pending WiFi Direct delivery) ─────
  final List<Map<String, dynamic>> _bleOutbox = [];
  int get bleQueueLength => _bleOutbox.length;

  // ── Logs & streams ─────────────────────────────────────────
  final List<String> logs = [];

  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  StreamSubscription? _connectivitySub;
  StreamSubscription? _hotspotSub;
  StreamSubscription? _clientSub;
  StreamSubscription? _clientListSub;
  StreamSubscription? _receivedTextSub;
  Timer? _rescanTimer;

  // =========================
  // 🚀 START
  // =========================
  Future<void> start({Function(String)? onLog}) async {
    if (_started) return;
    _started = true;

    _deviceId = await AuthService.getDeviceId();
    _log('Mesh starting — device: $_deviceId', onLog);

    // Monitor internet
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((result) async {
      final online = result != ConnectivityResult.none;
      final wasOnline = isOnline;
      isOnline = online;
      _connectivityController.add(online);

      if (!wasOnline && online) {
        _log('🌐 Internet restored — flushing upload queue', onLog);
        await _flushUploadQueue(onLog: onLog);
      } else if (!online) {
        _log('📡 Offline — mesh mode active', onLog);
      }
    });

    final current = await Connectivity().checkConnectivity();
    isOnline = current != ConnectivityResult.none;
    _connectivityController.add(isOnline);
    _log(isOnline ? '🌐 Online' : '📡 Offline', onLog);

    await _decideRoleAndStart(onLog: onLog);
  }

  // =========================
  // 🎯 SCAN-FIRST ROLE DECISION
  // Spins up a temporary client scan for kRoleDecisionTimeout
  // seconds. If any host is discovered → stay client and
  // connect. If timeout expires with no host → become host.
  // =========================
  Future<void> _decideRoleAndStart({Function(String)? onLog}) async {
    // Always need a client instance to scan, even if we end up as host
    _client = FlutterP2pClient();
    await _requestPermissions(p2p: _client!, onLog: onLog);
    await _client!.initialize();

    final wifiOn = await _client!.checkWifiEnabled();
    if (!wifiOn) {
      await _client!.enableWifiServices();
      await Future.delayed(const Duration(seconds: 1));
    }

    meshRole = MeshRole.searching;
    _log('🔍 Scanning for existing host ($kRoleDecisionTimeout s)...', onLog);

    bool hostFound = false;
    BleDiscoveredDevice? foundDevice;

    // Scan with a completer so we can break out early on first host found
    final completer = Completer<void>();

    await _client!.startScan((List<BleDiscoveredDevice> devices) {
      if (hostFound) return;
      for (final d in devices) {
        hostFound = true;
        foundDevice = d;
        if (!completer.isCompleted) completer.complete();
        break;
      }
    });

    // Wait for either a host to be found or the timeout to expire
    await Future.any([
      completer.future,
      Future.delayed(Duration(seconds: kRoleDecisionTimeout)),
    ]);

    await _client!.stopScan();

    if (hostFound && foundDevice != null) {
      _log('📱 Host found — joining as CLIENT', onLog);
      _isHost = false;
      meshRole = MeshRole.client;
      await _becomeClient(initialDevice: foundDevice!, onLog: onLog);
    } else {
      _log('👑 No host found — becoming HOST', onLog);
      _isHost = true;
      meshRole = MeshRole.host;
      // Dispose the temp client before becoming host
      try { _client?.dispose(); } catch (_) {}
      _client = null;
      await _becomeHost(onLog: onLog);
    }

    // Start periodic rescan — reconnects if peers drop
    _startRescanTimer(onLog: onLog);
  }

  // =========================
  // ♻️ RESCAN TIMER
  // Every kRescanInterval seconds, if no peers are connected,
  // tear down and re-run role decision so devices can find
  // each other again after disconnection or app restart.
  // =========================
  void _startRescanTimer({Function(String)? onLog}) {
    _rescanTimer?.cancel();
    _rescanTimer = Timer.periodic(
      Duration(seconds: kRescanInterval),
      (_) async {
        if (_connectedPeers.isNotEmpty) return; // still connected, skip
        _log('♻️ No peers — re-running role decision...', onLog);
        await _tearDownRole();
        _scannedDevices.clear();
        _lastLoggedPeerCount = -1;
        await _decideRoleAndStart(onLog: onLog);
      },
    );
  }

  // =========================
  // 👑 BECOME HOST
  // =========================
  Future<void> _becomeHost({Function(String)? onLog}) async {
    _host = FlutterP2pHost();

    try {
      // Request permissions BEFORE initialize()
      await _requestPermissions(p2p: _host!, onLog: onLog);

      await _host!.initialize();

      final wifiOn = await _host!.checkWifiEnabled();
      if (!wifiOn) {
        await _host!.enableWifiServices();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Creates WiFi Direct group and advertises via BLE
      final groupState = await _host!.createGroup(advertise: true);
      _log('📶 Group active: ${groupState.isActive} ssid: ${groupState.ssid}', onLog);
      if (groupState.failureReason != null) {
        _log('⚠️ Group failure: ${groupState.failureReason}', onLog);
      }

      _log('✅ Host started — advertising via BLE', onLog);

      // Stream hotspot state — only log when active state changes
      // Also trigger immediate rescan if group drops (e.g. WiFi change)
      bool _lastHostActive = false;
      _hotspotSub = _host!.streamHotspotState().listen((state) {
        if (state.isActive != _lastHostActive) {
          _lastHostActive = state.isActive;
          _log('📶 Hotspot active: ${state.isActive}', onLog);
          if (!state.isActive && _started) {
            _log('⚠️ Group lost — re-scanning immediately', onLog);
            _rescanNow(onLog: onLog);
          }
        }
      });

      // Stream connected clients — only log when count changes
      _clientListSub = _host!.streamClientList().listen((clients) {
        _connectedPeers.clear();
        for (final c in clients) {
          _connectedPeers.add(c.id ?? c.username ?? 'unknown');
        }
        if (_connectedPeers.length != _lastLoggedPeerCount) {
          _lastLoggedPeerCount = _connectedPeers.length;
          _log('👥 Clients connected: ${_connectedPeers.length}', onLog);
        }
      });

      // Listen for incoming text messages from clients
      _receivedTextSub = _host!.streamReceivedTexts().listen((text) {
        _log('📥 Received from client', onLog);
        _handleReceivedText(text, onLog: onLog);
      });
    } catch (e) {
      _log('❌ Host start error: $e', onLog);
    }
  }

  // =========================
  // 📱 BECOME CLIENT
  // Connects to already-discovered host (initialDevice),
  // then keeps scanning for additional peers.
  // =========================
  Future<void> _becomeClient({
    required BleDiscoveredDevice initialDevice,
    Function(String)? onLog,
  }) async {
    // _client already initialized in _decideRoleAndStart
    try {

      // Stream hotspot/connection state — only log transitions
      bool _lastClientActive = false;
      _hotspotSub = _client!.streamHotspotState().listen((state) {
        if (state.isActive != _lastClientActive) {
          _lastClientActive = state.isActive;
          _log('📶 Client connected to group: ${state.isActive}', onLog);
          if (!state.isActive && _started) {
            _log('⚠️ Disconnected from group — re-scanning immediately', onLog);
            _rescanNow(onLog: onLog);
          }
        }
      });

      // Stream client list — only log when count changes
      _clientListSub = _client!.streamClientList().listen((clients) {
        _connectedPeers.clear();
        for (final c in clients) {
          _connectedPeers.add(c.id ?? c.username ?? 'unknown');
        }
        if (_connectedPeers.length != _lastLoggedPeerCount) {
          _lastLoggedPeerCount = _connectedPeers.length;
          _log('👥 Peers in group: ${_connectedPeers.length}', onLog);
        }
      });

      // Listen for text received from host
      _receivedTextSub = _client!.streamReceivedTexts().listen((text) {
        _log('📥 Received from host', onLog);
        _handleReceivedText(text, onLog: onLog);
      });

      // Connect to the host we already found during role decision
      await _connectToHost(initialDevice, onLog: onLog);

      // Keep scanning for additional hosts (multi-hop future support)
      await _client!.startScan((List<BleDiscoveredDevice> devices) {
        for (final d in devices) {
          final addr = d.deviceAddress ?? d.deviceName ?? 'unknown';
          if (_scannedDevices.contains(addr)) continue;
          _scannedDevices.add(addr);
          _log('🤝 Found additional host: ${d.deviceName} ($addr)', onLog);
          _connectToHost(d, onLog: onLog);
        }
      });

      _log('✅ Client scan started', onLog);
    } catch (e) {
      _log('❌ Client start error: $e', onLog);
    }
  }

  // =========================
  // 🔗 CONNECT CLIENT TO HOST
  // =========================
  Future<void> _connectToHost(
    BleDiscoveredDevice device, {
    Function(String)? onLog,
  }) async {
    if (_client == null) return;

    try {
      _log('🔗 Connecting to ${device.deviceName}...', onLog);

      // Stop scan before connecting — prevents "scanning too frequently"
      // error during the WiFi Direct handshake.
      await _client!.stopScan();

      await _client!.connectWithDevice(device);
      _log('✅ Connected to host: ${device.deviceName}', onLog);
      _connectedPeers.add(device.deviceAddress ?? device.deviceName ?? 'unknown');
      await _flushBleOutbox(onLog: onLog);
    } catch (e) {
      _log('❌ Connect error: $e', onLog);
      // Remove from scanned so we can retry this device
      _scannedDevices.remove(device.deviceAddress ?? device.deviceName);
      // Wait before restarting scan to respect Android's rate limit
      await Future.delayed(const Duration(seconds: 30));
      _log('🔍 Restarting scan after failure...', onLog);
      await _client!.startScan((List<BleDiscoveredDevice> devices) {
        for (final d in devices) {
          final addr = d.deviceAddress ?? d.deviceName ?? 'unknown';
          if (_scannedDevices.contains(addr)) continue;
          _scannedDevices.add(addr);
          _log('🤝 Found host via BLE: ${d.deviceName} ($addr)', onLog);
          _connectToHost(d, onLog: onLog);
        }
      });
    }
  }

  // =========================
  // 📤 SEND PAYLOAD
  // Called by report_screen and sos_screen.
  // =========================
  Future<void> sendPayload({
    required Map<String, dynamic> meshMessage,
    required Map<String, dynamic> apiPayload,
    Function(String)? onLog,
  }) async {
    // Always queue for API upload
    _uploadQueue.add(apiPayload);

    if (isOnline) {
      _log('🌐 Online — uploading directly', onLog);
      await _flushUploadQueue(onLog: onLog);
      return;
    }

    // Offline — send via WiFi Direct mesh
    _bleOutbox.add(meshMessage);
    _log('📡 Queued for mesh delivery (${_bleOutbox.length} pending)', onLog);

    await _flushBleOutbox(onLog: onLog);
  }

  // =========================
  // 📤 FLUSH BLE OUTBOX
  // Sends queued messages over WiFi Direct to peers.
  // =========================
  Future<void> _flushBleOutbox({Function(String)? onLog}) async {
    if (_bleOutbox.isEmpty) return;

    final toSend = List<Map<String, dynamic>>.from(_bleOutbox);

    for (final msg in toSend) {
      final text = jsonEncode(msg);
      bool sent = false;

      try {
        if (_isHost && _host != null && _connectedPeers.isNotEmpty) {
          // Host broadcasts to all clients
          await _host!.broadcastText(text);
          sent = true;
        } else if (!_isHost && _client != null && _connectedPeers.isNotEmpty) {
          // Client sends text to host
          await _client!.broadcastText(text);
          sent = true;
        }
      } catch (e) {
        _log('❌ Send error: $e', onLog);
      }

      if (sent) {
        _bleOutbox.remove(msg);
        _log('📤 Message sent via WiFi Direct', onLog);
      }
    }
  }

  // =========================
  // 📩 HANDLE RECEIVED TEXT
  // =========================
  void _handleReceivedText(String text, {Function(String)? onLog}) {
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      final type = data['type'] ?? 'UNKNOWN';
      _log('📥 Processing received $type', onLog);

      // Reconstruct API payload
      final inner = data['payload'];
      if (inner is Map<String, dynamic>) {
        _uploadQueue.add(inner);
      } else {
        // Fallback: build minimal payload from envelope
        _uploadQueue.add({
          'report_type': type == 'SOS' ? 'SOS' : 'OTHER',
          'description': type == 'SOS'
              ? 'Emergency Alert (relayed via mesh)'
              : 'Report (relayed via mesh)',
          'latitude': data['data']?['lat'],
          'longitude': data['data']?['lng'],
          'urgency_level': type == 'SOS' ? 'HIGH' : 'MEDIUM',
          'sent_mode': 'MESH',
        });
      }

      if (isOnline) {
        _flushUploadQueue(onLog: onLog);
      } else {
        _log('💾 Stored — will upload when online', onLog);
      }
    } catch (e) {
      _log('❌ Parse error on received text: $e', onLog);
    }
  }

  // =========================
  // ☁️ FLUSH UPLOAD QUEUE
  // =========================
  Future<void> _flushUploadQueue({Function(String)? onLog}) async {
    if (_uploadQueue.isEmpty || !isOnline) return;

    _log('☁️ Uploading ${_uploadQueue.length} item(s)...', onLog);

    final toUpload = List<Map<String, dynamic>>.from(_uploadQueue);
    _uploadQueue.clear();

    for (final payload in toUpload) {
      try {
        await ApiService.reportIncident(payload);
        _log('✅ Upload successful', onLog);
      } catch (e) {
        _log('❌ Upload failed — re-queuing: $e', onLog);
        _uploadQueue.add(payload);
      }
    }
  }

  // =========================
  // 🔐 PERMISSIONS
  // Uses permission_handler directly so we control exactly
  // which permissions are requested and can log each result.
  // Android 14 (API 34) requires all of these to be granted
  // at runtime before flutter_p2p_connection will work.
  // =========================
  Future<void> _requestPermissions({
    required dynamic p2p,
    Function(String)? onLog,
  }) async {
    // Core permissions needed on all supported Android versions
    final permissions = [
      Permission.location,              // BLE scan + WiFi Direct
      Permission.locationWhenInUse,     // Required on Android 14
      Permission.bluetoothScan,         // BLE scanning (API 31+)
      Permission.bluetoothConnect,      // BLE connect (API 31+)
      Permission.bluetoothAdvertise,    // BLE advertising (API 31+)
      Permission.nearbyWifiDevices,     // WiFi Direct (API 33+)
      Permission.storage,               // File transfer support
    ];

    for (final perm in permissions) {
      try {
        final status = await perm.status;
        if (status.isGranted) {
          _log('✅ Already granted: $perm', onLog);
          continue;
        }
        if (status.isPermanentlyDenied) {
          _log('🚫 Permanently denied: $perm — open settings', onLog);
          continue;
        }
        final result = await perm.request();
        if (result.isGranted) {
          _log('🔐 Granted: $perm', onLog);
        } else {
          _log('❌ Denied: $perm → $result', onLog);
        }
      } catch (e) {
        // Some permissions don't exist on older API levels — skip silently
        _log('⚠️ Permission not applicable: $perm', onLog);
      }
    }

    // Also call the plugin's own checker so it registers the grant
    // internally — but only after we've already requested via handler.
    try {
      if (!await p2p.checkP2pPermissions()) {
        _log('⚠️ P2P permission still missing after request', onLog);
      }
      if (!await p2p.checkBluetoothPermissions()) {
        _log('⚠️ Bluetooth permission still missing after request', onLog);
      }
    } catch (e) {
      _log('⚠️ Plugin permission check error: $e', onLog);
    }

    _log('🔐 Permission check complete', onLog);
  }

  // =========================
  // ⚡ RESCAN NOW
  // Triggered immediately on disconnection rather than
  // waiting for the 30-second timer.
  // =========================
  Future<void> _rescanNow({Function(String)? onLog}) async {
    _rescanTimer?.cancel();
    await _tearDownRole();
    _scannedDevices.clear();
    _lastLoggedPeerCount = -1;
    meshRole = MeshRole.searching;
    await _decideRoleAndStart(onLog: onLog);
    _startRescanTimer(onLog: onLog);
  }

  // =========================
  // 🔄 TEAR DOWN CURRENT ROLE
  // Called before re-running role decision on rescan.
  // =========================
  Future<void> _tearDownRole() async {
    await _hotspotSub?.cancel();
    await _clientSub?.cancel();
    await _clientListSub?.cancel();
    await _receivedTextSub?.cancel();
    _connectedPeers.clear();
    _lastLoggedPeerCount = -1;

    try {
      if (_isHost) {
        await _host?.removeGroup();
        _host?.dispose();
        _host = null;
      } else {
        await _client?.stopScan();
        _client?.dispose();
        _client = null;
      }
    } catch (_) {}
  }

  // =========================
  // 🛑 STOP
  // =========================
  Future<void> stop() async {
    _rescanTimer?.cancel();
    await _tearDownRole();
    await _connectivitySub?.cancel();
    _scannedDevices.clear();
    _started = false;
  }

  // =========================
  // 📝 LOGGER
  // =========================
  void _log(String msg, Function(String)? external) {
    logs.add(msg);
    _logController.add(msg);
    external?.call(msg);
  }
}

final meshService = MeshService();