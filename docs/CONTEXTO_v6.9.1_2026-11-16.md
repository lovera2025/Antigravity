# CONTEXTO — la 6.9.1: "Primero las familias de una sola mesa" en el cartel del SORTEO

**Estado (16-nov-2026, a la noche): PROGRAMADA y probada en el sandbox, con el salón justo resuelto. Falta publicar
con el usuario.** El usuario eligió publicar el tilde solo, primero, como **versión 6.9.1**. La decisión del salón
justo la tomó en el segundo chat del 16-nov, sobre un dibujo (ver "El salón justo: una detrás de la otra", abajo).
La mesa adicional "a confirmar" (la Parte B) quedó guardada aparte, sin terminar.

## Para retomar en otro chat

### Lo que pidió el jefe (16-nov) y lo que decidió el usuario

- **Un tilde en el cartel del SORTEO: "Primero las familias de una sola mesa".** Las familias con **una sola mesa en el
  contrato** van en las primeras filas; detrás, las que tienen adicional.
- Se combina con "Las mesas adicionales": **Con su familia** (detrás, cada familia con todas sus mesas juntas) y **Al
  final** (primero las de una sola mesa, después las principales de las demás y al final las adicionales).
- Con **Cumplimiento debido**: cada grupo ordenado por cumplimiento.
- Cuenta **el contrato**: quien contrató una adicional y no la pagó va atrás (aunque hoy se le sortee solo la base).
- **Reglas que el usuario repitió el 16-nov y no se negocian:** ninguna familia de una sola mesa va atrás, y **la
  principal y sus adicionales van siempre juntas** (con "Con su familia").

### Lo programado del tilde (commit `ed01cec`)

- `lib/features/plano/services/sorteo_con_plano.dart` (**el motor no se tocó**):
  - `EntradaSorteoPlano.unaMesaPrimero` (y en `conPasto`); `SorteoConPlano.primerGrupo(e)` y `vaEnElPrimerGrupo`: una
    sola cuenta para sortear y para `validar` (`MesasExtraUtils.cantidadMesasFisicasSorteo(a) <= 1`, solo en el
    sorteo entero).
  - `_entera`: la pasada de adelante se parte en dos con el mismo `_sortearEn`: primero las de una sola mesa (y lo que
    se completa a quien ya tiene mesa), después, con todo lo de antes tapado, las nuevas con adicional. "Hasta qué
    mesa" estira el segundo grupo. "Al final" sigue después.
  - `PlanSorteo.unaMesaHasta` y `conAdicionalDesde` (la vista previa).
  - `validar`: ninguna mesa de una familia con adicional antes que una de una sola mesa (por casillero).
- `lib/features/plano/services/orden_en_el_salon.dart` (Cumplimiento debido; **el puntaje no se tocó**):
  - `paraElSorteo(unaMesaPrimero:)` y `primeroUnaMesa(orden)`: parte el orden (las de 1 mesa por contrato primero), sin
    cambiar el orden adentro de cada grupo, y renumera el puesto. La frase de las que tienen adicional suma
    `fraseConAdicional`.
  - `repartir(juntasEnLaFila:)` (solo con el tilde): cada familia de varias mesas va en la primera **tira** libre de su
    fila y su lado, una detrás de la otra. Sin esto, con el tilde quedaban familias partidas en el borde de una fila
    (el diagnóstico lo mostró: 3 de 12 contra 1 de 12 sin el tilde). Las del final no usan los huecos de antes de la
    última de adelante, **salvo que sin ellos no entren**.
  - `OrdenDelPlano.unaMesaPrimero` (clave `una` en `frente`).
- `lib/features/plano/widgets/ver_el_orden_dialog.dart`: VER EL PORQUÉ con los títulos "Una sola mesa" y "Con
  adicionales".
