# CONTEXTO — la 6.8.1: el rótulo de la mora y el recibo reimpreso entero

**Estado (14-nov-2026, a la tarde):** programada y probada sobre una copia de la base real, **sin publicar**. Rama
`release/6.8.x` (desde el tag `v6.8.0`, carpeta `..\arguello_events_6.8.x`), cada commit también en
`feature/v4.6-cierre-por-sesiones` con `cherry-pick`. **Ningún instalador de la 6.8.x sale de la rama feature** (tiene la
v80 y un SQL sin correr). Sin SQL ni migración. `pubspec.yaml` sigue en `6.8.0+74`: se sube a `6.8.1+75` (y el `.iss`)
al publicar.

## Para retomar en otro chat

**Qué es.** Una versión sola, decidida por el usuario el 14-nov (le recomendé sacarla antes que la 6.9.0: una familia
reclamó, y sola se compara limpia con las fotos de la mora). Tres cosas:

1. **El rótulo de la mora** (`docs/SPEC_remanente_mora_por_concepto_2026-11-14.md` y su
   `docs/SPEC_remanente_mora_ANEXO_D_filas_guardadas_2026-11-14.md`; el Anexo D original, con nombres, está fuera del
   repo, en `Desktop\PLAN`). Cada línea de mora va a lo que dice su concepto (`MoraTrackedOrigen._repartirMoraDelLote`),
   el Estado de cuenta nombra cada cuota con su mes (`MoraConceptoRotulo.rotuloFichaMora(contrato:, cuotasArrastre:)`)
   y la reimpresión reparte las mixtas con la misma regla.
2. **El recibo reimpreso entero** (aviso del jefe del 14-nov: "los recibos al reimprimir no tienen tantos datos").
   REIMPRIMIR del Estado de cuenta mandaba un solo renglón. Ahora los tres caminos (ese botón, "Generar recibo" de la
   grilla y Mi Empresa → Finanzas) arman el papel con `ReciboDeUnCobro` (`eventos/services/recibo_de_un_cobro.dart`):
   el cobro entero, sin anulados; Finanzas trae además el recuadro rojo fechado.
3. **La nota de la cuota pagada en partes** (la eligió el usuario viendo el dibujo): "el resto: antes se habían pagado
   $X" / "parcial: quedan $X" debajo de la cuota en el recuadro verde, en el reimpreso y en el recibo al cobrar. Sin
   perdón en la ficha (`ReciboDeUnCobro.conNotas`). Va siempre que va su cuota (no se apaga al compactar).

**Lo que cambió del plan de la spec, y por qué** (lo mostró el comparador sobre la copia):

- **Las cuotas del arrastre de un cobro ya guardado son las que nombra su texto** (`arrastreDeUnaLinea`,
  `cuotasNombradasDelArrastre`, en `concepto_pago_display.dart`). El Anexo D pedía tomarlas de la reconstrucción, y la
  reconstrucción no sabe de perdones ni de exenciones: en fichas así nombraba cuotas perdonadas. Solo se saca una cuota
  nombrada si otra línea de un día anterior ya la nombró y la reconstrucción dice que no se debía (el caso reclamado).
  Con un perdón en la ficha, ninguna.
- **Cuando la reconstrucción no alcanza para decir cuánto fue de cada cuota, un renglón con todas** ("Cuotas 2, 3 y 4",
  claves `cuotasPrevias` y `cuotasDeLaLinea`, que entiende `filasMoraCobradaPdf`), en vez de inventar un reparto.
- **Una línea de calendario de varias cuotas se reparte solo si lo que se debía ese día da justo lo cobrado**; una cuota
  del calendario sale "(parcial)" solo si la reconstrucción confirma que le quedó mora (`_parcialesConfirmados`).
- **Un cobro reimpreso que dejó una cuota a medias no dice "MORA SALDADA"** (`pdf_service.dart`, `moraQuedaSaldada`):
  el recibo del 12/11 de la familia lo decía arriba de "parcial: quedan $9.000".

