# El salón entero en el tótem, y las sillas en la puerta

> **Plan aprobado el 5-nov.** Lo que cambió al programarlo y en qué quedó cada parte está en
> `docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md` ("Para retomar en otro chat"). Donde este plan y ese
> CONTEXTO no coinciden, manda el CONTEXTO: por ejemplo, la tarjeta en la pista va resumida, el cartel de la
> pista es opaco y la venta de las sillas la cobra la barra con un vale (sin plata en la puerta).

Fecha: 4-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Va **antes** de retomar la etapa 5 de la barra
(decisión del usuario). Se programa en la rama; se publica con lo demás, o antes, cuando él diga. Lleva **dos SQL**
que solo agregan (tres columnas en `totem_config`, una tabla nueva `sillas_puerta`): se corren antes de instalar.

## Contexto

El jefe pidió hoy dos cosas:

1. **El tótem tiene que mostrar el salón entero mientras la gente hace la fila**, y al marcar un ingreso, que
   salte el nombre del egresado y se marque la mesa con el camino, por más tiempo que hoy. Hoy el plano aparece
   solo en la llegada, en la mitad de la pantalla (lo eligió el usuario el 11-oct: "forma A"), y una tarjeta dura
   7 s sola, 3 s con cola. Elegido con el usuario: **"salta y se acomoda"** (el nombre grande primero, con el
   salón atenuado detrás; después se achica al cuadro y queda con el camino), **los dos tiempos y el lugar del
   nombre a elección del jefe en Personalizar**, el salón **claro y legible** (mesas blancas, números grandes), y la
   tarjeta **sin las sillas** (hoy dice "10 sillas (8 + 2 extra)" debajo de la mesa: se saca; queda nombre,
   acompañantes y mesa). El plano ya es por fiesta (`planos_evento`): cada institución ve el suyo.
2. **La recepcionista tiene que ver, en palabras, cuántas sillas tiene cada mesa de la familia y cuántas puede
   agregar** (tope: 2 extra por mesa, también en la mesa adicional), **anotar la silla que se sumó esa noche con el
   vale de la barra, y que todas las recepcionistas lo vean al instante sin pisarse.** Contexto del negocio: hasta
   el 10-nov las sillas extra se venden en la oficina y van al contrato (Editar alumno, como siempre); desde que
   empiezan los sorteos se cierran las ventas y una silla más **se pide solo la noche de la fiesta, ya adentro,
   sentados**. Lo comprado en la oficina llega pagado a la fiesta: la puerta no marca el 50 % de eso. **Decisión del
   jefe (5-nov): la recepcionista no toca plata.** Ella dice si la familia puede agregar y la manda a **la caja de la
   barra**, que cobra la silla como un producto más ("Silla extra", con su precio por fiesta en el catálogo) y
   entrega el vale; la recepcionista suma la silla con el número del vale. Quién ve esas ventas en la barra (la
   encargada, no cualquier cajera) va con las etapas que faltan de la barra. Y **nada se puede desmarcar sin
   huella**: sumar y quitar quedan anotados para siempre, con quién, a qué hora y con qué vale; al cierre, las
   sillas vendidas en la barra y las sumadas en la puerta tienen que dar igual.

Las planillas no cambian: la recepcionista no las ve; su "planilla que se refresca" es la lista del celular.

## Queda para el jefe (antes de programar la Parte 2)

Lo principal quedó resuelto el 5-nov (puntos 1 y 2). Las dos partes se programan, el tótem primero. Lo que sigue
abierto no frena nada: el plan toma lo más simple y se cambia si él dice otra cosa.

1. **Resuelto (5-nov): la caja de las sillas es la caja de la barra.** La recepcionista no toca plata: manda a la
   familia a la barra y suma la silla con el vale. Si más adelante quiere que solo una recepcionista pueda sumar y
   quitar, la variante está lista: una tilde "Es la encargada de las sillas" al sumar el celular (CELULARES →
   "Sumar un celular"), y SUMAR SILLA y QUITAR aparecen solo en su puesto y en la PC.
2. **Resuelto (5-nov): el precio lo pone el jefe en el catálogo de la barra**, como a cualquier producto, por fiesta.
   Nada que programar en la puerta.
3. **¿La recepcionista puede quitar una silla sumada, con motivo y huella, o solo el jefe?** El plan deja que pueda,
   siempre con motivo y a la vista.
3b. **¿Quién ve en la barra las ventas de "Silla extra"?** Dijo "la encargada de la barra, no cualquier cajera". Hoy la
   cajera ve su caja y el jefe todo (etapa 7, sin hacer). Va con las etapas que faltan de la barra, no acá.
4. **¿Desde el 10-nov la oficina deja de cargar sillas extra al contrato?** Hoy Editar alumno lo permite; el plan no
   lo traba. Si quiere trabarlo después del sorteo, es un cambio aparte.
5. **Si una familia quiere otra mesa la noche de la fiesta, ¿cómo se divide?** Fuera de este plan: el salón lo cambia
   solo el jefe y antes de la fiesta. Lo que diga se anota para después.
6. **¿Quién puede tocar los segundos del tótem desde el celular?** El plan deja que cualquiera (la PC siempre); si
   nombra una encargada, solo ella.

## Los datos al día