- `lib/features/eventos/widgets/sorteo_mesas_dialog.dart`: el tilde (`primero_una_sola_mesa`) dentro de
  `_lasAdicionales`, debajo de los chips; viene destildado; por división apagado con el motivo. Vista previa
  `una_mesa_rangos` ("Una sola mesa: de la 1 a la 24 · Con adicionales: de la 25 a la 36." / con "Al final", tres
  tramos; con Cumplimiento, una frase). Avisos `una_mesa_aviso`: salón que no está numerado "Fila por fila", y
  Cumplimiento "Por columnas".
- `lib/features/eventos/services/sorteo_del_cartel.dart` (**nuevo**): `SorteoDelCartel.armar(...)`, `sortear()` y
  `controlFinal()`. **Un solo camino** de lo elegido en el cartel al sorteo: lo usan `_ejecutarSorteoConPlano`
  (`detalle_evento_masivo_screen.dart`), `tool/plano_prueba.dart` y las pruebas.
- `SorteoMesasDialogResult.unaMesaPrimero`; `SorteoMesasRegistro.unaMesaPrimero` (clave `_una_primero` en
  `resultado`; una versión anterior la ignora); `ArmarAMedida.esAMedida`.

### Lo que se probó (antes de la discusión del salón justo)

- `test/sorteo_una_mesa_primero_test.dart` (servicio y Cumplimiento) y
  `test/sorteo_una_mesa_primero_de_punta_a_punta_test.dart` (**el cartel de verdad → SORTEAR → el PLANO de verdad**,
  con `test/helpers/plano_en_memoria.dart`, 6 combinaciones × 40 semillas).
- **7 reglas rotas a propósito** (`tool/romper_una_regla.sh`): las pruebas fallan en las 7.
- **Suite entera: 5.162 pruebas en verde** (con el tilde solo, sin la Parte B).
- **Simulacro sobre una copia de la base** (`tool/simulacro_una_mesa_primero_test.dart`, copia del 16-nov en el
  scratchpad de la sesión; la base real quedó igual): 8 fiestas con plano; ningún sorteo con problemas. Las familias
  con mesa fijada a mano quedan fuera de los grupos (como en la app).
- **Con el mouse** en `tool/plano_prueba.dart` (huella de la base IGUAL antes y después). Las capturas, en
  `build/capturas_tilde/` (se le mandaron).

### El salón justo: una detrás de la otra (decidido y programado el 16-nov, segundo chat)

Lo que dijo el usuario: "que los que tienen mesa principal, o sea juntas, que van atrás, ellos o algunos de ellos,
mientras sea juntos, ocupen algunos huecos". Se le mostró un dibujo (izquierda: hoy, dos huecos de una mesa junto a la
pasarela y una familia sin lugar; derecha: esa familia con la mesa del hueco y la de atrás) y eligió **"Sí, así"**:
**solo cuando no entra de otra forma, la familia con adicional tapa el hueco junto a la pasarela con sus mesas una
detrás de la otra, del mismo lado de la pasarela.** Nadie de una sola mesa va atrás y cada familia queda junta. El
plan aprobado: `C:\Users\lover\.claude\plans\sigamos-donde-nos-quedamos-vectorized-adleman.md`.

Lo programado (el motor del sorteo **no** se tocó):
- **`plano/services/mesas_juntas.dart` (`MesasJuntas`)**: una sola regla de "juntas" para el control final, la
  pantalla y el papel. Juntas = seguidas y pegadas (los tramos de siempre, `tramosPegados`) **o una detrás de la
  otra** (`unaDetrasDeLaOtra`: pegadas y en línea, nunca en diagonal ni a los dos lados de la pasarela). `grupos`,
  `juntas`, `usaUnaDetrasDeLaOtra` y `capsulas` (la línea de la cápsula: el tramo, o el recorrido que pasa por la de
  atrás).
