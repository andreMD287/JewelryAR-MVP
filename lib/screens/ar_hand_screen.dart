import 'package:flutter/material.dart';

// Pantalla de AR para manos — prueba virtual de pulseras.
//
// Integración pendiente:
//   - ar_flutter_plugin_2: ARView con plano horizontal / seguimiento de superficie
//   - Detección de manos: MediaPipe Hands o ARCore Hand Tracking (plugin nativo)
//   - permission_handler: solicitar permiso de cámara antes de iniciar ARView
//   - camera: preview de cámara como fallback si ARCore no está disponible
class ARHandScreen extends StatelessWidget {
  const ARHandScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B6914),
        foregroundColor: Colors.white,
        title: const Text('AR Manos — Pulseras'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.back_hand_outlined, size: 80, color: Color(0xFF8B6914)),
            SizedBox(height: 24),
            Text(
              'ARView de Pulseras',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Aquí se integrará ar_flutter_plugin_2 para superponer\n'
                'modelos 3D de pulseras sobre la muñeca detectada.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ),
            SizedBox(height: 32),
            Chip(label: Text('TODO: ar_flutter_plugin_2')),
            SizedBox(height: 8),
            Chip(label: Text('TODO: detección de manos')),
            SizedBox(height: 8),
            Chip(label: Text('TODO: permission_handler (CAMERA)')),
          ],
        ),
      ),
    );
  }
}