| Dato | De dónde sale | Cuándo se pone al día |
|---|---|---|
| El salón que ve la tele | `FichaTotem.plano`, por el puente, desde la PC (ya existe) | al abrir, cada 60 s, al cambiar de evento. Sin internet anda. |
| Los tiempos y el lugar del nombre | `totem_config` (tres columnas nuevas) | al guardar Personalizar; la ventana del salón se entera sin reabrir (`notifyConfigUpdated`) |
| Sillas del contrato | `contratos_alumnos` (como hoy; **no se toca**) | con el sync de siempre |
| Sillas sumadas en la puerta, y las quitadas | **tabla nueva `sillas_puerta`**, filas que solo se agregan | la notebook las escribe en su base y suben por la cola; los celulares reciben la lista nueva al instante por el wifi del salón, con o sin internet; bajan en "Lista para trabajar sin internet" |

## Para → camino desde la fiesta

| Para | Camino |
|---|---|
| Ver el salón entero en la tele | Recepción → abrir el tótem, en un masivo sorteado. Nada que configurar. |
| Elegir los tiempos y dónde va el nombre | Recepción → Personalizar tótem → sección "LA LLEGADA" (solo en un masivo): "El nombre en grande" y "El salón con el camino", en segundos; "Dónde va el nombre": Automático · Arriba · Abajo · Izquierda · Derecha. "Ver una llegada" muestra el salón de la fiesta. |
| Cambiar los segundos esa noche, a mano | Recepción → sobre la vista del tótem, al lado de la paleta, el reloj: "Nombre 4 s − +" y "Camino 8 s − +". Cada toque cambia la tele al instante y queda guardado en la PC; sube a la nube cuando hay internet. En el celular de la puerta, el mismo reloj: la notebook lo aplica. |
| Ver las sillas de cada mesa y cuántas puede agregar | Recepción (PC o celular) → debajo de la familia, una línea por mesa: "Mesa 12: 8 sillas + 2 extra · ya no puede agregar" / "Mesa adicional 13: 8 sillas · puede agregar hasta 2 · se cobran en la barra". |
| Sumar una silla esa noche | En la misma fila, SUMAR SILLA → hoja: a qué mesa va, "le quedan N", el número del vale de la barra → CONFIRMAR. Sin vale no se suma. Sin PIN. |
| Quitar una sumada por error | En la línea "+1 silla · mesa 12 · vale 0012 · Juli 22:14", QUITAR → pide el motivo. La línea queda tachada, no desaparece. |
| Ver el conteo de la noche | Arriba de la lista: "Esta noche: 4 sillas sumadas · vales 0012, 0015, 0021, 0030 · 1 quitada". Se compara con lo que vendió la barra. |
| Cobrar la silla | En la barra, como cualquier producto: el jefe carga "Silla extra" en el catálogo con su precio por fiesta. Nada nuevo que programar ahora. |
| Ver en la oficina qué pasó esa noche | Grilla de la fiesta, celda Mesa: "· +1 puerta" y el detalle al pasar el mouse (vale, quién, hora); Editar alumno, una línea gris con sumadas y quitadas. **No cambia la cuenta del alumno.** |

## Antes y después

| Momento | Tele | Lista de la puerta |
|---|---|---|
| Particular, o masivo sin sortear, o web `?totem` | Como hoy (foto, frases, QR en particular) | Como hoy, sin líneas de sillas ni SUMAR SILLA |
| Masivo sorteado, esperando | Salón entero, claro, con números, sin nombres; foto y frases en el cuadro (el lugar elegido, o automático: la pista si hay y entra; si no, el hueco más grande; si no, la franja que el salón deja; si no, se achica apenas) | Una línea por mesa con sus sillas y cuántas puede agregar; SUMAR SILLA |
| Marcan un ingreso | El nombre grande N s con el salón atenuado → se achica al cuadro, la mesa se enciende y el camino se dibuja M s. Con cola dura lo mismo; la siguiente espera. Sin sillas en la tarjeta. | Como antes |
| Ya adentro, una familia suma una silla | Nada cambia en la tele | "+1 silla · mesa · vale · quién · hora" en todas las pantallas al instante |

## Cómo sería la noche

1. Antes de abrir, la tele muestra el salón de la Normal, claro, con los números; en la pista, "Bienvenidos ·
   Egresados 2026".
2. Juli toca "Ingresó" en PÉREZ. Salta "PÉREZ, JULIANA" grande; a los 4 s se achica a la pista, la mesa 12 se
   enciende y el camino se dibuja desde el Ingreso. Queda 8 s más. Si llega otra familia, espera su turno y después
   se muestra entera, con sus mismos segundos.
3. Ya sentados, los PÉREZ se dan cuenta de que les falta una silla y se la piden a Pato, la recepcionista de
   adentro. Pato busca PÉREZ en su celular y ve "Mesa 12: 8 sillas + 1 extra · puede agregar 1 más · se cobra en
   la barra". Les dice: "pasen por la caja de la barra".
4. En la barra, Cami vende "Silla extra" como cualquier producto; sale el vale "VALE POR 1 SILLA EXTRA · 0012" y la
   plata queda en la caja de la barra, con su cierre y su anulación como todo lo demás.
5. Los PÉREZ vuelven con el vale. Pato toca SUMAR SILLA, elige la mesa 12, escribe 0012 y confirma. Todos los
   celulares y la PC dicen "+1 silla · mesa 12 · vale 0012 · Pato 23:05" y "ya no puede agregar". Si Juli toca a la
   vez para la misma familia, la notebook atiende de a uno: Juli recibe "ya está en el tope".
