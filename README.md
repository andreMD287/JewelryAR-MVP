# Jewelry AR — MVP de Prueba Virtual de Joyería

Proyecto Flutter de validación tecnológica para una app de **prueba virtual de joyería con Realidad Aumentada**. El objetivo no es construir la app final, sino responder preguntas concretas sobre factibilidad técnica antes de comprometer recursos de desarrollo.

---

## ¿Qué se está construyendo?

Una app Flutter que actúa como laboratorio de pruebas para tres tecnologías de AR aplicadas a joyería:

| Pantalla | Tecnología | Pregunta que responde |
|----------|------------|----------------------|
| **Test Modelo 3D + AR** | `model_viewer_plus` + `ar_flutter_plugin_2` | ¿Se renderiza PBR correctamente? ¿ARCore/ARKit coloca objetos en superficies reales? |
| **Test AR Manos** | `hand_landmarker` (MediaPipe via JNI) | ¿Podemos obtener la posición 3D de la muñeca (WRIST — punto 0) en tiempo real para anclar pulseras? |
| **Test AR Rostro** | `google_mlkit_face_detection` | ¿Podemos detectar landmarks de orejas para anclar aretes? |

---

## Estructura del proyecto

```
jewelry_ar_mvp/
├── assets/
│   └── models/
│       └── test_jewelry.glb        # Modelo PBR de referencia (Damaged Helmet)
├── lib/
│   ├── main.dart                   # Navegación (named routes)
│   └── screens/
│       ├── home_screen.dart        # Menú principal con 3 botones
│       ├── model_viewer_screen.dart # Visor 3D PBR + botón "Ver en AR"
│       ├── ar_placement_screen.dart # ARCore/ARKit: colocar GLB en superficie
│       ├── ar_hand_screen.dart     # MediaPipe: tracking landmarks de mano
│       └── ar_face_screen.dart     # ML Kit: detección facial (stub)
├── android/
│   └── app/
│       ├── build.gradle.kts        # minSdk 24 (ARCore)
│       └── src/main/
│           ├── AndroidManifest.xml # CAMERA + INTERNET + ARCore
│           └── kotlin/.../MainActivity.kt  # FlutterFragmentActivity
└── ios/
    └── Runner/Info.plist           # NSCameraUsageDescription + ARKit
```

---

## Pantalla 1 — Modelo 3D con PBR (`ModelViewerScreen`)

### Qué se prueba
- Rendering de modelos GLB con materiales **PBR metallic-roughness** (glTF 2.0)
- Interacción táctil (rotación orbital, zoom)
- Transición a AR nativo del dispositivo (Scene Viewer en Android, Quick Look en iOS)

