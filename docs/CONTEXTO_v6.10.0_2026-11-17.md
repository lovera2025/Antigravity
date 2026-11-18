# CONTEXTO — la 6.10.0: la planilla del sorteo, el descuento según el sorteo, el link del delegado y "a confirmar"

**Estado (17-nov-2026, a la noche): EN CURSO, sin publicar.** Plan aprobado por el usuario ese día
(`C:\Users\lover\.claude\plans\hay-un-tema-en-precious-owl.md`), en cuatro partes. **Programadas a medias las Partes 1
y 2**; la 3 y la 4, sin empezar. Nada instalado, ningún SQL corrido, `pubspec.yaml` sigue en `6.9.1+76`.

## Para retomar en otro chat

### Dónde quedó

- **Parte 1 (la planilla del sorteo): programada y con sus pruebas.** Falta sacar las muestras en PDF y mostrárselas.
- **Parte 2 (el descuento solo para lo que la familia tenía al sorteo): programado el núcleo** (lo que se anota al
  sortear, la cuenta partida, la entrega, VENDER y los dos papeles). **Falta** la lista para revisar en PRECIOS (las
  fiestas ya sorteadas), guardar lo aceptado, `tablasDeLaPuerta`, las pruebas propias del servicio y el simulacro.
- **Parte 3 (el link del delegado) y Parte 4 ("a confirmar"): sin empezar.**
- La suite entera, al cortar: ver "Cómo quedó la suite", abajo.

### Qué pidió el usuario (17-nov) y qué decidió

1. **La planilla del sorteo confundía las entradas**: sumaba las sillas extra como "generales" ("1 con cena · 9
   generales") y no nombraba las entradas de la mesa adicional. Era la cuenta del 24-sep; la regla del 4-nov (solo la
   mesa del contrato trae 8 sin cargo) nunca se le había pasado.
2. **Regla nueva del descuento** (confirmada dos veces, con un ejemplo): las entradas de la mesa adicional y las
   sillas extra que la familia **ya tenía cargadas al sorteo, pagadas o no**, van con el descuento de PRECIOS (viene
   en 50) y **las compra cuando quiera, antes o después del sorteo**. **Lo que agrega después del sorteo paga la
   entrada entera.** Quien entra a la fiesta después del sorteo con adicional, entera. Deshacer todo y sortear otro
   día: cuenta el sorteo nuevo. Restaurar: sigue contando el sorteo que se restaura.
3. **Las fiestas ya sorteadas**: pidió que el programa lo deduzca "por huellas, con el horario". Lo que no deja
   huella queda **"para revisar"** (sus palabras), sin cobrarle entera a nadie por una duda.
4. **El link del delegado**: **todos corrigen todo** (lo ya cargado se marca "ya cargado" y se puede abrir, con un
   cartel de aviso: "total, no creo que pase nada malo"); **Enviar no bloquea**; **el único cierre es la fecha
   límite**; reabre las veces que quiera poniendo otra fecha; **lo que él ya aceptó también se puede corregir** y le
   llega para aceptar de nuevo; quiere ver **quién cargó a quién y cuándo**; y una forma mejor de administrarlo.
5. **La mesa adicional "a confirmar"** (la Parte B guardada el 16-nov): **entra en esta versión, al final.**
6. Preguntó si cada cosa lleva sus pruebas: sí, se escriben junto con cada parte.

### Lo programado (17-nov, sin publicar)

**La cuenta, una sola para todos** — `lib/features/eventos/services/retiro_entradas.dart`
- `EntradasDeAlumno` pasó a `{mesas, sillas, vip, alSorteo}`. `generales` son las que completan las 8 de la mesa del
  contrato (las sillas nunca). **`alCincuenta` ya no existe**: ahora `conDescuento`, `sinDescuento`, `aComprar`, y
  `deMesas` / `deSillas` (`LugaresAparte`), para decir cada cosa en su columna.
- Los VIP que pasan de 8 ocupan, sin pagar entrada, en este orden: las mesas que tenía al sorteo, sus sillas, y
  recién después lo agregado. Así agregar un lugar nunca le sube lo que va con descuento.