6. Se arrepienten: Pato toca QUITAR, escribe "devolvieron el vale en la barra". La línea queda tachada con "quitada
   por Pato 23:20". Nada se borra: el jefe ve las dos cosas.
7. Al cierre, arriba: "Esta noche: 4 sillas sumadas · vales 0012, 0015, 0021, 0030 · 1 quitada". La barra dice
   cuántas "Silla extra" vendió: tienen que dar igual. Al otro día la grilla muestra "· +1 puerta" en cada familia.

---

# Parte 1 — El tótem

## 1.1 `CuadroDelSalon`: dónde van el salón y el cuadro (puro, con tests)

Nuevo `lib/features/totem/services/cuadro_del_salon.dart`. Decide **una vez por plano, tamaño de pantalla y lugar
elegido** el rect del salón (`panel`) y el del cuadro (`cuadro`), igual en la espera y en la llegada acomodada, así
la tarjeta cae donde estaban las frases y el salón no se mueve.

- `static CuadroDelSalon? para(ArmadoSalon?, {required Size pantalla, required double u, LugarElegido lugar =
  LugarElegido.automatico})` → null sin plano o sin mesas. Campos: `hoja`, `panel`, `cuadro`, `lugar`
  (`pista | hueco | franjaLibre | franjaForzada`), `alCostado`, `radioPx`.
- `hojaPrincipal(a)`: la del Ingreso (`CaminoALaMesa.ingresoEn`), si no la de más mesas.
- **Automático**, en orden: (1) la pista (`TipoSector.pista`, `armado_salon.dart:213-226`) llevada a pantalla con
  `EncuadrePlano.de` (`pintor_plano.dart:23-35`), si mide ≥ `cuadroMinimo = 10u × 8u`; (2) el hueco más grande sin
  mesas ni sectores (grilla de paso `radio/2`, como `_Grilla` de `camino_a_la_mesa.dart`, rectángulo máximo por
  histograma); (3) la franja libre del encuadre, con el salón pegado abajo (vertical) o a la derecha (apaisada);
  (4) una franja forzada arriba o a la izquierda, el salón se achica a lo que queda.
- **Elegido** (arriba, abajo, izquierda, derecha): la franja de ese lado, libre si el encuadre la deja, forzada si
  no. Márgenes: 0,8u lados y arriba; 2,6u abajo ("N más en camino" + la línea).
- Con la Normal 2A: apaisada 1920×1080 → pista; vertical 1080×1920 → franja libre arriba.
- Tests `test/cuadro_del_salon_test.dart`: los cuatro lugares automáticos, los cuatro elegidos, dos hojas, el hueco
  no toca mesas, `para(null)`, armado sin mesas → null, 360×640 sin excepción.

## 1.2 Los tiempos y el lugar: `TotemConfig` + SQL + `finDeBienvenida`

- `lib/models/totem_config.dart`: `llegadaNombreSeg` (default **4**, 2 a 10), `llegadaCaminoSeg` (default **8**,
  3 a 30) y `llegadaLugar` (`String?`: null = automático; `arriba | abajo | izquierda | derecha`; desconocido →
  automático). En constructor, `fromJson` (patrón `foto_tamano` con clamp), `toJson` (claves `llegada_nombre_seg`,
  `llegada_camino_seg`, `llegada_lugar`), `copyWith` **y `conFondoDe`** (si falta ahí, guardar Personalizar los
  resetea).
- SQL `supabase/migrations/20261105100000_totem_config_llegada.sql`, copiado de
  `20261023200000_totem_config_foto.sql`: dos `smallint` y un `text`, `add column if not exists`, sin NOT NULL ni
  CHECK, con ROLLBACK y la verificación de conteos. `test/totem_config_test.dart` (306-376): sumarlo a la lista y a
  los bucles.
- `lib/features/totem/services/bienvenidas_totem.dart`: `class TiemposDeBienvenida { nombre, camino; de(cfg);
  total }`. **Con cola no se acorta nada** (decisión del usuario, 4-nov): cada familia dura `nombre + camino`
  siempre y la siguiente espera su turno. `kBienvenidaSola`/`kBienvenidaConCola` se van; `finDeBienvenida(…,
  tiempos:)` ya no mira `hayCola` (el parámetro queda para `seSumo`, que sigue: al que se suma a la tarjeta se le
  dan 3 s más como mínimo). `IngresosTotem.tiempos`; `ReproductorBienvenidas.tiempos = …` reprograma el fin
  (`_programarFin`, sin tocar una tarjeta que se va). `totem_display.dart` y `totem_local.dart` lo setean al leer la
  config.
- Riesgo anotado: con 130 familias y 12 s por tarjeta, si la puerta marca más rápido la tele se atrasa; el remedio es
  bajar los segundos en Personalizar. "N más en camino" sigue abajo para que se vea la cola.
- Tests: `bienvenidas_totem_test.dart` (de(cfg), `total`, con cola dura lo mismo, `seSumo` sigue mandando),
  `reproductor_bienvenidas_test.dart` ("con cola, cada una dura 3 s" pasa a "con cola, cada una dura lo configurado";
  "con N=6 y M=5 dura 11 s"; "cambiar los tiempos con la tarjeta puesta reprograma").

## 1.3 `EscenaTotem`: la espera con el salón entero, claro

`lib/features/totem/estilos/escena_totem.dart` y `plano_del_totem.dart`:

