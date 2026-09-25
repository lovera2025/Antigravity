# Fase 2: sillas extra, retiro de entradas y registro del sorteo

**Fecha:** 2026-09-25
**Rama:** `feature/v4.6-cierre-por-sesiones` (sobre la 5.0.0)
**Estado:** hecho en la rama, **sin publicar**. El 25-sep se probó la migración sobre una copia de la base real y no
cambió ningún dato. Falta correr el SQL en la nube, que se hace cuando el usuario avise (ver "Lo que falta").

> **Referencia:** `Fase 2` · `retiro de entradas` · `sillas_reparto` · `entradas_retiro` · `sorteos_mesas` · `v72`
> Anterior: [CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24](CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24.md), con la spec,
> la Fase 0 y el plan original de siete piezas.

## De dónde salió

El plan de la Fase 2 tenía siete piezas. El 25-sep el usuario lo revisó y lo simplificó:

- **"Avisar" y el "código del sorteo":** no les veía sentido. Se sacaron. Del sorteo quedó un registro simple, que
  sirve para responder una queja.
- **La ficha "Familia" era demasiado.** Lo que hace falta es una **sección para marcar quién retiró las entradas**, que
  quede anotado en el programa y también en papel.
- **El reparto de sillas:** un selector simple ("4 sillas → 2P · 2A"), no una tabla para completar.
- **Menores de 10:** se anotan en el momento del retiro. No hay fecha de nacimiento.
- **El plano** tiene que salir de lujo. Pasa a la Fase 3, con maquetas antes de programar.
- **Los permisos de la lista de la puerta (RLS)** pasan a diciembre, con el tótem
  ([pendiente](pendientes/rls-invitados.md)).
- **Tiene miedo a las migraciones:** ya se rompieron cobros con migraciones mal hechas.

### Decisiones del 25-sep

| Tema | Decisión |
|---|---|
| Qué se entrega | VIP por cantidad (sin número) + generales **con número del talonario** |
| Quién retira | Parentesco + nombre y apellido. **Sin DNI.** Familiar directo (egresado, madre, padre, tutor, hermano mayor, abuelo) u otra persona con autorización firmada y motivo |
| El papel | Quien retira **escribe su nombre y apellido**: no firma, porque una firma la dibuja cualquiera. La app no confirma sin tildar que lo escribió |
| Si debe algo | **No se entrega**, mora incluida. Botón "Ir a cobrar" |
| Sorteo | Registro simple: fecha, quién y cómo quedó cada uno. Sin código |
| Datos | Solo tablas nuevas y aparte. **Nunca columnas nuevas en `contratos_alumnos`** |

## Qué cambió en la app

1. **Sillas extra (lista de alumnos, columna Mesa).**
   - El renglón "+3 sillas" se toca y ofrece solo las formas posibles ("2P · 1A", "1P · 2A"): hasta 2 por mesa, que
     sumen lo comprado.
   - Si hay una sola forma posible, no pregunta.
   - Si después compran otra silla, lo elegido deja de valer solo y vuelve a "a confirmar".
   - El chip **"Sillas a confirmar"** junta a quienes hay que llamar.
   - Con los datos del 25-sep, solo 5 de los 17 alumnos con sillas tienen algo para elegir.
2. **Retiro de entradas** (⋮ del evento). Pantalla por institución: resumen, vista *Mostrador* (buscador) y vista
   *Por división*. El diálogo de entrega:
   - bloquea si debe, si la ficha y los pagos no coinciden, si no tiene mesa, si sus mesas no coinciden con la cuenta
     o si no entran;
   - calcula "hasta el N" a partir del primer número del talonario, y acepta dos tramos si el talonario salta;
   - no deja usar un número ya entregado a otra familia del evento;
   - pide parentesco, nombre y apellido, menores de 10 y el tilde de la planilla;
   - **antes de guardar vuelve a leer todo** y le pregunta a la nube si la otra PC ya entregó;
   - anular pide motivo y no borra nada.

   La **planilla de entrega** sale una hoja A4 acostada por división, con el nombre siempre en blanco.
