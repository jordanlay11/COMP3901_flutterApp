import 'package:flutter/material.dart';
import 'screens/mesh_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh App',
      home: MeshScreen(),
    );
  }
}