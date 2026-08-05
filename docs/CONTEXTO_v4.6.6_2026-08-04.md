# Contexto — Junior Eventos v4.6.6 (4 de agosto de 2026)

> **Referencia:** `CONTEXTO_v4.6.6` · `release 4.6.6` · `autocierre caja jefe` · `caja abierta en otra PC` · `mora parcial` · `PDFs que entran en la hoja`
> Si en un chat futuro decís *"leé el contexto de 4.6.6"*, *"lo del autocierre de caja"*,
> *"por qué la mora parcial mostraba el total"* o *"lo del papel que no entraba"*,
> apuntá a este archivo.

**Estado:** **RELEASE** — `4.6.6+33`
**Instalador:** `Setup Junior Eventos v4.6.6.exe` (`installer/dist/` vía `.\installer\build_installer.ps1`)
**Rama:** `feature/v4.6-cierre-por-sesiones`

Release de **confiabilidad**: sesiones de caja que no quedan colgadas, papeles que
dicen lo que se cobra y papeles que entran en la hoja.

**Sin migración de base.** `_version` sigue en **66**: no se agregan, renombran ni
borran columnas. Se puede reinstalar el build anterior encima y la base sigue
funcionando — no hay camino de ida.

---

## Qué incluye este release (desde 4.6.5 → 4.6.6)

### 1. La caja del jefe se autocierra al cambiar el día

**El problema.** El único corte por cambio de día vivía dentro de
`ensureSesionModoJefe()` y se disparaba **solo al cobrar**. Consecuencias:

- Si el jefe cobraba un día y no volvía a cobrar, esa sesión quedaba
  `cerrada_at IS NULL` **para siempre**: el cierre de ese día no tenía hora de
  cierre ni arqueo.
- Con la app abierta pasada la medianoche, el latido seguía publicando la sesión
  de ayer como abierta: el chip mentía y el cierre de hoy no listaba nada
  (`sesionesDelDia` filtra por `abierta_at`).
- El botón **Cerrar caja** opera sobre `state.sesionActiva`, así que al día
  siguiente cerraba la sesión de ayer **sellándola con la hora de hoy**,
  ensuciando el cierre de ayer.

**La solución.** Autocierre sellado a las **23:59:59 de su propio día**, no a la
hora en que se detecta. Ese sello es lo que hace que no importe cuándo se
detecte: con la app cerrada no corre nada, así que el cierre ocurre recién al
volver a abrir, pero queda registrado en el día que corresponde — se abra al otro
día o tres días después.

Corre al arrancar la app, al volver del segundo plano y en cada latido (60 s), y
**en cualquier dispositivo**: la PC del operario que abre a la mañana cierra la
caja que el jefe dejó abierta anoche, y el UPDATE sube para todos.

Iniciar sesión como jefe **no abre caja**. La caja se abre al cobrar (o con el
botón manual "Iniciar caja").

**Detalle crítico:** `cerrada_at` se sella en el pasado, pero `updated_at` y
`last_heartbeat` quedan en el instante real. El motor de sync usa `updated_at`
como watermark: sellarlo en el pasado dejaría el UPDATE sin subir nunca.

### 2. El jefe cobra desde cualquier máquina (y por qué no necesita bloqueo)

Asimetría deliberada, no un permiso extra:

- El **operario** tiene una caja **por dispositivo**: declara un cambio inicial en
  la PC donde va a trabajar. Dos PCs son dos cajas físicas distintas → conflicto
  real → aviso (punto 4).
- El **jefe** tiene una caja **por día**, no por máquina. `ensureSesionModoJefe()`
  reutiliza la sesión abierta del día sin mirar `device_id`, así que cobrar desde
  el salón y desde la oficina converge en **la misma sesión**.

