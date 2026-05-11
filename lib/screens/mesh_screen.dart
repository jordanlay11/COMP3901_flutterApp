import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mesh_service.dart';

class MeshScreen extends StatefulWidget {
  @override
  _MeshScreenState createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final ScrollController _logScrollController = ScrollController();
  String _messageInput = '';

  late StreamSubscription<bool> _connectivitySub;
  late StreamSubscription<String> _logSub;

  @override
  void initState() {
    super.initState();

    _connectivitySub = meshService.connectivityStream.listen((_) {
      if (mounted) setState(() {});
    });

    _logSub = meshService.logStream.listen((_) {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    });

    // Start mesh — idempotent, safe to call multiple times
    meshService.start(onLog: (_) {});
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _logSub.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendTestMessage() async {
    if (_messageInput.trim().isEmpty) return;
    final text = _messageInput.trim();

    await meshService.sendPayload(
      meshMessage: {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': 'MESSAGE',
        'text': text,
        'hopCount': 0,
        'payload': {
          'report_type': 'OTHER',
          'description': text,
          'urgency_level': 'LOW',
          'sent_mode': meshService.isOnline ? 'INTERNET' : 'MESH',
        },
      },
      apiPayload: {
        'report_type': 'OTHER',
        'description': text,
        'urgency_level': 'LOW',
        'sent_mode': meshService.isOnline ? 'INTERNET' : 'MESH',
      },
    );

    setState(() => _messageInput = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Network')),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // ── Status row ──────────────────────────────────
            Row(
              children: [
                Icon(
                  meshService.isOnline ? Icons.wifi : Icons.wifi_off,
                  color: meshService.isOnline
                      ? Colors.greenAccent
                      : Colors.yellowAccent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  meshService.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: meshService.isOnline
                        ? Colors.greenAccent
                        : Colors.yellowAccent,
                  ),
                ),
                const Spacer(),
                // ── Role indicator ───────────────────────────
                _roleChip(meshService.meshRole),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${meshService.connectedPeers} peer(s)',
                    style: const TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // ── Queue counters ───────────────────────────────
            Row(
              children: [
                _chip(
                  'Pending send: ${meshService.bleQueueLength}',
                  Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                _chip(
                  'Upload queue: ${meshService.uploadQueueLength}',
                  Colors.cyanAccent,
                ),
              ],
            ),

            const Divider(height: 20),

            // ── Live log ─────────────────────────────────────
            Expanded(
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: meshService.logs.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    meshService.logs[i],
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white60),
                  ),
                ),
              ),
            ),

            const Divider(height: 16),

            // ── Test message input ────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => _messageInput = v,
                    decoration: const InputDecoration(
                        hintText: 'Test mesh message'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendTestMessage,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleChip(MeshRole role) {
    final label = switch (role) {
      MeshRole.host     => '👑 Host',
      MeshRole.client   => '📱 Client',
      MeshRole.searching => '🔍 Searching',
    };
    final color = switch (role) {
      MeshRole.host     => Colors.amberAccent,
      MeshRole.client   => Colors.greenAccent,
      MeshRole.searching => Colors.white38,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12)),
    );
  }
}