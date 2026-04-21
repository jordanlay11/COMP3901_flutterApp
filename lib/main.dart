import 'package:flutter/material.dart';
import 'screens/mesh_screen.dart';   // your existing mesh test
import 'screens/sos_screen.dart';
import 'screens/report_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int index = 0;

  final List<Widget> pages = [
    MeshScreen(),   // 🧪 testing page
    SosScreen(),    // 🚨 emergency
    ReportScreen(), // 📝 report
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.developer_mode),
            label: "Test",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning),
            label: "SOS",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description),
            label: "Report",
          ),
        ],
      ),
    );
  }
}