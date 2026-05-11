import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

// ============================================================
// ADMIN DASHBOARD
//
// Loads all reports, clusters nearby ones into zones, shows
// them on an embedded map and in an expandable list.
// Updating status on a cluster updates every report inside it.
// ============================================================

/// Reports within this distance (km) are grouped into one zone.
const double kClusterRadiusKm = 0.5;

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Future<List<AdminReport>> _reportsFuture;
  String? _updatingClusterId;
  int? _expandedClusterIndex;
  final MapController _mapController = MapController();
  final Map<String, String> _locationCache = {};

  @override
  void initState() {
    super.initState();
    _reportsFuture = _loadReports();
  }

  // =========================
  // 📥 LOAD + CLUSTER
  // =========================
  Future<List<AdminReport>> _loadReports() async {
    final response = await ApiService.getAllReports();
    final reports = response is Map ? response['reports'] : null;
    if (reports is List) {
      return reports
          .whereType<Map<String, dynamic>>()
          .map(AdminReport.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> _refreshReports() async {
    setState(() {
      _reportsFuture = _loadReports();
      _expandedClusterIndex = null;
    });
  }

  // =========================
  // 🗂️ BUILD CLUSTERS
  // Groups reports within kClusterRadiusKm of each other.
  // =========================
  List<ReportCluster> _buildClusters(List<AdminReport> reports) {
    final withCoords = reports.where((r) => r.latitude != null && r.longitude != null).toList();
    final noCoords   = reports.where((r) => r.latitude == null || r.longitude == null).toList();

    final used = List.filled(withCoords.length, false);
    final clusters = <ReportCluster>[];

    for (int i = 0; i < withCoords.length; i++) {
      if (used[i]) continue;
      final group = [withCoords[i]];
      used[i] = true;

      for (int j = i + 1; j < withCoords.length; j++) {
        if (used[j]) continue;
        if (_distanceKm(
          withCoords[i].latitude!, withCoords[i].longitude!,
          withCoords[j].latitude!, withCoords[j].longitude!,
        ) <= kClusterRadiusKm) {
          group.add(withCoords[j]);
          used[j] = true;
        }
      }

      final lat = group.map((r) => r.latitude!).reduce((a, b) => a + b) / group.length;
      final lng = group.map((r) => r.longitude!).reduce((a, b) => a + b) / group.length;
      clusters.add(ReportCluster(reports: group, lat: lat, lng: lng));
    }

    // No-coord reports each get their own cluster (no map marker)
    for (final r in noCoords) {
      clusters.add(ReportCluster(reports: [r], lat: null, lng: null));
    }

    // Sort: most reports first, SOS zones first within same count
    clusters.sort((a, b) {
      final aScore = (a.hasSos ? 1000 : 0) + a.reports.length;
      final bScore = (b.hasSos ? 1000 : 0) + b.reports.length;
      return bScore.compareTo(aScore);
    });

    return clusters;
  }

  //geocode
  Future<String> _getZoneLocation(
  double? lat,
  double? lng,
) async {
  if (lat == null || lng == null) {
    return "Unknown location";
  }

  final cacheKey = "${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}";

  if (_locationCache.containsKey(cacheKey)) {
    return _locationCache[cacheKey]!;
  }

  try {
    final places = await placemarkFromCoordinates(lat, lng);

    if (places.isNotEmpty) {
      final p = places.first;

      final parts = [
        p.street,
        p.subLocality,
        p.locality,
        p.subAdministrativeArea,
        p.administrativeArea,
      ].where((e) => e != null && e.isNotEmpty && e!="Unnamed Road").toList();

      if (parts.isNotEmpty) {
        final location = parts.join(", ");

        _locationCache[cacheKey] = location;

        return location;
      }
    }
  } catch (_) {}

  final fallback =
      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

  _locationCache[cacheKey] = fallback;

  return fallback;
}
  //

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * 3.14159265 / 180;
    final dLon = (lon2 - lon1) * 3.14159265 / 180;
    final a = _sin2(dLat / 2) +
        _cos(lat1) * _cos(lat2) * _sin2(dLon / 2);
    return r * 2 * _atan2(a);
  }

  double _sin2(double x) => _sin(x) * _sin(x);
  double _sin(double x)  { var r = x % 6.28318; return r - r*r*r/6 + r*r*r*r*r/120; }
  double _cos(double x)  => _sin(x + 1.5707963);
  double _atan2(double a) => 2 * (0.7854 + (1-a) / (1+a) * (-0.7854)); // approx

  // =========================
  // 📤 UPDATE STATUS
  // Updates every report in the cluster.
  // =========================
  Future<void> _updateClusterStatus(ReportCluster cluster, String status) async {
    setState(() => _updatingClusterId = cluster.id);

    int failed = 0;
    for (final report in cluster.reports) {
      try {
        await ApiService.updateStatus(report.reportId, status);
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;

    final msg = failed == 0
        ? 'All ${cluster.reports.length} report(s) marked $status'
        : '$failed of ${cluster.reports.length} updates failed';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );

    setState(() => _updatingClusterId = null);
    await _refreshReports();
  }

  // =========================
  // 🗺️ PAN MAP TO CLUSTER
  // =========================
  void _panTo(ReportCluster cluster) {
    if (cluster.lat != null && cluster.lng != null) {
      _mapController.move(LatLng(cluster.lat!, cluster.lng!), 14);
    }
  }

  // =========================
  // 🎨 BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF10131A),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshReports),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService.clearToken();
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
            },
          ),
        ],
      ),
      body: FutureBuilder<List<AdminReport>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.redAccent),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load reports: ${snapshot.error}',
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }

          final reports  = snapshot.data ?? [];
          final clusters = _buildClusters(reports);

          if (reports.isEmpty) {
            return Center(
              child: Text(
                'No reports available.',
                style: TextStyle(color: Colors.grey[300]),
              ),
            );
          }

          // Stats
          final sosCount    = reports.where((r) => r.type == 'SOS').length;
          final meshCount   = reports.where((r) => r.sentMode == 'MESH').length;
          final activeZones = clusters.where((c) => c.reports.length >= 2).length;

          // Map markers — only clusters with coords
          final mapClusters = clusters.where((c) => c.lat != null).toList();
          final allCoords   = mapClusters.map((c) => LatLng(c.lat!, c.lng!)).toList();
          final mapCenter   = allCoords.isEmpty
              ? const LatLng(18.1, -77.3)
              : LatLng(
                  allCoords.map((l) => l.latitude).reduce((a, b) => a + b) / allCoords.length,
                  allCoords.map((l) => l.longitude).reduce((a, b) => a + b) / allCoords.length,
                );

          return RefreshIndicator(
            onRefresh: _refreshReports,
            child: CustomScrollView(
              slivers: [
                // ── Stats row ──────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        _statChip('${reports.length}', 'Reports', Colors.blueAccent),
                        const SizedBox(width: 8),
                        _statChip('$activeZones', 'Active Zones', Colors.redAccent),
                        const SizedBox(width: 8),
                        _statChip('$sosCount', 'SOS', Colors.redAccent),
                        const SizedBox(width: 8),
                        _statChip('$meshCount', 'Via Mesh', Colors.amberAccent),
                      ],
                    ),
                  ),
                ),

                // ── Map ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 220,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: mapCenter,
                            initialZoom: 9,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.example.mesh',
                            ),
                            MarkerLayer(
                              markers: mapClusters.map((c) {
                                final color = c.hasSos
                                    ? Colors.redAccent
                                    : c.reports.length >= 3
                                        ? Colors.amberAccent
                                        : Colors.blueAccent;
                                return Marker(
                                  point: LatLng(c.lat!, c.lng!),
                                  width: 40,
                                  height: 40,
                                  child: GestureDetector(
                                    onTap: () {
                                      final idx = clusters.indexOf(c);
                                      setState(() => _expandedClusterIndex = idx);
                                      _panTo(c);
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: color, width: 2),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${c.reports.length}',
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Section label ───────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'INCIDENT ZONES  ·  ${clusters.length} zone${clusters.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                // ── Cluster cards ───────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildClusterCard(clusters[index], index),
                      ),
                      childCount: clusters.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // =========================
  // 🃏 CLUSTER CARD
  // =========================
  Widget _buildClusterCard(ReportCluster cluster, int index) {
    final isExpanded  = _expandedClusterIndex == index;
    final isUpdating  = _updatingClusterId == cluster.id;
    final accentColor = cluster.hasSos
        ? Colors.redAccent
        : cluster.reports.length >= 3
            ? Colors.amberAccent
            : Colors.blueAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2028),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? accentColor.withOpacity(0.5) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          // ── Header row (always visible) ─────────────────
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _expandedClusterIndex = isExpanded ? null : index;
              });
              if (!isExpanded) _panTo(cluster);
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Count badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${cluster.reports.length}',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Location info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<String>(
                          future: _getZoneLocation(cluster.lat, cluster.lng),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.data ?? cluster.locationLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                        const SizedBox(height: 3),
                        if (cluster.lat != null)
                          Text(
                            '${cluster.lat!.toStringAsFixed(5)}, ${cluster.lng!.toStringAsFixed(5)}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Tags
                        Wrap(
                          spacing: 6,
                          children: [
                            if (cluster.hasSos)
                              _tag('SOS ×${cluster.sosCount}', Colors.redAccent),
                            if (cluster.meshCount > 0)
                              _tag('MESH ×${cluster.meshCount}', Colors.amberAccent),
                            _tag(
                              '${cluster.reports.length} report${cluster.reports.length != 1 ? 's' : ''}',
                              Colors.white38,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded: individual reports + status buttons ─
          if (isExpanded) ...[
            const Divider(color: Colors.white12, height: 1),

            // Individual report items
            ...cluster.reports.map((r) => _buildReportItem(r)),

            const Divider(color: Colors.white12, height: 1),

            // Status buttons — apply to ALL reports in cluster
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cluster.reports.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Update all ${cluster.reports.length} reports in this zone:',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isUpdating
                              ? null
                              : () => _updateClusterStatus(cluster, 'IN_PROGRESS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isUpdating
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : const Text('In Progress'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isUpdating
                              ? null
                              : () => _updateClusterStatus(cluster, 'RESOLVED'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Resolve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================
  // 📄 INDIVIDUAL REPORT ITEM
  // Shown inside an expanded cluster card.
  // =========================
  Widget _buildReportItem(AdminReport report) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                report.typeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: report.statusColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.status.toUpperCase(),
                  style: TextStyle(
                    color: report.statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.description.isNotEmpty ? report.description : 'No description.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'by ${report.reporterName}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              Text(
                report.createdAtLabel,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 16),
        ],
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────
  Widget _statChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ============================================================
// CLUSTER MODEL
// ============================================================
class ReportCluster {
  final List<AdminReport> reports;
  final double? lat;
  final double? lng;

  ReportCluster({required this.reports, required this.lat, required this.lng});

  String get id => '${lat}_${lng}_${reports.length}';

  bool get hasSos => reports.any((r) => r.type == 'SOS');

  int get sosCount => reports.where((r) => r.type == 'SOS').length;

  int get meshCount => reports.where((r) => r.sentMode == 'MESH').length;

  /// Best human-readable label for this cluster's location.
  String get locationLabel {
    // Try report location strings, filter out unhelpful ones
    final locations = reports
        .map((r) => r.location)
        .where((l) =>
            l != null &&
            l.trim().isNotEmpty &&
            !l.toLowerCase().contains('unnamed') &&
            l.toLowerCase() != 'unknown')
        .toList();

    if (locations.isNotEmpty) {
      // Prefer shortest (avoids over-long concatenated strings)
      locations.sort((a, b) => a!.length.compareTo(b!.length));
      return locations.first!;
    }

    if (lat != null) return '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
    return 'Unknown location';
  }
}

// ============================================================
// ADMIN REPORT MODEL — unchanged from original
// ============================================================
class AdminReport {
  final String reportId;
  final String type;
  final String description;
  final String urgencyLevel;
  final String status;
  final String reporterName;
  final String reporterEmail;
  final double? latitude;
  final double? longitude;
  final String? location;
  final String? sentMode;
  final DateTime? createdAt;

  AdminReport({
    required this.reportId,
    required this.type,
    required this.description,
    required this.urgencyLevel,
    required this.status,
    required this.reporterName,
    required this.reporterEmail,
    required this.latitude,
    required this.longitude,
    required this.location,
    required this.sentMode,
    required this.createdAt,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return AdminReport(
      reportId:      (json['reportid'] ?? json['reportID'] ?? json['report_id'] ?? '').toString(),
      type:          (json['report_type'] ?? 'OTHER').toString(),
      description:   (json['description'] ?? '').toString(),
      urgencyLevel:  (json['urgency_level'] ?? 'MEDIUM').toString(),
      status:        (json['status'] ?? 'PENDING').toString(),
      reporterName:  (json['reporter_name'] ?? json['reporterName'] ?? 'Unknown').toString(),
      reporterEmail: (json['reporter_email'] ?? json['reporterEmail'] ?? 'unknown@example.com').toString(),
      latitude:      parseDouble(json['latitude']),
      longitude:     parseDouble(json['longitude']),
      location:      json['location']?.toString(),
      sentMode:      json['sent_mode']?.toString(),
      createdAt:     parseDate(json['created_at'] ?? json['createdAt']),
    );
  }

  String get typeLabel => type.replaceAll('_', ' ').toUpperCase();

  String get locationText {
    if (location != null && location!.isNotEmpty) return location!;
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    }
    return 'Location unavailable';
  }

  String get createdAtLabel {
    if (createdAt == null) return 'Unknown date';
    return '${createdAt!.month}/${createdAt!.day}/${createdAt!.year} '
        '${createdAt!.hour.toString().padLeft(2, '0')}:'
        '${createdAt!.minute.toString().padLeft(2, '0')}';
  }

  Color get statusColor {
    switch (status.toUpperCase()) {
      case 'RESOLVED':    return Colors.greenAccent;
      case 'IN_PROGRESS': return Colors.orangeAccent;
      default:            return Colors.redAccent;
    }
  }
}