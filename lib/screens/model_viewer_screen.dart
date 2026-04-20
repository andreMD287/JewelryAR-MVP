import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'ar_placement_screen.dart';

// Pantalla de validación de modelo 3D con PBR.
// Tecnología: model_viewer_plus (WebView + <model-viewer> web component).
// El rendering 3D ocurre dentro del WebView a su propio framerate.
// El HUD de FPS mide el UI thread de Flutter, no el WebView.
class ModelViewerScreen extends StatefulWidget {
  const ModelViewerScreen({super.key});

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen>
    with SingleTickerProviderStateMixin {
  // Ticker sincronizado con VSync para medir FPS del UI thread de Flutter
  late final Ticker _ticker;
  int _frameCount = 0;
  double _fps = 0.0;
  int _lastMs = 0;

  // El WebView tarda ~1.5 s en cargar; ocultamos el loader con un timer
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _modelReady = true);
    });
  }

  void _onTick(Duration elapsed) {
    _frameCount++;
    final ms = elapsed.inMilliseconds;
    if (ms - _lastMs >= 1000) {
      final dt = (ms - _lastMs) / 1000.0;
      if (mounted) {
        setState(() {
          _fps = _frameCount / dt;
          _frameCount = 0;
          _lastMs = ms;
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Color get _fpsColor {
    if (_fps >= 55) return Colors.greenAccent;
    if (_fps >= 30) return Colors.orange;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        title: const Text('Modelo 3D — PBR Test'),
        actions: [
          // Acceso directo a AR desde el AppBar
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ARPlacementScreen()),
            ),
            icon: const Icon(Icons.view_in_ar, color: Colors.white70, size: 20),
            label: const Text(
              'AR',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Visor principal ──────────────────────────────────────────────
          // model_viewer_plus sirve el asset desde un servidor HTTP local.
          // ar: true habilita el botón nativo de AR del <model-viewer>
          //   → iOS: AR Quick Look (USDZ)
          //   → Android: Scene Viewer / WebXR
          ModelViewer(
            src: 'assets/models/test_jewelry.glb',
            alt: 'Damaged Helmet — modelo PBR de referencia (Khronos glTF Samples)',
            ar: true,
            arModes: const ['scene-viewer', 'webxr', 'quick-look'],
            autoRotate: true,
            autoRotateDelay: 0,
            cameraControls: true,
            shadowIntensity: 1,
            // Entorno neutral de alta calidad para demostrar reflejos PBR
            environmentImage: 'neutral',
            exposure: 1.0,
          ),

          // ── HUD — esquina superior izquierda ─────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HudBadge(
                  icon: Icons.speed,
                  label: 'Flutter UI: ${_fps.toStringAsFixed(0)} fps',
                  color: _fpsColor,
                ),
                const SizedBox(height: 6),
                // GLB usa materiales PBR metallic-roughness por especificación glTF 2.0
                const _HudBadge(
                  icon: Icons.auto_awesome,
                  label: 'PBR: Activo (glTF 2.0 metallic-roughness)',
                  color: Colors.greenAccent,
                ),
                const SizedBox(height: 6),
                const _HudBadge(
                  icon: Icons.web_asset,
                  label: 'Renderer: WebView / model-viewer',
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ),

          // ── Loader inicial ───────────────────────────────────────────────
          if (!_modelReady)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF8B6914),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Cargando modelo PBR…',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      // ── Botón "Ver en AR" — usa ar_flutter_plugin_2 ─────────────────────
      // A diferencia del botón nativo del model-viewer (Scene Viewer / Quick Look),
      // este botón abre ARPlacementScreen que usa ar_flutter_plugin_2 directamente,
      // permitiendo colocar el modelo en superficies detectadas por ARCore/ARKit.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ARPlacementScreen()),
        ),
        backgroundColor: const Color(0xFF8B6914),
        icon: const Icon(Icons.view_in_ar, color: Colors.white),
        label: const Text(
          'Ver en AR',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _HudBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HudBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