- **El tema claro del tótem.** `temaPlanoDelTotem(estilo, color)` pasa a dar un `TemaPlano` claro para las cinco
  apariencias (`estilo_plano.dart:44-89` tiene todos los colores): panel blanco hueso casi opaco, mesas blancas con
  borde gris, números negros, sectores y pista en gris suave con su texto, la mesa de la familia en el color del
  evento (número blanco o negro según contraste), el camino en el color del evento, el borde del panel en el color.
  Los números van más grandes que en la PC: si `TemaPlano`/`NivelDetalle` no lo permiten, un parámetro del pintor
  solo para el tótem. El fondo animado de la apariencia sigue alrededor del panel. **Muestra claro vs. oscuro** las
  dos, para que el usuario vea; se deja el claro.
- `PanelPlano` recibe lo que dibuja (`armado, hoja, estado, resaltadas, ruta, tema, borde, u, animar,
  progresoCamino, atenuado`) en vez de `guia`. Para la espera, `EstadoPlano` **vacío** (sin ocupantes: todas las
  mesas con su número, `PintorPlano` ya lo hace). `VistaPlano`/`PintorPlano` no cambian de forma.
- Cachés en el estado: `_cuadro` por `(identical(plano), Size, lugar)`, `_estadoVacio` por `identical(plano)`: la
  misma instancia cuadro a cuadro, así `PintorPlano.shouldRepaint` no repinta el salón (solo el pulso, en su capa).
- En `build`: si `cuadro == null` → **todo como hoy**. Si hay: el `PanelPlano` siempre presente detrás; la espera va
  en `Positioned.fromRect(cuadro.cuadro)` con `escena.espera(d.conPlanoEn(cuadro.cuadro.size, alCostado:))`. Las
  cinco apariencias no cambian (`conPlanoEn` ya existe; Neón ya baja el horizonte; `Centrado` achica).
- **La tarjeta sin sillas:** `ContenidoBienvenida` deja de llevar `sillas` (`contenido_bienvenida.dart:37-38,
  92-107`); `FichaTotem` y el puente no se tocan. Tests de `contenido_bienvenida_test.dart` y
  `tarjeta_bienvenida` se ajustan.
- Tests `escena_totem_test.dart`: 415-426 se invierte ("en la espera de un masivo con plano está el salón entero",
  en las tres pantallas y las cinco apariencias; `estado.mesas` vacío, `ruta` null); "sin plano la espera es la de
  siempre"; "el salón no tapa las frases" (rects); "el lugar elegido manda". Muestra nueva en
  `tool/totem_muestra_test.dart`: "el salón en la espera", vertical y apaisada, cinco apariencias, claro y oscuro.

## 1.4 La llegada en dos fases

- `enum FaseLlegada { grande, acomodada }`; `EscenaTotem.faseFija` (tests y muestras); `acomodo = 800 ms`.
- Un `AnimationController _acomodo` y un `Timer` a `empezo + tiempos.nombre`; se rearma al cambiar `claveLlegada`. Fase grande: `escena.llegada(d, c)` entera (la de hoy) con el panel
  atenuado (`lerp(0.3, 1, a)`) y el estado vacío. Acomodo: `Rect.lerp(pantalla, cuadro.cuadro, a)`, el contenido
  se achica solo (`Centrado`); al terminar, el estado pasa al de `PlanoDeLaLlegada` (mesa encendida) y
  `_progresoCamino` arranca desde `empezo + nombre + acomodo`.
- `_conPlano` (400-453) se borra. "N más en camino" y la línea del tiempo quedan. `planosArmados` sigue en 1.
- Tests: quieta grande (nombre a pantalla, `resaltadas` vacío); quieta acomodada (nombre dentro del cuadro, el panel
  no lo pisa); animada con reloj real (`empezo = now` → sin resaltar; `empezo = now − (N+2 s)` → `{12}` y camino
  entero; con `enCamino: 1` se acomoda igual a los N s); "el cuadro de la llegada es el de la espera". Muestras: grande y
  acomodada, vertical y apaisada.

## 1.5 Personalizar

`lib/features/totem/widgets/totem_config_sheet.dart`:

- `_llegadaNombre`, `_llegadaCamino`, `_llegadaLugar` en `initState`, `_preview` **y** `_guardar` (campo por
  campo; sin tocar, se guardan como estaban).
- Sección "LA LLEGADA" en `_ajustes`, solo en un masivo: texto "Primero el nombre en grande; después la tarjeta se
  acomoda y el salón muestra el camino a la mesa. Cada familia dura esto, aunque haya cola.", dos `BarraDeTamano` con
  "N s" (`Key('llegada_nombre')`, `Key('llegada_camino')`) y las fichas "Dónde va el nombre" (Automático · Arriba ·
  Abajo · Izquierda · Derecha, `Key('llegada_lugar_*')`).
- La vista grande pasa `plano: planoDelEventoProvider(eventoId)` y el lugar elegido; `LlegadaDeEjemplo` elige una
  mesa real de la hoja principal (hoy la '12' fija puede no existir y el salón no se vería). `_verLlegada` usa
  `tiempos.sola`.
- `test/helpers/personalizar_en_memoria.dart`: reemplazar el repo del plano como `PuertaEnMemoria`.
  `personalizar_totem_test.dart`: "ver una llegada en un masivo con plano muestra el salón"; "las barras y el lugar
  se guardan y, sin tocarlos, como estaban".

## 1.6 Detalles que rompen si se olvidan