### Modelo de prueba
**Damaged Helmet** — modelo canónico de referencia PBR del grupo Khronos.  
Fuente: [KhronosGroup/glTF-Sample-Models](https://github.com/KhronosGroup/glTF-Sample-Models/tree/main/2.0/DamagedHelmet/glTF-Binary)  
Razón de elección: es el modelo de referencia estándar de la industria para validar que un renderer PBR implementa correctamente metalicidad, roughness, occlusion maps y normal maps.

### Tecnología
- **`model_viewer_plus` 1.10.0** — Widget Flutter que embebe el [Web Component `<model-viewer>`](https://modelviewer.dev/) de Google en un WebView. El rendering 3D ocurre en el WebView (no en el canvas de Flutter).
- El botón "Ver en AR" del AppBar/FAB navega a `ARPlacementScreen`.
- El botón nativo de AR dentro del visor (ícono pequeño) abre el AR nativo del SO.

### HUD de validación
| Indicador | Fuente |
|-----------|--------|
| Flutter UI FPS | `Ticker` sincronizado con VSync del Dart main isolate |
| PBR: Activo | Estático — todo GLB/glTF 2.0 usa PBR por especificación |
| Renderer | WebView / `<model-viewer>` (no el canvas de Flutter) |

---

## Pantalla 2 — Colocación AR en superficie (`ARPlacementScreen`)

### Qué se prueba
- Detección de superficies planas (ARCore en Android, ARKit en iOS)
- Colocación de un modelo GLB en coordenadas del mundo real
- Manejo de errores cuando el dispositivo no soporta AR

### Tecnología
- **`ar_flutter_plugin_2` 0.0.3** — Fork activo del plugin original `ar_flutter_plugin` (sin mantenimiento desde 2022). Usa ARCore (Android) y ARKit (iOS) mediante PlatformViews.
- Fuente del fork: [hlefe/ar_flutter_plugin_2](https://github.com/hlefe/ar_flutter_plugin_2)

### Flujo de estados
```
scanning ──(3s)──► ready ──(tap en plano)──► placed
                                               └──(reset)──► ready
    └──(error)──► error / unsupported
```

### Requisitos de configuración
- `MainActivity` extiende `FlutterFragmentActivity` (necesario para PlatformViews de AR en Android)
- `minSdkVersion 24` (requerido por ARCore)
- `<meta-data android:name="com.google.ar.core" android:value="required"/>` en AndroidManifest

---

## Pantalla 3 — Tracking de manos (`ARHandScreen`)

### Qué se prueba
**Pregunta central: ¿Podemos obtener la posición 3D de la muñeca (WRIST — punto 0 en la topología de MediaPipe Hands) en tiempo real desde Flutter para anclar pulseras?**

> **Scope de joyas:** pulseras ✅ · aretes ✅ · collares ✅ · anillos ❌ *(fuera de scope — requieren landmark 5 Index MCP, mayor complejidad de tracking en dedo)*

### Investigación de opciones (pub.dev, abril 2026)

| Opción | Paquete | Estado | Razón de decisión |
|--------|---------|--------|-------------------|
| **A** | `google_mediapipe` (oficial) | ❌ No existe | Google no ha publicado un paquete oficial de MediaPipe para Flutter mobile con hand tracking |
| **B** | `hand_landmarker` 2.2.0 | ✅ **Elegida** | MediaPipe real via JNI, acepta `CameraImage` directamente, da 3D coords, GPU delegate |
| **C** | `hand_detection` 2.0.9 | 🟡 Candidato iOS | TFLite + Mat, cross-platform, pero requiere conversión manual YUV→BGR con opencv_dart |
| **D** | `google_mlkit_pose_detection` | ⚠️ Fallback parcial | Detecta muñeca (landmark corporal) — suficiente para pulseras, insuficiente para aretes/collares |
| **E** | `hand_landmarker_mediapipe` | ❌ Descartada | v0.0.1, 83 descargas, GPL-3.0 — demasiado inmaduro |

### Tecnología elegida: `hand_landmarker` 2.2.0
- **Fuente:** [IoT-gamer/hand_landmarker](https://github.com/IoT-gamer/hand_landmarker)
- **Publicado en:** [pub.dev/packages/hand_landmarker](https://pub.dev/packages/hand_landmarker)
- **Arquitectura:** JNI Bridge → MediaPipe Hand Landmarker Task API (Android nativo)
- **Plataforma:** Android únicamente. iOS pendiente.

### API utilizada
```dart
// Inicialización
final plugin = HandLandmarkerPlugin.create(
  numHands: 1,
  minHandDetectionConfidence: 0.6,
  delegate: HandLandmarkerDelegate.gpu,
);

// Detección en cada frame de cámara
final List<Hand> hands = plugin.detect(cameraImage, sensorOrientation);

// Acceso al landmark 0 (WRIST = muñeca — ancla para pulseras)
final Landmark wrist = hands[0].landmarks[0];
print('x=${wrist.x}  y=${wrist.y}  z=${wrist.z}');
// → x=0.4821  y=0.7302  z=-0.0012
```

### Topología MediaPipe Hands (21 landmarks)
```
WRIST (0)   ← Punto 0 = ancla de pulsera  ◉
├── THUMB: CMC(1) → MCP(2) → IP(3) → TIP(4)
├── INDEX: MCP(5) → PIP(6) → DIP(7) → TIP(8)
├── MIDDLE: MCP(9) → PIP(10) → DIP(11) → TIP(12)
├── RING finger: MCP(13) → PIP(14) → DIP(15) → TIP(16)  [dedo anular — no joya]
└── PINKY: MCP(17) → PIP(18) → DIP(19) → TIP(20)
```

### Coordenadas
| Eje | Descripción | Rango |
|-----|-------------|-------|
| `x` | Posición horizontal en imagen | 0.0 (izquierda) → 1.0 (derecha) |
| `y` | Posición vertical en imagen | 0.0 (arriba) → 1.0 (abajo) |
| `z` | Profundidad relativa a la muñeca (wrist) | negativo = más cerca de cámara |

### Respuesta a la pregunta central
> **Sí en Android**: `hand_landmarker` expone `x`, `y`, `z` normalizados de la muñeca (WRIST — punto 0) en tiempo real con delegate GPU (~10 FPS en implementación actual).  
> **No en iOS aún**: la integración JNI de este plugin es Android-only. Para iOS, la alternativa es `hand_detection` (TFLite) o ARKit Hand Anchors via método nativo.

### Limitación de rendimiento conocida
`detect()` es sincrónico y bloquea el main isolate de Dart ~15-40 ms. La implementación actual throttlea a ≤10 FPS. **Para producción**, la solución es un isolate dedicado con su propia instancia del plugin, pasando los bytes del frame via `SendPort`.

---

## Pantalla 4 — AR Rostro (`ARFaceScreen`) — Stub

Pendiente de implementación. Usará `google_mlkit_face_detection` para detectar landmarks de orejas y anclar modelos de aretes. Ver issue correspondiente.

---

## Requisitos para ejecutar

### Android
```bash
# Requisitos mínimos
minSdkVersion: 24  # ARCore
targetSdkVersion: 35
flutter: >=3.x

# Instalar ARCore si no está presente (se instala automáticamente desde Play Store)
# El AndroidManifest declara: android:value="required"
```

### iOS
```bash
# ARKit requiere dispositivo físico (no simulador)
# Xcode 14+, iOS 14+
```

### Flutter
```bash
flutter pub get
flutter run --debug  # en dispositivo físico (AR no funciona en emulador)
```

---

## Dependencias y recursos

| Paquete | Versión | Propósito | Recurso |
|---------|---------|-----------|---------|
| `ar_flutter_plugin_2` | ^0.0.3 | AR en superficie (ARCore/ARKit) | [pub.dev](https://pub.dev/packages/ar_flutter_plugin_2) · [GitHub](https://github.com/hlefe/ar_flutter_plugin_2) |
| `model_viewer_plus` | ^1.10.0 | Visor 3D GLB con PBR | [pub.dev](https://pub.dev/packages/model_viewer_plus) · [model-viewer.dev](https://modelviewer.dev) |
| `google_mlkit_face_detection` | ^0.13.2 | Detección facial (aretes) | [pub.dev](https://pub.dev/packages/google_mlkit_face_detection) · [flutter-ml.dev](https://flutter-ml.dev) |
| `hand_landmarker` | ^2.2.0 | MediaPipe Hands via JNI (Android) | [pub.dev](https://pub.dev/packages/hand_landmarker) · [GitHub](https://github.com/IoT-gamer/hand_landmarker) |
| `camera` | ^0.11.1 | Feed de cámara en tiempo real | [pub.dev](https://pub.dev/packages/camera) |
| `permission_handler` | ^11.4.0 | Permisos en runtime | [pub.dev](https://pub.dev/packages/permission_handler) |
| `vector_math` | ^2.1.0 | Vector3/Vector4 para ARNode | [pub.dev](https://pub.dev/packages/vector_math) |

### Recursos de referencia
- [MediaPipe Hand Landmarker (Google)](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker) — documentación oficial de la tarea MediaPipe que `hand_landmarker` expone en Flutter
- [glTF 2.0 PBR Specification (Khronos)](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials) — especificación de materiales PBR metallic-roughness
- [ARCore Supported Devices (Google)](https://developers.google.com/ar/devices) — lista de dispositivos Android con soporte ARCore
- [ARKit Overview (Apple)](https://developer.apple.com/augmented-reality/arkit/) — documentación de ARKit para iOS
- [model-viewer Web Component](https://modelviewer.dev/docs/) — documentación del componente HTML que usa `model_viewer_plus`
- [glTF Sample Models — Damaged Helmet](https://github.com/KhronosGroup/glTF-Sample-Models/tree/main/2.0/DamagedHelmet) — modelo PBR de referencia usado en las pruebas

---

## Decisiones de arquitectura

### ¿Por qué GLB y no USDZ/OBJ?
GLB (binary glTF 2.0) es el único formato que funciona en ARCore (Android), ARKit vía Quick Look (iOS) y `model_viewer_plus` (WebView). USDZ es exclusivo de Apple; OBJ no tiene soporte PBR nativo.

### ¿Por qué `hand_landmarker` y no implementar MediaPipe directamente?
Implementar MediaPipe via FFI desde cero requiere compilar las librerías nativas de MediaPipe para cada arquitectura (arm64, x86_64) y escribir los bindings JNI/Swift manualmente — semanas de trabajo de integración nativa. `hand_landmarker` ya resuelve esto con 371 descargas comprobadas.

### ¿Por qué `ar_flutter_plugin_2` y no SceneKit/RealityKit directamente?
Los SDKs nativos de AR (ARCore/ARKit) requieren código nativo por plataforma. `ar_flutter_plugin_2` provee una API unificada en Dart que funciona en ambas plataformas, reduciendo el scope del MVP.

### ¿Por qué `FlutterFragmentActivity`?
`ar_flutter_plugin_2` usa PlatformViews de Android que requieren que la Activity del host extienda `FragmentActivity`. `FlutterActivity` (la clase por defecto) no extiende `FragmentActivity`, causando errores en runtime al crear el `ARView`.

---

## Estado del proyecto

| Feature | Estado |
|---------|--------|
| Navegación base (3 pantallas) | ✅ Implementado |
| Visor 3D con PBR (model_viewer_plus) | ✅ Implementado |
| Colocación AR en superficie (ar_flutter_plugin_2) | ✅ Implementado |
| Tracking de manos (hand_landmarker) | ✅ Implementado — Android |
| Tracking de manos — iOS | 🔲 Pendiente (hand_detection TFLite) |
| Detección facial para aretes | 🔲 Pendiente (google_mlkit_face_detection) |
| Modelo GLB de joya real (no casco) | 🔲 Pendiente |
| Optimización FPS (isolate dedicado) | 🔲 Pendiente |
