# Contexto — Junior Eventos v4.7.8 (16 de agosto de 2026)

> **Referencia:** `CONTEXTO_v4.7.8` · `perdón mora durable` · `botón perdonar en la grilla` · `mora_tracked_ajuste` · `migración v68`
> Si en un chat futuro decís *"leé el contexto de 4.7.8"*, *"por qué volvía la mora al sync"*,
> *"el botón de perdonar en cada alumno"* o *"mora_tracked_ajuste"*, apuntá a este archivo.

**Estado:** publicado. Setup + GitHub Release **v4.7.8**. Columna aplicada en Supabase.
**App:** `4.7.8+42` · SQLite **v68** · instalador `Setup Junior Eventos v4.7.8.exe`
**Release:** https://github.com/lovera2025/Antigravity/releases/tag/v4.7.8

Hay que instalar esta versión en **todas** las PCs que cobran. Una máquina vieja
sigue pisando `mora_pendiente_tracked` desde el historial y puede resucitar la ficha
en la nube.

---

## Qué se entregó

1. **El perdón de ficha ya no se revierte al sincronizar.**
2. **Botón por alumno** (solo modo jefe) en la grilla del masivo, misma lógica que
   Mi Empresa → Restaurar / perdonar mora. **No mueve Reg.**

Novedades del Release (aviso breve en la app):

- Perdón de mora desde cada alumno (solo modo jefe), sin ir a Mi Empresa
- La mora perdonada queda guardada: ya no vuelve al sincronizar
- Instalá esta versión en todas las PCs que cobran

---

## El bug que se arregló

Desde v4.6.2 el recovery post-pull (`MoraTrackedRecovery.reconciliarTodos`)
recalculaba `mora_pendiente_tracked` **solo desde el historial de pagos** y lo
pisaba. La exención de cuotas (`mora_exenta_hasta`) ya estaba protegida;
la ficha no.

Caso Bernel: historial ⇒ tracked $15.000. Perdonar ficha a $0. Al sync siguiente
volvían los $15.000. Igual al perdonar cuotas + ficha (exención ok, remanente no)
y al poner mora a mano.

El único ajuste que sobrevivía era mover la fecha de Reg. Eso ya no hace falta
para perdonar interés.

Detalle viejo: `docs/CONTEXTO_v4.6.2_2026-07-31.md` (sección de auditoría; ahora
resuelta acá).

---

## Cómo queda durable

Columna `mora_tracked_ajuste` (SQLite + Supabase):

```
tracked_final = max(0, objetivo_desde_historial + mora_tracked_ajuste)
ajuste        = deseado − objetivo_desde_historial
```

| Acción | Deseado | Efecto |
|--------|---------|--------|
| Perdonar ficha / todo | 0 | ajuste negativo; el replay no resucita |
| Poner mora a mano X | X | ajuste = X − historial |
| Nada de admin | historial | ajuste 0; el self-heal de tracked inflado sigue |

Un cobro **nuevo** de cuota sin mora suma remanente **solo de esa cuota**. El
ajuste viejo se queda: no borra mora futura.

El cobro normal **no toca** el ajuste. `payloadPerdonMora` sigue **sin** `created_at`.

Migración SQL nube:
`supabase/migrations/20260816000000_contratos_mora_tracked_ajuste.sql`
(corrida el 15-ago-2026).

El pull **preserva** un ajuste local si la nube viene en 0 / sin columna.

---

## UI

**Mi Empresa → Restaurar / perdonar mora:** mismo panel, ahora persiste el ajuste
(individual, masivo y “poner / restaurar” tracked).

**Grilla masivo, modo jefe:** ícono de limpieza al lado de pausa / recibo.
Visible en **todos** los alumnos. Si está al día: *“Este alumno está limpio.
No hay mora para perdonar.”* Con mora: cuotas (prefijo), remanente/ficha,
Todas / Solo ficha. PIN (`AdminGate` con `forceVerification: true`).

No está en el modal de cobro (esos checks son para **cobrar** mora, no perdonar)
ni en particulares.

La selección de cuotas del perdón sigue siendo **prefijo** (tildar C3 incluye C1 y C2).
No es cherry-pick.

---

## Archivos

- `lib/models/contrato_alumno.dart` — `moraTrackedAjuste`
- `lib/core/database/local_database.dart` — v68
- `lib/features/eventos/services/mora_tracked_recovery.dart` — `ajusteParaDeseado` / `trackedEfectivo` / `reconciliarTodos`
- `lib/features/eventos/repositories/contratos_repository.dart` — `aplicarPerdonMora` / `aplicarTrackedDeseado`
- `lib/features/eventos/widgets/perdonar_mora_alumno_dialog.dart`
- `lib/features/eventos/detalle_evento_masivo_screen.dart` — botón
- `lib/core/services/sync_engine.dart` — whitelist + preserve-on-pull
- `test/mora_pendiente_display_test.dart` — grupo `mora_tracked_ajuste (perdón durable)`

---

## Qué no es bug

Mora **nueva** de cuotas que vencen después del perdón puede aparecer. Eso es
calendario, no el remanente perdonado volviendo.

Perdones **solo ficha hechos antes de v4.7.8** no tienen ajuste: el recovery los
puede seguir recalculando desde el historial. Hay que reaplicarlos en esta versión.

---

## Documentos relacionados

- **`docs/CONTEXTO_MORA_OPERATIVA.md`** — modelo tracked/offset/exención (actualizado 16-ago).
- **`docs/CONTEXTO_v4.6.2_2026-07-31.md`** — auditoría que dejó este pendiente.
- **`docs/CONTEXTO_v4.3.0_2026-07-09.md`** — perdón por exención sin Reg.
- **`docs/CONTEXTO_v4.3.1_2026-07-10.md`** — perdón solo ficha (ahora durable).
