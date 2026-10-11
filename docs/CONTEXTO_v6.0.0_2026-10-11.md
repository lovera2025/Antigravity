# v6.0.0 — El plano del salón, el sorteo por división y las entradas

**Fecha:** 2026-10-11
**Rama:** `feature/v4.6-cierre-por-sesiones`
**Con migración de base:** la local pasa de la v71 a la **v73** (cinco tablas nuevas, vacías) y la nube necesita
**dos SQL** que crean esas mismas tablas. Ninguna tabla de las que ya existen cambia. Cobros, cuentas, saldos, mora
y caja no cambian.

> **Referencia:** `CONTEXTO_v6.0.0` · `plano del salón` · `sorteo por bloques` · `retiro de entradas` · `v73`
> Anterior: [v5.0.0](CONTEXTO_v5.0.0_2026-09-24.md) (el sorteo según lo pagado).
> El detalle de cada parte, con sus decisiones y sus commits:
> [CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26](CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md) (plano, sorteo, personalizar,
> los que faltan, la verificación) y [CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25](CONTEXTO_FASE2_SILLAS_ENTRADAS_2026-09-25.md)
> (sillas, entradas, registro del sorteo).
> Plan aprobado: `C:\Users\lover\.claude\plans\en-que-nos-quedamos-radiant-gadget.md`.

**Estado: programada, verificada y con el instalador armado. SIN PUBLICAR.** Las PCs siguen con la 5.0.0.
- `pubspec.yaml` en `6.0.0+57` y el `.iss` en `6.0.0` (`8ca3598`).
- Instalador: `installer/dist/Setup Junior Eventos v6.0.0.exe` (33,3 MB; la carpeta no va a git). **Si se toca el
  programa antes de publicar, hay que armarlo de nuevo** con `installer\build_installer.ps1`.
- No hay release `v6.0.0` en GitHub y los dos SQL de la nube no se corrieron.
- El usuario está mirando las pantallas (`build/muestras_6.0.0/Recorrido_6.0.0.html`, 26 pantallas numeradas).
  Todavía no opinó.

---

## Por qué

El sorteo es en noviembre y las fiestas en diciembre. El jefe armaba el salón en Canva y sorteaba con una lista;
quería hacerlo sobre el plano de verdad, por división, y llegar al sorteo sabiendo sin lugar a dudas cuántas mesas y
sillas tiene cada familia y quién las pagó. El usuario pidió **una sola versión con todo adentro**, sin
intermedias: por eso salta de la 5.0.0 a la 6.0.0 y junta 76 commits.

## Qué trae

| Qué | Dónde |
|---|---|
| **El plano del salón**, en tres estilos (Gala, Arquitecto, Neón), armado a medida del playón o con los armados del Canva del jefe | Barra de la fiesta → PLANO |
| **Sorteo por división** (cada una en su bloque) **o toda la escuela junta**, con el pasto solo si hace falta | Barra → SORTEO ▾ |
| **Fijar mesas y dejarlas libres** antes del sorteo; **cambiar o mudar familias** después, con motivo, deshacer e Historial | PLANO → PERSONALIZAR → Mesas |
| **Acomodar el salón a mano** (agregar, sacar, correr, separar o juntar), las **medidas** y los **colores y textos** | PLANO → PERSONALIZAR |
| **Sortear a los que faltan** con el mismo botón, sin mover a nadie; **Deshacer** solo los últimos sorteados o todo | SORTEO ▾ |
| **Plano impreso** y **planilla del sorteo** nueva, por división, con bloque, pasto y a quién avisar; se puede sacar solo de los últimos | PLANILLAS ▾ |
| **Retiro de entradas** en la oficina, con su planilla de entrega | Barra → ENTRADAS |
| **Mesas y sillas de cada uno** antes del sorteo, con lo agregado resaltado y un filtro de quién las pagó | Columna MESA y chip "Mesas y sillas" |
| **El reparto de sillas ("2P · 1A") se elige con las mesas ya sorteadas** | Columna MESA |
| **Lo que cambia el salón, solo en modo jefe**; lo demás se ve, se imprime y se entrega | Toda la fiesta |
| "Pasar a la lista de la puerta", **trabado hasta diciembre** | MÁS |
| El recibo reimpreso cuenta bien las cuotas (lo de GAUNA) | Recibos |
| Mi Empresa: lo disponible en efectivo y en transferencia, las extracciones aparte y el bolsillo arreglado | Mi Empresa |
| La cola de subida no pierde un cambio hecho mientras subía el anterior, y lo trabado se reintenta todo junto | Sincronización |

**Lo que no cambia:** cómo se cobra, las cuentas, los saldos, la mora, la caja, la web, Recepción y el tótem. Una
fiesta sin plano sortea igual que en la 5.0.0. **Recepción y el tótem nuevos siguen pendientes, para diciembre**
(`docs/pendientes/PENDIENTES.md`).

## Dónde está

- **El plano:** `lib/features/plano/` (`modelo/`, `dibujo/`, `estilos/`, `services/`, `widgets/`), la pantalla en
  `plano_evento_screen.dart` y la barra en `lib/features/eventos/widgets/grupo_fiesta_toolbar.dart`.
