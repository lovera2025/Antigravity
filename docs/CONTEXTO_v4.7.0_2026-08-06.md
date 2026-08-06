# Contexto — Junior Eventos v4.7.0 (6 de agosto de 2026)

> **Referencia:** `CONTEXTO_v4.7.0` · `un cobro una fila` · `aviso antes de cerrar caja` · `hoja de cierre A4` · `consultas por sesión` · `ningún PDF con alto fijo`
> Si en un chat futuro decís *"leé el contexto de 4.7.0"*, *"lo de unificar los montos por alumno"*,
> *"la hoja que sale al cerrar caja"*, *"por qué el aviso muestra el cambio inicial"*
> o *"por qué ningún PDF usa alto fijo"*, apuntá a este archivo.

**Estado:** **CANDIDATO DE RELEASE GENERADO** — código completo, `flutter analyze`
sin errores (quedan advertencias históricas), **249 tests verdes**, build Windows
y Setup v4.7.0 generados. Solo queda la validación operativa manual de punta a
punta con datos reales.
**Rama:** `feature/v4.6-cierre-por-sesiones`

Release de **legibilidad y confianza en el papel de caja**: un cobro es una fila,
el operario ve cuánto tiene que contar antes de cerrar, y al cerrar le sale sola
una hoja A4 con el arqueo arriba y el detalle por alumno abajo.

**Migración mínima de base a v67.** No cambia columnas ni datos: crea el índice
`idx_pagos_contrato_sesion_caja` sobre `pagos_contrato_alumno(sesion_caja_id)` para
que las nuevas consultas por sesión escalen. Las columnas agregadas al `SELECT`,
`contrato_alumno_id` y `line_kind`, **ya existían**. La actualización desde 4.6.6
es segura; no se promete volver a instalar 4.6.6 sobre una base ya abierta por
4.7.0 porque el número de versión de SQLite queda en 67.

---

## Qué incluye este release (desde 4.6.6 → 4.7.0)

### 1. Un cobro es una fila, no cinco

**El problema.** Cierre de Caja mostraba **una fila por línea de pago** en los tres
lugares donde muestra movimientos: la lista `MOVIMIENTOS DE LA SESIÓN`, el detalle
de las tarjetas y los PDF. Un cobro de plan + mora escribe 4-5 registros en
`pagos_contrato_alumno`, así que el mismo alumno aparecía 4-5 veces con la misma
hora. Con 15 alumnos la lista era ilegible y el papel no entraba en ninguna hoja.

**La solución.** `agruparIngresosPorCobro`
(`lib/features/cierre_caja/services/cobro_agrupado.dart`, sin imports de Flutter
para que el test no necesite bindings). La fila pasa a ser:

```
DESCALZO, JONATHAN GABRIEL                             $ 37.100,00
17:54 hs · Efectivo · cuota base 4/9, int. mora Jul
```

Se da vuelta el orden: **el alumno es el título** y los conceptos el subtítulo,
porque la fila ya representa a una persona que pagó una vez, no a una línea del
plan. El contador de arriba a la derecha cuenta **cobros**, no líneas.

**Ventana de 10 segundos, no inventada.** Es el mismo umbral con el que
`getUltimosPagosLote` (`contratos_repository.dart:664`) ya define "el último lote"
de un contrato. Usar el mismo valor hace que la pantalla de caja y la reimpresión
de recibos coincidan en qué consideran un cobro. Un bucket por minuto partiría un
cobro que cruza 09:36:59,9 → 09:37:00,1; 2-3 minutos fusionaría un recobro genuino
del mismo alumno, que tiene que quedar aparte.

La ventana se mide contra **el primer registro del grupo**, no se encadena contra
el último. Por eso cobros a 0 s, 9 s y 18 s producen dos filas, no una sola fila de
18 segundos. Si el alumno hace otro pago real, aparece en otra fila.

**Clave = `contratoAlumnoId ?? nombre normalizado`.** Por eso se agregó
`p.contrato_alumno_id` al SELECT. Agrupar por nombre fusionaría dos alumnos
homónimos del mismo colegio —`nombre_alumno` es texto libre y en una cohorte
escolar los homónimos son normales— y eso pondría la plata de una familia en la
fila de otra, **en el papel con el que se cuenta la caja**.

