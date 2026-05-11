import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'report_screen.dart';
import 'sos_screen.dart';
import 'mesh_screen.dart';
import '../services/mesh_service.dart';


class AppContainer extends StatefulWidget {
  const AppContainer({super.key});

  @override
  State<AppContainer> createState() => _AppContainerState();
}

class _AppContainerState extends State<AppContainer> {
  int currentIndex = 0;

  final PageStorageBucket bucket = PageStorageBucket();

  final List<Widget> pages = [
    const HomeScreen(),
    ReportScreen(),
    SosScreen(),
    MeshScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _startMesh();
  }

  Future<void> _startMesh() async {
  await meshService.start(onLog: (msg) {
    // Log messages globally
    setState(() {
      // You can store logs in a list if needed
    });
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageStorage(
        bucket: bucket,
        child: IndexedStack(
          index: currentIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF10131A),
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.report),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning),
            label: 'SOS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.hub),
            label: 'Mesh',
          ),
        ],
      ),
    );
  }
}