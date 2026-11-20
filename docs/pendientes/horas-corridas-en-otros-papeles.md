# "Emitido:" 3 horas antes en tres papeles, y la fecha de Finanzas de madrugada

**Estado:** pendiente: **preguntarle al usuario** si se arregla (son papeles de cobros y mora, ya publicados)
**Encontrado el:** 2026-11-20

## Qué pasa

Lo encontró la revisión de la caja de entregas (20-nov), buscando el mismo error que tenía su papel ("Impreso
el" 3 horas antes, arreglado en la 6.9.3). `ArTime.formatFechaHora` y `ArTime.formatFechaCorta` **ya pasan a la
hora de Argentina**; si reciben `ArTime.nowAr()` (que ya es la hora de Argentina, marcada UTC), le restan 3
horas otra vez.

- **"Emitido:" sale 3 horas antes** en los papeles que reciben `generadoEn: ArTime.nowAr()`:
  - `lib/features/eventos/detalle_evento_masivo_screen.dart:2883`;
  - `lib/features/mi_empresa/widgets/cobro_masivos_tab.dart:672` y `:706` (los listados de cobro).
  El que lo hace bien es `contratos_firmados_bulk_dialog.dart:172` (`ArTime.nowUtc()`).
- **La fecha de Finanzas** (`lib/features/mi_empresa/finanzas_view.dart:682` y `:1091`,
  `formatFechaCorta(ArTime.nowAr())`) dice **ayer** entre las 00:00 y las 03:00. Solo el rótulo: los totales no
  se tocaron.
- La revisión vio además que la hoja de cierre de sesión y el "· HOY" del cierre podrían fallar entre las 00:00 y
  las 02:59 (`state.dia` es la medianoche del día de Argentina en hora local). **Sin comprobar.**

## Por qué no se arregló

Son papeles de cobros, mora y Finanzas, ya publicados: la regla del usuario es que no se tocan sin pedirlo. El
arreglo es cambiar `ArTime.nowAr()` por `ArTime.nowUtc()` en esos lugares, cada uno con su test (sin pasar la
hora, comparar con la de Argentina de antes y de después, con `toUtc()`: esta PC está en UTC−3 y si no el test
queda al revés; el modelo es el test 8 de `test/entregas_sin_cargo_pdf_test.dart`).