- **`plano/services/familias_en_los_huecos.dart` (`FamiliasEnLosHuecos.acomodar`)**: búsqueda con vuelta atrás sobre
  las mesas libres en el orden del recorrido; cada familia en mesas seguidas o una detrás de la otra, y **las menos
  familias posibles una detrás de la otra**. Sin azar da siempre lo mismo y la primera de la lista toma el primer
  lugar (Cumplimiento); con azar, cada sorteo distinto. Guarda los callejones sin salida (`fallidas`) y tiene un tope
  de pasos: nunca se cuelga.
- **`sorteo_con_plano.dart` `_entera`**: si las familias con adicional no entran en mesas seguidas detrás de las de
  una sola mesa (y ninguna tiene "lejos"), `_enLosHuecos` las ubica con la menor capacidad (buscada por mitades) y
  `PlanSorteo.unaDetrasDeLaOtra` dice cuántas. `validar` mide "juntas" con `MesasJuntas`.
- **`orden_en_el_salon.dart` `repartir(armado:)`** (Cumplimiento debido con el tilde): si con las tiras alguna
  familia con adicional quedaba partida, se ubican de nuevo con `FamiliasEnLosHuecos`, en el orden del cumplimiento.
  **Antes, con el salón justo, Cumplimiento dejaba familias partidas sin avisar** (una quedó con la 1, la 21 y la
  22): lo mostró la prueba nueva.
- **El dibujo y el papel** (`familias_en_el_plano.dart`): la familia una detrás de la otra lleva la cápsula, no el
  aro punteado. **En un plano ya sorteado no cambia ninguna mesa**: solo una familia que ya tenía una mesa justo
  detrás de la otra con números no seguidos (p. ej. una adicional completada pegada) se dibuja con la cápsula en vez
  del aro y la flecha. `cambios_de_mesa.dart` dice "queda con sus mesas juntas" con la misma regla.
- **El cartel** (`sorteo_mesas_dialog.dart`): sin rojo; debajo de los rangos, en gris (`una_mesa_detras`): "Con el
  salón justo, N familias con adicional quedan con sus mesas una detrás de la otra, junto a la pasarela." El rojo
  queda solo si ni así entra. Con Cumplimiento debido no hay línea de rangos (como antes): se ve en el plano.

### (Historia) La decisión que estuvo abierta: el salón justo