**Hueco tapado:** si la segunda PC está sin red, no ve la sesión del jefe y crea
una segunda; el índice único remoto rechaza una **en silencio**. Ahora
`sesionAbiertaDeOperador` ordena `abierta_at ASC, id ASC` (antes `DESC LIMIT 1`),
así que **todos los dispositivos eligen la misma** apenas sincronizan, y
`consolidarSesionesDuplicadas` cierra la sobrante — solo si no da señales, para no
sacarle la caja de abajo a alguien que la está usando.

### 3. Nunca más un cobro sin sesión

**El agujero más grave del release.** `sesionCajaIdParaCobro()` devolvía `null`
en silencio cuando el rol era caja sin sesión activa, y `registrarPago` **omitía
la columna**: el pago se guardaba **sin `sesion_caja_id`** y no aparecía en el
cierre de nadie — caía en la vista "Sin sesiones". Es la causa de que "lo de Maxi
o Juan no cierre".

Ahora lanza `SinCajaAbiertaException` y el modal lo frena con *"No hay caja
abierta. Abrí tu caja antes de cobrar"*, liberando el botón de confirmar.

Frenar es preferible a guardar huérfano: un cobro huérfano no se detecta hasta el
arqueo, y para entonces ya no se sabe de quién era.

**Los pagos que ya quedaron sin sesión no se reasignan** (decisión explícita). Lo
que cambia es que de acá en adelante no se pueden generar más.

### 4. Caja abierta en otra PC: informar sin acusar

El índice único `idx_sesiones_caja_operador_unica_abierta` es **por dispositivo**
(cada PC tiene su SQLite), así que dos PCs pueden abrir la misma caja y las dos
pasan el chequeo local.

Antes de abrir se hace pull (`refreshBeforeOpen()`, 3 reintentos) y se mira
`device_id` + antigüedad del latido. **El umbral se deriva del período del
latido, no se elige a dedo:** el latido se publica cada 60 s, así que una caja
realmente en uso **nunca** puede tener un latido de más de ~70 s.

| Antigüedad del latido | Qué se sabe | Qué dice | Botón por defecto |
|---|---|---|---|
| < 90 s | Otra PC lo está usando **ahora** | "La caja de Maxi está en uso en `pc-…` · último movimiento hace 40 s" | Cancelar |
| 90 s – 5 min | **No se sabe** | "Figura una caja abierta que dejó de dar señales hace 3 min" | Abrir acá |
| > 5 min | Quedó abierta sin cerrar | "Quedó una caja sin cerrar · sin señales hace 2 h" | Tomar la caja acá |

**Un latido de 3 minutos NO significa "abierta en otra PC"** — significa que hay
una fila abierta que nadie está tocando. El programa no puede distinguir una PC
apagada de una que cerró sin red, así que **no afirma ninguna de las dos**: dice
lo único que le consta y deja pasar.

**Nunca es una puerta cerrada.** Siempre hay salida en dos clics como máximo,
porque hay al menos tres caminos por los que el dato remoto puede estar viejo:

- **Cierre sin red** — `flushBestEffort()` no lanza si no hay conexión.
- **Reloj desfasado** — el latido se escribe con el reloj de la otra PC.
  Antigüedades negativas se tratan como cero.
- **`device_id` regenerado** — tras reinstalar, la misma PC se ve como otra.

Sin conectividad **no bloquea**: avisa que no pudo verificar y deja abrir. El
índice remoto sigue siendo el backstop.

### 5. El cierre sin red avisa en el momento

Pieza que hace coherente a todo lo anterior. `cerrarSesionCaja` terminaba en
`flushBestEffort()`, que **se traga cualquier error**: el operario cerraba sin
internet, la app decía "caja cerrada" como si todo hubiera salido bien, y el
problema aparecía horas después en otra PC **desconectado de su causa**. Eso es
lo que se vive como bug del programa.

Ahora `cerrarSesionCaja` / `cerrarCajaJefe` devuelven si el cierre **realmente**
llegó al servidor (`flushConfirmandoSesion` pregunta si quedó algo suyo en la
cola — `flushPending` nunca lanza, así que preguntarle a la cola es la única
forma honesta de saberlo) y el diálogo avisa:

