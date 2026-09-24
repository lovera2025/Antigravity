# Contexto — v4.9.9 EN CURSO (23 de septiembre de 2026)

> **Referencia:** `CONTEXTO_v4.9.9-wip` · `sorteo de mesas` · `sillas extra` · `caja: anular varios` · `Disk IO`
> **Para retomar en un chat nuevo:** "leé `docs/CONTEXTO_v4.9.9-wip_2026-09-23.md` y seguimos el plan".
> Plan completo aprobado (más largo, con todo el razonamiento):
> `C:\Users\lover\.claude\plans\necesito-verifcar-que-todo-prancy-meerkat.md`

**Estado:**
- La parte del **sorteo de mesas** ya está hecha, probada, con commit y push (`9ce58a0`).
- Falta, en orden:
  1. corregir los datos de 7 alumnos;
  2. la parte de caja;
  3. el tótem;
  4. armar la versión.
- **No hay versión nueva todavía:** el `pubspec.yaml` sigue en 4.9.8+54. En las dos PCs está instalada la 4.9.8.

---

## Reglas acordadas con el usuario (no romper)

1. **Nada se publica hasta que el usuario lo diga.**
   - Se puede hacer commit y push a `feature/v4.6-cierre-por-sesiones`, y builds de prueba.
   - No se puede, sin su aviso: publicar el release, pasar el instalador, desplegar la web ni instalar en las PCs.
2. **Una sola versión, la 4.9.9, con todo junto:** sorteo, caja y tótem. Así no hay dos instalaciones ni dos
   números de versión. Tiene que estar instalada en las dos PCs **antes de noviembre**, que es cuando se sortea.
3. **La app sigue funcionando como hoy, pero mejor.** Cobros, mora, saldos y recibos no se tocan.
4. **No se borra ningún dato.** Las correcciones se hacen modificando, **solo en los alumnos señalados** y con los
   pagos intactos. La única excepción es el pago de ESMAY que se parte (aprobado).
5. **Prevenir, no manejar.** El sorteo está "hecho para no fallar"; la validación final es solo una red de
   seguridad.
6. **Las correcciones de datos se aplican después de las 20 hs y cuando el usuario avise**, porque durante el día
   se cobra. El esquema es siempre el mismo:
   - foto de solo lectura;
   - script en DRY-RUN;
   - antes → después a la vista del usuario;
   - su OK en el chat;
   - copia de `data.db`;
   - APPLY con la app cerrada;
   - abrir la app y tocar "Subir pendientes";
   - comparar contra la foto, en local y en Supabase.

## Reglas del negocio

- **Mesas:** a cada alumno le toca 1 mesa base + 1 por cada mesa extra que figure en su cuenta, **esté pagada o
  no**. Van juntas, salvo que se marque separarlas.
- **Sillas:** cada mesa (base o extra) trae **8 sillas** y admite **como máximo 2 sillas extra**. El máximo de un
  alumno es `2 × (1 + mesas extra)`.
- **Precios:** silla extra **$8.000**; mesa extra **$70.000** c/u.
- **Qué sillas cuentan:** solo las que figuran en la cuenta, es decir, con precio. Con precio $0 no aparecen, igual
  que en el estado de cuenta.
- **Personas por mesa:** alumno + acompañantes, contra `8 × mesas + sillas extra` lugares.
- **Fechas:**
  - el sorteo se hace en **noviembre**, día a definir;
  - las fiestas son en **diciembre**, cada institución en su propia fecha, a definir;
  - las fechas cargadas en el sistema son de relleno.
- **Cada institución se sortea sola** y numera desde 1. Las mesas del salón se reutilizan de una fiesta a otra.

---

## HECHO — commit `9ce58a0` (subido a origin)

**Motor nuevo** — `lib/features/eventos/services/sorteo_mesas_motor.dart`
- Números únicos por construcción.
- `capacidadMinima` y `esFactible`: el mismo recorrido con el que arranca `sortear`, así que si da factible, el
  sorteo termina.
- Ubicación constructiva de las separadas: nunca quedan pegadas.
- Completa a quien compró una mesa extra después, pegada a su bloque.
- Respeta los números ocupados y los de bajas.
- `validar` como red final y `firma` para detectar si la lista cambió.

**Salón** — `lib/features/eventos/services/salon_mesas.dart`
- Textos de la columna MESA ("12-14 (2 extra)", "12-13 + 40 (separada)"), aviso de mesas ("le falta 1 mesa").
- Sillas repartidas de a 2 por mesa, `OcupacionAsientos` ("3 de 8 lugares"), `PreciosHabituales` (la moda del
  evento) y los avisos de "Revisar antes de sortear".

