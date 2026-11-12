# Contexto: la 6.7.1 — "Cumplimiento debido" en el cartel del SORTEO, y la cruz para alinear

12-nov-2026 (tarde y noche). Rama `feature/v4.6-cierre-por-sesiones`. Sin SQL y sin migración (la
base del equipo sigue en la v79). Viene de `docs/CONTEXTO_v6.7.0_2026-11-12.md`.

## Para retomar en otro chat

**Estado: la 6.7.1 está PROGRAMADA y probada en el sandbox, SIN PUBLICAR.** Versión `6.7.1+73` en
`pubspec.yaml` y en el `.iss`. La 6.7.0 está publicada (12-nov, 15:47) y el usuario la probó: de ahí
salió todo esto.

| | Estado |
|---|---|
| El tilde en el cartel del SORTEO, con "Por columnas · Por filas" | Programado |
| Reacomodar con el sorteo ya hecho, sin deshacerlo | Programado |
| El plano sin el tilde; el porqué en el Historial | Programado |
| La cruz para alinear en Acomodar | Programada |
| Pruebas | `flutter test` entero: **4.600, todas pasan**. `flutter analyze`: sin errores ni nada en lo tocado |
| Simulacro sobre la copia de la base (la fiesta del 12-nov) | Columnas y filas, con y sin "al final": 200 sorteos con el salón vacío y 200 reacomodos cada uno, todos bien |
| Recorrido con el mouse (`tool/plano_prueba.dart`) | Hecho: cartel, tilde, sorteo, plano, Historial, "Ver el porqué", ya sorteado y la cruz. Capturas en `build/recorrido_671/` |
| Publicar | **Falta su "publicá"**: le mando las capturas y le pregunto |

### Lo que falta, en orden

1. Mostrarle las capturas (está en el celular) y esperar su "publicá".
2. Publicar: foto de la mora "antes de 6.7.1", el instalador por pasos, el APK, tag, release y web
   (el paso a paso, en "Cómo se publicó" de `docs/CONTEXTO_v6.7.0_2026-11-12.md`).
3. Que instale, primero la PC que sortea, y la foto de la mora "después".
4. Decirle que **destilde "Cumplimiento debido" en el plano de la fiesta donde lo tildó con la
   6.7.0** si todavía no lo hizo (la 6.7.1 lo limpia sola al sortear, pero hasta entonces el plano
   muestra las mesas con candado).

### Lo que NO se probó

- **La grilla de verdad** (`detalle_evento_masivo_screen.dart`): no se puede abrir en el sandbox
  (necesita la base). Lo que decide está afuera y probado (`OrdenEnElSalon`, el cartel), y el
  guardado es el de siempre (`asignarNumerosMesa`), pero `_ejecutarSorteoConPlano` con el tilde no
  corrió de punta a punta. El primer sorteo de verdad es la prueba.
- Deshacer "solo lo último" después de un reacomodo, con la pantalla: probado en la cuenta
  (`UltimosSorteados`), no con el cartel de deshacer.
- Dos PCs.

## Qué pidió, después de probar la 6.7.0

- "Yo le doy al check de cumplimiento y ya me hace el sorteo en el plano": **se pierde la emoción**.
  Lo de siempre era: el cartel, SORTEAR, carga, salen los números en la grilla y después se ve el
  plano. **El tilde iba en el cartel, no en el plano.**
- Con el tilde puesto en el plano, el cartel del SORTEO se confundía (encontraba todas las mesas ya
  dadas).
- "Todo eso de fila y columna hay que sacar del plano."
- Que sirva también con el salón **ya sorteado**, sin deshacer: "entonces ya se reacomoda según
  marca ese check".
- Que el porqué esté en el plano, **en el Historial**.
- Textos cortos, sin tecnicismos.
- Le gusta que las adicionales puedan ir "al final", después de las principales: tiene que seguir.
- "Cambiar" y "Mover" (las familias cambian de lugar y la mesa conserva su número): ya existían y
  quedan.
- **El alineador**: primero entendí guías que pegan, después botones de alinear; lo que quería era
  **"esa cruz en el mismo mouse cuando mantenés apretado"**. Lo probó en una maqueta y dijo "es así".
- Quiere **las capturas de cada prueba** antes de publicar: está en el celular.

## Cómo queda

**En el cartel del SORTEO** (grilla → SORTEO):
- Un tilde **"Cumplimiento debido"** ("Las mejores mesas, para quien mejor cumplió."), destildado.
  Tildado, debajo: **Por columnas · Por filas** (viene en columnas).
- Tildado, el cartel esconde lo que ya no decide: por división, "hasta qué mesa", "lejos" y las
  mesas nuevas al fondo. **Queda "Las mesas adicionales: Con su familia · Al final"**: con "Al
  final", primero todas las principales por orden y después las adicionales.
- Con el salón vacío, sortea así. **Ya sorteado, reacomoda**: "Se reacomoda el salón · N familias
  cambian de mesa. Nadie pierde mesas."

**En el plano:** sin tilde ni recorrido. **HISTORIAL**: "Las mesas se ubicaron por orden: N
familias", con **VER EL PORQUÉ** (solo modo jefe), mientras alguna familia siga en su mesa.

**En Acomodar, la cruz:** mientras se arrastra una mesa o un sector, dos líneas por su medio;
verde y gruesa cuando queda en línea con otro. Al soltar se va.

## Cómo está hecho

### La cuenta: `plano/services/orden_en_el_salon.dart`