> Caja cerrada. **No se pudo avisar al servidor** (sin conexión) — se sincroniza
> sola cuando vuelva internet. Hasta entonces, en otra PC puede figurar abierta.

Con eso, el aviso posterior en la otra PC **confirma** lo que le dijeron en vez de
contradecirlo.

### 6. Corte de día y marca de cierre para operarios

Mismo autocierre que el jefe, con nota `'Cierre automático por cambio de día ·
sin arqueo'`. Enganchado en `loginCaja`: al quedar sin sesión activa, el flujo que
**ya existía** en `RoleGateScreen` dispara solo el diálogo "Abrir caja" y el
operario declara su cambio inicial del día. Sin pasos nuevos que aprender.

En el **cierre de caja**, las sesiones cerradas por el sistema se marcan
`⚠ cerrada automáticamente · sin arqueo` en pantalla y `auto s/arq` en la columna
Dif. del PDF. El jefe distingue de un vistazo quién cerró como corresponde y
quién se fue sin cerrar, **sin que se pierda ni un cobro**.

También: si la caja se cierra desde otra PC, el latido lo detecta en ≤60 s, suelta
la sesión y vuelve al gate.

> **Criterio de aceptación:** el operario que trabaja bien **no nota ninguna
> diferencia**. Toda la fricción que se agrega aparece únicamente en las tres
> situaciones que hoy ensucian los datos.

### 7. El pago parcial de mora muestra lo parcial

**El problema.** Mora $45.000, la familia entrega $15.000 → el desglose del modal
y el PDF listaban las líneas por su importe **completo**. Causa raíz: la
reconciliación contra el monto realmente cobrado solo corregía diferencias de
hasta **$0,05** (redondeo), así que un parcial de miles pasaba de largo.

Lo que se **guardaba** ya era correcto — por eso al reimprimir desde el historial
salía bien. El error era de **presentación en el momento del cobro**, y
contaminaba tres salidas: desglose del modal, "RESUMEN A ABONAR" y recibo de
confirmación.

**La solución.** `MoraConceptoRotulo.repartirMoraParcial` reparte el monto entre
las cuotas involucradas, espejando el orden con que el libro mayor descuenta el
saldo (`postCobroTrackedOffset`): si el pago entra entero en el arrastre va todo
ahí; si no, primero las cuotas vencidas del calendario (de la más vieja a la más
nueva) y el resto al arrastre.

- **Es no-op si lo cobrado alcanza para todo** → un cobro de mora completa y las
  reimpresiones históricas salen **exactamente igual que antes**.
- La cuota cubierta a medias lleva sufijo **`(parcial)`**.
- Se conservan `moraDebida`, `diasMora`, `vencimiento` y `fechaPagoCuota` al
  recortar: son los que explican **cuánto se debía**, y si se recortaran el recibo
  diría que solo se debía lo parcial.
- Se corrige también el **rótulo persistido**: un parcial sobre las cuotas 3 y 5
  se guardaba como *"Interés mora cuotas 3, 5"* aunque solo se hubiera cubierto la 3.

**Límite honesto:** `postCobroTrackedOffset` tiene una rama (cuando el cobro además
liquida cuotas base) que no reparte nada, solo netea totales. Ahí el libro mayor
no dice *a qué cuota* se imputó, así que la regla es la mejor aproximación
disponible, no una copia. Lo que sí queda garantizado siempre: **las líneas suman
exactamente lo cobrado y el pendiente coincide con el saldo de la ficha.**

**Dónde se nota, con precisión:**

| Superficie | Cambia |
|---|---|
| Mora pendiente en grilla / ficha / cronograma | **No** |
| Lista de checks de mora del modal | **No** (muestra la mora completa: es lo que se está por elegir) |
| Desglose del modal, mora **completa** | **No** |
| Desglose del modal, mora **parcial** | **Sí** — es el bug |
| Resumen PDF y recibo de confirmación | **Sí** en el parcial |
| Reimpresión de recibos históricos | Casi nunca |