- **La ficha de cada 60 s trae otra instancia de `ArmadoSalon`** (`totem_display.dart:246-256`): invalidaría los
  cachés y repintaría todo. `FichaTotem.reusar(nuevo, viejo)` devuelve el viejo si el JSON es igual;
  `_ficha = ficha.conPlanoDe(_ficha)`. Test en `ficha_totem_test.dart`.
- `_pausar()`: nada nuevo habla con la nube; el timer muere con el widget.
- Riesgos anotados: Canva en dos hojas (se muestra la principal; si la mesa está en la otra, el panel cambia de hoja
  esa llegada); Póster con la foto debajo (el panel claro casi opaco la tapa en ese sector: mirar la muestra);
  apellido bajo la mesa solo si `radioPx ≥ 26` (a Full HD no: el nombre va en la tarjeta, es lo pedido).
- Arnés para mirarlo sin base: `tool/tu_fondo_prueba.dart` recibe `plano:` (la Normal 2A) y una llegada de ejemplo
  → `flutter run -d windows -t tool/tu_fondo_prueba.dart`.

## 1.7 Los segundos a mano, la noche de la fiesta

Personalizar es para dejar la fiesta armada; la noche, quien está a cargo tiene que poder tocar los segundos sin
buscar nada y sin internet (pedido del usuario: uno recibe en la puerta y el que está a cargo puede estar más
adentro, con el celular).

- `TotemConfigRepository.guardarTiempos(eventoId, {nombre, camino})` (`totem_config_repository.dart:49-64`):
  **primero `TotemConfigCache.save`** (así el tótem que reabre sin internet los tiene), después
  `KioskLauncher.notifyConfigUpdated` (la tele cambia en el momento) y el upsert a la nube **a mejor esfuerzo**: si
  falla, queda `TiemposPendientes` en la PC y se reintenta cuando vuelve la conectividad (`AppConnectivity`). Hoy
  `guardar` hace el upsert primero y sin internet no guarda nada: eso no se toca para Personalizar.
- **En la PC**: `VistaDelTotem` (`vista_del_totem.dart:67`), al lado de la paleta, un botón con reloj (para
  cualquiera que tenga Recepción abierta, sin el permiso del tótem) → un popover chico con dos renglones "Nombre
  4 s − +" y "Camino 8 s − +" (de a 1 s, dentro de los topes de `TotemConfig`). Cada toque aplica. Sin "Guardar".
- **En el celular**: `PantallaPuesto` suma el mismo reloj en su barra → la misma hoja; cada toque manda
  `PedidoPuerta(que: tiemposTotem, tiempos: {nombre, camino})` por `ClienteCentral`; la central (`_resolver`) llama a
  `guardarTiempos`. La lista que manda la central (`{t:'puerta', …}`) lleva `tiempos` vigentes, así todos los
  celulares muestran los mismos números. `decidirPedido`: `tiemposTotem` siempre se hace, con clamp. Por ahora
  puede cualquiera; si el jefe nombra una encargada (Parte 2), solo ella.
- Tests: `totem_config_repository_test` (cache antes que la nube; la nube caída deja el pendiente y el cache igual;
  al volver sube); `recepcion_pantalla_test.dart` (el reloj cambia y la vista del tótem usa los nuevos);
  `central_puerta_test.dart` ("el celular cambia los tiempos y la PC los guarda y los manda a todos");
  `cliente_central_test.dart`; `pedidos_de_la_puerta_test.dart` (clamp).

---

# Parte 2 — Las sillas en la puerta

## 2.1 Datos: modelo, v78, SQL, repositorio, sync

- Nuevo `lib/models/silla_puerta.dart`: `id` (uuid v4, **filas que solo se agregan**), `eventoId`,
  `contratoAlumnoId`, `mesa` (a qué número va), `cantidad` (1), `vale` (el número del vale de la barra, texto,
  obligatorio), `anotadoPor`, `nota`, `quitadaAt`, `quitadaPor`, `quitadaMotivo`, `createdAt`, `updatedAt`;
  `vigente => quitadaAt == null`. Sin plata: la cobra la barra.
- `local_database.dart`: `_version = 78`; `crearTablasV78` (patrón `crearTablasV77`, `CREATE TABLE IF NOT EXISTS`
  + dos índices) en `_onCreate`, `_initDb` y `_onUpgrade` (`oldVersion < 78`). Copia antes de migrar ya existe.
  Tests: `test/migracion_v78_test.dart` (copiar v77) y `tool/verificar_migracion_v78_test.dart` sobre una copia de
  la base real (la app instalada cerrada: se le pide al usuario).
- SQL `supabase/migrations/20261105120000_sillas_puerta.sql`, copiado de `20261023210000_mora_congelada.sql`: la
  tabla (uuid, text, timestamptz), tres índices, RLS `authenticated`, los dos disparadores de
  `update_updated_at_column`, **sin CHECK, sin FK, sin índice único, fuera de Realtime**, conteos antes/después.
- Nuevo `lib/features/recepcion/repositories/sillas_puerta_repository.dart` (patrón
  `sillas_reparto_repository.dart:35-72`): `delEvento` (vigentes y quitadas), `vigentesDe(contratoId)`, `anotar`,
  `quitar(id, por:, motivo:)` (reescribe la fila con `quitada_*` y encola; **nunca `DELETE`**), `cambios`.
