# v5.0.0 — El sorteo solo le da mesa a lo que tiene algo pagado

**Fecha:** 2026-09-24
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Sin migración de base.** Ni local ni en Supabase. Cobros, cuentas, saldos y mora no cambian.

> **Referencia:** `CONTEXTO_v5.0.0` · `sorteo según lo pagado` · `sin mesa (sin pagar)`
> Anterior: [v4.9.9](CONTEXTO_v4.9.9_2026-09-24.md) (sorteo, caja, lista de la puerta).
> Plan aprobado: `C:\Users\lover\.claude\plans\con-ese-termino-me-lucky-panda.md`

**Estado:** **publicada el 24-sep**, con el OK del usuario:
- release: https://github.com/lovera2025/Antigravity/releases/tag/v5.0.0;
- tag `v5.0.0` sobre `36e8958`;
- `pubspec.yaml` 5.0.0+56 y el `.iss` coinciden.

Se instala primero en el operario (antes de abrir caja) y después en el jefe. Convive sin problema con la 4.9.9:
solo cambian el sorteo y la Planilla.

---

## Por qué

Hasta la 4.9.9, el sorteo le daba mesa a todo alumno activo y le sumaba las mesas extra cargadas, **pagadas o
no**. Al 24-sep eso significaba reservar:

| | Total | Sin nada pagado |
|---|---|---|
| Alumnos (cuota base) | 636 | **101** (100 anotados en marzo) |
| Alumnos con mesas extra | 83 | 15 (entre ellos Ortiz, con 2) |
| Alumnos con sillas extra | 17 | 4 |

El usuario quería que el sorteo no le reserve mesa a quien no pagó nada, y que lo cargado **siga cargado**: lo
sigue debiendo y lo puede pagar después.

## Cómo funciona

**Qué cuenta como pagado:**
- Se mira **por alumno** y con **sus pagos**, no con los campos del contrato. Es la misma clasificación del
  saldo: `grossHistoricoClaseCobro` por base, mesas y sillas.
- **Por alumno y no por mesa:** Ponce pagó cuotas de $20.000 que cubrían sus dos mesas a la vez. La regla de la
  cuenta (lo pagado va primero a la Mesa 1) deja la segunda en $0, y por mesa se la habría sacado.
- **Con los pagos y no con los campos:** ARGUELLO, TOMAS figura con $30.000 de base según el saldo del contrato y
  no tiene ningún pago cargado.
- Mora y recargo por transferencia no cuentan como pago de la base. Una entrega parcial de la primera cuota sí.

**En el diálogo del sorteo**, arriba de todo: "¿A quién se le sortea?", con dos opciones:
- "Solo a lo que tiene algo pagado", la preseleccionada;
- "A todo lo cargado", como antes.

Con la primera aparecen dos listas desplegables. Cada fila muestra el monto y una casilla "sortear igual" para
las excepciones (pagó y no se cargó, lo autoriza el jefe):
- "Sin nada pagado de la cuota base": no se les sortea mesa. Si además tienen mesas extra sin pagar y se los
  sortea igual, van solo con la base.
- "Con mesas extra sin nada pagado": solo la mesa base.

**Lo demás:**
- La capacidad sugerida se recalcula sola. Si la capacidad escrita era la sugerida, la sigue; si alguien la
  escribió a mano, solo sube cuando no alcanza.
- **Si pagan después**, "Sortear" de nuevo le da mesa al que no tenía y le suma la extra al que le faltaba, sin
  mover a nadie. El motor ya lo hacía.
- **Lo ya asignado no se toca nunca**, pague o no.
- **Las sillas extra no cambian el sorteo**, porque no ocupan número. En el diálogo y en la Planilla figuran
  "sin pagar".
- **Freno de lista vieja:** antes de guardar se relee también lo pagado (`firmaPagos`). Si entró un cobro con el
  diálogo abierto, se vuelve a mostrar con los datos nuevos.
- **"Sorteo listo"** suma cuántos quedaron sin mesa y cuántos solo con la base.

**Planilla de cursos:**
- "sin mesa (sin pagar)", "le falta 1 mesa (sin pagar)" y sillas "(sin pagar)";
- en el resumen del salón, "N sillas extra (+M sin pagar)" y "K alumno(s) sin nada pagado de la cuota base".

## Dónde está

- `lib/features/eventos/services/pago_para_sorteo.dart`:
  - `PagoAlumno` y `pagosPorAlumno`;
  - `candidatosPorPago`: quiénes quedarían afuera;
  - `exclusionSorteo`: con las casillas, que se guardan como **excepciones**, así un pago o un alumno nuevo con
    el diálogo abierto se acomoda solo;
  - `firmaPagos`.
- `SorteoMesasMotor.pedidos(..., sinMesa, soloBase)`. El algoritmo del motor no cambió.
- `SorteoMesasDialogResult`: `soloPagado`, `incluirBase` e `incluirExtras`.
- `sorteo_mesas_dialog.dart`: la pregunta, las listas, los montos por alumno y "sin pagar" en sillas.
- `detalle_evento_masivo_screen.dart`:
  - `_pagosPorContrato` trae los pagos de todos los alumnos;
  - `_sortearMesas`, `_ejecutarSorteo` y `_generarPlanillaCursos` los usan.
- `pdf_service.dart`: `construirPlanillaCursosPdf(..., pagos:)`.

## Verificación

- `test/pago_para_sorteo_test.dart`, con 21 tests:
  - clasificación de pagos;
  - Ortiz, Ponce, ARGUELLO y las bajas;
  - lo ya asignado;
  - las casillas;
  - la capacidad;
  - el segundo sorteo después de pagar.
- `app_update_checker_test.dart`: 5.0.0 se reconoce como más nueva que 4.9.9.
- `flutter test` completo: 626 pasan. `flutter analyze`: sin errores nuevos.
- Planilla de muestra (`tool/planilla_cursos_muestra_test.dart`), revisada: MEDINA sin mesa, NÚÑEZ solo base,
  sillas de LEDESMA "(sin pagar)", totales aparte.
- **Falta, en la app y sin sortear** (es producción): abrir el diálogo en un evento, ver las listas y los montos,
  alternar la pregunta, ver que cambie la capacidad y **cancelar**.
