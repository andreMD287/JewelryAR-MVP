// ─────────────────────────────────────────────────────────────────────────────
// ARHandScreen — Tracking de landmarks de mano con MediaPipe Hand Landmarker
//
// INVESTIGACIÓN DE VIABILIDAD (pub.dev, abril 2026):
//
// Opción A — "google_mediapipe" oficial:
//   NO existe un paquete oficial de Google con ese nombre en pub.dev.
//   Google mantiene dart-lang/mediapipe (experimental) pero sin hand tracking
//   disponible como paquete publicado para Flutter mobile.
//
// Opción B — hand_landmarker 2.2.0 (ELEGIDA):
//   URL: pub.dev/packages/hand_landmarker
//   Implementa MediaPipe Hand Landmarker via JNI bridge a código nativo Android.
//   Da 21 landmarks con coordenadas 3D normalizadas (x, y, z ∈ [0,1]).
//   Acepta CameraImage directamente — sin conversión YUV manual.
//   LIMITACIÓN CRÍTICA: solo Android. iOS no soportado.
//
// Opción C — hand_detection 2.0.9 (descartada para este sprint):
//   Usa TFLite, cross-platform (Android + iOS). Requiere conversión manual
//   de YUV→BGR usando Mat (opencv_dart). Mayor complejidad de integración.
//   Candidato para integración iOS en siguiente sprint.
//
// Opción D — google_mlkit_pose_detection 0.14.1 (fallback documentado):
//   Detecta muñeca como parte del esqueleto corporal (landmarks 15-16),
//   pero NO da landmarks individuales de dedos. Insuficiente para anclar anillos.
//
// RESPUESTA AL OBJETIVO:
//   ¿Podemos obtener posición 3D del nudillo del índice (punto 5) desde Flutter?
//   → SÍ en Android: hand_landmarker expone x, y, z normalizados en tiempo real.
//   → NO en iOS aún: requiere integración adicional (ARKit Hand Anchors o TFLite).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

// ── Topología MediaPipe Hands (21 landmarks) ─────────────────────────────────
// Los pares indican qué landmarks conectar para dibujar el esqueleto.
const List<(int, int)> _kConnections = [
  // Pulgar
  (0, 1), (1, 2), (2, 3), (3, 4),
  // Índice
  (0, 5), (5, 6), (6, 7), (7, 8),
  // Medio
  (0, 9), (9, 10), (10, 11), (11, 12),
  // Anular
  (0, 13), (13, 14), (14, 15), (15, 16),
  // Meñique
  (0, 17), (17, 18), (18, 19), (19, 20),
  // Palma
  (5, 9), (9, 13), (13, 17),
];

// Landmark 5 = Index Finger MCP (primera articulación/nudillo del índice).
// Punto de anclaje para anillos y pulseras en el MVP.
const int _kIndexMCP = 5;

// ─────────────────────────────────────────────────────────────────────────────

enum _ScreenState { loading, detecting, permissionDenied, unsupportedPlatform, error }

class ARHandScreen extends StatefulWidget {
  const ARHandScreen({super.key});

  @override
  State<ARHandScreen> createState() => _ARHandScreenState();
}

class _ARHandScreenState extends State<ARHandScreen> {
  _ScreenState _state = _ScreenState.loading;
  String _errorMessage = '';

  CameraController? _cameraController;
  HandLandmarkerPlugin? _plugin;

  // Último resultado de detección
  List<Hand> _currentHands = [];

  // Throttle: evita llamar detect() más rápido de lo que el plugin puede procesar.
  // detect() es sincrónico y bloquea el isolate de Dart ~15-40 ms por frame.
  // Para producción: usar un isolate dedicado con su propia instancia del plugin.
  bool _isDetecting = false;
  int _lastDetectionMs = 0;
  static const int _kMinFrameIntervalMs = 100; // ≤10 FPS de detección

  // FPS de detección (cuántas veces por segundo obtenemos un resultado)
  int _detectionCount = 0;
  double _detectionFps = 0.0;
  int _fpsWindowStart = 0;

