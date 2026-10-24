# 🚀 Inicio Rápido - Recepción Interactiva

Guía express para tener el sistema funcionando en **5 minutos**.

---

## ✅ Checklist de Configuración

### 1️⃣ Configurar Base de Datos (2 min)

1. Abrir **Supabase Dashboard** → SQL Editor
2. Copiar y pegar todo el contenido de `database/invitados_setup.sql`
3. Presionar **RUN** (ejecutar)
4. ✅ Verificar que aparece: "Success. No rows returned"

### 2️⃣ Activar Realtime (1 min)

1. Ir a **Database** → **Replication**
2. Buscar la tabla `invitados`
3. Activar el **toggle verde** a la derecha
4. ✅ Debería decir "Enabled"

### 3️⃣ Crear Datos de Prueba (1 min)

**Opción A - SQL (Recomendado)**:

```sql
-- Obtener ID del primer evento
SELECT id FROM eventos LIMIT 1;

-- Copiar el ID y usarlo aquí (reemplazar <EVENTO_ID>)
SELECT generar_invitados_prueba('<EVENTO_ID>', 20);
```

**Opción B - Desde la App**:
1. Dashboard → Recepción
2. Seleccionar evento
3. Agregar invitados manualmente uno por uno

### 4️⃣ Probar el Sistema (1 min)

1. **Dashboard** → botón **RECEPCIÓN**
2. Seleccionar el evento con datos de prueba
3. Presionar **OPERADOR**
4. Marcar ingreso de 2-3 invitados
5. ✅ Deberías ver:
   - Confirmación "Ingreso registrado"
   - Estadísticas actualizándose
   - Invitados con ✅ verde

---

## 🎮 Uso Diario

### Para el Staff (Operador)

1. Abrir app → Dashboard → **RECEPCIÓN** → **OPERADOR**
2. Seleccionar el evento del día
3. Cuando llega un invitado:
   - Buscar su nombre en la barra de búsqueda
   - Tap en su tarjeta o botón "INGRESAR"
   - ✅ Listo

### Para la Pantalla (Tótem)

1. Abrir app en tablet/TV vertical
2. Dashboard → **RECEPCIÓN** → **TÓTEM**
3. Dejar la pantalla ahí
4. Cuando el operador marca un ingreso:
   - Aparece bienvenida automáticamente
   - Se muestra nombre y mesa
   - Desaparece sola después de 7 segundos

---

## 🔥 Tips Pro

### Probar Rápido con Testing Screen

```
Dashboard → RECEPCIÓN
↓
Seleccionar evento
↓
AGREGAR 5-10 invitados manualmente
↓
Presionar botón "login" verde para simular ingresos
↓
Abrir TÓTEM en otra ventana para ver animaciones
```

### Resetear Todo

```
Testing Screen → RESETEAR
(Marca todos como "pendiente" otra vez)
```

### Copiar ID de Evento

```
Testing Screen → COPIAR ID
(Útil para SQL queries)
```

---

## ❗ Problemas Comunes

| Problema | Solución Rápida |
|----------|----------------|
| "No hay eventos activos" | Crear un evento en la sección Eventos |
| Lista vacía | Generar datos de prueba (SQL o manual) |
| No funciona realtime | Activar en Supabase Dashboard → Database → Replication |
| Tótem no fullscreen | Reiniciar app, verificar orientación portrait |
| Error de conexión | Verificar internet, revisar credenciales Supabase |

---

## 📞 Ayuda

Si algo no funciona:

1. **Leer el README completo**: `RECEPCION_README.md` (tiene TODO)
2. **Ver logs**: `flutter logs` en terminal
3. **Verificar Supabase**: Dashboard → Logs

---

**¡Listo! Sistema funcionando en 5 minutos** ⚡

Para testing avanzado, personalización y troubleshooting, ver `RECEPCION_README.md`.