Con el salón **justo** (las mesas exactas, como la ventana de prueba con 35 mesas para 35, o 1 de las 8 fiestas del
simulacro con "Con su familia"), **con el tilde no entra**: las familias con adicional no se parten en la pasarela y
quedan huecos que solo taparía una de una sola mesa. Hoy el cartel lo dice en rojo ("Agregá mesas en Acomodar, o sacá
el tilde") y no deja sortear. Con "Al final" ese mismo salón sí entra.

Lo que pidió el usuario el 16-nov, en orden: "que me deje sortear sin que salga ese cartel"; después "la idea es que
eso de que vayan atrás no pase"; después "ojo que las principales y adicionales deben ir juntas". **Las tres juntas no
se pueden cumplir en un salón justo.** Lo que ya se probó y se descartó:
- Mandar atrás a las menos de una sola mesa que hagan falta → **rechazado** ("que no vayan atrás").
- Separar la adicional de una familia a otra mesa libre → **rechazado** ("deben ir juntas").

Lo que se iba a proponer (agregar las mesas que faltan al fondo, o sugerir "Al final") quedó de lado: el 16-nov
eligió "una detrás de la otra" (arriba).

**Estado del código en este momento:** se volvió a la versión **estricta** (la probada): con el salón justo, frena con el
cartel rojo ("Agregá mesas en Acomodar, o sacá el tilde") y SORTEAR queda apagado; sacando el tilde, deja sortear. En
`sorteo_con_plano.dart`, `sorteo_mesas_dialog.dart` y `orden_en_el_salon.dart` no queda nada de los dos intentos
descartados. Las pruebas del tilde (35) pasan, también la del salón justo (frena), y la suite entera se corrió antes
del commit.

### Lo que se probó del salón justo (16-nov, segundo chat)

- **Pruebas nuevas**: `test/mesas_juntas_test.dart` (qué es juntas, la cápsula) y `test/familias_en_los_huecos_test.dart`
  (el salón de 35 para 35: entra con una sola familia una detrás de la otra, la 25 con la 33; nunca cruzando la
  pasarela ni en diagonal; sin azar siempre igual y la primera de la lista en el primer lugar; con azar, distinto
  cada vez; **las menos posibles, comparado con una cuenta a fuerza bruta en 300 pedazos de salón al azar**; un salón
  de 81 mesas no tarda, entre o no entre).
- **Cambiadas**: "salón por salón" (de 25 a 40 mesas: si sin el tilde entra, con el tilde también, y en los sorteos
  las que quedan una detrás de la otra son las que dijo la vista previa), la de punta a punta (el cartel de verdad sin
  rojo y con la línea gris, SORTEAR con 40 semillas, y el PLANO de verdad sin familias separadas y con la cápsula por
  las dos mesas) y una nueva de punta a punta con **Cumplimiento debido (por filas y por columnas, con su familia y
  "Al final") en el salón justo: cada familia junta**. `test/familias_en_el_plano_test.dart`: la familia una detrás
  de la otra lleva cápsula.
- **8 reglas rotas a propósito** (`tool/romper_una_regla.sh`, casos en el scratchpad de la sesión): las pruebas fallan
  en las 8. La de "las menos posibles" no la agarraba ninguna prueba hasta que se sumó la de fuerza bruta.
- **Simulacro sobre una copia de la base del 16-nov** (`build/simulacro_691/`, sin nombres): 8 fiestas, ningún sorteo
  con problemas y **ninguna "NO ENTRA con el tilde"**. La fiesta 6 (la que antes frenaba) entra con 2 familias una
  detrás de la otra, lo mismo que dice el cartel. Con Cumplimiento, 0 familias partidas con el tilde (sin el tilde,
  hasta 1 en algunas fiestas, como siempre). El simulacro ahora cuenta las partidas con `MesasJuntas` (las que
  pidieron "lejos" no cuentan) y las que quedan una detrás de la otra.
- **Con el mouse** en `tool/plano_prueba.dart` (35 mesas para 35, numerado "Fila por fila"): el cartel con la línea
  gris, el plano después de sortear (la familia de 3 en la 30, la 29 y la 33, con la línea en L) y Cumplimiento
  debido por filas (una familia en la 29 y la 33). Capturas en `build/capturas_691/` (**se le mandaron**). IMPRIMIR
  dejó el PDF (`build/plano_prueba/`); no se pudo pasar a imagen en esta PC, pero el papel usa las mismas cápsulas
  (`FamiliasEnElPlano.capsulas`) y sus pruebas pasan. La huella de la base dio IGUAL antes y después.
- **Ojo:** la huella dice que **la base de esta PC ya está en la versión 80** (la de la 6.9.0): la 6.9.0 se abrió en
  esta PC. Preguntarle al usuario en qué PCs la instaló antes de dar por hecho lo de "ninguna PC la tiene".

### Lo que falta, en orden

1. ~~Decidir el salón justo~~ (16-nov: una detrás de la otra) y ~~programarlo con sus pruebas~~ (hecho).
2. ~~Versión 6.9.1~~: `pubspec.yaml` → `6.9.1+76`; `installer/junior_eventos_setup.iss` → `MyAppVersion "6.9.1"`.
3. ~~La suite entera~~ (5.182 pruebas, ninguna falla) y ~~el commit~~ (solo el tilde y el salón justo: la Parte B
   sigue en el stash).
4. **Publicar con él**, como la 6.9.0 (su "Cómo se publicó"), preguntando cada paso: la foto de la mora "antes de
   6.9.1" (`supabase/mora_fotos.sql`, por el conector), **sin SQL**, el instalador **por pasos** (el script de la
   6.9.0 está copiado en el scratchpad de la sesión: la clave de firma, la página del celular de cero con sus tres
   archivos, `ISCC` y su lista de archivos, el APK con `apksigner`), comparar los commits con los nombres de la copia
   antes de subir, el tag `v6.9.1`, el release con el Setup y el APK y las novedades, y la web en Vercel.