**`resumenConceptos` clasifica, no parsea.** Los rótulos los generan
`ConceptoPagoDisplay` y `MoraConceptoRotulo`, así que las formas son conocidas:
`line_kind` cuando está (exacto) y las heurísticas de `pago_interes_mora.dart`
cuando es `null` (filas previas a la columna) — el mismo layering que ya usa
`moraCobradaDelPeriodoVigente`. Cuenta cuotas con un regex que acepta el **guion
largo U+2013** de `Cuotas Base (1–3/9)`, comprime meses de mora consecutivos a
`May–Jul`, y topea en 3 fragmentos + `+N más`. Nunca devuelve vacío.

### 2. Un cobro mixto es una fila, y el medio no está en la clave

**El problema conceptual.** La lista principal mezcla efectivo y transferencia en
una columna; las tarjetas muestran un medio cada una. Si el medio formara parte de
la identidad del grupo, un cobro mixto daría **dos filas en la lista principal**,
que es justo lo que se quiere evitar.

**La solución.** El medio **no** va en la clave. Cada grupo lleva su desglose
(`montoEfectivo` / `montoTransferencia`) y `parte(transferencia:)` proyecta la
porción de un medio. De ahí salen las dos vistas sin contradecirse:

- **lista principal**: una fila con el **total**, ícono y color propios
  (cian `0xFF00A8CC` + `Icons.call_split_rounded`, distinto de los cinco colores ya
  en uso), la palabra `MIXTO`, y una **tercera línea solo en las filas mixtas** con
  `$ X efectivo + $ Y transferencia`. Las filas normales siguen de dos líneas.
- **cada tarjeta y el papel**: `grupo.parte(...)`, o sea **solo su parte** de ese
  medio, con `(mixto)` atrás del nombre (un `*` en el PDF, con nota al pie).

Sin el `(mixto)`, alguien vería $20.000 en EFECTIVO y $37.100 en el recibo del
alumno sin entender por qué. Y si la tarjeta mostrara el total, la suma de las
filas dejaría de dar el bruto del bucket: el papel serviría para contar mal.

**`parteDeMixto` es un campo, no un getter.** Después de proyectar, las líneas son
de un solo medio y `esMixto` daría `false`; sin guardarlo, el rótulo sería
imposible de mostrar.

### 3. Cerrar caja avisa cuánto hay que contar

**El problema.** Se tocaba "Cerrar caja" y se abría directo el arqueo. La caja
quedaba cerrada sin que nadie hubiera visto cuánto efectivo y cuánta transferencia
debería haber, y sin ningún comprobante impreso.

**La solución.** Un aviso previo, **solo para el operario** (el jefe cierra igual
que antes):

```
¿Cerrar la caja?
Revisá los totales antes de confirmar.

EFECTIVO                                  $ 314.100,00
   cambio inicial                 $  20.000,00
   cobrado en efectivo            $ 294.100,00
   retiros / gastos               −$        0,00

TRANSFERENCIA                             $       0,00
```

**El total de EFECTIVO es `cambioInicial + efectivoNeto`**, la misma fórmula que
`_ticketCajaBloqueCierreSesion` (`pdf_service.dart`) usa para el "Efectivo esperado
en caja" y contra la que se compara el arqueo. Con el bruto cobrado en su lugar, el
operario contaría contra un número que no incluye su cambio inicial ni descuenta
los retiros, y **el arqueo daría diferencia siempre**: el aviso empeoraría las
cosas en vez de arreglarlas.

Los dos medios van parejos, cada uno con su desglose. Ninguno se rotula como que no
hace falta revisarlo: el efectivo se cuenta con los billetes y la transferencia se
coteja contra el banco.

**El arqueo sigue siendo opcional**, igual que antes.

### 4. Los dos pasos viven en un solo diálogo (y por qué importa)

**El detalle crítico.** Los tres botones que abren el cierre
(`dashboard_screen.dart:1227, 1423, 1527`) hacen `Navigator.pop(context)` para
cerrar el drawer y **después** llaman a `showCerrarCajaDialog` con ese mismo
context. Hoy funciona porque el `showDialog` sale en el mismo tick.

Si el aviso previo se hubiera hecho con un segundo `showDialog` en cadena —o con
cualquier `await` antes del primero, como cargar los totales— ese context ya
estaría desmontado y **el diálogo no aparecería: la caja no se cerraría y nadie
sabría por qué**.

