# Mesas, plano, recepción y tótem de los masivos: cómo convive la spec con lo que ya está

**Fecha:** 2026-09-24
**Rama:** `feature/v4.6-cierre-por-sesiones` (5.0.0)
**Sin migración de base y sin código.** Es el informe de la Fase 0 (solo lecturas del repo y de la base de
producción) más todo lo que se decidió el 24-sep a la noche.

> **Referencia:** `CONTEXTO_MESAS_PLANO_RECEPCION` · `spec de mesas` · `quién retira las entradas` · `primero noviembre`
> Spec: `C:\Users\lover\Desktop\COSAS\Desarrollo\PLANES JRe\PROMPT_mesas_plano_recepcion_totem_v1.md` (fuera del repo).
> Anterior: [v5.0.0](CONTEXTO_v5.0.0_2026-09-24.md) (sorteo según lo pagado).

> **Actualizado el 25-sep:** la Fase 2 se revisó con el usuario y está hecha en la rama, sin publicar. Lo vigente está
> en [CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25](CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25.md): sacó "avisar", el
> código del sorteo y la ficha "Familia", sumó la sección Retiro de entradas y pasó la RLS a diciembre. Lo de abajo
> sobre la Fase 2 quedó como historia.

**Estado:**
- La Fase 0 está hecha.
- El orden de trabajo lo eligió el usuario: **primero noviembre**, es decir el sorteo, la planilla y el plano.
- Recepción y tótem son para las fiestas de diciembre. Se diseñaron con maquetas aprobadas y quedaron como pendientes
  decididos en `docs/pendientes/` (ver "Recepción y tótem").

---

## De dónde salió

La spec cubre las fiestas de egresados:

- sorteo con plano;
- reparto de sillas;
- entrega de entradas;
- recepción sin internet con dos puestos;
- tótem rediseñado.

Pide arrancar por una Fase 0 de solo lectura. El usuario pidió además que lo ya hecho **conviva con esto o se adapte**.
Lo ya hecho es:

- el sorteo (4.9.9 y 5.0.0);
- la lista de la puerta;
- el tótem editable;
- Recepción offline-first.

## Las decisiones

**Del 24-sep a la tarde, sobre la spec:**

1. **La mesa adicional es la mesa extra** que compró la familia.
   - Va pegada a la principal salvo que se pida separarla.
   - La familia elige cuántas sillas extra van en cada una de sus mesas, con un máximo de 2 por mesa.
   - No hay mesas compartidas.
2. **Acompañante = VIP con cena**, como dice la spec. Hasta 2, con excepción y motivo. Las entradas generales son los
   lugares de sus mesas menos los VIP.
3. **Dos versiones:** la **A** antes del sorteo de noviembre y la **B** antes de las fiestas de diciembre.
4. **Se rediseña solo la planilla del sorteo de mesas**, la que hoy es la "Planilla de cursos". Mora, cobros, caja y
   contratos firmados quedan como están.

**Del 24-sep a la noche:**

5. **Quién retira las entradas:** ver la sección de abajo.
6. **Recepción y tótem se simplifican.** Se anulan el spike de hardware y el diseño grande de hub, emparejamiento y
   secuencias. En palabras del usuario:
   - "que se carguen todos los alumnos con internet primero y después se pueda manejar sin internet";
   - todo en tiempo real;
   - "quizás con un router alcanzará para modo local", y que los dos recepcionistas no se pisen;
   - bienvenida, plano y guía en el tótem;
   - "no nos complicamos mucho; cualquier cosa lo mejoramos más adelante".
7. **Cada noche es una sola escuela.** Las 9 instituciones tienen fechas distintas. La más grande es la Normal, y
   habría dos tótems, quizás tres.
8. **Orden: primero noviembre.** El usuario eligió arrancar por el sorteo y la planilla y dejar el tótem para
   después.

---

## Qué supone la spec y cómo es en realidad