> Regla corta: **lo que se debe se sigue leyendo igual en todos lados; lo que
> cambia es cuánto dice que se está pagando, y solo cuando el pago es parcial.**

### 8. Los PDFs se compactan hasta entrar en la hoja

**El problema.** El "RESUMEN A ABONAR" era `pw.Page` con **A4 fijo**, sin paginar
y sin escalar. Lo que no entraba en los 842 pt **se caía del MediaBox sin error ni
aviso**. Como el total va al final del layout, lo primero que desaparecía era
**TOTAL A PAGAR AHORA** y **CÓMO QUEDA LA CUENTA**: el papel podía salir con el
detalle de conceptos **y sin el total**.

**La solución: medir, no adivinar.** Con alto libre el motor recorta la página al
alto real del contenido, así que esa altura **es** la medida
(`PdfService._medirAlto`). Se sube por una escalera de compactación y se usa el
**primer** nivel con el que entra.

> **Abreviar antes que achicar.** La letra chica es el último recurso.

| Nivel | Qué hace |
|---|---|
| 0 | Nada — el papel de siempre |
| 1 | Comprime espaciados y márgenes |
| 2 | Saca los subtextos auxiliares (`nom. $X`, explicaciones del arrastre) |
| 3 | Abrevia rótulos (`Cuota 3 de 9 — venció 31/05/2026` → `Cuota 3/9 · vto 31/05`) |
| 4–6 | Recién acá achica la tipografía, con piso de **7 pt** (6,5 en subtextos) |

**Objetivos:**

- **Resumen a abonar** y **recibo** → media A4 (dos por hoja).
- **Ticket de cierre de caja** → como es `MultiPage`, "que entre" significa **una
  sola página**: se mide la cantidad de páginas (`_ajustarParaPaginas`). Si ni así
  entra, se queda con el nivel que menos páginas usó — seguir apretando solo
  empeoraría la lectura sin ahorrar papel.

Además, el **recibo ahora compacta cuotas base** (`compactarCuotasBaseParaPdf`,
renombrada porque dejó de ser exclusiva del resumen): un cobro de 9 cuotas
estiraba el papel mucho más de lo necesario. El autodesactivado por mora anidada
es **por tramo**, así que los tramos sin mora se siguen fusionando.

**Comprobante de anulación:** es el tercer PDF con A4 fijo, pero usa `pw.Spacer()`
para empujar el pie al fondo y `Spacer` exige alto acotado — convertirlo obligaba
a rediseñarlo entero. Mitigación: se acota el motivo (su único campo de largo
libre) a 400 caracteres, que elimina la única vía de desborde.

**Lo que sigue sin resolverse:** si ni el nivel más compacto entra, la hoja crece
igual. No es una elección — la alternativa es imprimir el papel sin el total, que
es el bug que se está matando. Con la escalera completa no debería pasar.

---

## Archivos tocados