Por eso `showCerrarCajaDialog` **mantiene su firma** (cero call sites tocados) y
maneja los dos pasos con estado interno (`_Paso.aviso` → `_Paso.arqueo`). Los
totales cargan **dentro** del diálogo con `addPostFrameCallback`, el mismo patrón
que ya usaba `_loadTotal()`: el aviso se dibuja enseguida y los números aterrizan
cuando llegan.

**Cerrar la caja nunca se bloquea.** Si la consulta de totales falla, el aviso sale
con "No se pudieron calcular los totales" y el botón de confirmar **sigue
habilitado**. Dejar a un operario atrapado al final de su turno es peor que el
fallo que se estaría evitando.

### 5. La hoja de cierre: un A4, mitad arqueo y mitad detalle

**El problema.** El PDF de sesión existía pero era un botón manual en otra
pantalla, y su tabla de ingresos imprimía una fila por línea con el concepto
truncado a 22 caracteres (`"Interés mora cuotas 2,…"`).

**La solución.** `PdfService.generarHojaCierreSesionPdf`: **un archivo, una
ventana, una hoja**. Arriba el resumen y el arqueo (lo que se firma), abajo el
detalle nominal por alumno (lo que se coteja contra la plata).

**Las dos mitades no repiten información** — es lo que hace realista el 50/50. La
mitad de arriba **no** lleva las tablas de ingresos/retiros del ticket viejo: el
detalle es la mitad de abajo.

**El pie dice `HOJA A4 COMPLETA · NO CORTAR`.** No es decorativo: todos los demás
papeles de esta app son de media A4 para cortar dos por hoja (`_mediaA4`), así que
el reflejo aprendido es cortar — y el corte caería justo en la línea divisoria,
partiendo el arqueo del detalle. Es la única línea que no se compacta en ningún
escalón. El mismo aviso aparece en el paso de arqueo, arriba del botón rojo, que es
el momento en que la persona está por apretar lo que dispara la impresión.

**Con la sesión todavía abierta** la hoja sale igual pero no miente: dice
`CAJA EN CURSO — no es el cierre`, `sesión aún abierta` y arqueo pendiente. Sirve
para un control a mitad de turno. Nombre de archivo `Caja_en_curso_…`.

**La invariante que evita que la hoja se contradiga consigo misma:** las dos
mitades reciben **el mismo `DatosCierreSesion`** y el arqueo usa
`datos.efectivoNeto`, no un neto recalculado aparte. En el código de 4.6.6 había
tres cálculos independientes de neto; un papel que existe para cotejar plata no
puede tener dos números distintos para lo mismo. Va con test.

### 6. El algoritmo que hace entrar el 100% de la info

Dos garantías duras, en este orden:

1. **No se pierde ni un dato.** Nunca se recorta una fila, nunca se dice "y N más".
2. **Nunca hay hoja 2.** Es una sola `pw.Page`: no existe paginación.

Y una tercera, más débil: **la hoja mide exactamente una A4**. Si un caso extremo
no lo lograra, cede *esta* —la hoja se estira y el visor la escala al imprimir— y
nunca las dos de arriba. El orden de sacrificio importa: mejor una hoja un poco
escalada que un nombre que desapareció.

**Formato: alto libre con piso de A4**, no A4 fija:
`PdfPageFormat(a4.width, double.infinity)` + `ConstrainedBox(minHeight: a4.height)`.
El mismo patrón de los recibos. Con alto fijo, lo que no entrara se recortaría en
silencio.

**El divisor flota.** El resumen es de tamaño casi fijo, así que se lo topea en la
mitad con `_ajustarParaEntrar` y **el detalle recibe todo lo que sobra**: la mitad,
o más. Un día normal el resumen ocupa menos de su mitad y el detalle se queda con
~55-60%. Con pocos movimientos sobra hoja abajo, y eso es lo esperado: el detalle
va llenando ese espacio a medida que crece el día.

**Escalada del detalle** (`_ajustarDetalleMedios`), de menos a más invasiva:

| # | Col. | Escalón | Qué cede | Capacidad aprox. |
|---|---|---|---|---|
| 1-4 | 1 | 0-3 | aire, después el subtítulo de conceptos | ~15-25 cobros |
| 5-9 | **2** | 2-6 | ancho por fila | ~50-70 |
| 10-12 | **3** | 4-6 | más ancho | ~105 |
| 13 | 3 | piso 6 pt | letra chica de verdad | ~130+ |