| La spec dice | Cómo es en el repo |
|---|---|
| Stack con **Drift** | sqflite con migraciones propias (`local_database.dart`, v71). Se sigue con sqflite. |
| "Hoy todo se hace a mano en Excel y Canva" | Sorteo, planilla de cursos y lista de la puerta **ya están en la app**. Falta el **plano** (los números van de 1 a N sin geometría) y el **reparto elegido** de sillas. |
| "El tótem tiene modos particulares y masivo" | No hay modos. Hay una lista por evento, y lo que cambia es cómo se carga. |
| Sillas extra por egresado | Están (`sillas_extra_cantidad`, que cuenta solo si tiene precio). Existen además las **mesas extra** (84 alumnos), que la spec no nombra. |
| "Un egresado con 3 acompañantes" | En la app **nadie** tiene acompañantes cargados: 0 de 643. |
| Tablets Android | Nunca se publicó para Android: `applicationId com.example.arguello_events`, firma debug, solo permiso INTERNET. |

## Informe de la Fase 0

### Recepción y tótem hoy

- **Marcar un ingreso:** `InvitadosRepository.marcarIngreso` (`invitados_repository.dart:319`):
  - escribe en SQLite y encola en `_sync_queue`;
  - le avisa al tótem de la misma PC por el puente (`KioskLauncher.notifyGuestCheckin`), que no necesita red;
  - le avisa por broadcast en `totem_<id>`;
  - si hay red, sube directo.
- **Tótem del salón** (`totem_display.dart`):
  - lee el stream de Supabase, el broadcast, el puente y una relectura cada 60 s;
  - arma una cola en memoria y muestra cada bienvenida **7 s** (`:705`). La spec pide 8 a 10;
  - sin red muestra "Reconectando...", visible al público.
- **Panel de Recepción** (`totem_panel.dart`): lee de SQLite y es una copia casi idéntica del tótem, con unas 800
  líneas duplicadas.
- **QR `/lista`:** el invitado se marca solo desde su celular.
  - Baja la lista completa y compara el DNI **en el celular**.
  - Si no hay DNI, que es el caso de los alumnos, entra directo.
- **Doble marca:** no duplica, porque es un estado, pero no queda quién ni cuándo. `accesos` (log con `marcado_por` y
  `timestamp`) existe, tiene 0 filas y hoy solo lo escribe el check-in web por DNI.

### Modelo de datos

- **El alumno** vive en `contratos_alumnos`:
  - `numero_mesa`: texto como "12-14", lo escribe el sorteo;
  - `mesa_extra_cantidad` y `mesas_extra_estado`;
  - `sillas_extra_cantidad` y `sillas_extra_precio_total`;
  - `cantidad_acompanantes` y `nombres_acompanantes`;
  - `curso_division`, que es texto libre.

  No tiene DNI, fecha de nacimiento ni tutor (`local_database.dart:206-245`).
- **Observaciones:** existe `notas_operativas_contrato`, con texto y "resuelto" (24 filas). No tiene la marca "avisar".
- **Sorteo:**
  - las piezas son `SorteoMesasMotor`, `SalonMesas` y `pago_para_sorteo.dart`;
  - **no es reproducible:** `sortear` se llama sin semilla (`detalle_evento_masivo_screen.dart:3370`) y cae en
    `Random.secure()` (`sorteo_mesas_motor.dart:211`);
  - no queda registro de quién sorteó ni cuándo.
- **Ingresos:** `invitados.estado_ingreso` más `updated_at`. No hay UUID de ingreso ni operador.
- **Datos reales al 24-sep:**
  - 10 eventos de egresados con 643 alumnos;
  - 84 con mesas extra;
  - 17 con sillas extra (máximo 4), y ninguno supera 2 por mesa;
  - **0 con número de mesa**: todavía no se sorteó;
  - divisiones escritas de formas distintas ("a" y "B"; "1", "1RA" y "7 1 ERA"), y Puerto Viejo sin división.

### Dependencia de internet

- **Escritorio:** offline-first. Recepción más el tótem en la misma PC andan sin red gracias al puente. La carga
  inicial del tótem lee Supabase.
- **Dos PCs** se coordinan solo a través de la nube: sin internet, no se ven.
- **Sesión:** `AuthWrapper._effectiveSession` (`main.dart:566`) la rehidrata del disco sin red, y el rol se cachea.
  Falta la prueba de la spec: modo avión más de 1 h con el token vencido.
- **Web** (`?totem`, `?lista`, `?buscar`, `/op`): depende 100 % de Supabase.

### Build Android

- Hay proyecto en `android/` y `sqflite` nativo ya previsto. En Windows va `sqfliteFfiInit`
  (`local_database.dart:73`).
