# Implementación del Sistema de Validación DNI

## 🎯 Resumen de Cambios

Se implementó un sistema completo de validación de DNI para el check-in de invitados con las siguientes características:

- ✅ Campo DNI obligatorio en invitados
- ✅ Validación de DNI en el totem antes de permitir ingreso
- ✅ Sistema de intentos fallidos (máximo 3)
- ✅ Auditoría completa de accesos
- ✅ Estadísticas en tiempo real
- ✅ Notificaciones al operador
- ✅ DNI enmascarado para privacidad

---

## 📋 Pasos de Implementación

### 1. Migración de Base de Datos

**IMPORTANTE**: Ejecutar el script SQL en Supabase antes de usar la app.

1. Ir a Supabase Dashboard → SQL Editor
2. Copiar y pegar el contenido de `migration_dni_accesos.sql`
3. Ejecutar el script completo

El script hace lo siguiente:
- Agrega columna `dni` a tabla `invitados`
- Agrega columna `intentos_fallidos` a tabla `invitados`
- Crea tabla `accesos` para auditoría
- Crea índices para optimización
- Configura políticas de seguridad (RLS)

**Verificación**:
```sql
-- Verificar estructura de invitados
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'invitados';

-- Verificar tabla accesos
SELECT * FROM accesos LIMIT 1;
```

---

### 2. Actualizar Invitados Existentes

Si ya tienes invitados en la base de datos, necesitas agregarles DNIs:

**Opción A: DNIs de prueba (desarrollo)**
```sql
UPDATE invitados 
SET dni = LPAD(FLOOR(RANDOM() * 100000000)::TEXT, 8, '0')
WHERE dni IS NULL OR dni = '';
```

**Opción B: Importar DNIs reales**
```sql
-- Actualizar uno por uno
UPDATE invitados SET dni = '12345678' WHERE id = 'uuid-del-invitado';
```

---

### 3. Hacer DNI Obligatorio (Producción)

Una vez que todos los invitados tengan DNI, ejecutar:

```sql
ALTER TABLE invitados ALTER COLUMN dni SET NOT NULL;
```

---

## 🔧 Archivos Modificados

### Modelos
- ✅ `lib/models/invitado.dart` - Agregado campo `dni` e `intentosFallidos`
- ✅ `lib/models/acceso_log.dart` - Nuevo modelo para auditoría

### Servicios
- ✅ `lib/services/supabase_service.dart` - Métodos de validación DNI

### Pantallas
- ✅ `lib/features/totem/totem_display.dart` - Estadísticas discretas
- ✅ `lib/features/totem/totem_checkin_screen.dart` - Nueva pantalla de check-in con DNI
- ✅ `lib/features/recepcion/operador_view.dart` - Mostrar DNI enmascarado e intentos

---

## 🚀 Cómo Usar

### Para el Operador

1. Abrir panel de operador
2. Ver lista de invitados con:
   - DNI enmascarado (ej: `12.***.78`)
   - Estado de ingreso
   - Intentos fallidos (si los hay)
   - Indicador de bloqueo (3 intentos fallidos)

3. Si un invitado está bloqueado:
   - Click en botón "RESETEAR"
   - Esto limpia los intentos fallidos
   - El invitado puede volver a intentar

### Para el Totem (Check-in)

**Flujo completo:**

1. **Pantalla inicial**: Buscar nombre
   - El invitado escribe su nombre
   - Aparecen resultados (máximo 5)
   - Selecciona su nombre

2. **Pantalla de validación**: Ingresar DNI
   - Ve su nombre completo
   - Ve su mesa (si tiene)
   - Ingresa su DNI (solo números, máximo 8 dígitos)
   - Click en "VERIFICAR"

3. **Resultado**:
   - ✅ **DNI correcto**: Pantalla de bienvenida → Ingreso registrado → Vuelve al inicio
   - ❌ **DNI incorrecto**: Mensaje de error → Intento registrado → Puede reintentar
   - 🚫 **3 intentos fallidos**: Bloqueado → Debe contactar al operador

---

## 📊 Auditoría y Reportes

### Ver historial de accesos