**Columnas antes que letra chica**, al revés del orden habitual de `AjustePdf`
("abreviar antes que achicar"). Es deliberado: estas filas son cortas (hora +
nombre + monto), así que dos columnas a tamaño completo se leen mejor que una
columna al 76%. Acá lo que falta es **alto**, no ancho.

**El subtítulo de conceptos se ata a `ajuste.subtextos`**, así el escalón 2 lo saca
solo — es lo único de la fila que es contexto y no plata. **Lo único que se abrevia
es el nombre**, con `_pdfCierreTrunc`, y solo de 2 columnas en adelante. Hora y
monto no se tocan en ningún escalón.

**Mediciones acotadas.** Cada medición es un `doc.save()` completo. Arrancar
siempre del escalón 0 haría 13 documentos para una sesión grande, y el cierre
esperaría por impaciencia del código. `_pasoInicialDetalle` estima el escalón por
cantidad de filas y arranca **uno antes** para no compactar de gancho; un día
normal mide 1-2 veces.

### 7. Los papeles salen solos al cerrar, sin condicionar el logout

**El riesgo.** `cerrarSesionCaja` desloguea al operario y limpia `AppRoleState` al
final. Generar el PDF **adentro** del provider, antes del `logout()`, sería un
error: `_verPdfEnWindows` cae a `Printing.layoutPdf` ante cualquier excepción, y
ese `await` no termina hasta que un humano cierre el diálogo del sistema. Dejaría
la caja cerrada con el operario todavía logueado — justo el medio-estado que se
quiere evitar, y `try/catch` no ayuda porque no hay excepción, solo no completa.

**La solución.** `cerrarSesionCaja` y `cerrarCajaJefe` devuelven
`CierreCajaResultado { cerrada, sincronizado }`. `sesRepo.cerrar()` ya devolvía la
sesión cerrada con su `cerradaAt`, así que es gratis. El orden interno del provider
no se toca (`_stopHeartbeat` sigue **antes** de `cerrar`: moverlo después dejaría un
latido cayendo sobre una sesión cerrada).

Orden en `_confirmar()`:

1. capturar los repos en locales **antes** de llamar al provider;
2. cerrar;
3. **snackbar de offline primero** si no sincronizó — el visor de PDF roba el foco,
   así que lo que se encole después queda detrás de esa ventana;
4. `emitirPapelesDeCierre(...).timeout(45 s)` en try/catch;
5. `Navigator.pop`.

**Si el papel falla, el mensaje dice la verdad.** El operario queda deslogueado y
**no puede** volver a Cierre de Caja a reimprimir. Tampoco se afirma que el archivo
se guardó si la generación falló antes de escribirlo: el mensaje informa que la
caja sí quedó cerrada y le pide al operario que solicite al jefe regenerar la hoja
desde Cierre de Caja.

Antes de confirmar, el diálogo avisa exactamente qué va a ocurrir: al cerrar se
abre el PDF y el operario debe imprimir **ese documento** en una hoja A4 completa.
No se manda directo a la impresora; queda disponible el visor para imprimir o
guardar.

**Acceso manual:** el botón de PDF pasa a ser el menú **PAPELES** con dos entradas:
*Hoja de cierre* (habilitada con cualquier sesión seleccionada, incluso sin
movimientos) y *Ticket detallado* (requiere movimientos y conserva el
`_exportarPdf` de siempre, con su rótulo dinámico como subtítulo). Dos entradas en
vez de un tercer botón: la barra tiene lugar para dos y un tercero dejaría los
rótulos ilegibles en pantallas angostas.

### 8. Las consultas piden la sesión, no toda la historia

**El problema, que estaba desde antes.** Para mostrar **una** sesión, el código
cargaba **toda la historia de la base**: `obtenerIngresosDetallados()` corría tres
queries con JOIN **sin filtro** —todos los pagos de contratos, todas las
transacciones, todos los pagos de alquiler, de siempre— y `getEgresosConEvento()`
traía todos los egresos. Recién después se descartaba en Dart lo que no era de la
sesión. La lentitud crecía con **los años del negocio**, no con el tamaño de la
sesión.