- `window_manager` y `desktop_multi_window` son solo de escritorio.
- Para la red local faltaría `network_security_config`, permisos de red y un servicio en primer plano.

### Operadores, PINs y RLS (verificado en la base)

- `operadores_caja.pin` está **en texto plano**, en SQLite y en Supabase (`sync_engine.dart:2196`).
- `eventos.pin_operador` (`/op`) también está en texto plano, y se compara en el cliente. Ningún evento lo usa.
- El PIN maestro de Mi Empresa es `'2026'` por defecto, en SharedPreferences y en claro (`admin_provider.dart:30`).
- **`invitados`:** cualquier anónimo **lee y modifica todas las filas de todos los eventos**, DNI incluido
  (`lectura_publica_invitados` y `actualizacion_publica_invitados`, verificado el 24-sep). Hoy son 7 filas de prueba;
  al pasar la lista de la puerta serían los 643 alumnos.
- **`eventos`:** sin políticas para `anon`. El tótem web no puede leer la modalidad del evento.
- **`contratos_alumnos`, `pagos_contrato_alumno`, `eventos` y `operadores_caja`:** cualquier usuario logueado tiene
  acceso total. Al Asesor se lo limita solo en pantalla.

### Saldo

- La verdad es lo pagado: `grossHistoricoClaseCobro` y `recalcularSaldoDesdePagos` (`cobro_abono_acumulado.dart:559` y
  `:600`), lo mismo que usa el sorteo de la 5.0.0. `saldo_deudor` es un derivado.
- En Supabase los pagos son `numeric`. En el contrato, `mesa_extra_pagado`, `sillas_extra_pagado` y
  `porcentaje_descuento` son `real` (float4). La app compara con un margen de 0,01.

---

## Mapa de convivencia

| Lo que ya existe | Qué pasa con eso |
|---|---|
| `SorteoMesasMotor` | **Se queda sin cambiar el algoritmo.** "Números consecutivos = mesas juntas" es justo lo que la serpentina garantiza en el salón. Se corre por bloque de división, con `ocupadas` igual a todo lo que está fuera del bloque, y con un generador propio y sembrado. |
| Sorteo según lo pagado (5.0.0) | **Se queda**, aplicado dentro de cada bloque. |
| Mesas extra | **Pasan a ser la "mesa adicional".** Ya salen pegadas por construcción, salvo "separar". |
| `SalonMesas` | **Se adapta:** `repartoSillas` lee lo que eligió la familia. Si no eligió, usa el reparto de hoy, marcado "pendiente". |
| `numero_mesa` (texto) | **Sigue siendo la verdad** de qué números tiene cada alumno. El plano traduce número → posición. |
| Planilla de cursos (`construirPlanillaCursosPdf`) | **Se rediseña y se amplía.** Es la única planilla existente que cambia. |
| Lista de la puerta | **Se queda.** Lleva al alumno y a sus acompañantes VIP con nombre. |
| `accesos` | **Se reusa como registro de ingresos**, si hace falta registrar quién marcó. |
| `_sync_queue` | **Es el outbox de la spec.** Ya sube por upsert con id: reintentar no duplica. |
| `notas_operativas_contrato` | **Se reusa** para las observaciones, con la marca `avisar`. |

**Reglas del repo que valen para todo lo nuevo:**

- toda tabla sincronizada lleva su trigger de `updated_at`;
- no se agrega nada a la publicación de Realtime;
- ningún camino nuevo borra por fuera de `filasAPodar`;
- las columnas nuevas van a la lista del `sync_engine`;
- las versiones viejas tienen que tolerar lo nuevo, porque el operario se actualiza antes que el jefe.

## Avisos

- **RLS de `invitados`:** cerrarla **antes de pasar la lista de la puerta** (versión A). `/lista` y `?buscar` pasan a
  RPC `security definer`, que no devuelven la lista ni el DNI. Requiere desplegar la web, con OK.
- **No agregar `en_curso` al enum `estado_evento`.** Las versiones viejas leen un valor desconocido como
  "Planificación" y lo pisan al guardar. El congelamiento del evento va en una columna aparte.
- **Semilla del sorteo:** `Random(seed)` y `shuffle` de Dart no garantizan la misma secuencia entre versiones del SDK.
  Para que el sorteo sea reproducible hacen falta un generador y una mezcla propios, con test.