**Cómo se probó** (todo en esta PC, sobre copias):

- La copia de la base se sacó el 14-nov a las 15:41 con `VACUUM INTO` en solo lectura, con el programa cerrado (el
  usuario lo abrió para que bajara lo del día). La base real quedó con el mismo SHA-256. Quedó en el scratchpad de la
  sesión; si se borró, se saca otra con `python -I tool/copiar_base_solo_lectura.py <archivo>` (pedirle antes que
  cierre el programa).
- **El comparador** (`tool/rotulo_mora_antes_despues_test.dart`, el mismo archivo en una carpeta con la 6.8.0 y en esta;
  `tool/comparar_rotulo_mora.py` cruza los dos JSON y escribe `rotulo_mora.txt`, con nombres, fuera del repo).
  Resultado final: **ninguna suma se mueve**; cambian 4 fichas, las del Anexo D (la quinta, la del reclamo, ya pagó);
  el Estado de cuenta cambia de cuotas en **una sola fila**, la del recibo reclamado (las demás solo suman el mes); el
  papel y la pantalla nombran lo mismo en todas las filas; la mora sin cuota en los recibos enteros baja de 149 a 23;
  el recibo nombra lo que dijo el original en 89 de 91 cobros (la 6.8.0, 73); los 2.934 cobros suman lo cobrado.
- **Los papeles** (`tool/papeles_rotulo_mora_muestra_test.dart`): el Estado de cuenta y los recibos con mora de las 5
  familias, como salían con la 6.8.0 y con esta, en PDF (con la letra Outfit de la app). Se le mandaron al usuario.
- Una revisión con siete agentes (buscar y verificar cada hallazgo): 10 hallazgos reales, todos resueltos o dentro de
  los límites de abajo. La suite entera pasa en las dos ramas.

**Límites conocidos (no se arreglan acá):**

- Dos cobros del mismo alumno el mismo día: la reconstrucción corta por día (la spec lo deja así).
- Una mixta anterior al 21/08/2026 cuyo calendario se recalcula más alto que lo cobrado deja el arrastre en 0 en la
  reimpresión (un caso en la base; igual que en la 6.8.0).
- Al reimprimir, "MORA SALDADA" mira la mora de hoy: un cobro que pagó su calendario y dejó arrastre de otras cuotas
  sin tocar puede decir "saldada" si hoy está en 0 (como en la 6.8.0).

**Lo que falta, en orden:**

1. Que el usuario mire los PDF y el informe, y dé el OK.
2. Publicar con él (sección 8.3 de la spec): que nadie esté cobrando; respaldo; foto de la mora "antes de 6.8.1";
   `6.8.1+75` en `pubspec.yaml` y en `installer/junior_eventos_setup.iss`; `flutter test` entero; el instalador **por
   pasos** desde `..\arguello_events_6.8.x` (con la página del celular entera antes de `ISCC`, la clave de firma y
   `apksigner`); tag `v6.8.1`, release con el Setup y el APK, novedades (propuesta: "Correcciones en la mora y en los
   recibos reimpresos", sin nombres); la web desde esta carpeta.
3. Instalar: **la PC del jefe primero**, después las otras dos y las tablets el mismo día (el rótulo se arma en cada
   equipo). Foto "después de 6.8.1" y comparación.
4. Reimprimir para la familia el recibo del 14/11 (y el del 12/11) desde el Estado de cuenta.

**Mientras no esté instalada:** en las fichas con remanente, si la familia viene a pagar, cobrar todo el remanente
junto y no por tilde suelto; no usar el perdón por mes.

**No se probó:** con el mouse en el programa (el botón REIMPRIMIR, Finanzas) ni el recibo al cobrar con la nota en la
app de verdad; los PDF salieron por el mismo servicio que usa la app, sobre la copia.
