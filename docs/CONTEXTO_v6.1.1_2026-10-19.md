# v6.1.1 — Lo que se borra en una PC desaparece también en la otra

**Fecha:** 2026-10-19
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Estado: PROGRAMADA el 19-oct, sin publicar ni instalar.** La versión en `pubspec.yaml` y en el instalador sigue en
6.1.0: se sube al armar la versión, con su OK.

> Anterior: [v6.1.0](CONTEXTO_v6.1.0_2026-10-18.md), publicada el 19-oct e instalada en la PC de la casa y en la del
> operario; la del jefe sigue con la 6.0.0 y puede pasar directo a la 6.1.1.
> Plan del chat, aprobado con ExitPlanMode: `C:\Users\lover\.claude\plans\donde-nos-quedamos-sparkling-puffin.md`.
> El usuario trajo una spec escrita en otro chat ("SPEC — Pagos borrados que sobreviven en la otra PC y pisan el
> saldo en la nube"); lo que pedía está acá, con dos cambios que se explican abajo.

## Qué pasó el 19-oct

Lo contó él: "en la PC del modo jefe borré un dato y en la PC del modo jefe se borró, pero no actualizó la del
operario". Lo que quiere: **lo que se borra o se cambia en modo jefe tiene que verse al instante en la del operario,
como pasa cuando se perdona la mora.**

- **DE CARLO, MICAELA ESTEFANIA** (Colegio Nacional, pactado $296.100). A las 18:08 el jefe borró con la escobita
  una entrega de $60.000 del 28/05. A las 18:09 el operario le cobró la entrega de $60.000 de ese día. Su PC todavía
  tenía el pago borrado, contó los dos y subió un saldo de **$176.100 en vez de $236.100**. Lo volvió a subir a las
  18:27, al guardar una nota. El usuario corrigió el saldo en la nube y borró a mano el pago en la PC del operario.
- **ZAMPALLONI, JOSIAS**: a las 17:31 el jefe borró un pago de $35.000 del 21/04 ("Cuota Base (1/9)"). En la nube
  está bien (pactado $350.000, dos pagos del 19-oct, saldo $230.000). Pero el pago seguía en la PC de la casa y casi
  seguro en la del operario: si le cobraban ahí, le pisaban el saldo con $195.000.

**Lo que se miró, solo leyendo:**
- **La nube está bien**: en los 643 contratos el saldo coincide con el pactado menos los pagos (sin mora ni cargo por
  canal, como `pagoCuentaParaClaseCobro`).
- **Los registros de la nube**: las dos PCs de la oficina entran con el mismo usuario y se distinguen por la sesión.
  La del operario bajaba alumnos y pagos cada pocos segundos, sin cortes: **los cambios le llegaban**. Los dos
  borrados los hizo la otra sesión, la del jefe, que dejó de conectarse a las 18:40.
- **La PC de la casa**, cerrada desde las 14:16, tenía los 2 pagos borrados y **23 renglones de presupuesto borrados**
  en agosto y septiembre, en tres presupuestos: uno mostraba 27 renglones donde la nube tiene 9. Egresos,
  transacciones, notas y servicios de evento, iguales a la nube.
- Los permisos de la nube dejan ver todas las filas de esas tablas a cualquier usuario con sesión: una foto de la nube
  es entera.

## Por qué pasaba

**Un cambio cruzaba; un borrado no.** El pull baja lo nuevo y lo cambiado (`updated_at`), nunca lo que dejó de
existir. Un borrado tenía dos caminos, y los dos fallaban:
1. **El aviso al instante (el pulso)** llevaba los borrados, pero si llegaba con la PC ocupada (baja datos cada 10
   segundos) se tiraba a propósito: "el ciclo de siempre lo cubre". Para los borrados no había ciclo que lo cubriera.
   Desde acá no se pudo saber por qué se perdió el de las 18:08: la PC ocupada, la conexión cortada, o algo que lo
   pierde siempre.
2. **La revisión de cada 10 minutos** miraba solo seis tablas padre (clientes, eventos, presupuestos, contratos,
   alquileres y servicios), con el comentario "las hijas caen por cascada". Eso vale cuando se borra el padre, no
   cuando se borra un pago suelto con el alumno vivo.

Y con el pago todavía adentro, `recalcularProgresoContrato` (al cobrar, editar o anotar) rehacía la cuenta con los
dos y la subía.

## Qué cambió

Todo en `lib/core/services/sync_engine.dart`, el archivo nuevo `lib/core/services/borrados_de_otra_pc.dart` y
`ContratosRepository`. Sin cambios en la base ni en la nube.

1. **El aviso de un borrado no se tira.** Si llega con la PC ocupada, se guarda y se reintenta a los 3 segundos
   (`_atenderElPulso`). Las tablas a bajar se sueltan como antes: el ciclo de 10 s las baja igual.
2. **La cuenta de cada ciclo de 10 s** (`_contarParaVerBorrados`), agregada a pedido suyo durante el trabajo ("que se
   actualice instantáneamente"). Después de bajar, cuenta en la nube los pagos, los alumnos y los egresos (un
   `count`, sin bajar nada). Si en la nube hay menos que en la PC, sin contar lo que espera subir, revisa esa tabla en
   el momento. **Así un borrado llega en 10 segundos como mucho aunque el aviso se pierda.**
3. **Al abrir un alumno se le pregunta a la nube por sus pagos** (`revisarPagosDelAlumno`). Lo llaman:
   - `getHistorialPagosAlumno`, que usan la ventana de cobro, el historial, el estado de cuenta, el recibo y perdonar
     la mora;
   - `recalcularProgresoContrato`, antes de hacer la cuenta (menos `recalcularTodoElEvento`, que recorre todos);
   - la ventana de cobro y el historial, **antes de leer la ficha**: así el saldo de arriba ya es el bueno. Si sacó
     algo, **avisa con un cartel** ("Se sacó un pago que se borró en otra PC…"): lo pidió él ("que me avise por lo
     menos").

   La consulta es de ese alumno (la lista y la cuenta en un pedido), con 3 s de tope y una vez cada 15 s por alumno.
   **Sin internet no consulta y no demora**: se cobra igual. Si la nube devuelve cero pagos, se mira que el alumno se
   vea: si no se ve, es una sesión vencida y no se toca nada.
4. **La revisión de cada 10 minutos mira todas las tablas que se borran a mano**: además de las seis, pagos,
   renglones de presupuesto, servicios de evento, egresos, transacciones, notas, obligaciones, compromisos del
   personal, anotaciones del cierre, pedidos de cotización, pagos y líneas de alquiler, operadores y sesiones de caja.
   - Sigue la regla de siempre (`_idsCompletosDeLaNube`, `fotoDeLaNubeEsCreible`, `filasAPodar`): sin foto completa
     y contada no se borra nada, lo que espera subir no se toca, y no se manda ningún borrado a la nube.
   - **Lee lo de la PC y la cola antes que la nube.** Al revés, como era, un cobro que subía mientras se leían las
     páginas de la nube no estaba en la foto ni en la cola, y se tomaba por borrado.
   - **Al abrir el programa corre antes que la revisión de la mora**, que se rehace desde los pagos.
   - Las tablas que no se revisan están en `_tablasSinRevisarBorrados`, con el motivo. `invitados` queda afuera:
     tiene su propio camino.
5. **Al sacar un pago, se rehace la cuenta del alumno**, solo si sus pagos quedaron iguales a los de la nube. Si
   falta bajar alguno, la cuenta daría que debe de más y subiría: se rehace la próxima vez que se lo toque.
6. **Queda escrito** en `Documentos\Junior Eventos\borrados_en_otra_pc.txt`, con la fecha, por qué camino se enteró
   la PC (el aviso, la cuenta, al abrir el alumno o la revisión) y un renglón por cosa: un pago con el alumno, el
   monto, la fecha y el concepto. Así se sabe, en cada PC, si el aviso al instante anda.

**Lo que cambió de la spec:**
- En vez de la herramienta de `tool/` para buscar pagos de más en una PC, está el archivo del punto 6. En las PCs de
  la oficina no se puede correr un script, y la versión misma los saca y los anota.
- Se sumaron la cuenta de cada ciclo (punto 2), el aviso en pantalla y las tablas que no son pagos.

## Lo que se probó

- `test/borrados_de_otra_pc_test.dart`, 20 tests sobre una base temporal y una nube simulada:
  - DE CARLO con sus números: al abrirla queda un pago, el saldo $236.100, se sube ese saldo y no se manda ningún
    borrado. Igual por el historial, antes de cobrar, por la revisión y por la cuenta de cada ciclo;
  - un cobro que espera subir no se toca, tampoco si sube en el medio de la revisión;
  - con una foto incompleta, o una nube que no devuelve ni el alumno, no se toca nada;
  - sin internet no consulta nada;
  - si le falta bajar un pago, saca el borrado pero no rehace la cuenta;
  - el aviso que llega con la PC ocupada se aplica igual;
  - toda tabla que se baja dice si se revisa, y todo borrado a mano del código se revisa.
- **Cada arreglo, roto a propósito, hace fallar su test** (ocho roturas): el aviso que se tira, la nube leída antes
  que la cola, los pagos fuera de la revisión, el recálculo y el historial sin consultar la nube, el cero sin mirar
  el alumno, la cuenta rehecha aunque falten pagos, y sin la cuenta de cada ciclo.
- **`flutter test` entero: 2.722 tests bien** (los 2.702 de la 6.1.0 más estos 20). **`flutter analyze`: 312**, los
  mismos de la 6.1.0; ninguno nuevo.
- La comparación del cobro con la 6.1.0 (`tool/cobro_igual_que_hoy_test.dart`) no se corrió: arma el repositorio
  sin nube y el código del cobro no cambió, así que da idéntico por construcción. La prueba con datos reales es al
  instalar en la PC de la casa (abajo).

## Hasta instalar

- **ZAMPALLONI, JOSIAS en la PC del operario:** si su estado de cuenta muestra el pago de $35.000 del 21/04,
  borrarlo ahí con la escobita (el borrado que va a la nube no toca nada: ese pago ya no está). Hasta entonces, en
  esa PC no se le cobra, no se lo edita y no se le anota nada.
- **Después de borrar un pago en una PC, mirar en la otra** que haya desaparecido; si sigue, borrarlo también ahí.
- **En la PC de la casa, no abrir el programa** hasta instalar la 6.1.1: la revisión de la mora haría la cuenta de
  DE CARLO y ZAMPALLONI con el pago de más.

## Publicar (con él presente; cada paso con su OK)

0. Subir la versión a 6.1.1 en `pubspec.yaml` y en el instalador, `flutter test` entero, `flutter analyze`, armar el
   instalador y el release.
1. **La PC de la casa primero**: copia de la base con el programa cerrado, instalar, y mirar que saque
   **exactamente** los 2 pagos y los 23 renglones, y nada más (comparado con la nube y con la copia, tabla por tabla).
2. **La del operario.** Mirar qué escribió en `borrados_en_otra_pc.txt` y que ZAMPALLONI quede igual que la nube.
   Prueba sin plata, con las dos PCs abiertas: anotar una nota en ARGUELLO, TOMAS en una y borrarla; en la otra tiene
   que desaparecer en segundos, y el archivo dice por qué camino.
3. **La del jefe**, de la 6.0.0 directo a la 6.1.1. Después, **lo de TOÑANEZ** que quedó de la 6.1.0 (ver "La
   publicación" en su CONTEXTO): la misma sentencia de las 16:15, con su OK, y que su ventana de cobro diga $171.600.
4. La web no cambia (no tiene base en la PC).

## Para seguir en otro chat, pegar

```text
Seguimos con la 6.1.1 de Junior Eventos. Leé primero
docs/CONTEXTO_v6.1.1_2026-10-19.md entero, la sección "La publicación" de
docs/CONTEXTO_v6.1.0_2026-10-18.md, CLAUDE.md y la memoria del proyecto.
La 6.1.0 está publicada e instalada en la PC de la casa y en la del operario;
la del jefe sigue con la 6.0.0. La 6.1.1 está programada en la rama y sin
publicar: lo que se borra en una PC desaparece también en la otra (el aviso
que no se tira, la cuenta de cada 10 segundos, al abrir un alumno y la
revisión de cada 10 minutos de todas las tablas que se borran a mano).
Sigue publicarla conmigo: la PC de la casa primero (tiene que sacar los 2
pagos y los 23 renglones de presupuesto), después la del operario y la del
jefe, y con la del jefe instalada, lo de TOÑANEZ.
Contestame primero lo que te pregunto, en una línea, y siempre en español.
Lo que toque la base real o la nube, con mi OK en el momento. No corras la app
desde el working tree. Con "actualizá el contexto", frená y dejá todo anotado.
```
