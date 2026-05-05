import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService{
    static const String serverUrl = "http://192.168.0.9:5000";

    static String? token;

    static Map<String, String> get headers => {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
    };

    //Register user

    static Future register(String name, String email, String password) async {
        final response = await http.post(
            Uri.parse("$serverUrl/auth/register"),
            headers: headers,
            body: jsonEncode({
                "userName": name,
                "email": email,
                "password": password,
            }),
        );
        return jsonDecode(response.body);  
    }

    //Login user
    static Future login(String email, String password) async {
        final response = await http.post(
            Uri.parse("$serverUrl/auth/login"),
            headers: headers,
            body: jsonEncode({
                "email": email,
                "password": password,
            }),
        );
        final data = jsonDecode(response.body);

        if (data["token"] != null) {
            token = data["token"];
        }
        return data;
    }

    //Report incident
    static Future reportIncident(Map<String, dynamic> report) async {
        final response = await http.post(
            Uri.parse("$serverUrl/report"),
            headers: headers,
            body: jsonEncode(report),
        );
        return jsonDecode(response.body);
    }

    //Fetch user reports
    static Future getReports() async {
        final response = await http.get(
            Uri.parse("$serverUrl/userreport"),
            headers: headers,
        );
        return jsonDecode(response.body);
    }

    //Delete report
    static Future deleteReport(String reportId) async {
        final response = await http.delete(
            Uri.parse("$serverUrl/report/$reportId"),
            headers: headers,
        );
        return jsonDecode(response.body);
    }

    //Update Status
    static Future updateStatus(String reportId, String status) async {
        final response = await http.put(
            Uri.parse("$serverUrl/status/$reportId"),
            headers: headers,
            body: jsonEncode({"status": status}),
        );
        return jsonDecode(response.body);
    }

    //Alerts
    static Future getAlerts() async {
        final response = await http.get(
            Uri.parse("$serverUrl/alerts"),
            headers: headers,
        );
        return jsonDecode(response.body);
    }

    //Sync local reports with server
    static Future syncReports(List reports) async {
        final response = await http.post(
            Uri.parse("$serverUrl/sync"),
            headers: headers,
            body: jsonEncode(
                {"reports": reports}
                ),
        );
        return jsonDecode(response.body);
                
    }


    static Future meshUpload(List messages) async {
        final response = await http.post(
            Uri.parse("$serverUrl/mesh/upload"),
            headers: headers,
            body: jsonEncode({"messages": messages}),
        );
        return jsonDecode(response.body);
    }       

    static Future meshDownload() async {
    final response = await http.get(
        Uri.parse("$serverUrl/mesh/download"),
        headers: headers,
    );
        return jsonDecode(response.body);
    }


}