- **La planilla del sorteo baja la fuente de internet** (`PdfGoogleFonts`, `pdf_service.dart:4213`) en vez de usar
  `_fuentesOutfit()` (`:262`), que la lee de `assets/`. Sin red, y sin la fuente en memoria, falla. El día de la
  fiesta no hay red. Los demás PDF hacen lo mismo, pero **no se tocan**.
- **Hardware:** averiguar temprano el tótem real del predio (entrada HDMI, orientación).

---

## Quién retira las entradas

**La regla, con las palabras de la grabación del jefe:** retira un **familiar directo del egresado**, y no se le da a
otra persona.

- **Se registra** el nombre completo, el DNI y el parentesco de quien retira. Sin firma.
- **Un solo retiro activo** por egresado.

**Decidido por el usuario el 24-sep a la noche:**

| | Decisión |
|---|---|
| **D15** Quién es familiar directo | El egresado; padre, madre o tutor; hermanos mayores de edad (el operador lo ve en el DNI); abuelos. Nadie más: ni tíos, ni compañeros, ni terceros "autorizados de palabra". |
| **D16** Otra persona con autorización firmada | Se entrega como **excepción registrada**, con la autorización, el DNI de quien retira, el motivo y el operador que la aceptó. |
| **D7** Carga previa | **Las dos.** Si la familia dejó cargado a alguien, la app compara el DNI ("autorizado"). Si no, se escriben nombre, DNI y parentesco en el mostrador ("declarado"). La carga previa se hace cuando se completan los datos de cada familia. |
| **D5** Qué es "pagó todo" | **Mora incluida:** cuotas del plan, mesas y sillas extra, y la mora. La cuenta en cero, calculada con los pagos (`recalcularSaldoDesdePagos`) más la mora pendiente, con tolerancia de centavos explícita. |

**Hallazgo:** hoy la app no tiene ningún dato del tutor, ni el DNI del alumno. Entra en el modelo de la Fase 2.

---

## La planilla del sorteo

**Alcance:** se rediseña **solo la planilla del sorteo de mesas** (`construirPlanillaCursosPdf`), con su hoja
"Resumen del salón" y la hoja de cada curso. Mora, cobros, caja y contratos firmados no se tocan.

**El estilo nuevo**, en un solo lugar (`PlanillaTema`), que usan también las planillas nuevas de la spec (plano A4,
entrega de entradas, lista de emergencia):

- fuentes que vienen con la app, nunca descargadas;
- encabezado con banda de color, título, subtítulo y fecha; al pie, "Página X de Y";
- tabla con el encabezado repetido en cada hoja, filas alternadas, montos a la derecha y mesas centradas;
- se adapta al contenido, con cuerpo de 9 pt como mínimo;
- el color es acento y nunca el único dato: se tiene que leer igual en blanco y negro;
- compacta, sin hojas a medio llenar.

**Respeta la planilla que ya usa el jefe** (foto del 24-sep, Excel de una división):

- primero sus 5 columnas, en su orden: Egresados · Acompañante · Mesa principal · Adicional · Sillas (`2P`);
- la mesa principal en verde;
- la fila en amarillo cuando hay que avisar;
- la fila en rojo cuando no tiene mesa;
- la nota que hoy va dentro del acompañante ("vianda sin sal") pasa a una columna propia de observaciones.

**Qué lleva:**

- las columnas de la spec, más teléfono y música, que ya están hoy;
- cada acompañante con nombre y apellido, uno por renglón. Si no tiene: "sin acompañantes cargados";
- debajo de cada número de mesa, cómo se ocupa: "N con cena · M generales". Es 8 más las sillas extra de esa mesa,
  menos los que tienen cena, que van siempre en la principal;
- observaciones solo en la versión interna, y una versión para repartir sin ellas;
- una hoja por división, **A4 acostada**, con unos 30 egresados por hoja y los títulos repetidos al seguir;
- los nombres como están cargados, en mayúsculas;
- la semilla del sorteo en el encabezado;
- las filas se arman en una función pura con tests, separada del dibujo.

**Antes de programarla:** una **muestra real en PDF**, generada sin abrir la app, como
`tool/planilla_cursos_muestra_test.dart`, para aprobar el estilo.

---

## El plano

