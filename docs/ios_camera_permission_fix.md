# Fix: Permiso de cámara no funciona en iOS

## Síntomas

- Al pulsar "Visualizar en AR" no se abre la cámara.
- El botón "Grant Permission" no muestra el diálogo del sistema iOS.
- La cámara no aparece en Ajustes → Privacidad para esta app.

---

## Causa raíz — Podfile sin `PERMISSION_CAMERA=1`

`permission_handler` en iOS deshabilita **todos** los permisos a nivel de compilación por defecto. Para que el plugin incluya el código de cámara hay que activarlo con una macro de preprocesador en el `Podfile`.

Sin esta macro:
- `Permission.camera.request()` no muestra el diálogo del sistema.
- iOS nunca registra que la app solicitó la cámara.
- El permiso no aparece en Ajustes porque para iOS esta app nunca lo pidió.

---

## Fix 1 (crítico) — Agregar `PERMISSION_CAMERA=1` al Podfile

El archivo `ios/Podfile` debe contener el siguiente bloque `post_install`. Si el bloque ya existe, solo hay que agregar la línea de la macro dentro de él.

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        ## dart: PermissionGroup.camera
        'PERMISSION_CAMERA=1',
      ]
    end
  end
end
```

### Si el Podfile no existe

El Podfile no está commiteado en el repositorio. Para generarlo, desde la raíz del proyecto en el Mac:

```bash
flutter pub get
```

Esto crea `ios/Podfile` si no existe. Luego agregar el bloque `post_install` de arriba.

### Después de editar el Podfile

```bash
cd ios
pod install
cd ..
```

---

## Fix 2 (menor) — Re-verificar permisos al volver de Ajustes

**Archivo:** `lib/screens/ar_placement_screen.dart`, líneas 77-80.

**Problema actual:** cuando `openAppSettings()` abre Ajustes y el usuario regresa a la app, no se re-verifica si concedió el permiso.

**Cambio:**

```dart
// Antes
} else if (status.isPermanentlyDenied) {
    await openAppSettings();
}

// Después
} else if (status.isPermanentlyDenied) {
    await openAppSettings();
    await _checkPermission(); // re-verificar al volver
}
```

---

## Pasos para probar el fix (en orden)

1. En el Mac, abrir `ios/Podfile` y agregar el bloque `post_install` con `PERMISSION_CAMERA=1`.
2. Correr `pod install` desde la carpeta `ios/`.
3. **Desinstalar la app del iPhone** — obligatorio para limpiar el estado de permisos que quedó roto.
4. Recompilar e instalar desde Xcode o con `flutter run`.
5. Abrir la pantalla AR y pulsar "Grant Permission" — debe aparecer el diálogo del sistema iOS pidiendo acceso a la cámara.
6. Después de aceptar, la cámara debe abrirse y el feed AR debe iniciarse.

### Verificación adicional

Después de instalar con el fix, ir a **Ajustes → Privacidad y seguridad → Cámara** — la app debe aparecer listada ahí.

---

## Archivos involucrados

| Archivo | Estado | Problema |
|---|---|---|
| `ios/Podfile` | Faltante en el repo | No tiene `PERMISSION_CAMERA=1` |
| `lib/screens/ar_placement_screen.dart:77` | Presente | No re-verifica al volver de Settings |
| `ios/Runner/Info.plist:29` | Correcto | `NSCameraUsageDescription` sí está |
| `android/app/src/main/AndroidManifest.xml` | Correcto | Permisos Android sí están bien |
