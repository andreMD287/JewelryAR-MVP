import 'package:flutter/material.dart';

// Pantalla principal: punto de entrada a los tres modos de prueba del MVP.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B6914),
        foregroundColor: Colors.white,
        title: const Text('Jewelry AR — MVP'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Selecciona una prueba de tecnología',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D2B00),
              ),
            ),
            const SizedBox(height: 40),

            // Botón 1: AR con seguimiento de manos para pulseras
            // Tecnología a integrar: ar_flutter_plugin_2 + detección de manos (MediaPipe / ARCore Hand Tracking)
            _AROptionButton(
              icon: Icons.back_hand_outlined,
              label: 'Test AR Manos (Pulseras)',
              description: 'Prueba virtual de pulseras sobre la muñeca',
              color: const Color(0xFF8B6914),
              onTap: () => Navigator.pushNamed(context, '/ar-hands'),
            ),
            const SizedBox(height: 16),

            // Botón 2: AR con detección facial para aretes
            // Tecnología a integrar: google_mlkit_face_detection + ar_flutter_plugin_2
            _AROptionButton(
              icon: Icons.face_retouching_natural,
              label: 'Test AR Rostro (Aretes)',
              description: 'Prueba virtual de aretes sobre el rostro',
              color: const Color(0xFF5C4033),
              onTap: () => Navigator.pushNamed(context, '/ar-face'),
            ),
            const SizedBox(height: 16),

            // Botón 3: Visor de modelo 3D estático sin AR
            // Tecnología a integrar: model_viewer_plus con archivos glTF/GLB
            _AROptionButton(
              icon: Icons.view_in_ar,
              label: 'Test Modelo 3D Estático',
              description: 'Visualiza un modelo 3D interactivo de joya',
              color: const Color(0xFF2E7D5E),
              onTap: () {
                // TODO: navegar al visor de modelo 3D (model_viewer_plus)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Visor 3D — próximamente con model_viewer_plus'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AROptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _AROptionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
