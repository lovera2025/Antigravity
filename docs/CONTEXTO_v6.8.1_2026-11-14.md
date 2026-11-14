# CONTEXTO — la 6.8.1: el rótulo de la mora y el recibo reimpreso entero

**Estado (14-nov-2026, al cortar el chat a pedido del usuario):** **programada y probada sobre una copia de la base
real, sin publicar.** Rama `release/6.8.x` (desde el tag `v6.8.0`, carpeta `..\arguello_events_6.8.x`, un `git worktree`
de este repo); cada commit también en `feature/v4.6-cierre-por-sesiones` con `cherry-pick`. **Ningún instalador de la
6.8.x sale de la rama feature** (tiene la v80 y un SQL sin correr). Sin SQL ni migración. Nada subido a GitHub.
`pubspec.yaml` sigue en `6.8.0+74`: se sube a `6.8.1+75` (y el `.iss`) al publicar.

## Para retomar en otro chat

**Dónde quedó:**

- **Todo programado y probado.** La suite entera pasa en las dos ramas (6.8.x: 4.720; feature: 5.000). El comparador
  sobre la copia de la base no encontró nada que frene. Los papeles de las 5 familias (antes y después) están en
  `build/papeles_6.8.1/` de la carpeta principal (fuera de git) y se le mandaron al usuario.
- **El usuario vio los recibos de la familia que reclamó y pidió cambios, todos hechos** (título más formal y el
  recuadro con la tabla). Su último pedido fue actualizar este contexto. **Todavía no dijo "publicá":** lo próximo es
  preguntarle si da el OK para publicar, con él presente.
- **La 6.9.0 (venta de entradas) quedó en pausa** donde estaba (etapa 5 a medias): ver
  `docs/CONTEXTO_v6.9.0_2026-11-13.md`. La rama feature ya tiene todos los commits de la 6.8.1.

**Qué lleva.** Una versión sola, decidida por el usuario el 14-nov (le recomendé sacarla antes que la 6.9.0: una familia
reclamó, y sola se compara limpia con las fotos de la mora):

1. **El rótulo de la mora** (`docs/SPEC_remanente_mora_por_concepto_2026-11-14.md` y su
   `docs/SPEC_remanente_mora_ANEXO_D_filas_guardadas_2026-11-14.md`; el Anexo D original, con nombres, está fuera del
   repo, en `Desktop\PLAN`). En la ficha, cada línea de mora va a lo que dice su concepto
   (`MoraTrackedOrigen._repartirMoraDelLote`): las 5 fichas que nombraban cuotas ya pagadas pasan solas a verse bien.
   El Estado de cuenta nombra cada cuota con su mes (`MoraConceptoRotulo.rotuloFichaMora(contrato:, cuotasArrastre:)`)
   y la reimpresión reparte las mixtas con la misma regla.
2. **El recibo reimpreso entero** (aviso del jefe del 14-nov: "los recibos al reimprimir no tienen tantos datos").
   REIMPRIMIR del Estado de cuenta mandaba un solo renglón. Ahora los tres caminos (ese botón, "Generar recibo" de la
   grilla y Mi Empresa → Finanzas) arman el papel con `ReciboDeUnCobro` (`eventos/services/recibo_de_un_cobro.dart`):
   el cobro entero, sin anulados; Finanzas trae además el recuadro rojo fechado.
3. **El recuadro verde explica cada mora** (lo pidió el usuario: "que todo sea muy explicativo minuciosamente"; aprobó
   el dibujo y después eligió **dejar la tabla siempre**, también cuando todo se paga entero, para que todos los
   recibos tengan el mismo formato y el "Debía $9.000" del 14/11 enganche con el "Quedó $9.000" del 12/11):
   - el título, más formal (también lo pidió): **"MORA ABONADA EN SU TOTALIDAD"**, **"MORA ABONADA PARCIALMENTE"** o
     "MORA ABONADA EN ESTE PAGO" si no se puede saber, con la cantidad: "· 3 moras — $ 75.000,00";
   - una tabla **"Mora de · Debía · Pagó · Quedó"**, una fila por mora y el total;
   - debajo de la mora pagada en partes, un renglón: "pagada parcialmente: quedaron $X", o "era de $X: antes se
     pagaron $Y, hoy se terminó de pagar" en el pago que la termina;
   - al pie: "Se pagaron N moras enteras y M parcialmente." o "Con este pago no queda mora pendiente.".
   Va en el recibo al cobrar y en el reimpreso. **Con un perdón en la ficha no se puede comprobar cuánto se debía**:
   el recuadro queda como antes, con lo pagado (`ReciboDeUnCobro.conNotas`). La tabla no junta cuotas en "y N cuotas
   más": si el papel no entra en media hoja, achica la letra o crece. Código: `FilaMoraPdf.debia`/`quedo`,
   `notaMoraPorCuota`, `cantidadDeMorasPdf` (`cobro_masivo_conceptos_pdf.dart`) y `avisoRecibo` (`pdf_service.dart`).

**Lo que cambió del plan de la spec, y por qué** (lo mostró el comparador sobre la copia):

- **Para un cobro ya guardado, las cuotas del arrastre son las que nombra su texto** (`arrastreDeUnaLinea`,
  `cuotasNombradasDelArrastre`, en `concepto_pago_display.dart`). El Anexo D pedía tomarlas de la reconstrucción desde
  los pagos, y la reconstrucción no sabe de perdones ni de exenciones: en fichas así nombraba cuotas perdonadas. Solo se
  saca una cuota nombrada si otra línea de un día anterior ya la nombró y la reconstrucción dice que no se debía (el
  caso reclamado). Con un perdón en la ficha, ninguna.