**Respaldo del deshacer** — `lib/features/eventos/services/respaldo_sorteo.dart`
- Copia JSON en `Documentos/Junior Eventos/respaldos_sorteo/<eventoId>.json`.
- `planRestauracion` devuelve números sin pisar nada.

**Diálogo del sorteo** — `widgets/sorteo_mesas_dialog.dart`
- Demanda, listas "Con mesas extra" (con separar) y "Con sillas extra".
- Aviso ámbar con la casilla "Ya revisé".
- SORTEAR se deshabilita si la capacidad no alcanza.

**Pantalla del evento** — `detalle_evento_masivo_screen.dart`
- `_sortearMesas`:
  - chequea si otra PC tiene mesas sin bajar (`mesasDeOtraPcSinBajar`);
  - relee la lista antes de sortear;
  - ya **no llama a `reconciliarMesasExtrasEvento`**: el sorteo solo escribe `numero_mesa`.
- `_deshacerSorteoMesas` limpia a todos, también bajas, pide casilla y guarda la copia antes de borrar.
- `_restaurarSorteoAnterior`, con su entrada en el menú ⋮ cuando hay copia.
- Celda MESA nueva: `widgets/celda_mesa_alumno.dart`.

**Repositorio** — `contratos_repository.dart`
- `asignarNumerosMesa`: una sola transacción, solo toca `numero_mesa`.
- `mesasDeOtraPcSinBajar`: solo lectura; ignora los alumnos con cambios propios pendientes.

**Planilla de cursos** — `pdf_service.dart`
- `construirPlanillaCursosPdf`: primera hoja "Resumen del salón" (totales y la lista de quienes tienen mesas o
  sillas extra, con reparto por mesa y personas).
- En cada curso: MESA con formato y "(!)", columna "SILLAS EXTRA" y línea de control.
- Muestra sin abrir la app: `tool/planilla_cursos_muestra_test.dart`.

**Editar alumno** — `modal_alumno_premium.dart`
- `datosEdicionAlumno`: el número de mesa se guarda **solo si se cambió**, así otra PC no pisa el sorteo.
- No deja pasar de 2 sillas extra por mesa.
- Avisa precios distintos al habitual o en $0, y familias que no entran en sus lugares.

**`numerosMesaDesdeTexto`** lee "40-42", "40 al 42", "40 y 41" e ignora lo que está entre paréntesis.

**Tests**
- `test/sorteo_mesas_motor_test.dart`:
  - estrés con los 9 tamaños reales;
  - 2000 salones difíciles, con verificación de que más capacidad siempre entra.
- `test/respaldo_y_edicion_mesa_test.dart`.
- **`flutter test` completo: 556 pasan.**

Mesas que pide cada institución (23-sep): Iloza 133, Nacional 126, Sagrado Corazón 117, Pinaroli 97, Güemez 73,
Buena Vista 54, Rotonda 53, Gregoria 41, Puerto Viejo 31.

---

## PENDIENTE 1 — Corregir los datos de 7 alumnos (script, después de las 20 hs)

**Nada escrito todavía.** Script a crear: `tool/corregir_extras_alumnos_test.dart`.
- Sigue el patrón de `tool/aplicar_fix_mora_5_test.dart`: sqflite ffi sobre `Documents\Junior Eventos\data.db`,
  DRY-RUN por defecto y `--dart-define=APPLY=1` para escribir.
- Trabaja **solo sobre una lista cerrada de ids**, sin recorrer eventos.
- **Frenos.** Aborta sin escribir si:
  - un valor actual no es el esperado;
  - hay algo en `_sync_queue` para ese id;
  - la reconciliación quisiera renombrar un pago;
  - lo pagado quedaría mayor que el precio.
- **Cálculo con el código de la app:**
  - `recalcularSaldoDesdePagos` (`cobro_abono_acumulado.dart:600`);
  - extraer una función pura `MesasExtraUtils.estadoMesasReconciliado` de `reconciliarMesasEstadoContrato`
    (`contratos_repository.dart:650-747`), que el repositorio también use, con test.
- **APPLY:** una sola transacción, con `UPDATE` más `SyncQueue.enqueue(executor: txn, ...)`. Ningún `DELETE`.

