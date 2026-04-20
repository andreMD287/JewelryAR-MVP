import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/ar_hand_screen.dart';
import 'screens/ar_face_screen.dart';

void main() {
  runApp(const JewelryARApp());
}

class JewelryARApp extends StatelessWidget {
  const JewelryARApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jewelry AR MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B6914)),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        // Pantalla AR manos — integrará ar_flutter_plugin_2 + detección de manos
        '/ar-hands': (context) => const ARHandScreen(),
        // Pantalla AR rostro — integrará google_mlkit_face_detection + ar_flutter_plugin_2
        '/ar-face': (context) => const ARFaceScreen(),
      },
    );
  }
}