- **El sorteo sobre el plano:** `services/sorteo_con_plano.dart`. El motor (`sorteo_mesas_motor.dart`) no cambió.
- **Los que faltan:** `lib/features/eventos/services/ultimos_sorteados.dart` y `registro_sorteo.dart`.
- **Papeles:** `lib/features/common/services/plano_pdf.dart`, `planilla_sorteo_pdf.dart` y `planilla_tema.dart`.
- **Entradas:** `retiro_entradas_screen.dart`. **Mesas y sillas:** `pago_para_sorteo.dart`,
  `filtro_mesas_sillas.dart` y `celda_mesa_alumno.dart`.
- **Base:** `local_database.dart`, versiones 72 y 73. **Nube:** `supabase/migrations/20260925120000_sillas_retiro_sorteos.sql`
  y `20260926120000_planos_y_cambios_de_mesa.sql`.
- Las reglas que quedaron para el que toque esto después están en `CLAUDE.md`, sección "El salón: plano, sorteo y
  entradas", y en "Trampas conocidas".

## Verificación

- **1.697 tests** en verde y `flutter analyze` en 313 avisos, los mismos de antes de empezar.
- **La migración, probada sobre una copia de la base real** el 11-oct (`tool/verificar_migracion_v73_test.dart`):
  las 28 tablas de siempre iguales fila por fila, las cinco nuevas vacías, la vuelta a la 5.0.0 con los mismos datos,
  y la base real idéntica antes y después (mismo SHA-256).
- **Volver atrás es reinstalar la 5.0.0 sobre la misma base**, con todos los pagos al día: un test comprueba que la
  5.0.0 abre una base ya migrada. La copia `antes_de_v73.db` que saca la app al actualizar es la última red, no el
  camino: restaurarla dejaría afuera lo cobrado después.
- Las partes difíciles (el dibujo, la base, el sorteo, los cambios de mesa, personalizar) pasaron por revisores de
  solo lectura, y cada arreglo importante se comprobó rompiéndolo a propósito.
- **No se abrió la app nueva contra la base real**: no hay entorno de prueba y la v73 la migraría. Lo primero que
  la prueba de verdad es instalarla en la PC del usuario.
- El control de mesas y sillas con los datos reales (`tool/extras_muestra_test.dart`, 11-oct): 94 sin pago de la
  base, 17 con una mesa agregada sin pagar y 4 con sillas sin pagar. Es una foto del día: se vuelve a sacar cerca
  del sorteo.

## Lo que falta para publicar

El usuario propuso publicar el domingo 11-oct (sin cobros, las tres PCs el mismo día) y después frenó para mirar
las pantallas con calma. **No se publica sin su "publicamos".** En orden:

1. **Su opinión de las pantallas.** Si cambia algo del programa: suite, commit, y armar de nuevo el instalador.
2. **Los dos SQL en la nube, con su OK en el momento** (un domingo sin cobros o después de las 20 hs). Antes y
   después de cada uno, los conteos: el 11-oct daban **643 contratos, 3.963 pagos, 26 notas, 7 invitados y 30
   eventos**, y tienen que dar igual. Después, las consultas de verificación del final de cada archivo (RLS
   prendida, un trigger de insert y uno de update por tabla, la policy, y ninguna en Realtime).
3. **El release:** `powershell -File tool/publish_windows_release.ps1 -SoloNotas -NotesFile build\novedades_6.0.0.md`.
   Crea el tag `v6.0.0` sobre la rama y sube el instalador. El texto de novedades (cinco renglones, acortado a
   pedido) está también en el CONTEXTO de la Fase 3.
4. **Instalar:** primero la PC del usuario, para probarla; después la del operario y la de la oficina. Al abrir, la
   app saca sola la copia y actualiza la base.
5. **Mientras una PC tenga la 5.0.0 y otra la 6.0.0** se cobra normal. **No se sortea ni se entregan entradas
   hasta que todas tengan la 6.0.0**: la 5.0.0 no ve el plano, los repartos ni las entregas.
6. **Después de instalar:** mirar en la nube que las tablas nuevas reciben filas y que la cola de subida queda en 0.
7. Poner acá el estado en "publicada", con el tag y la fecha, y la memoria al día.

## Lo que sigue esperando del usuario (no frena publicar)

- La página 6 del Canva: la Normal ya tiene **137 mesas cargadas** (116 con lo pagado el 11-oct), y su armado del
  Canva tiene la hoja B provisoria. Mientras tanto está el armado a medida del playón, y las mesas que falten se
  agregan en Acomodar.
- Los cuatro lados del playón medidos con cinta (hoy son 30, 46 y 39 m, a ojo del satélite).
- Las respuestas del jefe: qué armado usa cada escuela, las numeraciones, el pasto, y por división o entera.
- La fecha del sorteo.
- Pidió, de paso, que en la app se vea **cuándo se escribió cada nota** de un alumno. Falta decidir si entra en
  esta versión. (Las 31 notas que estaban en su PC y no en la nube ya se resolvieron el 11-oct: ver "Las notas
  operativas que no están en la nube" en el CONTEXTO de la Fase 3.)