- `sync_engine.dart`, **las siete listas** (una que falte pisa en silencio): `_incrementalColumns`,
  `_tablasDelCobro`, el bloque de `_pullTable`, prioridad junto a `sillas_reparto`, `_cleanForSqlite` (las 13
  columnas), `_tablasSinRevisarBorrados` ('solo se agregan filas: quitar le pone quitada_at'), `tablasDeLaPuerta`.
  **No** va en las `relaciones` padre-hija de `sync_queue.dart`.
- Test `test/sillas_puerta_sql_test.dart`: cada clave de `toMap()` está en el SQL de la nube y en `crearTablasV78`;
  sin `check` ni `references`; con policy y triggers; el repositorio no tiene `delete`.

## 2.2 Lo puro: el tope por mesa y el grupo

- Nuevo `lib/features/recepcion/services/sillas_de_la_puerta.dart`:
  - `SillasDeUnaMesa(numero, esAdicional, extraDelContrato, sumadas)`: `tope = SalonMesas.maxSillasExtraPorMesa`,
    `puedeAgregar`, `texto` → "Mesa 12: 8 sillas + 2 extra · ya no puede agregar" · "Mesa adicional 13: 8 sillas ·
    puede agregar hasta 2 · se cobran en la barra" · "Mesa 12: 8 sillas + 3 extra · 1 de más: revisar".
  - `SillasDeLaFamilia.de(a, repartoGuardado, sumadasVigentes)`: una `SillasDeUnaMesa` por número, con el reparto
    del contrato como lo eligió la familia (`SalonMesas.repartoSillas` + `RepartoDeSillas.vigente`) y cada sumada en
    la mesa que dice su fila; `puedeAgregarTotal`, `mesaConLugar` (la primera con lugar, la principal antes), JSON.
  - `ConteoDeLaNoche.de(todas)`: "Esta noche: 4 sillas sumadas · vales 0012, 0015, 0021, 0030 · 1 quitada" (las
    quitadas no cuentan, pero se dicen aparte). Es lo que se compara con las "Silla extra" vendidas en la barra.
- `puerta_del_evento.dart`: `PuertaDelEvento.masivo(…, sillasPuerta:)`; `GrupoPuerta` suma `contratoId`,
  `sillasPorMesa` (reemplaza el texto `sillas`), `movimientos` (sumadas y quitadas: id, mesa, vale, quién, hora,
  quitada por/hora/motivo); `PuertaDelEvento.conteoDeLaNoche`. JSON con **lectura tolerante** (claves ausentes →
  sin líneas). `textoSillasPuerta` queda solo para `FichaTotem`/el tótem local, sin las sumadas.
- `recepcion_provider.dart`: `sillasPuertaDelEventoProvider` (molde de `alumnosDeLaPuertaProvider`, relee con
  `repo.cambios` y con el sync cuando baja `sillas_puerta`); `puertaDelEventoProvider` lo pasa en la rama masivo.
  La central ya escucha ese provider → los celulares reciben la lista nueva al instante.
- **Las sumadas no entran en `SalonMesas.sillasExtra` ni en `RepartoDeSillas`**: el sorteo, la planilla, el retiro
  de entradas y el plano no cambian.
- Tests: `sillas_de_la_puerta_test.dart` (una mesa con 0/1/2 del contrato; adicional con lugar; sumada va a la
  adicional si la principal está llena; de más; el conteo con cuatro vales y una quitada),
  `puerta_del_evento_test.dart` ("con una silla sumada, la línea de esa mesa cambia"; "antes del sorteo no hay
  líneas"; "lo cargado a mano no tiene líneas"), `puerta_del_evento_json_test.dart` (ida y vuelta; un JSON viejo se
  lee igual).

## 2.3 El candado: `decidirSilla`, el protocolo, `AccionesPuerta`

- `pedidos_de_la_puerta.dart`: `QuePide { ingresar, deshacer, sumarSilla, quitarSilla }` (`fromJson` ya descarta lo
  desconocido); `DatosSilla { mesa, vale, sillaId, nota, motivo }` en el pedido (`'silla': {…}`, opcional);
  `decidirSilla({pedido, grupo, vigentesEnLaBase, valesDeLaNoche})`: sin mesa → "Esa familia no tiene mesa
  todavía."; sin vale → "Hace falta el número del vale de la barra."; un vale ya usado esa noche en otra silla
  vigente → "El vale 0012 ya se usó para GÓMEZ."; la mesa pedida llena → prueba `mesaConLugar`; sin lugar en
  ninguna → `yaEnElTope(nombre)`; quitar lo que no está → "Esa silla ya se quitó."; quitar sin motivo → "Decí por
  qué se quita."
- **Un solo candado para PC y celulares.** Extraer la fila de `CentralPuerta` (`_fila`, `_resolver`) a
  `lib/features/recepcion/central/resolvedor_de_pedidos.dart`, que `CentralDeLaPuerta` crea **aunque la central esté
  apagada** y expone `resolverDeEstaPc(pedido, puesto:)`. `PuertaDeEstaPc` suma `sillasVigentes`, `sumarSilla`,
  `quitarSilla` (`PuertaDeEstaPcConBase` → el repositorio). La silla lleva `anotado_por = puesto`; la quitada,
  `quitada_por = puesto`.
- `acciones_puerta_provider.dart`: `Future<String?> sumarSilla(eventoId, grupo, datos)` y `quitarSilla` (devuelven
  el aviso si no se hizo); `quienSoy` (PC: `quienOpera`, cae a "PC"; celular: el nombre del puesto).
  `AccionesDeEstaPc` arma un
  `PedidoPuerta` y pasa por el resolvedor; `AccionesDelCelular` → `ClienteCentral` (pendientes en `localStorage`
  si no hay wifi, como hoy; `listaConCambios` ignora los de silla).