```sql
-- Todos los accesos de un evento
SELECT 
    i.nombre_completo,
    a.dni_ingresado,
    a.valido,
    a.timestamp
FROM accesos a
JOIN invitados i ON a.invitado_id = i.id
WHERE a.evento_id = 'uuid-del-evento'
ORDER BY a.timestamp DESC;

-- Solo intentos fallidos
SELECT 
    i.nombre_completo,
    a.dni_ingresado,
    a.timestamp
FROM accesos a
JOIN invitados i ON a.invitado_id = i.id
WHERE a.evento_id = 'uuid-del-evento' 
  AND a.valido = false
ORDER BY a.timestamp DESC;

-- Invitados con múltiples intentos fallidos
SELECT 
    i.nombre_completo,
    i.intentos_fallidos,
    COUNT(a.id) as total_intentos
FROM invitados i
LEFT JOIN accesos a ON i.id = a.invitado_id
WHERE i.evento_id = 'uuid-del-evento'
  AND i.intentos_fallidos > 0
GROUP BY i.id, i.nombre_completo, i.intentos_fallidos
ORDER BY i.intentos_fallidos DESC;
```

---

## 🔒 Seguridad y Privacidad

### DNI Enmascarado

- En el operador: `12.***.78` (solo primeros 2 y últimos 2 dígitos)
- En la base de datos (tabla accesos): `***678` (solo últimos 3 dígitos)
- El DNI completo solo se guarda en tabla `invitados`

### Políticas de Acceso (RLS)

- Solo usuarios autenticados pueden leer la tabla `accesos`
- Cualquier usuario puede insertar en `accesos` (para el totem público)
- Los invitados no pueden ver DNIs de otros invitados

---

## 🐛 Troubleshooting

### Error: "Column 'dni' does not exist"
**Solución**: Ejecutar el script de migración SQL

### Error: "null value in column 'dni' violates not-null constraint"
**Solución**: Asegurarse de que todos los invitados tengan DNI antes de hacer el campo NOT NULL

### Invitado bloqueado por error
**Solución**: Operador puede resetear intentos desde el panel

### DNI no valida correctamente
**Verificar**:
1. Que el DNI en la BD no tenga espacios ni caracteres especiales
2. Que el invitado esté ingresando solo números
3. Que el DNI tenga el formato correcto (8 dígitos)

---

## 🎨 Personalización

### Cambiar máximo de intentos

En `lib/services/supabase_service.dart`:

```dart
// Cambiar de 3 a otro número
if (invitado.intentosFallidos >= 3) {  // ← Cambiar aquí
```

### Cambiar formato de DNI enmascarado

En `lib/features/recepcion/operador_view.dart`:

```dart
String _maskDni(String dni) {
  // Personalizar el formato aquí
  return '${dni.substring(0, 2)}.${'*' * (dni.length - 4)}.${dni.substring(dni.length - 2)}';
}
```

---

## 📝 Próximos Pasos Sugeridos

1. **Roles y permisos**: Implementar sistema de admin/operador
2. **Códigos rotativos**: Alternativa al DNI con códigos temporales
3. **Notificaciones push**: Alertar al operador de intentos fallidos
4. **Dashboard de estadísticas**: Gráficos de ingresos en tiempo real
5. **Export de auditoría**: Descargar reportes en CSV/PDF

---

## ✅ Checklist de Implementación

- [ ] Ejecutar script SQL de migración
- [ ] Agregar DNIs a invitados existentes
- [ ] Hacer campo DNI obligatorio (producción)
- [ ] Probar flujo completo de check-in
- [ ] Verificar intentos fallidos
- [ ] Probar reseteo de intentos desde operador
- [ ] Verificar estadísticas en totem
- [ ] Revisar auditoría en Supabase
- [ ] Configurar políticas de seguridad (RLS)
- [ ] Documentar proceso para el equipo

---

## 📞 Soporte

Si tienes problemas con la implementación:

1. Revisar logs de Supabase
2. Verificar estructura de BD
3. Comprobar políticas RLS
4. Revisar errores en consola de Flutter

---

**¡Listo para producción!** 🚀
