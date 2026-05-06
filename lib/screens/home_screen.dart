import 'package:flutter/material.dart';

import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<UserReport>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = _loadReports();
  }

  Future<List<UserReport>> _loadReports() async {
    final response = await ApiService.getReports();
    final reports = response is Map ? response['reports'] : null;

    if (reports is List) {
      return reports
          .whereType<Map<String, dynamic>>()
          .map(UserReport.fromJson)
          .toList();
    }

    return [];
  }

  Future<void> _refreshReports() async {
    setState(() {
      _reportsFuture = _loadReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Response',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Stay aware. Stay connected.',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.redAccent,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2028),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.wifi,
                      color: Colors.redAccent,
                      size: 36,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Network Status',
                            style: TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Online and Mesh Ready',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Your Reports',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshReports,
                  child: FutureBuilder<List<UserReport>>(
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
                            'Unable to load reports.',
                            style: TextStyle(color: Colors.grey[300]),
                          ),
                        );
                      }

                      final reports = snapshot.data ?? [];

                      if (reports.isEmpty) {
                        return Center(
                          child: Text(
                            'No reports yet. Submit one from the Report tab.',
                            style: TextStyle(color: Colors.grey[300]),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: reports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          return _buildReportCard(reports[index]);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportCard(UserReport report) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                report.reportTypeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.locationText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey),
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
        ],
      ),
    );
  }
}

class UserReport {
  final String reportId;
  final String type;
  final String description;
  final String urgencyLevel;
  final String status;
  final double? latitude;
  final double? longitude;
  final String sentMode;
  final DateTime? createdAt;

  UserReport({
    required this.reportId,
    required this.type,
    required this.description,
    required this.urgencyLevel,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.sentMode,
    required this.createdAt,
  });

  factory UserReport.fromJson(Map<String, dynamic> json) {
    final String id = (json['reportid'] ?? json['reportID'] ?? json['report_id'] ?? '').toString();

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

    return UserReport(
      reportId: id,
      type: (json['report_type'] ?? json['reporttype'] ?? 'OTHER').toString(),
      description: (json['description'] ?? '').toString(),
      urgencyLevel: (json['urgency_level'] ?? json['urgencylevel'] ?? 'MEDIUM').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      sentMode: (json['sent_mode'] ?? json['sentmode'] ?? 'INTERNET').toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt'] ?? json['timestamp']),
    );
  }

  String get reportTypeLabel => type.replaceAll('_', ' ').toUpperCase();

  String get locationText {
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(0)}°, ${longitude!.toStringAsFixed(0)}°';
    }
    return 'Location not available';
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