- Tests: `pedidos_de_la_puerta_test.dart` (**dos pedidos seguidos con la base del momento: el segundo no suma**;
  sin vale no suma; el mismo vale dos veces no suma; quitar sin motivo no hace nada); `central_puerta_test.dart`
  ("dos celulares suman a una familia con un lugar: entra una, el otro recibe ya está en el tope"; la lista que sale
  lleva la silla con el vale y quién);
  `cliente_central_test.dart`; `central_provider_test.dart` ("`resolverDeEstaPc` con la central apagada escribe en
  la PC").

## 2.4 El panel

`panel_puerta.dart`:

- Debajo de la familia, **una línea por mesa** (`SillasDeUnaMesa.texto`): suave si puede agregar, ámbar si ya no,
  rojo si de más. Debajo, cada movimiento: "+1 silla · mesa 12 · vale 0012 · Pato 23:05" con QUITAR; una quitada
  queda **tachada** con "quitada por Pato 23:20: devolvieron el vale". Nada desaparece.
- En el renglón del titular, SUMAR SILLA (`OutlinedButton.icon`, Outfit), apagado con tooltip "Ya no puede
  agregar: 2 extra por mesa". Sin PIN (regla: fricción, no PIN).
- Nueva `lib/features/recepcion/widgets/hoja_sumar_silla.dart`: `HojaSumarSilla.abrir(context, grupo:, quienSoy:)`
  → "Sumar una silla a PÉREZ, JULIANA"; a qué mesa (fichas con las que tienen lugar, la primera elegida); "le quedan
  N en esa mesa"; **el número del vale** (teclado numérico, con una línea gris "La silla se cobra en la caja de la
  barra: pedí el vale"); nota opcional; CANCELAR / CONFIRMAR. El vale es obligatorio. `onTapUpOutside` solo en la
  web. La misma hoja en la PC y en el celular. QUITAR abre una hoja corta con el motivo obligatorio.
- Arriba de la lista, "Esta noche: …" (`ConteoDeLaNoche.texto`), solo si hubo movimientos.
- Tests `panel_puerta_test.dart` con `PuertaEnMemoria` (+ `SillasPuertaEnMemoria`): las líneas por mesa; sumar anota
  con `quienSoy` y la lista dice "+1 silla · vale 0012"; sin vale no confirma; en el tope el botón apagado; quitar
  pide motivo y deja la línea tachada; sin desbordes con dos sumadas y una quitada. `recepcion_pantalla_test.dart`:
  de punta a punta.
- Arnés para probarlo con un celular de verdad: `tool/central_puerta_prueba.dart` con sillas (Recepción en memoria,
  sin base).

## 2.5 Sin internet, la oficina, lo que no se toca

- Sin internet: `sillas_puerta` en `tablasDeLaPuerta` baja al abrir el evento; de noche todo es local y sube por la
  cola. `PuestaAlDiaPuerta` no cambia.
- Oficina, lo mínimo: `celda_mesa_alumno.dart` sufijo "· +1 puerta" y el detalle en el tooltip, sumadas y
  quitadas ("No cambian la cuenta"); `detalle_evento_masivo_screen.dart` carga `delEvento` como
  `_cargarRepartosSillas`; `modal_alumno_premium.dart` una línea gris junto a "Hasta N sillas extra".
- Test `test/sillas_puerta_no_toca_test.dart`: lee `salon_mesas.dart`, `planilla_sorteo.dart`,
  `pago_para_sorteo.dart`, `retiro_entradas_screen.dart`, `plano_de_la_fiesta.dart` y falla si aparece
  `sillas_puerta`/`SillaPuerta`.
- Riesgos: dos notebooks a la vez → cada una decide con lo suyo, la línea marca "de más: revisar" en rojo; un pedido
  viejo del celular suma si todavía hay lugar (lleva `hace`, no se bloquea: la silla se vendió igual); `quienOpera`
  sin operador → "PC".

---

## Para la barra (decisiones del 5-nov; se programan en sus etapas 5 a 7, no acá)

Lo que dijo el usuario, con lo que ya existe y lo que falta:

| Lo que quiere | Hoy | Qué falta |
|---|---|---|
| Las chicas (a, b, c, d) se loguean, abren su caja y venden; no ven totales | Así es (etapa 4; `AppRoleKind.barra`) | Nada |
| La encargada sabe con cuánto cambio arrancó cada una | `cambio_inicial` existe en `barra_cajas` y `ponerCambio`; abrir **no lo pregunta** | Preguntarlo al abrir ("¿Con cuánto cambio arrancás?"), o que lo ponga la encargada |
| La chica cierra sin ver cuánto debería haber | Etapa 6, diseñada "a ciegas" (`efectivo_contado`, `diferencia`); falta la pantalla | La pantalla de CERRAR LA CAJA |
| Anular siempre con motivo y huella | Anular es otra fila (`barra_anulaciones`), nunca borra; etapa 5: la chica solo su última venta, una vez, con motivo; el jefe cualquiera | La encargada anula cualquiera, con motivo (mismo poder que el jefe en la barra) |
| La encargada ve cómo va cada una, cuánto generó, y nada más que ella | No existe el rol: hay cajera y jefe (etapa 7, sin pantallas) | Permiso **"Encargada de barra"**: `permisos_operador.barra = 2` (hoy 0/1; sin SQL, la nube no tiene CHECK; `PermisosOperador.barra` pasa de bool a nivel). Ve las pantallas de la barra del jefe (cajas, ventas, anular, cierre), nada más del modo jefe |
| Verlo **en vivo** en el salón, con el wifi del router y **sin internet** (decidido el 5-nov: todas con el .apk, routers sin internet) | Cada tablet guarda lo suyo y sube **cuando hay internet** (etapa 10) | **La central de la barra**, en la notebook de la puerta (ya está en el wifi; una notebook, dos centrales): cada tablet le manda cada venta por el wifi en el momento y la guarda si se corta, como los celulares de la puerta (`ClienteCentral`, pendientes); la encargada entra con su PIN de "Encargada de barra" (sin modo jefe), ve en vivo en la notebook o desde su Android conectado a ella, y anula con motivo desde ahí. Decidido el 5-nov: **dos notebooks, una por sector**, las dos con el programa y la cuenta, abiertas antes con internet para bajar lo de la fiesta; la comparación "sillas vendidas en la barra vs. sumadas en la puerta" sale en la oficina cuando las dos suben (en vivo entre notebooks, un paso más, no ahora). Al volver el internet, todo sube. Las tablets se conectan escaneando un QR, como los celulares. Puede ser la notebook de la puerta o la segunda notebook del usuario; **prendida, enchufada, con la tapa abierta y en el wifi toda la noche** (así lo quiere el usuario; sin tocar nada de Windows). Si se cae un rato, las tablets guardan y reenvían. Etapa grande de la barra, sin empezar; va después de este plan. |
| "Silla extra" se vende en la barra | Es un producto más del catálogo, con su precio por fiesta | En el cierre y en la vista de la encargada, cuántas "Silla extra" vendió cada una, para comparar con las sumadas en la puerta |
| El jefe carga a las chicas con nombre y PIN | **Ya existe**: Mi Empresa → OPERADORES (doble llave), nombre, PIN y las tildes Cobros · Entradas · Barra (`operadores_caja_screen.dart`, `permisos_operador`) | Una tilde más, **"Encargada de barra"**, al lado de Barra: por dentro `barra = 2` (hoy 0/1; sin SQL). Cargar a las chicas recién con la versión de la barra publicada (hoy está dormida en las PCs) |
| La encargada tiene su propia caja | La cajera abre su caja y vende | La encargada entra con su PIN, abre su caja y vende como las demás, **y** tiene LAS CAJAS: cómo va cada chica, cambio, lo generado, anular con motivo. Nada más del modo jefe |
| El jefe ve lo que generó cada sector **en el cierre de caja de hoy** (decidido el 5-nov; cambia la etapa 7 del plan de la barra, que lo ponía en una tarjeta aparte) | El cierre de caja de modo jefe muestra Cobros | Un **selector de sector** arriba del cierre: **COBROS** (lo de hoy) · **BARRA** (por fiesta, `ResumenDeCajas`: una línea por caja con cambio inicial, efectivo, transferencia, mixtos, anuladas, contado y diferencia; totales; "Silla extra: N vendidas") · **ENTRADAS** (desde ahora, con "todavía no hay ventas" hasta la sección 8 de Entradas: el lugar queda listo). El catálogo y los precios de la barra, que son configuración, siguen en la tarjeta BARRA. **La plata de la barra no se mezcla con la de Cobros**: cada sector su cierre |

## Docs al cerrar

`docs/CONTEXTO_v6.4.0_2026-11-0X.md` (lo hecho, los dos SQL, que con cola no se acorta, el contexto de las sillas
desde el 10-nov y la decisión del jefe: la barra cobra, la puerta anota el vale); CLAUDE.md: "El plano en la llegada"
pasa a "El salón en el tótem", y Recepción suma las sillas de la noche; `docs/pendientes/modo-local-sin-internet.md`
una línea; `docs/HOJA_DE_RUTA_2026-11-02.md` anota este paso antes de la barra 5 y, para la barra, dos pendientes
nuevos: "Silla extra" en el catálogo y en el cierre, y quién ve esas ventas (la encargada); y una comparación
sillas vendidas vs. sumadas para la oficina (`docs/pendientes/sillas-barra-vs-puerta.md`). Commits por etapa, con el
efecto para el usuario.

## Verificación

1. `flutter analyze` y los tests de cada etapa; al final la suite entera en verde.
2. Muestras PNG de `tool/totem_muestra_test.dart` (espera con salón claro y oscuro, llegada grande, acomodada;
   vertical y apaisada; cinco apariencias) **sin recortar**, miradas una por una antes de mandarlas.
3. El arnés en la ventana de verdad: `flutter run -d windows -t tool/tu_fondo_prueba.dart` con plano y llegada, con el
   mouse: el salto, el acomodo, el camino, los tiempos y el lugar cambiados. Y los segundos a mano desde Recepción en
   memoria y desde un celular (`tool/central_puerta_prueba.dart`), sin internet.
4. Recepción en memoria con un celular de verdad (`tool/central_puerta_prueba.dart`): sumar desde dos celulares a la
   vez a una familia con un lugar; el mismo vale dos veces; quitar con motivo; el conteo de la noche.
5. `tool/verificar_migracion_v78_test.dart` sobre una copia de la base real (SHA-256 igual), con la app cerrada.
6. Los dos SQL **no se corren** hasta publicar, con el OK del usuario en el momento; foto de la mora antes y después,
   como siempre.