- **Cuando la reconstrucción no alcanza para decir cuánto fue de cada cuota, un renglón con todas** ("Cuotas 2, 3 y 4",
  claves `cuotasPrevias` y `cuotasDeLaLinea`), en vez de inventar un reparto.
- **Una línea de calendario de varias cuotas se reparte solo si lo que se debía ese día da justo lo cobrado**; una cuota
  del calendario sale "(parcial)" solo si la reconstrucción confirma que le quedó mora (`_parcialesConfirmados`).
- **Un cobro reimpreso que dejó una cuota a medias no dice "en su totalidad"** (`moraQuedaSaldada`): el recibo del 12/11
  de la familia decía "MORA SALDADA" arriba de lo que quedaba.
- **Con la familia que ya terminó de pagar (saldo 0) el arrastre se rearma igual** (la cuenta de la mora no devuelve
  nada con saldo 0: se usa el total del contrato).

**Cómo se probó** (todo en esta PC, sobre copias):

- **La copia de la base**: 14-nov a las 15:41, con `VACUUM INTO` en solo lectura y el programa cerrado (el usuario lo
  abrió antes para que bajara lo del día). La base real quedó con el mismo SHA-256. La copia estaba en el scratchpad de
  la sesión; si se borró, se saca otra con `python -I tool/copiar_base_solo_lectura.py <archivo fuera del repo>`
  (pedirle antes que cierre el programa).
- **El comparador** (`tool/rotulo_mora_antes_despues_test.dart`): el mismo archivo se corre en una carpeta con la 6.8.0
  (`git worktree add --detach <carpeta> v6.8.0`, `flutter pub get`, copiar el archivo a su `tool/`) y en esta, con
  `--dart-define=copia=… salida=… version=6.8.0|6.8.1`; `python -I tool/comparar_rotulo_mora.py <salida>` cruza los dos
  JSON y escribe `rotulo_mora.txt` (con nombres: fuera del repo; hay una copia en `build/papeles_6.8.1/`). Resultado:
  **ninguna suma se mueve**; cambian 4 fichas, las del Anexo D (la quinta, la del reclamo, ya pagó); el Estado de
  cuenta cambia de cuotas en **una sola fila**, la del recibo reclamado (las demás solo suman el mes); el papel y la
  pantalla nombran lo mismo en todas las filas; la mora sin cuota en los recibos enteros baja de 149 a 23; el recibo
  nombra lo que dijo el original en 89 de 91 cobros (la 6.8.0, 73); los 2.934 cobros suman lo cobrado. La tabla del
  recuadro se agregó después de la última corrida: no cambia ni las líneas ni los montos, solo cómo se dibujan.
- **Los papeles** (`tool/papeles_rotulo_mora_muestra_test.dart`, con `--dart-define=alumnos=<ids>;…` y
  `desde=2026-09-01`): el Estado de cuenta y los recibos con mora de las 5 familias, antes (como la 6.8.0) y después,
  con la letra Outfit de la app. Se miraron uno por uno.
- **Una revisión** con siete agentes (buscar y verificar cada hallazgo): 10 hallazgos reales, todos resueltos o dentro
  de los límites de abajo.

**Límites conocidos (no se arreglan acá):**

- Dos cobros del mismo alumno el mismo día: la reconstrucción corta por día (la spec lo deja así).
- Una mixta anterior al 21/08/2026 cuyo calendario se recalcula más alto que lo cobrado deja el arrastre en 0 en la
  reimpresión (un caso en la base; igual que en la 6.8.0).
- Al reimprimir, "EN SU TOTALIDAD" mira la mora de hoy: un cobro que pagó su calendario y dejó arrastre de otras cuotas
  sin tocar puede decirlo si hoy está en 0 (igual que en la 6.8.0).

**Lo que falta, en orden:**

1. **Preguntarle al usuario si da el OK para publicar** (vio los recibos de la familia; todo lo que pidió está hecho).
2. **Publicar con él** (sección 8.3 de la spec y "Cómo se publicó" de los CONTEXTO anteriores): que nadie esté
   cobrando; respaldo; foto de la mora "antes de 6.8.1" (`supabase/mora_fotos.sql`, por el conector); `6.8.1+75` en
   `pubspec.yaml` y en `installer/junior_eventos_setup.iss`; la suite entera; el instalador **por pasos** desde
   `..\arguello_events_6.8.x` (la página del celular entera antes de `ISCC`, la clave de firma y `apksigner`); tag
   `v6.8.1`, release con el Setup y el APK y las novedades (propuesta: "Correcciones en la mora y en los recibos",
   sin nombres; confirmarla con él); la web desde esa carpeta.
3. **Instalar: la PC del jefe primero**, después las otras dos y las tablets el mismo día (el rótulo se arma en cada
   equipo). Foto de la mora "después de 6.8.1" y la comparación: tiene que dar nada sospechoso (la versión no mueve
   montos).
4. **Reimprimir para la familia** los recibos del 12/11 y del 14/11 desde el Estado de cuenta.
5. Después, volver a la 6.9.0 (`docs/CONTEXTO_v6.9.0_2026-11-13.md`).

**Mientras no esté instalada:** en las fichas con remanente, si la familia viene a pagar, cobrar todo el remanente
junto y no por tilde suelto; no usar el perdón por mes.

**No se probó:** con el mouse en el programa (el botón REIMPRIMIR, Finanzas) ni el recibo al cobrar en la app de
verdad; los PDF salieron por el mismo servicio que usa la app, sobre la copia.
