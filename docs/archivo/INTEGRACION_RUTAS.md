# 🛣️ Integración de Rutas - Sistema de Check-in con DNI

## 📍 Nueva Ruta de Check-in

### Ruta Pública: `/buscar/:eventoId`

Esta ruta ya existe, pero ahora usa la nueva pantalla con validación DNI.

```dart
// En main.dart, actualizar la ruta existente:

if (isBuscar) {
  final eventoId = Uri.base.queryParameters['evento'] ?? '';
  debugPrint('V4 >>> LANZANDO BUSCAR CHECK-IN: eventoId=$eventoId');
  runApp(ProviderScope(child: BuscarApp(eventoId: eventoId)));
}
```

### Actualizar BuscarApp para usar TotemCheckinScreen

```dart
// En main.dart, reemplazar BuscarInvitadoScreen con TotemCheckinScreen

class BuscarApp extends ConsumerWidget {
  final String eventoId;
  const BuscarApp({required this.eventoId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Check-in — Argüello Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: TotemCheckinScreen(eventoId: eventoId), // ← Cambiar aquí
    );
  }
}
```

### Importar el nuevo widget

```dart
// En main.dart, agregar import:

import 'features/totem/totem_checkin_screen.dart';
```

---

## 🔗 URLs de Acceso

### Para Invitados (Check-in con DNI)

```
https://arguello-events.vercel.app/buscar?evento=UUID_DEL_EVENTO
```

**Ejemplo**:
```
https://arguello-events.vercel.app/buscar?evento=123e4567-e89b-12d3-a456-426614174000
```

### Para Totem (Pantalla completa con QR + Lista)

```
https://arguello-events.vercel.app/totem_display?evento=UUID_DEL_EVENTO
```

O usando la ruta interna:
```dart
Navigator.pushNamed(
  context,
  '/totem_display',
  arguments: {'eventoId': eventoId},
);
```

### Para Operador

```
https://arguello-events.vercel.app/operador
```

O usando la ruta interna:
```dart
Navigator.pushNamed(context, '/operador');
```

---

## 🎯 Flujo Completo de Navegación

### Opción 1: Recepción Unificada

```dart
// Pantalla con operador + totem lado a lado
Navigator.pushNamed(context, '/recepcion_unified');
```

Desde aquí el operador puede:
- Ver lista de invitados
- Marcar ingresos manualmente
- Resetear intentos fallidos
- Ver estadísticas en tiempo real

Y el totem muestra:
- QR para escanear
- Lista de invitados que ya llegaron
- Animaciones de bienvenida

### Opción 2: Totem Separado

```dart
// Solo totem en pantalla vertical fullscreen
Navigator.pushNamed(
  context,
  '/totem_display',
  arguments: {'eventoId': eventoId},
);
```

Ideal para:
- Múltiples pantallas en el evento
- Tablets/iPads en modo vertical
- Pantallas táctiles en la entrada

### Opción 3: Check-in Público (con DNI)

```dart
// Pantalla de búsqueda + validación DNI
// Accesible vía QR o URL directa
```

URL para generar QR:
```
https://arguello-events.vercel.app/buscar?evento=UUID_DEL_EVENTO
```

---

## 🔧 Configuración de Rutas en main.dart

### Actualizar onGenerateRoute

```dart
onGenerateRoute: (settings) {
  // Ruta de totem display
  if (settings.name == '/totem_display') {
    final args = settings.arguments as Map<String, dynamic>?;
    final eventoId = args?['eventoId'] as String? ?? '';
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => TotemDisplay(
        eventoId: eventoId,
        svc: SupabaseService(),
      ),
    );
  }
  
  // Ruta de operador
  if (settings.name == '/operador') {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const OperadorView(),
    );
  }
  
  // Ruta de recepción unificada
  if (settings.name == '/recepcion_unified') {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const RecepcionUnifiedScreen(),
    );
  }
  
  // Ruta de check-in público (nueva)
  if (settings.name == '/checkin') {
    final args = settings.arguments as Map<String, dynamic>?;
    final eventoId = args?['eventoId'] as String? ?? '';
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => TotemCheckinScreen(eventoId: eventoId),
    );
  }

  // Por defecto: SplashScreen
  return MaterialPageRoute(
    settings: settings,
    builder: (_) => const SplashScreen(),
  );
},
```