| Alumno (id) | Institución | Cambio | Plata |
|---|---|---|---|
| PONCE, AYELEN MILAGROS (`9544c706-81a2-4e85-89af-281f6322a1af`) | Colegio Nacional B | `mesa_extra_cantidad` 1→**2** (el precio total sigue en 140.000) | total y saldo iguales |
| SILVERO, MAXIMILIANO NAHUEL (`fbbd5418-7c44-4099-be9c-78b07af6baec`) | Técnica Pinaroli 1 | mesas extra 1→**2** | iguales |
| GONZALES, ALINA JAZMÍN (`424c1630-73dd-4839-95e5-3b358e46b0f1`) | Técnica Pinaroli 1RA | mesas extra 1→**2** (sus sillas 2×$16.000 ya están bien) | iguales |
| QUIROZ MEZA, MATÍAS NAHUEL (`3199a441-cc45-41d0-af94-13b820b75ce9`) | Normal Iloza 3 | sillas 2→**4** (total sillas sigue en $32.000) | iguales |
| ESMAY, THIAGO (`dd8af936-8880-4a50-8ee0-4de0086ce0e5`) | Güemez 3 | sillas 2→**4** a $8.000 (total sillas $36.000→$32.000) **y** se parte el pago del 25-jun "Sillas Extras - Entrega" $12.000 en $8.000 de sillas + $4.000 de abono de cuota base (misma fecha, medio y sesión de caja) | total 421.000→417.000, saldo 115.000→111.000 |
| BALDI, JUAN MARTÍN (`d5f01890-84f6-4d6e-be33-670e6e6aa348`) | Técnica Pinaroli 1 | silla 1 × $6.000 → **$8.000** | total +2.000, saldo +2.000 |
| CACERES, ANAEL (`b9fe4391-053a-4582-9758-5da1a7512150`) | Normal Iloza 5 | **NO SE TOCA**: su "2" de sillas sin precio no está en su cuenta; la app ya no lo muestra | — |

- **Orden de aplicación:**
  1. primero los 3 de mesas: Ponce, Silvero, Gonzales;
  2. después Quiroz, Baldi y Esmay.
- **Aprobaciones:** Esmay está aprobado por el usuario (23-sep). Antes de partir su pago hay que revisar dos cosas:
  con qué rótulo guarda la app un abono de cuota base, y que la caja de esa sesión siga sumando igual.
- **Valores al 23-sep** (se vuelven a leer ese día; los frenos comparan):
  - PONCE 410.000 / 260.000, pagado de mesa 60.000;
  - SILVERO 455.000 / 192.500, 87.500;
  - GONZALES 471.000 / 236.000, 60.000;
  - QUIROZ 372.000 / 100.000;
  - ESMAY 421.000 / 115.000;
  - BALDI 391.000 / 105.000.
- **Cómo queda el detalle por mesa:** lo pagado va primero a la Mesa 1. La mora no cambia, porque se calcula solo
  sobre la base.

## PENDIENTE 2 — Caja (sin empezar en el código)

El usuario pidió dos cosas:
- que cuando el jefe anula un cobro, **desaparezca en el momento** del cierre de caja del operario;
- anular (y corregir el medio de pago de) **varios cobros a la vez**.

**Causa verificada.**
- La anulación marca `anulado=1` (`finanzas_repository.dart:754-792`) y llega a la otra PC en segundos, por el
  pulso o por el ciclo de 10 s.
- El cierre ya descarta los anulados (`finanzas_repository.dart:223`).
- Pero `CierreCajaNotifier` (`cierre_caja/providers/cierre_caja_provider.dart`) **no se actualiza solo**: carga al
  abrir y con `refrescarManual()`.

**T. El cierre se actualiza solo.**
1. En `SyncEngine`, un aviso nuevo, `cambiosBajadosStream` (`Stream<Set<String>>`, broadcast), con un set
   `_tablasConCambios` y `_avisarCambiosBajados()`. **Se había empezado y se revirtió para dejar el repo limpio.**
   Dónde enganchar:
   - en `_pullTable`, después de `batch.commit`: `if (rows.length > skipped) _tablasConCambios.add(table)`;
   - en `_aplicarBorrados`, al borrar;
   - llamar a `_avisarCambiosBajados()` al final de `pullOperationalUpdates`, `_atenderElPulso`, `_pullFromCloud` y
     `_reconcileDeletes`;
   - cerrar el controller en `dispose`.
2. `CierreCajaNotifier` escucha el aviso. Si vienen cambios de `pagos_contrato_alumno`, `sesiones_caja`, `egresos`,
   `transacciones`, `pagos_prestamo_alquiler` o `cierre_caja_*`, hace un `_refrescar(silencioso: true)` con espera de
   aprox. 1 s: sin poner `cargando`, para que no parpadee.
   - El arqueo que se tipea vive en widgets hijos, así que el refresco no lo pisa.
3. Aviso visible "El jefe anuló 1 cobro de esta sesión: ALUMNO · $X", armado comparando los cobros de antes y de
   después.
4. En la PC del jefe, refrescar el cierre después de anular.
5. En una sesión ya cerrada, una línea aparte "Anulado después del cierre: $X". El arqueo guardado no cambia.