Lo muestran las fotos del Canva del jefe ("Plano Mesas Predio", páginas 1 a 6).

**Página 3 (Normal 2A, numerada por el jefe, 78 mesas):**
- bloque izquierdo de 5 columnas × 6 filas, por filas alternando: 5←1 (la 1 al lado del escenario), 6→10, 15←11,
  16→20, 25←21, 26→30;
- fila de abajo: 31, 32, 41, 42, 53;
- bloque derecho por columnas alternando: 33↑36 y 37↓40 en las filas 3 a 6 (arriba está el escenario), y 43↑47,
  48↓52, 54↑58, 59↓63, 64↑68, 69↓73 y 74↑78 en las filas 2 a 6;
- sectores: escenario en T arriba al centro, "Ingreso egresados" arriba a la derecha, "Sector brindis" a la izquierda,
  "Barra y cajas" a la derecha, "Barra" abajo a la izquierda, "Baños" abajo a la derecha y "Pista baile" abajo al
  centro.

Es exactamente la serpentina de la spec.

**Páginas 4 y 5 (Normal 2A, sin números en el Canva, 100 mesas):**
- escenario de lado a lado arriba, y pasarela al medio hasta unos 2/3 del alto;
- a cada lado, 9 filas: de la 1 a la 5 con 5 mesas, y de la 6 a la 9 con 6, con la columna de más del lado de afuera;
- 2 mesas al medio en la fila 9, debajo de la pasarela;
- numeración propuesta: bloque izquierdo por filas desde el escenario, alternando; después las 2 del medio (50 y 51);
  después el bloque derecho por filas desde abajo;
- reproduce exactamente los bloques de colores del jefe: 1–24, 25–49, 50–51 libres, 52–54, 55–80 y 81–100;
- la página 6 es la hoja B, que sigue abajo con filas de 6 + 2 + 6.

**Técnica 1A y 1B:** 82 mesas verdes en la 1A (más 6 grises de pasto) y 48 en la 1B (más 14), 130 en total.

**Decisiones que salieron de las fotos:**
- **D1:** A y B son el mismo salón partido en dos hojas. La numeración sigue, y el plano impreso puede ocupar 2 A4.
- **D8:** depende de la institución. Normal se sortea por bloques de división; Técnica, entera. El motor actual ya
  hace el modo "entera".
- **Pasto:** son las mesas grises de los costados. Hipótesis a confirmar: los números por encima de 130 del Excel son
  de pasto.
- **D11, hipótesis:** la fila roja del Excel es un egresado sin mesa, igual que "sin mesa (sin pagar)" de la 5.0.0.
- **No sabemos cuál es el salón de este año.** Por eso el plano no queda fijo en el código: la plantilla del predio es
  un dato editable, arranca con los armados del Canva y cada fiesta elige el suyo.

**Personalización** (decidida con una maqueta interactiva):
- **Solo en el programa de escritorio**, en la pantalla del evento masivo, después de tocar "Personalizar". En ningún
  otro lugar se modifica.
- Sin PIN: puede personalizar quien ya puede sortear en ese evento.
- **Lo personalizado es el plano definitivo**, el mismo en pantalla, planilla, impresión, tótem y Recepción.
- Se puede volver a personalizar antes de la fiesta. Desde que se activa la recepción del evento, queda trabado.
- Las cuatro cosas:
  1. **Cambiar y mover familias después del sorteo:**
     - "cambiar con otra familia", solo con una de la misma cantidad de mesas, o "mover a mesas libres", con las mesas
       juntas;
     - motivo obligatorio y aviso si pasa a otro bloque;
     - registro append-only con deshacer;
     - aviso si la familia ya retiró entradas o confirmó el reparto.
  2. **Fijar mesas antes del sorteo**, por ejemplo una silla de ruedas cerca del ingreso.
  3. **Acomodar el salón:** mover, agregar o sacar mesas, marcar el pasto y mover sectores. Después del sorteo, una
     mesa se corre en el dibujo pero su número no cambia.
  4. **Colores y textos** por fiesta.

**Las maquetas aprobadas** (con `show_widget`; no quedan guardadas):
- **la planilla**, con los botones "Interna / Para repartir" y "Color / Blanco y negro";
- **el plano**, con la geometría de las páginas 3 y 4, buscar mesa y cambiar de hoja;
- **los ajustes a mano** sobre la página 4.