3. **Registro del sorteo.**
   - Sortear, deshacer y restaurar dejan un renglón con quién, cuándo y cómo quedó, en la **misma transacción** que
     los números.
   - La planilla del sorteo lo imprime arriba de cada hoja y cuenta los "cambios a mano después".
4. **Planilla del sorteo.**
   - Usa el reparto elegido para "2P · 1A" y para las generales de la principal.
   - Marca "Confirmado" o "A confirmar".
   - **Ya no pinta filas en amarillo**: se pintaban con cualquier nota sin resolver, que suelen ser de cobro. La nota
     sigue en Observaciones.

**No cambió:** cobros, caja, mora, contratos, pagos, Editar alumno (los acompañantes se siguen cargando ahí), los
demás PDF, el algoritmo del sorteo y la lista de la puerta.

## Datos: cómo se protegió lo que ya existe

- **Tres tablas nuevas, v72.**
  - `sillas_reparto`: una fila por alumno.
  - `entradas_retiro`: una fila por alumno.
  - `sorteos_mesas`: solo se agregan renglones.
- **Cero cambios en tablas existentes.**
- **Por qué no columnas en `contratos_alumnos`:** esa es la fila de la plata, y se reescribe entera en tres lugares.
  - `datosEdicionAlumno` (Editar alumno) manda `toJson()` completo.
  - `_pullByEvento` la rearma desde el modelo con INSERT OR REPLACE.
  - `_pullTable` la rearma con la lista de columnas.

  Un dato nuevo ahí se pisa o se borra en silencio: es lo que pasó con el perdón de mora.
- **Id fijo por alumno** (`UuidUtils.sillasRepartoId`, `UuidUtils.entradasRetiroId`), el mismo en las dos PCs, igual
  que las notas. Por eso un egresado no puede tener dos retiros.
- **Ningún código nuevo escribe en `contratos_alumnos` ni en los pagos.** "Ir a cobrar" y "Editar alumno" abren las
  pantallas de siempre. La excepción es el registro del sorteo, que va dentro de la transacción de `numero_mesa` que
  ya existía.
- **Antes de migrar, copia automática:** `LocalDatabase.copiaAntesDeMigrar` hace `VACUUM INTO
  backups/antes_de_v72.db`, una sola vez. Si falla, la app abre igual.
- **La migración se puede correr dos veces sin efecto** (`crearTablasV72`, solo `CREATE ... IF NOT EXISTS`), y
  `_initDb` la repite en cada arranque como red.
- **Volver atrás:** con la 5.0.0, la base v72 abre (sqflite sin `onDowngrade` solo cambia el número) y las tablas
  nuevas sobran. Probado en `test/migracion_v72_test.dart`.
- **Sync:**
  - las tres tablas están en `_incrementalColumns`, `_pullFromCloud`, `_cleanForSqlite` (todas sus columnas),
    `getPriority` y las relaciones de `sync_queue.dart`;
  - ninguna entra en la limpieza de huérfanos ni en Realtime.

### En tiempo real entre las dos PCs

- **Subida.** Al guardar una entrega, una anulación o un reparto, `subirYa` (`common/utils/subir_ya.dart`) lo sube en
  el momento, con cualquier rol, y reintenta si el motor está ocupado.
  - Antes de esto, la subida dependía del ciclo: hasta 10 s en la PC del jefe (`afterMassiveMutation` solo sube
    cobros), y una sesión sin rol elegido (Asesor) podía no subir sola.
  - Si no pudo subir (sin internet), la app lo dice. En una entrega avisa que la otra PC todavía no la ve.
- **Aviso.** Al subir, el motor manda el pulso. La otra PC baja esas tablas en menos de un segundo.
- **Pantallas.** La de Retiro de entradas y la columna Mesa escuchan `cambiosBajadosStream` y se releen apenas baja
  algo. La de Retiro además relee cada 15 s.
- **Red de seguridad si el pulso no llega:** `entradas_retiro` y `sillas_reparto` bajan cada 10 s (lista de mostrador);
  `sorteos_mesas`, cada minuto.
- **Contra las entregas dobles:**
  - antes de guardar, la app le pregunta a la nube por la fila de ese alumno;
  - con todo recién leído, si mientras el diálogo estaba abierto cambió algo —otra PC entregó, un cobro, esos números
    del talonario—, no guarda y lo dice.
