# 🚀 Inicio Rápido - Sistema de Validación DNI

## ⚡ 3 Pasos para Empezar

### 1️⃣ Migrar la Base de Datos (5 minutos)

```bash
# 1. Ir a Supabase Dashboard
https://supabase.com/dashboard

# 2. Abrir SQL Editor
# 3. Copiar y pegar el contenido de: migration_dni_accesos.sql
# 4. Ejecutar el script
# 5. Verificar que se crearon las columnas y tabla
```

**Verificación rápida:**
```sql
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'invitados' AND column_name IN ('dni', 'intentos_fallidos');
```

---

### 2️⃣ Agregar DNIs de Prueba (2 minutos)

```sql
-- Solo para desarrollo/testing
UPDATE invitados 
SET dni = LPAD(FLOOR(RANDOM() * 100000000)::TEXT, 8, '0')
WHERE dni IS NULL OR dni = '';
```

**Para producción**: Importar DNIs reales desde CSV o agregar manualmente.

---

### 3️⃣ Probar el Sistema (3 minutos)

```bash
# 1. Ejecutar la app
flutter run -d windows

# 2. Ir a la URL de check-in
http://localhost:XXXX/buscar?evento=TU_EVENTO_ID

# 3. Buscar un invitado
# 4. Ingresar DNI de prueba
# 5. Verificar ingreso exitoso
```

---

## 🎯 URLs Importantes

### Desarrollo
```
Check-in:  http://localhost:XXXX/buscar?evento=UUID
Operador:  http://localhost:XXXX/operador
Totem:     http://localhost:XXXX/totem_display?evento=UUID
```

### Producción
```
Check-in:  https://arguello-events.vercel.app/buscar?evento=UUID
Operador:  https://arguello-events.vercel.app/operador
Totem:     https://arguello-events.vercel.app/totem_display?evento=UUID
```

---

## 📋 Checklist Mínimo

- [ ] Script SQL ejecutado en Supabase
- [ ] DNIs agregados a invitados
- [ ] App ejecutándose sin errores
- [ ] Check-in probado con DNI correcto
- [ ] Check-in probado con DNI incorrecto
- [ ] Operador ve intentos fallidos

---

## 🐛 Problemas Comunes

### Error: "Column 'dni' does not exist"
**Solución**: Ejecutar el script SQL de migración

### Error: "null value in column 'dni'"
**Solución**: Agregar DNIs a todos los invitados antes de hacer el campo NOT NULL

### No aparece la pantalla de DNI
**Solución**: Verificar que `TotemCheckinScreen` esté importado en `main.dart`

---

## 📞 Ayuda Rápida

**Documentación completa**: Ver `IMPLEMENTACION_DNI.md`

**Resumen de cambios**: Ver `RESUMEN_CAMBIOS.md`

**Integración de rutas**: Ver `INTEGRACION_RUTAS.md`

---

## ✅ Todo Listo!

Si completaste los 3 pasos y el checklist, el sistema está funcionando.

**Siguiente paso**: Capacitar al equipo y probar en un evento real.

---

_¿Necesitas ayuda? Revisa los logs de Supabase y la consola de Flutter._
