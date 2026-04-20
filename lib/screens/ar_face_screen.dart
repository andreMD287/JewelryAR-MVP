import 'package:flutter/material.dart';

// Pantalla de AR para rostro — prueba virtual de aretes.
//
// Integración pendiente:
//   - google_mlkit_face_detection: detectar landmarks faciales (orejas)
//   - camera: stream de frames al detector ML Kit
//   - ar_flutter_plugin_2: anclar modelos 3D de aretes en los puntos de las orejas
//   - permission_handler: solicitar permiso de cámara antes de iniciar la sesión
class ARFaceScreen extends StatelessWidget {
  const ARFaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF5C4033),
        foregroundColor: Colors.white,
        title: const Text('AR Rostro — Aretes'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face_retouching_natural, size: 80, color: Color(0xFF5C4033)),
            SizedBox(height: 24),
            Text(
              'ARView de Aretes',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Aquí se integrará google_mlkit_face_detection para localizar\n'
                'las orejas y anclar modelos 3D de aretes con ar_flutter_plugin_2.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ),
            SizedBox(height: 32),
            Chip(label: Text('TODO: google_mlkit_face_detection')),
            SizedBox(height: 8),
            Chip(label: Text('TODO: camera (CameraController)')),
            SizedBox(height: 8),
            Chip(label: Text('TODO: ar_flutter_plugin_2 (anchor en orejas)')),
            SizedBox(height: 8),
            Chip(label: Text('TODO: permission_handler (CAMERA)')),
          ],
        ),
      ),
    );
  }
}