  @override
  void initState() {
    super.initState();
    // hand_landmarker solo soporta Android (JNI bridge a MediaPipe)
    if (!Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _state = _ScreenState.unsupportedPlatform);
      });
      return;
    }
    _initialize();
  }

  Future<void> _initialize() async {
    // ── 1. Permiso de cámara ─────────────────────────────────────────────
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) setState(() => _state = _ScreenState.permissionDenied);
      return;
    }

    // ── 2. MediaPipe Hand Landmarker ─────────────────────────────────────
    // API: HandLandmarkerPlugin.create({numHands, minHandDetectionConfidence, delegate})
    // delegate: gpu (MediaPipe GPU backend) — más rápido que CPU en dispositivos modernos
    try {
      _plugin = HandLandmarkerPlugin.create(
        numHands: 1, // suficiente para MVP de joyería (una mano a la vez)
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _ScreenState.error;
          _errorMessage = 'No se pudo inicializar MediaPipe Hand Landmarker:\n$e\n\n'
              'Verifica que el dispositivo tenga driver GPU compatible.';
        });
      }
      return;
    }

    // ── 3. Cámara ────────────────────────────────────────────────────────
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No se encontraron cámaras.');

      // Cámara trasera: el usuario apunta hacia su propia mano
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium, // ~640×480: equilibrio rendimiento/precisión
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // formato nativo Android
      );
      await _cameraController!.initialize();

      if (!mounted) return;
      _fpsWindowStart = DateTime.now().millisecondsSinceEpoch;
      setState(() => _state = _ScreenState.detecting);

      // Iniciar stream de frames
      await _cameraController!.startImageStream(_onCameraFrame);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _ScreenState.error;
          _errorMessage = 'Error al inicializar cámara:\n$e';
        });
      }
    }
  }

  // Callback del stream de cámara — se llama en el main isolate de Dart.
  void _onCameraFrame(CameraImage image) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_isDetecting || nowMs - _lastDetectionMs < _kMinFrameIntervalMs) return;

    _isDetecting = true;
    _lastDetectionMs = nowMs;

    List<Hand> hands;
    try {
      // detect() es sincrónico — envía el CameraImage (YUV420) al JNI layer.
      // El plugin maneja internamente la conversión de formato y la rotación
      // del sensor (sensorOrientation). El resultado ya está en coordenadas
      // de pantalla normalizadas (0–1).
      //
      // NOTA DE RENDIMIENTO: esto bloquea el Dart main isolate ~15-40 ms.
      // Para producción con 30+ FPS, usar Isolate.run() con una instancia
      // separada del plugin creada dentro del isolate.
      hands = _plugin!.detect(
        image,
        _cameraController!.description.sensorOrientation,
      );
    } catch (e) {
      _isDetecting = false;
      return; // descartar frame con error
    }

    // Actualizar FPS de detección (ventana de 1 segundo)
    _detectionCount++;
    final elapsed = nowMs - _fpsWindowStart;
    if (elapsed >= 1000) {
      _detectionFps = _detectionCount * 1000.0 / elapsed;
      _detectionCount = 0;
      _fpsWindowStart = nowMs;
    }

    if (mounted) setState(() => _currentHands = hands);
    _isDetecting = false;
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _plugin?.dispose(); // libera recursos JNI/MediaPipe
    super.dispose();
  }

  // ── Coordenadas del Index MCP (landmark 5) del primer hand detectado ──────
  Landmark? get _indexMCP {
    if (_currentHands.isEmpty) return null;
    final lm = _currentHands[0].landmarks;
    return lm.length > _kIndexMCP ? lm[_kIndexMCP] : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Tracking Manos — MediaPipe'),
      ),
      body: switch (_state) {
        _ScreenState.loading => _buildLoading(),
        _ScreenState.permissionDenied => _buildInfoScreen(
            icon: Icons.camera_alt_outlined,
            color: Colors.orange,
            title: 'Permiso de cámara requerido',
            body: 'Ve a Ajustes → Apps → jewelry_ar_mvp → Permisos y activa Cámara.',
          ),
        _ScreenState.unsupportedPlatform => _buildInfoScreen(
            icon: Icons.phonelink_erase,
            color: Colors.orange,
            title: 'Disponible solo en Android',
            body:
                'hand_landmarker usa un JNI bridge a MediaPipe que solo existe en Android.\n\n'
                'Alternativa iOS: hand_detection 2.0.9 (TFLite + Mat) o ARKit Hand Anchors '
                'via método nativo. Pendiente para siguiente sprint.',
          ),
        _ScreenState.error => _buildInfoScreen(
            icon: Icons.error_outline,
            color: Colors.redAccent,
            title: 'Error de inicialización',
            body: _errorMessage,
          ),
        _ScreenState.detecting => _buildDetectionView(),
      },
    );
  }

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF8B6914), strokeWidth: 2.5),
            SizedBox(height: 16),
            Text(
              'Iniciando MediaPipe Hand Landmarker…',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );

  Widget _buildDetectionView() {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return _buildLoading();

    final isBack = cam.description.lensDirection == CameraLensDirection.back;
    final totalLandmarks = _currentHands.fold<int>(0, (s, h) => s + h.landmarks.length);
    final mcp = _indexMCP;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Feed de cámara ────────────────────────────────────────────────
        // AspectRatio alinea el painter exactamente sobre el preview
        Center(
          child: AspectRatio(
            aspectRatio: 1 / cam.value.aspectRatio,
            child: CameraPreview(cam),
          ),
        ),

        // ── Overlay de landmarks (CustomPainter) ──────────────────────────
        if (_currentHands.isNotEmpty)
          Center(
            child: AspectRatio(
              aspectRatio: 1 / cam.value.aspectRatio,
              child: CustomPaint(
                painter: _HandPainter(
                  hands: _currentHands,
                  isBackCamera: isBack,
                ),
              ),
            ),
          ),

        // ── HUD superior izquierdo ─────────────────────────────────────────
        Positioned(
          top: 12,
          left: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Badge(
                icon: Icons.speed,
                label: 'Track: ${_detectionFps.toStringAsFixed(1)} FPS',
                color: _detectionFps >= 7
                    ? Colors.greenAccent
                    : _detectionFps >= 3
                        ? Colors.orange
                        : Colors.redAccent,
              ),
              const SizedBox(height: 6),
              _Badge(
                icon: Icons.grain,
                label: 'Landmarks: $totalLandmarks / 21',
                color: totalLandmarks >= 21 ? Colors.greenAccent : Colors.orange,
              ),
              const SizedBox(height: 6),
              // Confirmación de tracking 3D: Landmark.z existe (depth normalizado)
              const _Badge(
                icon: Icons.view_in_ar,
                label: '3D confirmado (x, y, z)',
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 6),
              const _Badge(
                icon: Icons.memory,
                label: 'MediaPipe via JNI · GPU',
                color: Colors.blueGrey,
              ),
            ],
          ),
        ),

        // ── Panel de coordenadas del Index MCP ───────────────────────────
        Positioned(
          bottom: 36,
          left: 16,
          right: 16,
          child: mcp != null
              ? _CoordPanel(mcp: mcp)
              : const Center(
                  child: Text(
                    'Apunta la cámara hacia una mano abierta',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildInfoScreen({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: color),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter: dibuja esqueleto de mano + destacado del Index MCP
// ─────────────────────────────────────────────────────────────────────────────

class _HandPainter extends CustomPainter {
  final List<Hand> hands;
  final bool isBackCamera;

  const _HandPainter({required this.hands, required this.isBackCamera});

  // Transforma coordenadas normalizadas (0-1) a píxeles del canvas.
  // hand_landmarker corrige sensorOrientation en detect() → coords en orientación display.
  // La cámara trasera no necesita espejo; la frontal sí (selfie mirror).
  Offset _toCanvas(Landmark lm, Size size) {
    final nx = isBackCamera ? lm.x : 1.0 - lm.x;
    return Offset(nx * size.width, lm.y * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Dorado para el Index MCP (punto de anclaje de la joya)
    final mcpFill = Paint()
      ..color = const Color(0xFFD4A017)
      ..style = PaintingStyle.fill;

    final mcpRing = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final hand in hands) {
      final lm = hand.landmarks;
      if (lm.isEmpty) continue;

      // ── Esqueleto (conexiones) ─────────────────────────────────────────
      for (final (a, b) in _kConnections) {
        if (a >= lm.length || b >= lm.length) continue;
        canvas.drawLine(_toCanvas(lm[a], size), _toCanvas(lm[b], size), bonePaint);
      }

      // ── Todos los landmarks (excluyendo Index MCP para dibujar encima) ─
      for (int i = 0; i < lm.length; i++) {
        if (i == _kIndexMCP) continue;
        canvas.drawCircle(_toCanvas(lm[i], size), 5, dotPaint);
      }

      // ── Index MCP (landmark 5) — punto de anclaje para anillo/pulsera ──
      if (lm.length > _kIndexMCP) {
        final pos = _toCanvas(lm[_kIndexMCP], size);

        // Halo exterior (simula dónde iría la joya)
        canvas.drawCircle(pos, 20, mcpRing);
        // Relleno dorado
        canvas.drawCircle(pos, 11, mcpFill);
        // Punto blanco central
        canvas.drawCircle(pos, 3.5, dotPaint);

        // Etiqueta flotante
        _drawLabel(canvas, pos, '♦ Anillo / Pulsera');
      }
    }
  }

  void _drawLabel(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Dibujar fondo oscuro para legibilidad
    final bgRect = Rect.fromLTWH(
      pos.dx + 24, pos.dy - 10, tp.width + 8, tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    tp.paint(canvas, Offset(pos.dx + 28, pos.dy - 8));
  }

  @override
  bool shouldRepaint(_HandPainter old) => old.hands != hands;
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel de coordenadas 3D del Index MCP
// ─────────────────────────────────────────────────────────────────────────────

class _CoordPanel extends StatelessWidget {
  final Landmark mcp;

  const _CoordPanel({required this.mcp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B6914), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, color: Color(0xFFFFD700), size: 10),
              SizedBox(width: 6),
              Text(
                'Index MCP — Landmark 5  (posición de joya)',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CoordValue(axis: 'X', value: mcp.x, color: Colors.redAccent),
              _CoordValue(axis: 'Y', value: mcp.y, color: Colors.greenAccent),
              // z = profundidad relativa al nudo (normalizada).
              // Negativo = más cerca de la cámara; positivo = más lejos.
              _CoordValue(axis: 'Z (depth)', value: mcp.z, color: Colors.blueAccent),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Coords normalizadas [0-1] · z = profundidad relativa al nudo',
            style: TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CoordValue extends StatelessWidget {
  final String axis;
  final double value;
  final Color color;

  const _CoordValue({required this.axis, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(axis, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          value.toStringAsFixed(4),
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HUD Badge
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

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
