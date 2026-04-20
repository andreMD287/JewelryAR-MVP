import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

// Pantalla de colocación AR usando ar_flutter_plugin_2.
// Tecnología: ARCore (Android) / ARKit (iOS) mediante ar_flutter_plugin_2.
// Flujo: detección de plano → tap para colocar → modelo GLB en superficie.
class ARPlacementScreen extends StatefulWidget {
  const ARPlacementScreen({super.key});

  @override
  State<ARPlacementScreen> createState() => _ARPlacementScreenState();
}

enum _ARState {
  // Inicializando / buscando superficies planas
  scanning,
  // Superficie detectada — listo para colocar
  ready,
  // Modelo colocado en la escena
  placed,
  // Dispositivo no soporta ARCore/ARKit
  unsupported,
  // Error genérico al inicializar la sesión AR
  error,
}

class _ARPlacementScreenState extends State<ARPlacementScreen> {
  _ARState _state = _ARState.scanning;
  String _errorMessage = '';

  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;

  // Rastreo de nodos y anclas para poder reiniciar la colocación
  final List<ARNode> _nodes = [];
  final List<ARAnchor> _anchors = [];

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  // Callback principal de ar_flutter_plugin_2 — se ejecuta cuando la cámara AR está lista
  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;
    _arAnchorManager = arAnchorManager;

    // Inicializamos la sesión en un método async separado para manejar errores
    _initSession(arSessionManager, arObjectManager);
  }

  Future<void> _initSession(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
  ) async {
    try {
      await arSessionManager.onInitialize(
        showAnimatedGuide: false,
        showFeaturePoints: true, // puntos de feature útiles para debug visual
        showPlanes: true,        // planos detectados resaltados en verde/blanco
        showWorldOrigin: false,
        handlePans: false,
        handleRotation: false,
      );
      await arObjectManager.onInitialize();

      // Registrar callback de tap sobre planos/puntos
      arSessionManager.onPlaneOrPointTap = _onPlaneOrPointTap;

      // Dar 3 s para que ARCore/ARKit detecte superficies antes de pedir al usuario
      Timer(const Duration(seconds: 3), () {
        if (mounted && _state == _ARState.scanning) {
          setState(() => _state = _ARState.ready);
        }
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      // ARCore no instalado, dispositivo no compatible, o sesión no pudo iniciarse
      final msg = e.message ?? '';
      setState(() {
        _state = msg.toLowerCase().contains('support')
            ? _ARState.unsupported
            : _ARState.error;
        _errorMessage = msg.isNotEmpty ? msg : e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ARState.error;
        _errorMessage = e.toString();
      });
    }
  }

  // Tap en la vista AR → buscar hit en plano → colocar modelo GLB
  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hitTestResults) async {
    if (_state == _ARState.placed || hitTestResults.isEmpty) return;

    // Preferir hits en planos existentes; como fallback aceptar cualquier hit
    ARHitTestResult? planeHit;
    for (final r in hitTestResults) {
      if (r.type == ARHitTestResultType.plane) {
        planeHit = r;
        break;
      }
    }
    planeHit ??= hitTestResults.first;

    // Crear un ancla en la posición detectada
    final anchor = ARPlaneAnchor(transformation: planeHit.worldTransform);
    final didAddAnchor = await _arAnchorManager!.addAnchor(anchor);
    if (didAddAnchor != true) return;
    _anchors.add(anchor);

    // Agregar el nodo GLB anclado al plano
    // NodeType.localGLTF2: el plugin copia el asset a un directorio temporal
    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: 'assets/models/test_jewelry.glb',
      scale: Vector3(0.15, 0.15, 0.15),
      position: Vector3(0.0, 0.0, 0.0),
      rotation: Vector4(1.0, 0.0, 0.0, 0.0),
    );

    final didAddNode = await _arObjectManager!.addNode(node, planeAnchor: anchor);
    if (didAddNode == true) {
      _nodes.add(node);
      if (mounted) setState(() => _state = _ARState.placed);
    }
  }

  // Quitar el modelo y las anclas para volver a colocar
  Future<void> _resetPlacement() async {
    for (final node in _nodes) {
      await _arObjectManager?.removeNode(node);
    }
    for (final anchor in _anchors) {
      await _arAnchorManager?.removeAnchor(anchor);
    }
    _nodes.clear();
    _anchors.clear();
    if (mounted) setState(() => _state = _ARState.ready);
  }

  @override
  Widget build(BuildContext context) {
    final isErrorState =
        _state == _ARState.unsupported || _state == _ARState.error;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('AR — Colocar Modelo'),
        actions: [
          if (_state == _ARState.placed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reiniciar colocación',
              onPressed: _resetPlacement,
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Vista AR o pantalla de error ─────────────────────────────────
          if (isErrorState)
            _buildErrorView()
          else
            ARView(
              onARViewCreated: _onARViewCreated,
              planeDetectionConfig:
                  PlaneDetectionConfig.horizontalAndVertical,
            ),

          // ── Overlay de instrucciones (solo en estados AR activos) ─────────
          if (!isErrorState) _buildOverlay(),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return Positioned(
      bottom: 48,
      left: 24,
      right: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Estado: escaneando ───────────────────────────────────────────
          if (_state == _ARState.scanning) ...[
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 14),
            _StatusChip(
              text: 'Mueve lentamente el dispositivo para detectar superficies…',
              color: Colors.white70,
            ),
          ],

          // ── Estado: listo para colocar ───────────────────────────────────
          if (_state == _ARState.ready) ...[
            const Icon(Icons.touch_app, color: Colors.greenAccent, size: 32),
            const SizedBox(height: 10),
            _StatusChip(
              text: 'Toca una superficie plana para colocar el modelo',
              color: Colors.greenAccent,
            ),
          ],

          // ── Estado: modelo colocado ──────────────────────────────────────
          if (_state == _ARState.placed) ...[
            _StatusChip(
              text: '¡Modelo colocado! Mueve la cámara alrededor para ver el PBR',
              color: Colors.greenAccent,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _resetPlacement,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B6914),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Colocar de nuevo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    final isUnsupported = _state == _ARState.unsupported;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUnsupported ? Icons.phonelink_erase : Icons.error_outline,
              size: 72,
              color: isUnsupported ? Colors.orange : Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              isUnsupported ? 'AR no disponible' : 'Error al iniciar AR',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isUnsupported
                  ? 'Este dispositivo no soporta ARCore (Android) o ARKit (iOS).\n'
                    'Verifica que ARCore esté instalado y actualizado desde la Play Store.'
                  : _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver al modelo 3D'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }
}
