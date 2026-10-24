# 🚪 Módulo de Recepción Interactiva - Argüello Events

Sistema completo de check-in digital con pantalla tótem y control de acceso en tiempo real.

---

## 📋 Tabla de Contenidos

1. [Características](#características)
2. [Arquitectura](#arquitectura)
3. [Instalación](#instalación)
4. [Configuración de Supabase](#configuración-de-supabase)
5. [Uso del Sistema](#uso-del-sistema)
6. [Testing](#testing)
7. [Solución de Problemas](#solución-de-problemas)

---

## ✨ Características

### 🎯 Funcionalidades Principales

- ✅ **Check-in en tiempo real** con Supabase Realtime
- 📺 **Pantalla Tótem fullscreen** con animaciones fluidas (60 FPS)
- 🎮 **Panel de Operador** para control de accesos
- 🧪 **Pantalla de Testing** integrada para pruebas rápidas
- 📊 **Estadísticas en vivo** (total, ingresados, pendientes)
- 🔍 **Búsqueda de invitados** por nombre
- 🔄 **Reconexión automática** con backoff exponencial
- 🎨 **UI Premium** con tema oscuro/claro

### 🎨 Componentes Visuales

- **Animaciones suaves** con `SlideTransition`, `FadeTransition`, `ScaleTransition`
- **Indicador de conexión** en tiempo real
- **Feedback visual** para todas las acciones
- **Diseño responsive** optimizado para tablets y displays verticales

---

## 🏗️ Arquitectura

### Estructura de Archivos

```
lib/
├── models/
│   └── invitado.dart                    # Modelo de datos tipado
├── services/
│   └── supabase_service.dart            # Servicio centralizado con manejo de errores
├── features/
│   ├── recepcion/
│   │   ├── operador_view.dart           # Vista de control de operador
│   │   ├── testing_screen.dart          # Pantalla de testing/admin
│   │   └── providers/
│   │       └── recepcion_provider.dart  # Providers Riverpod
│   └── totem/
│       └── totem_display.dart           # Pantalla tótem fullscreen
└── database/
    └── invitados_setup.sql              # Scripts SQL de configuración
```

### Stack Tecnológico

- **Frontend**: Flutter 3.11+ con Material Design 3
- **Backend**: Supabase (PostgreSQL + Realtime)
- **Estado**: Riverpod 3.x
- **Animaciones**: Custom AnimationControllers
- **Fuentes**: Google Fonts (Oswald + Outfit)

---

## 🚀 Instalación

### 1. Clonar el Proyecto

El módulo ya está integrado en `arguello_events`. No requiere instalación adicional de paquetes.

### 2. Verificar Dependencias

Asegúrate de tener estas dependencias en `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.12.0
  flutter_riverpod: ^3.3.1
  google_fonts: ^8.0.2
```

### 3. Ejecutar Flutter Pub Get

```bash
flutter pub get
```

---

## ⚙️ Configuración de Supabase

### Paso 1: Crear Tabla de Invitados

1. Ve al **SQL Editor** de tu proyecto Supabase
2. Copia y ejecuta el script completo de `database/invitados_setup.sql`
3. Verifica que la tabla se creó correctamente:

```sql
SELECT * FROM pg_tables WHERE tablename = 'invitados';
```

### Paso 2: Habilitar Realtime

#### Opción A: Dashboard (Recomendado)

1. Ve a **Database → Replication**
2. Busca la tabla `invitados`
3. Activa el toggle para habilitar Realtime
4. Guarda los cambios

#### Opción B: SQL

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE invitados;
```

### Paso 3: Configurar RLS (Row Level Security)

Las políticas ya están incluidas en el script SQL. Verifica que estén activas:

```sql
SELECT * FROM pg_policies WHERE tablename = 'invitados';
```

Deberías ver 4 políticas:
- SELECT para usuarios autenticados
- INSERT para usuarios autenticados
- UPDATE para usuarios autenticados
- DELETE para usuarios autenticados

### Paso 4: Generar Datos de Prueba

Ejecuta la función helper para crear invitados de prueba:

```sql
-- Reemplaza <EVENTO_ID> con un ID real de tu tabla eventos
SELECT generar_invitados_prueba('<EVENTO_ID>', 30);

-- O para el primer evento disponible:
SELECT generar_invitados_prueba((SELECT id FROM eventos LIMIT 1), 30);
```

---

## 🎮 Uso del Sistema

### Acceso desde la App

1. **Iniciar sesión** en Argüello Events
2. En el **Dashboard**, buscar el botón **"RECEPCIÓN"** en el Centro de Comando
3. Seleccionar el tipo de pantalla que necesitas

### Pantalla de Testing (Recomendada para Probar)

**Ruta**: Dashboard → Recepción

#### Funcionalidades

1. **Selector de Evento**: Elige el evento que quieres gestionar
2. **Estadísticas**: Visualiza total, ingresados y pendientes
3. **Acciones Rápidas**:
   - 🚪 **OPERADOR**: Abre el panel de control de acceso
   - 📺 **TÓTEM**: Abre la pantalla de bienvenida fullscreen
   - 📋 **COPIAR ID**: Copia el ID del evento al portapapeles
   - 🔄 **RESETEAR**: Marca todos los invitados como "pendiente"
4. **Agregar Invitado**: Crea invitados manualmente para testing
5. **Lista de Invitados**: 
   - ✅ Simula ingresos con un clic
   - 🗑️ Elimina invitados de prueba

### Panel de Operador

**Ruta**: Dashboard → Recepción → OPERADOR

#### Cómo Usar

1. **Seleccionar evento** del dropdown
2. Ver **estadísticas en tiempo real** (total, ingresados, pendientes)
3. **Buscar invitados** usando la barra de búsqueda
4. **Marcar ingreso** de dos formas:
   - Tap en la tarjeta del invitado
   - Presionar botón "INGRESAR"
5. Ver **feedback visual** inmediato con snackbar de confirmación

#### Características

- ✅ Lista en tiempo real (actualización automática vía Realtime)
- 🔍 Búsqueda instantánea por nombre
- 📊 Barra de progreso visual
- ♿ Estados visuales claros (pendiente/ingresado)
- 🔄 Botón de refresh manual
- ❌ Manejo robusto de errores con reintentos

### Pantalla Tótem

**Ruta**: Dashboard → Recepción → TÓTEM

#### Cómo Usar

1. **Conectar a un display vertical** (TV/monitor en orientación portrait)
2. La pantalla se pone en **modo fullscreen** automáticamente
3. Cuando un invitado **ingresa** (marcado por el operador):
   - Aparece animación de bienvenida
   - Muestra nombre del invitado en dorado
   - Indica número de mesa
   - Permanece 7 segundos
   - Se desvanece automáticamente
4. La pantalla queda en **reposo** hasta el siguiente ingreso

#### Características Técnicas

- 📺 **Fullscreen inmersivo** (oculta barra de estado)
- 🔒 **Orientación portrait bloqueada**
- 🎬 **Animaciones 60 FPS** con múltiples controladores
- 📡 **Conexión resiliente** con reconexión exponencial
- 🎨 **UI de alta calidad** con gradientes y sombras
- 🔄 **Cola de invitados** para múltiples ingresos simultáneos
- 🧹 **Limpieza automática** de memoria cada 5 minutos

---

## 🧪 Testing

### Flujo de Prueba Completo

#### 1. Preparación

```bash
# Ejecutar app en modo debug
flutter run
```

#### 2. Configurar Datos de Prueba

1. Ir a **Dashboard → Recepción**
2. Seleccionar un evento activo
3. Agregar 5-10 invitados manualmente:
   - Nombre: "Test Invitado 1"
   - Mesa: "1"
   - Presionar **AGREGAR**
4. Verificar que aparezcan en la lista

#### 3. Probar Panel de Operador

1. Presionar **OPERADOR**
2. Seleccionar el mismo evento
3. Buscar "Test" en la barra de búsqueda
4. Marcar ingreso de 2-3 invitados
5. Verificar que:
   - Se muestra confirmación en snackbar
   - El invitado se marca con ✅
   - Las estadísticas se actualizan
   - La barra de progreso avanza

#### 4. Probar Pantalla Tótem

1. **En una tablet o segundo display**:
   - Abrir Testing Screen
   - Presionar **TÓTEM**
   - Poner en modo portrait

2. **En la pantalla de operador**:
   - Marcar ingreso de un invitado

3. **Verificar en el tótem**:
   - Aparece animación de bienvenida
   - Se muestra nombre y mesa
   - Desaparece después de 7 segundos
   - La pantalla vuelve al reposo

#### 5. Probar Reconexión

1. **Desconectar internet** por 10 segundos
2. Verificar indicador "Reconectando..." en el tótem
3. **Reconectar internet**
4. Verificar que todo vuelve a funcionar automáticamente

#### 6. Probar con Múltiples Ingresos

1. Desde Testing Screen, simular ingresos rápidos de 5 invitados
2. Verificar que el tótem los muestra uno por uno en cola
3. Verificar que no se saltan ni duplican

### Testing Automatizado (SQL)

```sql
-- Ver estado actual
SELECT 
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE estado_ingreso = 'ingresado') as ingresados,
  COUNT(*) FILTER (WHERE estado_ingreso = 'pendiente') as pendientes
FROM invitados 
WHERE evento_id = '<EVENTO_ID>';

-- Simular ingreso masivo (testing de cola)
UPDATE invitados 
SET estado_ingreso = 'ingresado', updated_at = now()
WHERE evento_id = '<EVENTO_ID>' AND estado_ingreso = 'pendiente'
LIMIT 5;

-- Resetear todos los ingresos
UPDATE invitados 
SET estado_ingreso = 'pendiente', updated_at = null
WHERE evento_id = '<EVENTO_ID>';
```

---

## 🔧 Solución de Problemas

### ❌ La tabla no existe

**Problema**: Error "relation 'invitados' does not exist"

**Solución**:
1. Ejecutar el script SQL completo de `database/invitados_setup.sql`
2. Verificar con: `SELECT * FROM invitados LIMIT 1;`

---

### 📡 Realtime no funciona

**Problema**: Los cambios no se ven en tiempo real

**Solución**:
1. Verificar que Realtime está habilitado en Supabase Dashboard
2. Verificar políticas RLS:
```sql
SELECT * FROM pg_policies WHERE tablename = 'invitados';
```
3. Verificar conexión a internet
4. Verificar logs en la consola de Flutter

---

### 🎨 Animaciones con lag

**Problema**: Animaciones se ven lentas o con saltos

**Solución**:
1. **Ejecutar en Release mode** (las animaciones son más lentas en debug):
```bash
flutter run --release
```
2. Verificar que el dispositivo tenga suficiente RAM
3. Reducir número de widgets en pantalla si es necesario

---

### 🔌 Error de conexión persistente

**Problema**: "Reconectando..." permanente en el tótem

**Solución**:
1. Verificar URL y anon key de Supabase en `main.dart`
2. Verificar que el evento existe y es válido
3. Probar conexión manual:
```dart
final response = await Supabase.instance.client
  .from('invitados')
  .select()
  .limit(1);
print(response);
```
4. Revisar logs de error en `_onError()` del tótem

---

### 📱 Pantalla tótem no es fullscreen

**Problema**: Se ven barras de sistema en el tótem

**Solución**:
1. En Android: Verificar que no hay gestos activos
2. En iOS: Verificar configuración de "Guided Access"
3. El código ya incluye `SystemUiMode.immersiveSticky`
4. Si persiste, reiniciar la app

---

### 🔍 No aparecen invitados en la lista

**Problema**: Lista vacía en operador o testing

**Solución**:
1. Verificar que hay invitados en la BD:
```sql
SELECT COUNT(*) FROM invitados WHERE evento_id = '<EVENTO_ID>';
```
2. Verificar que el evento seleccionado es el correcto
3. Revisar permisos RLS
4. Verificar que el usuario está autenticado

---

## 📞 Soporte

Para problemas técnicos o consultas:

1. Revisar logs de Flutter: `flutter logs`
2. Revisar logs de Supabase: Dashboard → Logs
3. Verificar el estado de Realtime: Dashboard → Database → Replication
4. Consultar documentación de Supabase: https://supabase.com/docs

---

## 🎯 Próximos Pasos

### Funcionalidades Futuras

- [ ] Exportar lista de asistencia a PDF/CSV
- [ ] Notificaciones push al staff cuando ingresa VIP
- [ ] Dashboard de métricas avanzadas (gráficos, tiempo promedio, etc.)
- [ ] Modo offline con sincronización posterior
- [ ] Scanner QR para check-in automático
- [ ] Multi-idioma (ES/EN)
- [ ] Temas personalizados por evento

### Optimizaciones

- [ ] Cache local con Hive/SharedPreferences
- [ ] Paginación para eventos con +500 invitados
- [ ] Compresión de imágenes en tótem
- [ ] Service Worker para PWA
- [ ] Tests unitarios y de integración

---

## 📄 Licencia

© 2026 Argüello Events. Todos los derechos reservados.

---

**¡Listo para usar!** 🚀

Para cualquier duda, revisa esta documentación o consulta el código fuente con comentarios detallados.
