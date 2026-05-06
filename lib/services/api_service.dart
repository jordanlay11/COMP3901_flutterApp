import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static const String serverUrl = "http://192.168.100.21:5000";

  static String? token;

  static Map<String, String> get headers => {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      };

  // 🔧 Generic request handler (prevents duplication)
  static Future<dynamic> _handleRequest(Future<http.Response> request) async {
    try {
      final response = await request.timeout(
        const Duration(seconds: 15), // Increased timeout from 5s to 15s
        onTimeout: () {
          throw TimeoutException(
            'Request timed out. Is the server running at $serverUrl?',
            const Duration(seconds: 15),
          );
        },
      );

      if (response.body.isEmpty) {
        throw Exception("Empty response from server (status: ${response.statusCode})");
      }

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (e) {
        throw Exception("Failed to decode backend response: ${response.body}");
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      } else {
        final message = data is Map && data["message"] != null
            ? data["message"]
            : data is Map && data["error"] != null
                ? data["error"]
                : "Request failed with status ${response.statusCode}";
        throw Exception("Backend error ($message) [status=${response.statusCode}] response=${response.body}");
      }
    } on TimeoutException catch (e) {
      throw Exception("Timeout: ${e.message}");
    } catch (e) {
      throw Exception("Network error: $e");
    }
  }

  // 🔐 Register
  static Future register(String name, String email, String password) async {
    return await _handleRequest(
      http.post(
        Uri.parse("$serverUrl/auth/register"),
        headers: headers,
        body: jsonEncode({
          "userName": name,
          "email": email,
          "password": password,
        }),
      ),
    );
  }

  // 🔐 Login
  static Future login(String email, String password) async {
    final data = await _handleRequest(
      http.post(
        Uri.parse("$serverUrl/auth/login"),
        headers: headers,
        body: jsonEncode({
          "email": email,
          "password": password,
        }),
      ),
    );

    if (data["token"] != null) {
      token = data["token"];
    }

    return data;
  }

  // 📤 Create Report
  static Future reportIncident(Map<String, dynamic> report) async {
    return await _handleRequest(
      http.post(
        Uri.parse("$serverUrl/report"),
        headers: headers,
        body: jsonEncode(report),
      ),
    );
  }

  // 📥 Get Reports
  static Future getReports() async {
    return await _handleRequest(
      http.get(
        Uri.parse("$serverUrl/userreport"),
        headers: headers,
      ),
    );
  }

  // ❌ Delete Report
  static Future deleteReport(String reportId) async {
    return await _handleRequest(
      http.delete(
        Uri.parse("$serverUrl/report/$reportId"),
        headers: headers,
      ),
    );
  }

  // 🔄 Update Status
  static Future updateStatus(String reportId, String status) async {
    return await _handleRequest(
      http.put(
        Uri.parse("$serverUrl/status/$reportId"),
        headers: headers,
        body: jsonEncode({"status": status}),
      ),
    );
  }

  // 🚨 Alerts
  static Future getAlerts() async {
    return await _handleRequest(
      http.get(
        Uri.parse("$serverUrl/alerts"),
        headers: headers,
      ),
    );
  }

  // 🔄 Sync (mesh → server fallback)
  static Future syncReports(List reports) async {
    return await _handleRequest(
      http.post(
        Uri.parse("$serverUrl/sync"),
        headers: headers,
        body: jsonEncode({"reports": reports}),
      ),
    );
  }

  // 📤 Mesh Upload (device → server)
  static Future meshUpload(List messages) async {
    return await _handleRequest(
      http.post(
        Uri.parse("$serverUrl/mesh/upload"),
        headers: headers,
        body: jsonEncode({"messages": messages}),
      ),
    );
  }

  // 📥 Mesh Download (server → device)
  static Future meshDownload() async {
    return await _handleRequest(
      http.get(
        Uri.parse("$serverUrl/mesh/download"),
        headers: headers,
      ),
    );
  }

  // 📸 Upload report photo
  static Future uploadReportPhoto(String reportId, File imageFile) async {
    final uri = Uri.parse("$serverUrl/photo/$reportId");
    final request = http.MultipartRequest('POST', uri);

    final authHeaders = Map<String, String>.from(headers);
    authHeaders.remove('Content-Type');
    request.headers.addAll(authHeaders);

    request.files.add(
      await http.MultipartFile.fromPath('photo', imageFile.path),
    );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw TimeoutException('Photo upload timed out.');
      },
    );

    final response = await http.Response.fromStream(streamedResponse);
    return await _handleRequest(Future.value(response));
  }
}