**La solución.** Dos métodos nuevos y aditivos (ninguno existente se toca, así que
Finanzas no se entera): `obtenerIngresosDeSesiones(Set<String>)` y
`getEgresosDeSesiones(Set<String>)`, con `WHERE sesion_caja_id IN (...)`.

La migración v67 agrega el índice sobre `pagos_contrato_alumno.sesion_caja_id`:
sin él, el filtro era correcto pero seguía recorriendo todos los pagos; con él, el
costo queda ligado a las sesiones pedidas.

**Solo el bloque "Masivo", y con eso alcanza.** `transacciones` y
`pagos_prestamo_alquiler` **no tienen columna `sesion_caja_id`**
(`local_database.dart:168-181` y `465-479`), así que nunca pudieron pertenecer a
una sesión de caja. Traerlos para después descartarlos era trabajo al vacío.

**El modo "sin sesiones" queda con las consultas viejas.** Es la vista de
diagnóstico del jefe sobre cobros de builds anteriores que quedaron sin id; ahí
traer todo y filtrar por rango horario AR es lo que corresponde, porque justamente
no hay id por el que filtrar. Un operario no pisa ese camino nunca.

### 9. Un solo lugar decide qué es transferencia, y un solo lugar carga los datos

`esTransferenciaCaja(String?)`
(`lib/features/cierre_caja/models/medio_pago_caja.dart`) — la regla estaba
retipeada en cinco lugares. Semántica **sin cambios**: transferencia es solo lo
rotulado `'transferencia'`; `null`, `''`, `'Efectivo'` y `'Mercado Pago'` cuentan
como efectivo. "Mejorarla" movería plata de un bucket al otro.

`medioPagoLabel(String?)` normaliza para mostrar: la base tiene `'Efectivo'` y
`'efectivo'` según por dónde entró el pago (el modal de cobro capitaliza, el de
retiro no).

`cargarDatosCierreSesion` + `DatosCierreSesion`
(`lib/features/cierre_caja/services/datos_cierre_sesion.dart`) — cuerpo levantado
del loop de `_refrescar`, que pasa a ser su primer consumidor. Es lo que permite
que el aviso previo y los papeles funcionen **después** del logout: no pueden leer
`cierreCajaProvider`, porque cuando el rol es caja `_refrescar` deriva todo de
`appRole.sesionActiva` y post-logout devuelve un turno vacío.

`turnoDeSesion` sube de privado del provider a público en `turno_caja.dart`: los
papeles lo necesitan cuando ya no hay estado de pantalla.

### 10. Las fuentes de los PDF no se bajan en el peor momento

**El problema.** Los 15 PDF cargan las fuentes con `PdfGoogleFonts`, que sin caché
hace un `http.get` **sin timeout**. En un salón con wifi que no sale a internet
—portal cautivo, el caso típico de un evento— son ~20 segundos por fuente antes de
caer a Helvetica. Pagado en el cierre, con la plata en la mano, se vive como que el
programa se colgó; y la hoja mide el documento varias veces contra la escalera, así
que la espera se repite.

**La solución definitiva.** `Outfit-Regular.ttf` y `Outfit-Bold.ttf` están
incluidas en `assets/google_fonts/`, declaradas en `pubspec.yaml` y empaquetadas
en el build. `PdfGoogleFonts` encuentra esos assets antes de intentar la red, por
lo que los PDF que usan Outfit regular/negrita ya no dependen de internet.
`PdfService.precalentarFuentes()` se mantiene en el `SplashScreen`, sin `await` e
idempotente, pero ahora precalienta recursos locales. Un test carga ambos archivos
desde `rootBundle` para evitar que una edición futura los deje afuera del build.

### 11. El comprobante de anulación ya no recorta el motivo

**El problema.** `compartirComprobanteAnulacionCobro` era el **único** `pw.Page` con
alto **fijo** de toda la app. Como el motivo de anulación es texto libre y un
`pw.Spacer` empujaba el pie al fondo de la hoja, el motivo se truncaba a **400
caracteres** con `…` para que el pie no se cayera afuera. O sea: parte de la
explicación que se le manda al cliente se perdía.

**La solución.** Alto libre + `ConstrainedBox(minHeight: a4.height)` +
`_ajustarParaEntrar`, el patrón de los recibos. El motivo va **completo** y la hoja
crece si hace falta. El `pw.Spacer` se reemplazó por un `SizedBox` (un Spacer sin
límite superior rompe el layout con alto libre) y `_truncar` se eliminó al quedar
sin uso.

