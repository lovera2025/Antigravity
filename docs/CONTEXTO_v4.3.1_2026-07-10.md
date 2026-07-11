# Contexto — Junior Eventos v4.3.1 (10 de julio de 2026)

> **Referencia:** `CONTEXTO_v4.3.1` · `perdón solo ficha` · `PDF previo cobro`
> Si en un chat futuro decís *"leé el contexto del 10 de julio"* o *"qué salió en 4.3.1"*, apuntá a este archivo.

**Versión:** **4.3.1+22** (`pubspec.yaml`)  
**Instalador:** `Setup Junior Eventos v4.3.1.exe` (`installer/dist/`)

---

## Resumen

### 1. Perdón mora — solo saldo en ficha (tracked)
En Mi Empresa → Restaurar / perdonar mora:
- Check de ficha **independiente** del desglose calendario.
- Atajo **Solo ficha** (individual) y modo masivo **Solo ficha** + filtro.
- Limpiar tracked **sin** escribir `mora_exenta_hasta` → la mora de cuotas vencidas (ej. junio) sigue viva.

### 2. PDF resumen a abonar
Texto “Documento previo al cobro” sin guión tipográfico que salía como cuadradito en la fuente del PDF.

### 3. Smoke / dry-run
Dry-run cobro masivos (9 activos): **1662/1662** escenarios OK (readonly).

---

## Build / instalador

- `pubspec.yaml` → `version: 4.3.1+22`
- `installer/junior_eventos_setup.iss` (y hermanos) → `#define MyAppVersion "4.3.1"`

Salida: `installer\dist\Setup Junior Eventos v4.3.1.exe`

| Fecha | Versión | Notas |
|-------|---------|--------|
| 9-jul-2026 | **4.3.0** | Perdón mora admin + smoke 9 masivos |
| 10-jul-2026 | **4.3.1** | Perdón solo ficha + fix PDF previo cobro |