- `RetiroEntradas.entradasDe(a, {foto})`, `filaPlanilla(..., foto)`, `resumen(..., foto)`; `FilaPlanillaEntrega` y
  `ResumenRetiro` llevan `conDescuento` y `sinDescuento`.
- `alPorcientoQuePaga(descuentoPct)` → "al 50 %": un solo texto para la entrega, la venta y los papeles (el
  porcentaje es el de PRECIOS, ya no va fijo).

**Lo que se anota al sortear** — `lib/models/sorteo_mesas_registro.dart` y el servicio nuevo
`lib/features/eventos/services/lugares_al_sorteo.dart`
- Claves nuevas en el `resultado` del renglón: `_lugares` (alumno → "mesas,sillas", solo de quien tiene algo más que
  la mesa del contrato) y `_lugares_el` (solo al restaurar). **Que `_lugares` esté, aunque vacío, es lo que dice que
  el sorteo los anotó.** `SorteoMesasRegistro.resultadoConLugares(crudo, lugares)` agrega la clave sin perder
  ninguna otra, tampoco una que esta versión no conozca.
- `LugaresCargados`, `FotoDeLosLugares` (`estado`: `sinSorteo`, `sinAnotar`, `anotados`; `de(alumnoId)` da null si no
  hay nada anotado → todo con descuento; con lo anotado, quien no figura tenía solo la mesa del contrato).
- `LugaresAlSorteo.sacar(alumnos)`, `primerDelJefe(registros)`, `vigente(registros)`, `paraRestaurar(registros)`,
  `enDuda(...)` (las huellas) y `alAceptar(...)`.
- **El sorteo de la fiesta es el primer renglón del jefe que sigue en pie** (los `_auto` no cuentan). Se pensó ir
  por división y se descartó: el sorteo por división es un solo renglón para toda la escuela.
- **Cada sorteo del jefe lleva `_lugares`** (`detalle_evento_masivo_screen.dart`: `_registroSorteo` y sus dos
  llamadas de SORTEAR); Restaurar copia los del sorteo que se había deshecho (`paraRestaurar`).

**Quién lo lee**
- `fotoDeLosLugaresProvider` (en `repositories/sorteos_mesas_repository.dart`): del registro de esta PC, anda sin
  internet; **si no se puede leer, todo va con descuento**; en la web no hay base.