### 12. La regla que evita que esto vuelva

Documentada arriba de `_ajustarParaEntrar`, que es donde la va a leer el próximo
que agregue un papel:

> **Ningún PDF de esta app usa `pw.Page` con alto fijo.** Es la única forma de
> perder datos en silencio. Las dos formas permitidas son `pw.MultiPage` (se
> desparrama en hojas, nunca recorta) o `PdfPageFormat(width, double.infinity)` +
> `ConstrainedBox(minHeight: …)` + `_ajustarParaEntrar` (entra, y si no entra
> crece).

`_ajustarParaPaginas` ahora acepta `margin` y `pageFormat` con default. Medir con
márgenes distintos a los de impresión da un lugar disponible que no existe, y la
escalera elegiría un nivel que en la hoja real no entra.

---

## Archivos tocados

**Nuevos**

| Archivo | Qué es |
|---|---|
| `lib/features/cierre_caja/models/medio_pago_caja.dart` | La regla única de qué es transferencia + rótulo normalizado |
| `lib/features/cierre_caja/services/cobro_agrupado.dart` | `CobroAgrupado`, `agruparIngresosPorCobro`, `cobrosDeMedio`, el resumen de conceptos |
| `lib/features/cierre_caja/services/datos_cierre_sesion.dart` | `DatosCierreSesion` + `cargarDatosCierreSesion` |
| `lib/features/cierre_caja/services/papeles_cierre_sesion.dart` | `emitirPapelesDeCierre` |
| `assets/google_fonts/Outfit-Regular.ttf` | Fuente regular local para los PDF |
| `assets/google_fonts/Outfit-Bold.ttf` | Fuente negrita local para los PDF |
| `assets/google_fonts/OFL.txt` | Licencia SIL Open Font License de Outfit |
| `test/cobro_agrupado_test.dart` | 13 casos, incluida la ventana no encadenada y la invariante de suma |
| `test/hoja_cierre_sesion_medida_test.dart` | 10 casos, garantías de datos de la hoja |
| `test/pdf_assets_test.dart` | Verifica que las dos fuentes se empaqueten como assets |

**Modificados**

- `lib/features/cierre_caja/cierre_caja_screen.dart` — filas unificadas, rama mixto,
  contador por cobros, menú PAPELES, `_exportarHojaCierre`
- `lib/features/cierre_caja/providers/cierre_caja_provider.dart` — `_refrescar` pasa
  a consumir `cargarDatosCierreSesion`; se va `_turnoDeSesion`
- `lib/features/cierre_caja/models/turno_caja.dart` — `turnoDeSesion` público
- `lib/features/caja_sesiones/providers/app_role_provider.dart` —
  `CierreCajaResultado`
- `lib/features/caja_sesiones/widgets/cerrar_caja_dialog.dart` — reescrito: dos
  pasos, aviso con totales, aviso de hoja A4, emisión del papel
- `lib/features/common/services/pdf_service.dart` — `generarHojaCierreSesionPdf` y
  su familia de helpers, `precalentarFuentes`, fix de la anulación,
  `_ajustarParaPaginas` parametrizado, la regla documentada
- `lib/features/mi_empresa/repositories/finanzas_repository.dart` — dos columnas al
  SELECT Masivo + `obtenerIngresosDeSesiones`
- `lib/features/mi_empresa/models/ingreso_detallado.dart` — `contratoAlumnoId`,
  `lineKind`
- `lib/features/egresos/repositories/egresos_repository.dart` —
  `getEgresosDeSesiones` + `_conEventoAnidado` extraído
- `lib/features/splash/splash_screen.dart` — precalentado de fuentes
- `lib/core/database/local_database.dart` — migración v67 e índice por sesión
- `pubspec.yaml` — versión `4.7.0+34` y fuentes locales
- `installer.iss`, `installer/junior_eventos.iss`,
  `installer/junior_eventos_setup.iss` — versión de Setup 4.7.0

**Tests.** 249 verdes. Los que más valen: *"la suma de los grupos es la suma de los
ingresos"* (protege la plata ante cualquier cambio de la agrupación), *"las partes
por medio suman los brutos de cada bucket"* (si falla, la tarjeta y la lista se
contradicen), la ventana no encadenada y la presencia de las fuentes locales.

---

## Verificación final