- **Lo que queda posible:** que las dos PCs confirmen la misma familia en el mismo par de segundos. Gana la última,
  porque es una sola fila. En el mostrador no pasa: la familia está en un solo lugar.
- **Lo nuevo no puede pisar un cobro:** no escribe en la cuenta ni en los pagos.
- **Nube:** `supabase/migrations/20260925120000_sillas_retiro_sorteos.sql`.
  - Contiene las tablas, FK con `ON DELETE CASCADE`, RLS "authenticated", disparadores de `updated_at` y el
    `ROLLBACK` de cada sentencia.
  - Trae las consultas para comparar conteos antes y después.
  - La 5.0.0 no lo ve.

## Commits

- `e69d5cd` base y sincronización (v72, tablas, copia antes de migrar, SQL);
- `b53c6b0` selector de sillas y planilla con el reparto;
- `d67964b` registro del sorteo;
- `3d14938` retiro de entradas y planilla de entrega;
- `a539588` este documento, el pendiente de la RLS y CLAUDE.md;
- `a5f97b6` la muestra de la planilla del sorteo con la línea de quién sorteó.

## Verificación hecha

- La suite completa pasa: **727 tests** (649 antes de la Fase 2). Tests nuevos:
  - `migracion_v72_test`: fila por fila, dos veces, vuelta a la 5.0.0 y copia;
  - `reparto_de_sillas_test`;
  - `registro_sorteo_test`;
  - `retiro_entradas_test`: pagó todo con y sin mora, ficha distinta de los pagos, anulados, talonario, quién retira,
    anular y la planilla;
  - `entrega_entradas_dialog_test`: widget tests del diálogo.
- **`planilla_sorteo_test`** cambió solo en lo del amarillo ("avisar" se sacó a pedido del usuario).
- **`flutter analyze`** no marca nada nuevo: los 34 avisos de `detalle_evento_masivo_screen.dart` y `pdf_service.dart`
  ya estaban.
- **Muestras en PDF** con datos inventados:
  - `tool/planilla_sorteo_muestra_test.dart`;
  - `tool/planilla_entrega_muestra_test.dart`.
- **La migración sobre una copia de la base real** (25-sep, con el OK del usuario), con
  `tool/verificar_migracion_v72_test.dart`:
  - la base real estaba en v71, y la copia quedó en v72;
  - las 28 tablas que ya existían quedaron iguales fila por fila (643 contratos, 3552 pagos, 54 notas; `_sync_queue`
    vacía);
  - aparecieron solo `entradas_retiro`, `sillas_reparto` y `sorteos_mesas`, las tres vacías;
  - la base real quedó idéntica, con el mismo tamaño, la misma fecha y el mismo SHA-256 antes y después;
  - la copia se borró.

## Lo que falta, en orden

1. **Hecho el 25-sep:** la migración sobre una copia de la base real no cambió ningún dato (ver "Verificación hecha").
2. **Correr el SQL en la nube** cuando el usuario avise, después de las 20 hs: primero los conteos, después el archivo y
   al final las consultas de verificación. El 25-sep se le ofreció dejarlo programado y prefirió avisar.
3. **Que el usuario mire las planillas de muestra** y pruebe la sección en la versión nueva.
   - Las muestras se generan con `flutter test tool/planilla_entrega_muestra_test.dart` y
     `tool/planilla_sorteo_muestra_test.dart`, con `--dart-define=salida=<carpeta>`.
   - Se le mandaron el 25-sep, y falta su opinión. Al revisarlas se vieron tres detalles, que se deciden con el usuario:
     - en la planilla de entrega, el título de la última columna se corta en dos renglones: "RETIR / Ó";
     - en la versión interna de la planilla del sorteo, la columna Reparto corta la palabra: "Confirmadc", "A
       confirmai". En la versión para repartir entra bien;
     - a la planilla de entrega le entran unos 23 renglones por hoja: una división de 26 ocupa dos hojas, y la segunda
       lleva 3 renglones. El renglón es alto para que se pueda escribir a mano; achicarlo ahorra papel.
   - **Para probar la versión nueva en una PC, antes tiene que estar el paso 2.** Sin las tablas en la nube, lo que se
     cargue en ellas (un reparto, una entrega) queda trabado en la cola de subida y marca error.
   - Probarla abre la base real de esa PC y la migra a v72. Es seguro —solo agrega tablas y antes saca la copia—, pero
     no hay entorno de prueba: una entrega de prueba sube a la nube. Probar con un alumno y anularla después.