- `retiro_entradas_screen.dart` (mira también `sorteos_mesas`), `entrega_entradas_dialog.dart` (la segunda cuenta de
  "quedan" se fue; `VentaAlCincuenta.descuentoPct`), `vender_entradas_screen.dart` (`_foto`; avisa "Agregó N lugares
  después del sorteo…"), `entradas/cuentas/lugares_de_la_familia.dart` (`sinDescuento`).
- Lo agregado después **se vende como entrada común**, sin tipo de renglón nuevo: nada cambia en
  `VentaEntradas.nueva` ni en el cierre.

**Los papeles**
- `planilla_sorteo.dart`: `PlanillaSorteo.fila` usa `RetiroEntradas.entradasDe`; campos nuevos `entradasGenerales`,
  `entradasAdicional`, `entradasSillas`; `ResumenDivision` y `ResumenPlanillaSorteo` suman `generales`,
  `conDescuento`, `sinDescuento`. De paso se fue una alarma falsa: "(!) faltan lugares" comparaba contra la principal
  sola (con dos mesas, 10 con cena entran).
- `planilla_sorteo_pdf.dart`: "8 al 50 %" debajo de la adicional y "2 al 50 %" debajo de las sillas (acostada y
  parada), "N sin descuento" para lo agregado después, los totales en el encabezado de cada división, dos tarjetas en
  el resumen (acostada, con más de 8 van en dos renglones) y la leyenda.
- `planilla_entrega_pdf.dart`: la columna se llama como dice PRECIOS; la celda "8 (+8)" (entre paréntesis, lo
  agregado después) con su leyenda.
- `pdf_service.dart`: `foto` y `descuentoPct` en las cuatro funciones de las dos planillas.

**Pruebas hechas**
- `test/planilla_sorteo_test.dart`: el caso que confundía, 10 con cena en dos mesas, lo agregado después, quien no
  figura en lo anotado, los totales, y las palabras en las cuatro hojas (interna y para repartir, acostada y parada).
- `test/retiro_entradas_test.dart`: pasó de `alCincuenta` a `conDescuento` (sin nada anotado dan lo mismo).
- `test/helpers/entrega_en_memoria.dart`: `SorteosEnMemoria` y su reemplazo; también en
  `tool/venta_entradas_prueba.dart`.

### Lo que falta, en orden

**Parte 2, lo que queda**
1. `test/lugares_al_sorteo_test.dart` (nuevo): `LugaresCargados`; `sacar`; `vigente` (sin sorteo, sin anotar,
   anotados, pila `[auto, sorteo]`, deshacer todo, deshacer últimos); `paraRestaurar`; ida y vuelta de las dos
   claves y `resultadoConLugares` con una clave desconocida; **convivencia** (con y sin `_lugares` dan lo mismo
   `sorteosEnPie`, `esperado`, `resumir`, `lineaParaPlanilla`, `UltimosSorteados.de`, `MesaNuevaSola.ultimoDelJefe`);
   y `enDuda` / `alAceptar` caso por caso. Más un grupo en `retiro_entradas_test` con la partición
   (`conDescuento + sinDescuento == aComprar`; agregar después nunca sube `conDescuento`; VIP > 8).
2. `SorteosMesasRepository.completarLugares(...)`: actualiza la fila de esta PC con `resultadoConLugares` (sobre el
   texto crudo) y encola la fila entera. La nube tiene política `for all` y el disparador de `updated_at`
   (`supabase/migrations/20260925120000_sillas_retiro_sorteos.sql`), y la subida de un `insert` es un `upsert`.
3. **PRECIOS** (`entradas/widgets/precios_de_entradas_dialog.dart`, solo modo jefe): con los lugares anotados, la
   línea "El descuento vale para lo cargado al sorteo del dd/mm"; en una fiesta **sorteada sin anotar**, la lista de
   `enDuda` con su porqué (tildados "paga entera" los que tienen huella de después; sin tildar los "para revisar") y
   **ACEPTAR**, con internet y releyendo alumnos y registro antes de guardar. Hasta que acepte, la fiesta sigue como
   hoy. Un recordatorio en ENTRADAS, en modo jefe, mientras falte.
4. `sync_engine.dart`: `sorteos_mesas` en `tablasDeLaPuerta` (la tablet que vende sin internet la necesita).
5. `test/solo_modo_jefe_test.dart` (el guardado nuevo, solo donde corresponde) y
   `test/venta_entradas_no_toca_test.dart` (la venta no escribe el registro).
6. **Simulacro sobre una copia de la base** (`tool/simulacro_lugares_al_sorteo_test.dart`, con
   `tool/copiar_base_solo_lectura.py`; la app instalada cerrada, se le pide a él): por cada fiesta ya sorteada, a
   quién propone "agregó después" y por qué. La lista va a `build/` (con nombres, fuera de git) y **la ve antes de
   publicar**. Sin nada aceptado, las cuentas de todos tienen que dar igual que hoy.
7. Las muestras: `tool/planilla_sorteo_muestra_test.dart` (con una familia que agregó después),
   `tool/planilla_entrega_muestra_test.dart` y `tool/venta_entradas_muestra_test.dart`. **Mandarle los PDF.**

**Parte 3 — el link del delegado** (todo el detalle, con las funciones una por una, en el plan)
1. **La maqueta primero** (`docs/maqueta_link_delegado_2026-11-17.html`): el panel nuevo en dos direcciones y la
   página del celular. **Se programa con su OK.**
2. SQL nuevo, solo de agregar: `supabase/migrations/20261117120000_link_delegado_reabrir.sql`. Ninguna función
   cambia de firma **ni de lo que devuelve** (`delegado_alumnos` es `returns table`: no se le puede agregar una
   columna con `create or replace`; lo de más va en una función nueva). Tabla nueva `cambios_delegado` (el
   historial). Se prueba en `tool/delegado_sandbox/` antes de darlo por bueno.
3. La página, la ventana propia (PLANILLAS ▾ → "Link para los delegados") y las pruebas.
4. Por qué no los dejaba entrar (diagnóstico del 17-nov): el delegado se reconoce por el navegador (un token en
   `localStorage`), no por la persona; el cupo cuenta aparatos y viene en 1; con el cupo lleno la página ni pide el
   nombre; cambiar la fecha no le reabre a quien ya envió; y REABRIRLE actúa sobre la fila del aparato viejo.

**Parte 4 — "a confirmar"**: `git stash pop` (`stash@{0}`), y lo que falta está en "La Parte B" de
`docs/CONTEXTO_v6.9.1_2026-11-16.md`. Su derecho al descuento no cambia (ya la tenía cargada).

**Después**: la suite entera, la versión `6.10.0+77` (`pubspec.yaml` y el `.iss`), CLAUDE.md, y publicar con él (foto
de la mora, el SQL del link con su OK en el momento, instalador por pasos, release y web).

### Lo que hay que saber antes de tocar

- **Una prueba que monte la entrega o VENDER tiene que reemplazar `sorteosMesasRepositoryProvider`**
  (`EntregaEnMemoria.reemplazos` ya lo hace; quien arme su lista a mano, con `entrega.sorteos`). Sin eso, esas
  pantallas van a leer el registro por `LocalDatabase.instance`: en `flutter test` no falla, se queda esperando (la
  pantalla no termina de cargar y 38 pruebas daban "no encontré el texto"). Se comprobó que la base de la PC no se
  tocó (su última modificación era de antes). En una ventana de prueba, `cerrarParaLaPrueba` lo hace fallar y el
  provider contesta "todo con descuento".
- **Aceptar la lista de una fiesta ya sorteada le agrega `_lugares` al renglón del sorteo que ya existe.** Es la
  única excepción a "solo se agregan renglones", y el usuario la aprobó con el plan: un renglón aparte rompería
  "deshacer solo los últimos" (la pila haría `removeLast` de ese renglón), el HISTORIAL ("Sorteo: 0 familias") y la
  línea de los papeles. Nada de lo que el renglón dice del sorteo cambia. **Hay que escribirlo en CLAUDE.md, con su
  test**, cuando esté programado.
- **`mora_cambios` no sirve de huella**: el trigger anota solo cuando cambia un campo de la mora, no cuando se
  agrega una mesa.
- **Lo que una huella no puede decir**: una adicional que recibió su número después del sorteo pudo estar cargada
  antes sin pagar (va "para revisar"). La única huella segura de "vino después" es el alumno cargado después del
  sorteo, o una mesa que el programa dio sola **sin ningún pago de mesa hasta ese momento** (solo pasa al agregarla
  con el sorteo hecho, la regla del 11-nov).
- **Un equipo con la 6.9.x no conoce la regla** y vende todo con descuento: al publicar, "no vender entradas desde un
  equipo sin esta versión".
- `ConfigEntradas.kDescuentoDeLosLugares` es una constante **de la clase**, no suelta.

### Cómo quedó la suite

`bash tool/suite_por_tandas.sh`, el 17-nov a la noche: **5.189 pruebas, ninguna falla** (301 archivos). La única que
falló en la primera pasada fue `test/plano_evento_cuerpo_test.dart` ("En la principal: 4 con cena · 6 generales"):
el panel del PLANO usa la misma cuenta que la planilla y ahora dice "4 generales". **Queda para mirar:** ese panel
no dice las entradas que se compran aparte (las de las sillas y la adicional); si hace falta, se le suma un renglón.

`flutter analyze` sobre `lib`, `test` y `tool`: sin errores nuevos (los tres que marca son de
`tool/_tmp_espindola_audit.dart`, de antes).

### Lo que no se va a poder probar acá

Un celular de verdad abriendo el link desde WhatsApp, y la venta con la regla nueva en una tablet sin internet.