Automatizada el 6-ago-2026:

- `flutter test`: **249 tests verdes**.
- `flutter analyze lib test`: **sin errores**; conserva 97 advertencias/info
  históricas fuera del alcance funcional de este release.
- `flutter build windows --release --no-pub`: correcto. Ejecutable
  `build/windows/x64/runner/Release/arguello_events.exe`, versión `4.7.0+34`,
  SHA-256 `D87E59CB0C49F7FEE89C9AD4947CCFE56BB72C601FC586F2866FE185B44361C2`.
- Inno Setup 6.7.1: correcto. Instalador
  `installer/dist/Setup Junior Eventos v4.7.0.exe`, versión `4.7.0`, SHA-256
  `4F17EBA537943F48CCE3B18DC26901EDBBB0F26B8B976C0213CCD3A896FEB4BC`.
- Ambos TTF están presentes en `flutter_assets/assets/google_fonts/` dentro del
  build Windows.

### Verificación pendiente en la app real

Ya verificado el 6-ago con `flutter run -d windows`: las filas unificadas, el
resumen de conceptos, el contador por cobros, los montos que cierran en los tres
lugares (filas = tarjeta = TOTAL NETO del papel), el `Efectivo esperado` =
cambio inicial + neto, una sola hoja, y **la reimpresión de una sesión ya cerrada
desde el menú PAPELES** — que es lo que hace verdadero el mensaje de error del
cierre.

Falta:

1. **El cierre automático de punta a punta** — abrir caja de operario, cobrar,
   cerrar: tiene que salir el aviso con los dos totales, después el arqueo, y la
   hoja sola en una ventana. Después de eso el operario queda en `RoleGateScreen`.
2. **Los totales después del refactor** — el tramo que movió el cálculo a
   `datos_cierre_sesion.dart` es refactor puro y el menos visible de todos: anotar
   los 9 totales de una sesión real y compararlos. Cualquier diferencia es un bug
   introducido.
3. **Volumen** — cobrar a ~40 alumnos en una sesión y sacar la hoja: una sola hoja,
   los 40 nombres, y que se lea.
4. **Un cobro mixto** — una fila en la lista con el desglose, y su parte en cada
   tarjeta. En las capturas del 6-ago no había ninguno.
5. **Cierre sin red** — el aviso naranja de sync tiene que aparecer **antes** del
   papel, y el operario terminar deslogueado igual.
6. **Anulación con motivo largo** — 3-4 párrafos: el texto tiene que salir entero.

---

## Lo que quedó afuera a propósito

Ninguna de las dos pierde datos; las dos piden cirugía dentro de generadores de
400+ líneas para pasar `AjustePdf` por cada tamaño de letra, y apurar eso es cómo
se rompen los recibos de las familias.

- **`generarEstadoCuentaAlumno`** — es `MultiPage`, así que los datos siempre salen
  completos, pero le falta la escalera: un alumno con 9 cuotas + mora + mesas
  imprime 3-4 hojas donde entrarían 1-2. El prerequisito ya está hecho
  (`_ajustarParaPaginas` acepta el margen; el real es `fromLTRB(24,22,24,22)`).
- **Escalones de dos columnas para `generarReciboAlumno` y
  `generarResumenAbonarAlumno`** — ya tienen alto libre + escalera y nunca
  recortan. El límite es que con planes de 12 cuotas + mora de varios meses la hoja
  **crece** y deja de ser media A4 cortable en dos.

---

## Versiones

| Fecha | Versión | Notas |
|-------|---------|--------|
| 27-jul-2026 | 4.6.1+28 | Operario edita base + aviso abrir caja |
| 31-jul-2026 | 4.6.2+29 | Papeles: mora fuera de término, sin redundancias |
| 4-ago-2026 | 4.6.6+33 | Autocierre de caja, cobro sin sesión imposible, mora parcial, PDFs que entran |
| **6-ago-2026** | **4.7.0+34 (candidato generado)** | **Un cobro una fila, aviso antes de cerrar, hoja de cierre A4, consultas por sesión** |

## Contextos relacionados

- `docs/CONTEXTO_v4.6.6_2026-08-04.md` (autocierre, escalera de `AjustePdf`)
- `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md` (modelo de sesiones)
- `docs/CONTEXTO_MORA_OPERATIVA.md` (rótulos de mora que lee el resumen de conceptos)
