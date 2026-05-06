import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Future<List<AdminReport>> _reportsFuture;
  String? _updatingReportId;

  @override
  void initState() {
    super.initState();
    _reportsFuture = _loadReports();
  }

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
    });
  }

  Future<void> _updateStatus(String reportId, String status) async {
    setState(() {
      _updatingReportId = reportId;
    });

    try {
      await ApiService.updateStatus(reportId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status changed to $status.')),
      );
      await _refreshReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingReportId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF10131A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshReports,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Report Control',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<AdminReport>>(
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

                  final reports = snapshot.data ?? [];

                  if (reports.isEmpty) {
                    return Center(
                      child: Text(
                        'No reports available.',
                        style: TextStyle(color: Colors.grey[300]),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refreshReports,
                    child: ListView.separated(
                      itemCount: reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        return _buildReportCard(reports[index]);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(AdminReport report) {
    final isUpdating = _updatingReportId == report.reportId;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2028),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.typeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Reported by ${report.reporterName} (${report.reporterEmail})',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: report.statusColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  report.status.toUpperCase(),
                  style: TextStyle(
                    color: report.statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            report.description.isNotEmpty ? report.description : 'No description provided.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.redAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.locationText,
                  style: const TextStyle(color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  report.urgencyLevel,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                report.createdAtLabel,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isUpdating
                      ? null
                      : () => _updateStatus(report.reportId, 'IN_PROGRESS'),
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
                      : () => _updateStatus(report.reportId, 'RESOLVED'),
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
    );
  }
}

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
      reportId: (json['reportid'] ?? json['reportID'] ?? json['report_id'] ?? '').toString(),
      type: (json['report_type'] ?? 'OTHER').toString(),
      description: (json['description'] ?? '').toString(),
      urgencyLevel: (json['urgency_level'] ?? 'MEDIUM').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      reporterName: (json['reporter_name'] ?? json['reporterName'] ?? 'Unknown').toString(),
      reporterEmail: (json['reporter_email'] ?? json['reporterEmail'] ?? 'unknown@example.com').toString(),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
    );
  }

  String get typeLabel => type.replaceAll('_', ' ').toUpperCase();

  String get locationText {
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    }
    return 'Location unavailable';
  }

  String get createdAtLabel {
    if (createdAt != null) {
      return '${createdAt!.month}/${createdAt!.day}/${createdAt!.year} ${createdAt!.hour.toString().padLeft(2, '0')}:${createdAt!.minute.toString().padLeft(2, '0')}';
    }
    return 'Unknown date';
  }

  Color get statusColor {
    switch (status.toUpperCase()) {
      case 'RESOLVED':
        return Colors.greenAccent;
      case 'IN_PROGRESS':
        return Colors.orangeAccent;
      default:
        return Colors.redAccent;
    }
  }
}