**U. Anular varios** (`mi_empresa/widgets/anular_cobro_cuota_dialog.dart`; hoy tiene un solo `_seleccion`).
- Casillas en los resultados, que se mantienen entre búsquedas, y arriba "N seleccionados · $total".
- "Todo el cobro": reusar `cierre_caja/services/cobro_agrupado.dart` (mismo contrato, momento y sesión).
- Un solo motivo, de 8 caracteres o más, y confirmación "Vas a anular N cobros por $total".
- En el repositorio, `anularPagosConMotivo(lista, motivo)` en **una sola transacción**, con la misma lógica que
  `anularPagoConMotivo` por fila (incluido el tracked de mora de las filas de interés).
- Cada contrato se recalcula una sola vez (`recalcularProgresoContrato`).
- Un solo comprobante PDF.

**V. Corregir medio de pago de varios** (`CorregirMedioPagoDialog`): la misma lista con casillas, el medio nuevo
una sola vez y una transacción.

**Tests:** todo o nada; recálculo una vez por contrato; el refresco se dispara solo con las tablas que importan; no
pisa lo tipeado.

## PENDIENTE 3 — Tótem (hacer un plan propio cuando se llegue)

- **Mesa en la puerta:** el sorteo guarda la mesa en `contratos_alumnos.numero_mesa`, pero el tótem, la lista del
  QR, la búsqueda por DNI y el operador leen **`invitados.numero_mesa`** (hoy solo 6 filas). Hay que planear que el
  día de la fiesta la puerta muestre la mesa sorteada.
- **Ahorro de Disk IO.** El usuario confirmó que tótem y Recepción no tienen datos delicados y alcanza con la PC que
  se use. Tiene que quedar sin que se note nada:
  - **Tótem escondido** (`KioskLauncher.close()` solo hace `hide()`, `kiosk_launcher.dart:129-136`): mientras está
    escondido, cortar `streamInvitados`, `streamAccesos`, el stream de `totem_config`, el canal broadcast y la
    relectura de 60 s (`totem_display.dart:514`). Al mostrarse, retomar y recargar.
  - **Recepción:** cortar `subscribeToChanges` (`invitados_repository.dart:627`) al salir de la pantalla.
  - **`invitados`:** sacarla del ciclo de 10 s (`sync_engine.dart`, pull de `invitados`). Bajarla al entrar a
    Recepción o al tótem y cada 5 min mientras estén en uso. Lo cargado se sigue subiendo al instante
    (`_syncImmediately`).
  - **Latido de caja** (cada 60 s): una subida que solo trae el latido no manda pulso. Los cobros siguen en segundos
    y el ciclo de 10 s no se toca.

## PENDIENTE 4 — Versión 4.9.9 (solo al final, con todo)

1. `pubspec.yaml` 4.9.9+55 y `installer/junior_eventos_setup.iss`, que tienen que coincidir.
2. El instalador.
3. `docs/CONTEXTO_v4.9.9_<fecha>.md`, que reemplaza a este.
4. Commit y push.
5. **Publicar e instalar en las dos PCs solo cuando el usuario lo diga.**
6. Prueba sin sortear: abrir el diálogo y cancelar, y generar la Planilla.

---

## Aviso de Supabase "Disk IO Budget" (llegó el 23-sep a las 19:45)

- Las estadísticas de Query Performance son **acumuladas desde el 11-mar-2026**. Las ~10,2 M lecturas de WAL son
  casi las mismas que en el incidente del 1-sep (ver `CONTEXTO_v4.9.4_2026-09-02.md`). Realtime **no** fue la causa
  de hoy.
- La base pesa 18 MB y vive en memoria (`blks_read` 1.707 contra 18.400 M `blks_hit`). Lo que gasta disco es
  escritura.
- **Punto de partida para medir** (23-sep, 00:35 UTC):
  - `wal_lsn` 59/84000160;
  - lecturas de WAL de Realtime 10.179.536;
  - latidos de caja (`UPDATE sesiones_caja`) 23.677;
  - consultas totales 12.637.597;
  - PostgREST 876.329;
  - 0 conexiones de Realtime.
- **Qué hacer:**
  - volver a medir con la misma consulta de solo lectura y mirar el gráfico **por hora** del mail;
  - **no tocar "Reset report" antes de esa medición**;
  - operativo: cerrar la app entera al terminar el día, porque cerrar solo el tótem no alcanza.
- Si la medición muestra consumo diario en horario de trabajo, se puede ofrecer adelantar solo el arreglo del
  tótem y Recepción.

## Tarea aparte (ya registrada)

- `mesas_extra_estado` se guarda como `toString()` de Dart en vez de JSON (`sync_engine.dart:2207`, `value.toString()`
  en la limpieza del pull), en local y en la nube. No afecta al sorteo, que usa la cantidad. Conviene que entre en
  la 4.9.9.