---

## 📱 Generación de QR para Check-in

### Opción 1: QR con URL directa

```dart
import 'package:qr_flutter/qr_flutter.dart';

QrImageView(
  data: 'https://arguello-events.vercel.app/buscar?evento=$eventoId',
  version: QrVersions.auto,
  size: 200,
)
```

### Opción 2: QR con deep link (futuro)

```dart
QrImageView(
  data: 'arguelloevents://checkin/$eventoId',
  version: QrVersions.auto,
  size: 200,
)
```

---

## 🎨 Personalización de Rutas

### Agregar parámetros adicionales

```dart
// URL con parámetros extra
https://arguello-events.vercel.app/buscar?evento=UUID&mode=kiosk&lang=es

// Leer parámetros
final mode = Uri.base.queryParameters['mode'] ?? 'normal';
final lang = Uri.base.queryParameters['lang'] ?? 'es';
```

### Modo Kiosk (sin navegación)

```dart
if (mode == 'kiosk') {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
```

---

## 🔐 Seguridad de Rutas

### Rutas Públicas (sin autenticación)

```dart
'/buscar'          // Check-in con DNI
'/lista'           // Ver lista de invitados
'/cotizar'         // Catálogo público
```

### Rutas Protegidas (requieren login)

```dart
'/operador'        // Panel de operador
'/recepcion_unified' // Recepción unificada
'/admin'           // Panel de administración (futuro)
```

### Middleware de autenticación

```dart
// Verificar sesión antes de acceder a rutas protegidas
final session = Supabase.instance.client.auth.currentSession;

if (session == null && settings.name == '/operador') {
  return MaterialPageRoute(
    builder: (_) => const LoginScreen(),
  );
}
```

---

## 📊 Analytics de Rutas (Opcional)

### Registrar navegación

```dart
void _logNavigation(String route, String eventoId) {
  // Firebase Analytics, Mixpanel, etc.
  analytics.logEvent(
    name: 'screen_view',
    parameters: {
      'screen_name': route,
      'evento_id': eventoId,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}
```

---

## 🧪 Testing de Rutas

### Test de navegación

```dart
testWidgets('Navegar a check-in screen', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // Navegar a check-in
  await tester.tap(find.text('Check-in'));
  await tester.pumpAndSettle();
  
  // Verificar que estamos en la pantalla correcta
  expect(find.byType(TotemCheckinScreen), findsOneWidget);
});
```

---

## 🚀 Deploy y URLs de Producción

### Vercel

```bash
# Deploy automático desde GitHub
git push origin main

# URLs generadas:
# - https://arguello-events.vercel.app
# - https://arguello-events-git-main-youruser.vercel.app
# - https://arguello-events-pr123.vercel.app (preview)
```

### Variables de entorno

```env
# .env.production
SUPABASE_URL=https://bucnrydgojyzntgesxqb.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
WEB_BASE_URL=https://arguello-events.vercel.app
```

---

## 📝 Checklist de Integración

- [ ] Importar `TotemCheckinScreen` en `main.dart`
- [ ] Actualizar `BuscarApp` para usar nueva pantalla
- [ ] Agregar ruta `/checkin` en `onGenerateRoute`
- [ ] Generar QR con URL de check-in
- [ ] Probar navegación desde QR
- [ ] Verificar parámetros de URL
- [ ] Configurar modo kiosk (opcional)
- [ ] Agregar analytics (opcional)
- [ ] Testing de navegación
- [ ] Deploy a producción

---

## 🎯 Ejemplo Completo

```dart
// main.dart - Sección de rutas

import 'features/totem/totem_checkin_screen.dart';

// ...

class BuscarApp extends ConsumerWidget {
  final String eventoId;
  const BuscarApp({required this.eventoId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Check-in — Argüello Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: TotemCheckinScreen(eventoId: eventoId),
    );
  }
}

// ...

onGenerateRoute: (settings) {
  if (settings.name == '/checkin') {
    final args = settings.arguments as Map<String, dynamic>?;
    final eventoId = args?['eventoId'] as String? ?? '';
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => TotemCheckinScreen(eventoId: eventoId),
    );
  }
  
  // ... otras rutas
},
```

---

**¡Listo para integrar!** 🎉

Siguiente paso: Actualizar `main.dart` con los cambios sugeridos.