4. **Publicar**, cuando el usuario lo diga, junto con la Fase 3 (versión A).
   - Instalar el mismo día: primero el operario, después el jefe.
   - **No entregar entradas hasta que las dos PCs tengan la versión nueva.**
5. **No pasar la lista de la puerta** de ninguna fiesta hasta cerrar la RLS ([pendiente](pendientes/rls-invitados.md)).

## Límites conocidos

- **Completar una entrega** (compró otra silla después de retirar): la fila avisa "cambió la cuenta". Se resuelve
  anulando, con motivo, y volviendo a entregar con todos los números. El formulario se precarga con lo de la vez
  anterior.
- **Para entregar tiene que tener mesa.** Si le falta una mesa del sorteo, se completa el sorteo antes.
- **Sin DNI** de quien retira, por decisión del 25-sep. El registro fuerte es el nombre escrito a mano en el papel.
- **Dos PCs entregando a la misma familia sin internet** se pueden pisar: la última gana, porque es la misma fila. La
  app avisa y pide confirmar antes de entregar sin red.

## Lo que tiene que traer el usuario

- **El aviso para correr el SQL** (paso 2). El OK para la prueba sobre la copia lo dio el 25-sep.
- **Qué le parecieron las dos muestras** en PDF, que se le mandaron el 25-sep.
- **Para la Fase 3:**
  - el Canva del predio exportado, guardado en `PLANES JRe`;
  - las respuestas del jefe (abajo).

## Queda para el jefe

Juntas acá las preguntas abiertas de los dos CONTEXTO, ordenadas según lo que frenan (25-sep). El usuario las tiene
para mandárselas.

**Frenan la Fase 3:**
1. Qué salón se arma este año: el de la página 3 del Canva (78 mesas numeradas), el de las páginas 4 a 6 (100 mesas con
   pasarela), o si cambia según la fiesta.
2. Las mesas grises del pasto: si se numeran después de las comunes (131 en adelante) y se usan solo si faltan lugares.
3. Qué escuelas se sortean por división, con bloques de colores como la Normal, y cuáles enteras, como la Técnica.
4. Si la fila roja de su Excel es alguien sin mesa. La planilla ya lo supone (D11).

**No frenan nada (entrega de entradas):**
5. Si los menores de 10 cenan. Solo cambia la cuenta de la cocina.
6. Si la pulsera VIP es de otro color. No cambia lo que se anota.

**Para diciembre (Recepción y tótem):**
7. Si el ingreso se marca por familia o por persona (D9).
8. Si los dos puestos de recepción van juntos o en lados opuestos del predio (D12).
9. Cómo se reparte la gente entre los dos puestos: por letra, por división o sin reparto.
10. Qué pantalla hay en el predio para el tótem: si tiene entrada HDMI y si va vertical u horizontal.

## Cómo seguir: Fase 3

Plano de lujo y sorteo por bloques.

- **Antes de programar:** dos o tres direcciones de diseño lado a lado, con `show_widget`. En pantalla tiene que ser de
  lujo, innovador, llamativo y prolijo; el impreso, limpio y legible en blanco y negro.
- **Hace falta:**
  - el Canva del predio exportado y guardado en `PLANES JRe` (las fotos del 24 no quedaron);
  - las respuestas del jefe.

Para seguir en otro chat, pegar:

```text
Seguimos con el plan de mesas de los masivos. Leé primero
docs/CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25.md (secciones "Lo que falta" y
"Lo que tiene que traer el usuario") y la memoria del proyecto. La Fase 2
(sillas, retiro de entradas, registro del sorteo) está hecha en la rama y sin
publicar, y la migración v72 ya se probó sobre una copia de la base. Falta el
SQL de la nube: se corre cuando yo avise, después de las 20 hs. Después, Fase 3:
mostrame 2-3 diseños del plano lado a lado antes de programar. No se publica
nada hasta que yo lo diga.
```