| Archivo | Qué |
|---|---|
| `lib/core/utils/ar_time.dart` | `arToUtc()` y `finDeDiaArUtc()` — sello a las 23:59 del día propio |
| `lib/features/caja_sesiones/models/sesion_caja.dart` | Umbrales del latido, `enUsoAhora`/`sinSenales`, notas de cierre automático, `cierreAutomatico` |
| `lib/features/caja_sesiones/repositories/sesiones_caja_repository.dart` | `cerrar()` con sello, autocierre por día, consolidación de duplicadas, orden determinístico, `flushConfirmandoSesion` |
| `lib/features/caja_sesiones/providers/app_role_provider.dart` | `autocerrarSesionesVencidas`, `estadoCajaEnOtroDispositivo`, `SinCajaAbiertaException`, toma de caja, cierre que informa |
| `lib/features/caja_sesiones/widgets/abrir_caja_dialog.dart` | Diálogo de tres estados, sin bloqueo duro |
| `lib/features/caja_sesiones/widgets/cerrar_caja_dialog.dart` | Aviso de cierre sin red |
| `lib/features/caja_sesiones/widgets/sesion_caja_status_chip.dart` | Usa los umbrales compartidos |
| `lib/features/caja_sesiones/services/caja_auto_sync_service.dart` | `refreshBeforeOpen()` |
| `lib/features/common/widgets/operational_sync_coordinator.dart` | Autocierre al arrancar y al volver del segundo plano |
| `lib/features/cierre_caja/cierre_caja_screen.dart` + `models/resumen_sesion_pdf.dart` | Marca de cierre automático sin arqueo |
| `lib/features/eventos/services/mora_concepto_rotulo.dart` | `repartirMoraParcial` + emisión de líneas por el importe cobrado |
| `lib/features/common/services/ajuste_pdf.dart` | **Nuevo** — escalera de compactación |
| `lib/features/common/services/pdf_service.dart` | Medición y ajuste de resumen, recibo y ticket de cierre |
| `lib/features/eventos/services/cobro_masivo_conceptos_pdf.dart` | `abreviarDisplayPdf`, rename `compactarCuotasBaseParaPdf` |
| `lib/features/eventos/detalle_evento_masivo_screen.dart` | Captura de `SinCajaAbiertaException` en el cobro |

**Tests: 225/225.** Analyzer sin errores.

Nuevos: `test/mora_pago_parcial_test.dart`, `test/sesion_caja_corte_dia_test.dart`,
`test/ajuste_pdf_test.dart`, `test/pdf_ajuste_medido_test.dart`.

Los dos que más valen: *"9 cuotas con subtextos entran en media hoja A4"* (mide el
PDF real y falla si desborda) y *"un cobro común sale intacto"* (garantiza que el
papel de todos los días no cambia).

---

## Verificación pendiente en la app real

Lo que no se puede cubrir con tests y hay que probar a mano:

1. **Autocierre del jefe** — adelantar el reloj de Windows un día con la app
   abierta: el chip tiene que pasar a "Caja cerrada" en ≤60 s, y en el cierre del
   día original la sesión aparece con hora **23:59** y su nota.
2. **Dos PCs** (o dos instalaciones con `caja_device_id` distinto) — abrir en
   PC-A, intentar en PC-B; matar PC-A y esperar 5 min para el "Tomar la caja acá".
3. **Falso positivo, el caso que más importa** — en PC-A **desconectar la red** y
   cerrar caja con arqueo. En PC-B va a avisar que figura abierta, porque el
   cierre nunca llegó. Lo que se valida es que se pueda seguir en **dos clics** y
   que al reconectar PC-A no quede ninguna sesión duplicada abierta.
4. **PDFs** — alumno con 9 cuotas + mora en varias + arrastre + descuento + cargo
   por transferencia: el resumen tiene que salir con el TOTAL presente y entrar en
   media hoja. Con 1-2 cuotas tiene que salir con la letra de siempre.
5. **Regresión de mora completa** — el rótulo y las líneas tienen que salir
   idénticos a 4.6.5.

---

## Versiones

| Fecha | Versión | Notas |
|-------|---------|--------|
| 24-jul-2026 | 4.6.0+27 | Caja jefe explícita + PDFs cierre por sesión |
| 27-jul-2026 | 4.6.1+28 | Operario edita base + aviso abrir caja |
| 31-jul-2026 | 4.6.2+29 | Papeles: mora fuera de término, sin redundancias, "viene de" con cuotas |
| **4-ago-2026** | **4.6.6+33** | **Release** — autocierre de caja, cobro sin sesión imposible, mora parcial correcta, PDFs que entran |

## Contextos relacionados

- `docs/CONTEXTO_v4.6.2_2026-07-31.md`
- `docs/CONTEXTO_SESIONES_CAJA_2026-07-17.md`
- `docs/CONTEXTO_MORA_OPERATIVA.md` (v54 carry-over)