---

## Recepción y tótem

Para las fiestas de diciembre. Se diseñaron el 24-sep a la noche con maquetas, y quedaron como pendientes decididos,
uno por archivo, con todo lo necesario para retomarlos sin rediseñar:

- [Comunicación entre Recepción y el tótem](pendientes/totem-comunicacion.md): cuatro arreglos. Entre ellos, que un
  aviso que falla una vez desconecta el tótem por el resto de la noche.
- [El tótem con cuatro apariencias](pendientes/totem-apariencias.md):
  - Neón, Cristal, Póster y Gala, con fondos por shaders;
  - sin "Ya llegaron";
  - QR solo en particulares.
- [Recepción más amigable](pendientes/recepcion-redisenio.md): para PC, tablet y celular, con solo la paleta sobre la
  vista del tótem.
- [Modo kiosco](pendientes/totem-kiosco.md): pantalla completa sin bordes, que se sale con Esc o doble clic.
- [Tótems vinculados a recepcionistas](pendientes/totems-vinculados.md): cada tótem, lo de su puerta, para que no se
  pisen.

Lo que **no** va:

- el hub con emparejamiento y secuencias de la spec;
- el QR para llevar el tótem a otra pantalla ("no tiene sentido");
- el botón "Abrir en el salón" en Recepción.

---

## Fases, en el orden elegido

| Orden | Qué | Para |
|---|---|---|
| 1 | ~~Planilla del sorteo nueva~~ **hecha el 24-sep** (`08fb774`, ver abajo) | noviembre |
| 2 | **Fase 2, modelo y reglas:** acompañantes VIP con fecha de nacimiento y excepción; reparto de sillas por mesa con historial; marca `avisar`; plantilla del predio; auditoría del sorteo con semilla y generador propio; modelo del retiro de entradas; RLS de `invitados` | noviembre |
| 3 | **Fase 3, plano, sorteo y planilla:** geometría única, sorteo por bloques o entero, personalización y planilla nueva | noviembre |
| 4 | **Fase 6, entrega de entradas:** bloqueo por deuda, quién retira, VIP y rango, un retiro activo, planilla | noviembre |
| 5 | Recepción y tótem (los cinco pendientes) | diciembre |

Si el sorteo cae a principios de noviembre, la entrega de entradas es la que puede correrse.

## Preguntas para el jefe

1. ¿Qué salón se arma este año: el de la página 3, el de las páginas 4 a 6, o cambia según la fiesta?
2. Las mesas grises del pasto: ¿se numeran después de las comunes (131 en adelante) y se usan solo si faltan lugares?
3. En su Excel, ¿la fila roja es alguien sin mesa (no pagó o se dio de baja)?
4. ¿Qué instituciones se sortean por división, con bloques de colores como Normal, y cuáles enteras, como Técnica?
5. ¿Cómo se reparte la puerta entre las dos recepciones: por letra (A–L / M–Z), por división, o sin reparto?
6. Las que quedan de la spec:
   - D4: talonario o números del sistema;
   - D6: menores de 10;
   - D9: ingreso por familia o por persona;
   - D12: si los dos puestos están juntos o separados;
   - D13: pulsera VIP;
   - D14: numeración de las generales de la mesa adicional.

## Decisiones pendientes y cuándo bloquean

- **Antes de la Fase 3:** qué salón es el de este año y cómo se numera el pasto (preguntas 1 y 2).
- **En la Fase 2:** D6, que queda parametrizable con `// DECISIÓN PENDIENTE: D6`.
- **En la Fase 6:** D4, D13 y D14.
- **Antes de Recepción y tótem:** D9, D12 y el reparto de la puerta.
- **En la planilla:** D11, la fila roja (va con la hipótesis de "sin mesa").

## Estado al 24-sep a la noche y cómo seguir

**Regla del usuario: no se publica nada hasta terminar el plan completo.** Commit y push a la rama sí; release,
instalador y web, no.

### Hecho en esta sesión