`OrdenEnElSalon.paraElSorteo(...)` devuelve un `OrdenParaElSorteo`:

- **`configDelSorteo`**: el plano con cada mesa fijada ("Por orden") para su familia, **solo para
  esa corrida**. El motor de siempre se las entrega: no se tocó.
- **`configAGuardar`**: sin esas fijadas, con `frente` (quién, cuándo, el recorrido, los lugares y
  las oraciones). **Las fijadas del orden ya no se guardan**: por eso deshacer el sorteo deja el
  salón vacío, sin mesas esperando con candado.
- **`alumnosDelSorteo`** y **`exclusionDelSorteo`**: la fiesta como la tiene que ver el sorteo.

Con el sorteo ya hecho:
- Las familias que entran al orden van al sorteo **como si no tuvieran mesa** y reciben las que les
  tocan. Cada una, al menos tantas como tiene: `meta = max(las que tiene, las que le da el sorteo
  hoy)`.
- Al motor solo se le puede pedir "la base" o "todas las del contrato". Quien tiene más que las
  pagas y menos que las del contrato **se queda donde está** (darle una de menos o una de más sería
  peor).
- **Se queda donde está** también quien tiene una mesa fijada a mano por el jefe, quien está de
  baja y quien tiene un número que no se entiende. Sus mesas no se reparten.
- Una fijada de "mesa nueva al fondo" (6.5.1) no es "a mano": esa familia se reacomoda y la fijada
  se va.
- Quien tiene mesa sin haber pagado la base también se reacomoda (queda último).
- Con el sorteo hecho **por división** (bloques guardados) no se puede: sigue pendiente.

`repartir(alFinal:)`: primero las de adelante de todos, después las del final, en el mismo orden.
`sinFijadasDelOrden` y `apagado` limpian lo que dejó la 6.7.0; `vigente` dice si el porqué sigue
valiendo; `entrada` arma la entrada del sorteo; `noCumple` es el control de que cada familia quedó
en lo suyo (si no, no se guarda nada).

### El cartel: `eventos/widgets/sorteo_mesas_dialog.dart`

Recibe `eventoId` y `pagosCrudos` (sin ellos el tilde no aparece). Tildado, `_entrada()` sale de
`OrdenEnElSalon.entrada`. `_config` es el plano sin las fijadas de la 6.7.0: con eso adentro el
cartel creía que no quedaba nada por dar. `SorteoMesasDialogResult.porCumplimiento` y `recorrido`.
**El recorrido va con pastillas (`ChoiceChip`), no con un botón de dos partes**: sobre el fondo del
recuadro no se notaba cuál estaba elegido (se vio en el recorrido con el mouse).

### La grilla: `detalle_evento_masivo_screen.dart`

`_sortearMesas` le pasa al cartel los pagos que ya lee. `_ejecutarSorteoConPlano` recalcula el orden
con lo recién leído, sortea, exige `SorteoConPlano.validar` y `OrdenEnElSalon.noCumple`, y guarda
números, registro y plano en la transacción de siempre. Un sorteo entero sin el tilde apaga el
porqué de otro.

### Deshacer un reacomodo

El renglón del sorteo lleva la marca **`_reacomodo`** (`SorteoMesasRegistro.reacomodo`, adentro del
texto `resultado`: sin columna ni valor nuevo en `tipo`). Con ella, `UltimosSorteados.de` devuelve a
cada familia **a su mesa de antes** (hasta ahora "deshacer solo los últimos" solo sabía sacar lo que
un sorteo había sumado). Si alguna de esas mesas ya la tiene otra familia, **ninguna de las movidas
se toca**. Una versión anterior no conoce la marca: dice "no quedó anotado qué mesa tenía antes" y
no las toca, que es lo seguro.

### La cruz: `plano/services/cruz_de_alineado.dart`

Cuenta pura. Un sector se alinea con los otros sectores y con el medio del playón (si la hoja trae
su borde: sin borde, la caja de la hoja crece al arrastrar y no hay un medio que valga). Una mesa,
con las otras mesas (su fila y su columna); con el medio de un sector no, porque quedaba "en línea"
con el medio de la pasarela en vez de en su fila. `SesionAcomodo` la guarda mientras dura el arrastre
y `PintorAcomodo` la dibuja.

**A menos de medio paso de la línea (12 cm), lo arrastrado queda justo en línea.** Él pidió que no
se pegue; pero todo se mueve de a un cuarto de metro desde donde estaba, y sin ese ajuste podía no
caer nunca en línea con algo que no está en esa grilla (la cruz no se ponía verde nunca). No se
nota al arrastrar.

## Probado

- `test/orden_en_el_salon_test.dart` (33): vacío, ya sorteado, "al final", por filas, lo fijado a
  mano, la mesa nueva al fondo, deshacer lo último, lo que dejó la 6.7.0, y el sorteo de verdad con
  40 semillas.
- `test/sorteo_por_cumplimiento_dialog_test.dart`: el cartel.
- `test/cruz_de_alineado_test.dart`.
- `test/plano_evento_screen_test.dart`, grupo "Cumplimiento debido": el plano sin tilde y el
  Historial.
- `tool/orden_del_frente_test.dart` sobre la copia de la base, con `recorrido=filas` y
  `adicionales=final`: 47 familias en 54 mesas; en un reacomodo sobre un sorteo común cambian de
  mesa 46 de las 47.
- `tool/plano_prueba.dart`: el ícono del cartel sirve también con familias sentadas, y hay un ícono
  de Historial.