### La Parte B: la mesa adicional "a confirmar" (sin terminar)

- **Guardada en `git stash`**: `stash@{0}` "Parte B: la mesa adicional a confirmar (sin terminar, 16-nov)". Copia de
  respaldo fuera del repositorio: `..\respaldo_parte_b_a_confirmar_16nov\` (`cambios.patch` y los dos archivos
  nuevos). Para retomarla: `git stash pop` (no choca con el tilde: son otros archivos).
- **Lo decidido por el usuario:** la noche de la fiesta, la adicional que no está paga entera se ve **"a confirmar"**,
  apagada y discreta (ni "debe" ni "sin pagar"; la familia puede ver la pantalla). La recepcionista **no** cobra ni
  anula: al tocar, solo "Esta mesa la confirma el jefe". El tótem enciende solo las mesas pagas. **COBRAR y ANULAR,
  solo en el PLANO y en modo jefe.** Con algo pagado, esa noche **no** se anula (lo decide el jefe en la oficina); con
  $0, ANULAR baja la adicional del contrato y deja la mesa libre.
- **Hecho en el stash:** `AdicionalesDeLaFamilia` (`recepcion/services/adicional_a_confirmar.dart`, de los pagos con
  `grossHistoricoClaseCobro` + `MesasExtraUtils.repartirPagadoFifo`; sin pagos (null) no marca nada) con 12 pruebas;
  los pagos en `leerAlumnosDeLaPuerta` (y `pagos_contrato_alumno` en las tablas que relee la puerta);
  `PuertaDelEvento.masivo(pagos:)`, `GrupoPuerta.mesasAConfirmar`, `adicionalesSinMesa` y `mesaConfirmada`;
  `SillasDeUnaMesa.aConfirmar` (sin lugar para sillas, texto discreto) y `EstadoMesaPuerta.aConfirmar`; la línea
  apagada con la nota en `panel_puerta.dart`; `decidirSilla`; la ficha del tótem con `mesaConfirmada`. **Sin probar
  esa parte de Recepción y el tótem.**
- **Falta:** dibujar la mesa punteada "a confirmar" (VER EN EL PLANO de la recepcionista y el PLANO del jefe:
  `VistaPlano`/`PintorPlano`, el aro punteado ya existe en `pintor_plano.dart` `_marcaDeFamilia`); en el PLANO, modo
  jefe, "A pagar: $X" con COBRAR (el plano devuelve a quién cobrarle con `Navigator.pop` y la fiesta abre
  `_mostrarModalPagoAlumno`; hoy `_abrirPlano` usa `MaterialPageRoute<void>`) y ANULAR (un `soltarUna` nuevo en
  `CambiosDeMesa` por `_cambiarMesas`, que **tiene que frenar sin internet**; y bajar la adicional del contrato por el
  mismo camino que Editar alumno: `construirParaGuardar`, `datosEdicionAlumno` sobre un contrato recién leído,
  `actualizarContrato`, `recalcularProgresoContrato`; hoy está todo adentro de `_submit` en `modal_alumno_premium.dart`
  y conviene sacarlo a un servicio). Riesgos que encontró el lector: un tipo de movimiento nuevo una versión vieja lo
  lee como "mover"; `test/solo_modo_jefe_test.dart` exige que los guardados del plano sean solo `_guardar`,
  `_cambiarConfig` y `_cambiarMesas`; la prueba de T:1894 dice que bajar pagos no recarga el plano.
- El plan aprobado de las dos partes: `C:\Users\lover\.claude\plans\hay-que-modificar-algo-jolly-torvalds.md`.