- **`5c6bbfd`:** este documento y los cinco pendientes del tótem.
- **`08fb774`:** la planilla del sorteo nueva, en la app.
  - Lógica pura en `lib/features/eventos/services/planilla_sorteo.dart` (`PlanillaSorteo.fila`, `porDivision` y
    `resumen`), con 23 tests en `test/planilla_sorteo_test.dart`.
  - Estilo común de las planillas nuevas: `lib/features/common/services/planilla_tema.dart`. Color o blanco y negro;
    cada marca lleva su palabra.
  - El papel: `lib/features/common/services/planilla_sorteo_pdf.dart`. Hoja de resumen y una hoja A4 acostada por
    división, numerada por sección ("5° A · hoja 1 de 2"), armada en dos pasadas porque `pagesCount` no sirve con
    varias secciones.
  - `PdfService.construirPlanillaSorteoPdf` y `generarPlanillaSorteo` reemplazan a los de la "Planilla de cursos",
    con las fuentes desde `assets/` (`_fuentesOutfit`).
  - En la pantalla del evento masivo:
    - el menú dice "Planilla del sorteo";
    - un diálogo pregunta la versión (Interna o Para repartir) y la impresión (Color o Blanco y negro);
    - el aviso de "Sorteo listo" ofrece "PLANILLA".
  - La muestra se genera con
    `flutter test tool/planilla_sorteo_muestra_test.dart --dart-define=salida=C:\carpeta`. Salen 4 PDF con datos
    inventados.
  - La suite tiene 649 tests en verde. `flutter analyze` no marca nada nuevo: 313 avisos, contra 314 antes, todos de
    código viejo.

### Lo que la planilla deduce hasta que exista en la base (Fase 2)

- **El reparto de sillas** figura siempre "Pendiente", con el reparto de siempre: de a 2 por mesa, la principal
  primero.
- **"Avisar"** es la nota operativa sin resolver.
- **La semilla del sorteo** no va en el encabezado hasta que el sorteo la guarde.
- **Los números de cada división** salen salpicados, porque hoy se sortea la institución entera. Con el sorteo por
  bloques (Fase 3) quedan en uno o dos tramos. Mientras tanto, el resumen dice "en N tramos".
- **"Para repartir" saca también los teléfonos**, no solo las observaciones, porque son datos de otras familias. Si
  el jefe los quiere, es una línea en `PlanillaSorteoPdf.columnas`.

### Lo que falta, en orden

1. **Fase 2, modelo y reglas.** Primero el plan, y frenar. Las migraciones v72+ llevan su `ROLLBACK` comentado y van
   después de las 20 hs, con OK:
   - acompañantes VIP con fecha de nacimiento y excepción (D6 queda parametrizable);
   - confirmación del reparto de sillas por familia, con historial. Pasa la planilla de "Pendiente" a "Confirmado";
   - marca "avisar" explícita en `notas_operativas_contrato`;
   - plantilla del predio, en JSON versionado;
   - auditoría del sorteo: semilla, generador propio con test de reproducibilidad, quién y cuándo;
   - modelo del retiro de entradas, con D5, D7, D15 y D16;
   - RLS de `invitados`, antes de pasar la lista de la puerta, con RPC para `/lista` y `?buscar`. Requiere desplegar
     la web, con OK.
2. **Fase 3:** plano, sorteo por bloques (Normal) o entero (Técnica) y personalización del plano. La planilla suma la
   semilla y los bloques. Antes hacen falta las respuestas del jefe (preguntas de arriba).
3. **Fase 6:** entrega de entradas.
4. **Para diciembre:** los cinco pendientes de tótem y Recepción.

### Para seguir en otro chat, pegar

```text
Seguimos con el plan de mesas, plano y entradas de los masivos. Leé primero
docs/CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24.md (sección "Estado al 24-sep a la
noche y cómo seguir") y la memoria del proyecto. La planilla del sorteo ya está
hecha (08fb774). Seguimos por la Fase 2: presentame el plan (archivos,
migraciones v72+ con su ROLLBACK, riesgos) y frená. No se publica nada hasta
terminar el plan completo.
```

## Las fotos del jefe

Dos tomas del Canva "Plano Mesas Predio" (páginas 1 a 6) y el Excel de una división. El usuario las pasó por chat el
24-sep y quedaron en una carpeta temporal de esa sesión. Conviene exportar el Canva y guardarlo en
`C:\Users\lover\Desktop\COSAS\Desarrollo\PLANES JRe\`, junto a la spec, fuera del repo.

**El Excel tiene nombres reales:** no se copian a docs, ni a maquetas, ni a muestras.
