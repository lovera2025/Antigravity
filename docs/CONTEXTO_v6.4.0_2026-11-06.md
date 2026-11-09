# La 6.4.0 (en curso): el tótem con el salón y las sillas de la noche

## Para retomar en otro chat (8-nov, noche): la 6.4.0 está completa, falta publicarla

> **Todo lo del plan general está programado y probado en la rama: 27 de 28 partes, 96 %.** El 8-nov a la noche, con el usuario
> en casa, se sumaron dos partes que estaban decididas desde el 5-nov y habían quedado afuera (la **Encargada de barra** y el
> **cierre de caja por sector**), más lo que pidió al ver la maqueta (**probar la impresora sin vender y el nombre de cada
> impresora**), y se hicieron las dos pruebas que eran opcionales (el aviso entre PCs contra la nube y PAPEL con la TP-POS58).
> La parte 28 es publicar, **con el usuario presente** (su regla: el OK es suyo). La suite entera, en verde; `flutter analyze` sin
> errores en `lib/` y `test/`. Frase para retomar: "Publicamos la 6.4.0: leé 'Para retomar en otro chat' de
> docs/CONTEXTO_v6.4.0_2026-11-06.md y vamos paso a paso."

**Lo que lleva la 6.4.0** (respecto de la 6.3.3 instalada):

| Qué | Dónde está contado |
|---|---|
| El tótem con el salón entero y claro, el nombre que salta y se acomoda, los segundos en Personalizar y a mano | `docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md` |
| Las sillas de la noche (la puerta anota cada silla con el vale de la barra; la traba en la oficina por fiesta sorteada) | Abajo, en este archivo |
| La barra entera: VENDER, vales, VENTAS, cerrar la caja, el jefe en la PC y en el iPhone, la central, Android firmado, el aviso de papel | `docs/CONTEXTO_BARRA_2026-11-02.md` |
| Entradas 4 y 5: la entrega según los permisos, "En caja" y "pagó: ya podés entregar", anular solo el jefe | `docs/CONTEXTO_OPERADORES_2026-11-02.md` |
| Cambiar la fecha de un cobro lo saca de su caja abierta (ENRIQUE, MAXIMO) | `docs/CONTEXTO_v6.3.4_2026-11-07.md` |
| El aviso entre PCs que llegaba por el socket ya no se tira: la otra PC se pone al día sola, también minimizada; el tótem de la web saluda al instante | `docs/SPEC_pulso_por_el_socket_2026-11-07.md` |
| **La Encargada de barra** (8-nov): una casilla en OPERADORES; vende con su caja y además ve LAS CAJAS y anula o reimprime cualquier venta | `docs/CONTEXTO_BARRA_2026-11-02.md`, "La Encargada de barra" |
| **El cierre de caja por sector** (8-nov): COBROS · BARRA · ENTRADAS arriba del cierre de hoy, en modo jefe | `docs/CONTEXTO_BARRA_2026-11-02.md`, "El cierre por sector" |
| **Probar la impresora y su nombre** (8-nov): IMPRIMIR UNA PRUEBA sin vender nada; cada impresora con su nombre | `docs/CONTEXTO_BARRA_2026-11-02.md`, "Probar la impresora" |

**La revisión de bugs del 8-nov (noche)**, sobre todo lo que cambió desde la 6.3.3 (`git diff v6.3.3 HEAD`), arregló tres cosas, con
sus tests:
- **La central de la barra con relojes distintos:** una caja cerrada en una tablet con el reloj atrasado se descartaba en la notebook
  si la notebook había bajado de la nube la caja abierta (con la hora del servidor). Ahora una caja cerrada gana siempre
  (`cambiaLaFila`).
- **El tótem de la PC de Recepción**, ahora que atiende los avisos del canal, recibe todo dos veces (puente y canal) y el canal llega
  más tarde: una baja vieja podía sacar a alguien que se volvió a marcar. Una baja del canal no saca lo que marcó el puente
  (`IngresosTotem.vinoPorElPuente`); si lo deshace otra PC, lo trae `totem_lista` en segundos.
- **Corregir medio de pago:** una fecha elegida para un cobro quedaba puesta si después se tildaba otro, y al guardar se le ponía a ese
  (y lo sacaba de su caja). Ahora se borra al cambiar de cobro. Y el aviso cuenta las líneas que de verdad cambiaron.

También se arreglaron dos ventanas de prueba de `tool/` que no compilaban, y **el script del release ahora sube también el APK de la
tablet** (`tool/publish_windows_release.ps1`): sin el APK en el release, la tablet no tiene qué bajar desde la pantalla del PIN.

**Antes de publicar: hecho el 8-nov a la noche.**
1. **La migración v78 sobre una copia de la base real, con la app cerrada:** aparecen `sillas_puerta`, `barra_vales` y
   `barra_recargos`, vacías; todo lo demás igual (643 contratos, 4.907 pagos); la vuelta a la 6.3.1 igual; la base real con el mismo
   SHA-256 (`8f3b1520…`). Si pasan días antes de publicar, repetirla.
2. **PAPEL con la TP-POS58:** contesta. Con rollo `hay (0x12)`, sin rollo `noHay (0x72)`: el aviso de VENDER va a salir de verdad.
3. **El aviso entre PCs contra la nube** (con su OK, "opcionales hay que hacer"): pasó; por el socket llega suelto y por REST
   envuelto, y la app saca lo mismo de los dos (SPEC, 7.9). Queda mirar los registros con las PCs instaladas (SPEC, sección 9).

**Publicada el 9-nov a la madrugada, con el usuario (pasos 1 a 5 hechos):** la foto "antes de 6.4.0" (643 alumnos, `5176b94e…`);
los cuatro SQL como migraciones (`totem_config_llegada`, `sillas_puerta`, `barra_vales`, `barra_recargos`), con los conteos iguales
antes y después y las tres tablas con su RLS, su policy y sus dos disparadores, fuera de Realtime; la versión `6.4.0+66` (commit
`c4f1202`, tag `v6.4.0`); el release con `Setup Junior Eventos v6.4.0.exe` y `Junior Eventos v6.4.0.apk` (firmado), novedades "La barra,
la entrega de entradas y las sillas de la noche"; y la web (`version.json` en 6.4.0+66). El instalador se frenó la primera vez por
correrlo con `*>&1` (el aviso de Wasm del compilador sale por stderr y el script tiene `Stop`): **se corre con
`powershell -File installer\build_installer.ps1`**, sin redirigir el stderr. **Faltan los pasos 6 y 7**: que el usuario instale las tres
PCs y la foto "después".

**Publicar, paso a paso (cada paso con su OK):**
1. Foto de la mora "antes de 6.4.0" (`supabase/mora_fotos.sql`).
2. **Los cuatro SQL, que solo agregan:** `20261105100000_totem_config_llegada.sql`, `20261105120000_sillas_puerta.sql`,
   `20261107100000_barra_vales.sql`, `20261107140000_barra_recargos.sql`, con las consultas de verificación de cada uno.
3. Versión **`6.4.0+66`** en `pubspec.yaml` y `installer/junior_eventos_setup.iss`. Novedades (propuesta, elige el usuario): **"La
   barra, la entrega de entradas y las sillas de la noche"**, en `build/novedades_6.4.0.md`.
4. `.\installer\build_installer.ps1` (necesita `android\key.properties`; frena sin la clave y comprueba la firma del APK): deja
   `installer\dist\Setup Junior Eventos v6.4.0.exe` y `installer\dist\Junior Eventos v6.4.0.apk`.
5. Release: `tool/publish_windows_release.ps1 -SoloNotas -NotesFile build/novedades_6.4.0.md` (sube los dos). La web a Vercel (ver
   CLAUDE.md).
6. Instalar las tres PCs el mismo día (el operario antes de abrir la caja; el jefe después) y abrirlas: la revisión de la mora corre al
   arrancar. La tablet, con el APK.
7. Foto "después de 6.4.0" y la comparación: tiene que dar vacía.
8. Recién ahí: dar Entradas a alguien, **tildar a la Encargada de barra** y crear operadores sin Cobros; la prueba de Entradas en dos
   PCs; el pulso con los registros de la nube; la tablet con el TP-Link del salón; ponerle nombre a cada impresora (y una etiqueta).

**Sigue pendiente** la comparación de la oficina, vale por vale, entre las sillas vendidas en la barra y las sumadas en la puerta
(`docs/pendientes/sillas-barra-vs-puerta.md`). El cierre por sector ya dice cuántas sillas vendió la barra.

---

6-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. **En la rama, sin publicar.** Va en la misma versión que lo que falta de la barra y
de Entradas: **se publica cuando esté, sin apuro de fecha** (lo dijo el usuario el 6-nov: "cuando salga nomás, ahora hay más tiempo"),
preguntándole. El plan aprobado es `docs/PLAN_TOTEM_SALON_Y_SILLAS_2026-11-05.md`; lo del tótem (Parte 1, 5-nov) está contado en
`docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md`. Acá, la Parte 2: las sillas de la noche, hechas el 6-nov.

> **6-nov (noche): antes de la 6.4.0 salen la 6.3.2 y la 6.3.3**, cada una sola desde la rama `release/6.3.x`: la mora adelantada
> (`docs/CONTEXTO_v6.3.2_2026-11-09.md`, meta lunes 9-nov) y el sync en reposo (`docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md`). La barra
> y Entradas esperan a que salgan. Esta versión lleva también esos dos arreglos (sus commits están en esta rama).

## Qué es

Desde que empiezan los sorteos (10-nov), **una silla extra se pide solo la noche de la fiesta, ya sentados** (decisión del jefe, 5-nov).
Esa noche no se piden mesas: la silla va siempre a una mesa que la familia ya tiene. **La recepcionista no toca plata:** ve si la familia
puede agregar, la manda a la caja de la barra, que cobra "Silla extra" como un producto y da un vale, y con el número de ese vale anota la
silla en Recepción. Quitar una deja la huella: quién, cuándo y por qué. Nada se borra.

## Qué quedó hecho (6-nov, cinco commits)

| Commit | Qué |
|---|---|
| `c2836fe` | `sillas_puerta` sube y baja: las siete listas del motor (`_incrementalColumns`, `_tablasDelCobro`, la prioridad 4, `_pullTable`, `_cleanForSqlite` con sus 13 columnas, `_tablasSinRevisarBorrados` y `tablasDeLaPuerta`). **No** está en las `relaciones` de la cola: una silla sin subir nunca se descarta. `test/sync_tablas_v78_test.dart` compara el motor, la base, el modelo y el SQL. `tool/verificar_migracion_v78_test.dart`, **corrido sobre la base real el 6-nov** (la app cerrada): solo aparece `sillas_puerta`, vacía; volver a la 6.3.1 deja todo igual; el SHA-256 de la base real, idéntico. |
| `cfd6e76` | Lo puro (`recepcion/services/sillas_de_la_puerta.dart`): `SillasDeUnaMesa` (el tope de 2 por mesa, sus textos y su color), `SillasDeLaFamilia` (las extra del contrato con el reparto que eligió la familia, más las sumadas; `mesaConLugar`, `conSumadas`), `ConteoDeLaNoche` y `valeNormalizado`. `GrupoPuerta` suma `contratoId`, `sillasPorMesa` y `movimientos`; `PuertaDelEvento` el `conteoDeLaNoche`; el JSON se lee tolerante (una central vieja manda sin sillas). `sillasPuertaDelEventoProvider` relee con lo que anota esta PC y con lo que baja. |
| `40c3bc1` | **Un solo candado para la PC y los celulares**: `central/resolvedor_de_pedidos.dart` (`ResolvedorDePedidos`), la fila que antes vivía en `CentralPuerta`. `CentralDeLaPuerta.resolverDeEstaPc` la usa **aunque la central esté apagada**. `decidirSilla` decide con la base del momento: sin mesa no; sin vale no; el mismo vale dos veces no (aunque se escriba distinto); mesa llena → otra de la familia, y lo dice; en el tope, "ya no puede agregar: 2 extra por mesa"; quitar pide el motivo. `QuePide` suma `sumarSilla`, `quitarSilla` y `tiemposTotem`. El celular guarda la silla sin conexión y la manda al volver, sin confundirla con un ingreso. |
| `9efe7ae` | El panel (`PanelPuerta`, la PC y el celular): una línea por mesa, cada movimiento con QUITAR (la quitada queda tachada), SUMAR SILLA (`widgets/hoja_sumar_silla.dart`: la mesa, el vale obligatorio, la nota) y "Esta noche: …" arriba. El reloj de los segundos también en el celular (`PantallaPuesto`). Muestras: `tool/recepcion_muestra_test.dart` (5, 6 y 7). El arnés `tool/central_puerta_prueba.dart` suma sillas. |
| `e0c8de3` | La oficina: la grilla dice "+1 en la puerta" con el detalle en el tooltip; Editar alumno, cuántas se le sumaron. **La traba:** con la fiesta ya sorteada, el + de las sillas extra lleva un candado (`puedeSumarSillasAlContrato`, segunda llave `sillasExtraTrabadas` al guardar); en modo jefe se puede. `test/sillas_puerta_no_toca_test.dart` vigila que el sorteo, la planilla, lo pagado, el retiro de entradas y el plano no conozcan las sillas de la puerta. |

## Decisiones

- **5-nov (jefe):** las sillas, solo la noche de la fiesta; las cobra la barra, la puerta anota el vale; esa noche no se piden mesas.
- **6-nov (usuario):** la traba de la oficina es **por fiesta ya sorteada** (no por fecha), **el jefe la saltea en modo jefe** para un
  caso puntual, y **la recepcionista puede quitar** una silla, con motivo y huella. Publicar, cuando esté.
- **El vale se anota con sus números** (`valeNormalizado`): el papel de la barra dice "Caja 2 · Marta · N° 0017-3"; cada caja numera desde
  1, así que va la caja. "2 0017", "2-0017" y "caja 2 n 17" dan "2-17". El "-3" (una compra con varios vales) se respeta.
- **Las sumadas no cambian nada del contrato**: no entran en `SalonMesas.sillasExtra` ni en `RepartoDeSillas`. Solo se muestran.

## Lo que hay que saber antes de publicar

- **Dos SQL sin correr**, los dos solo agregan: `supabase/migrations/20261105100000_totem_config_llegada.sql` (los segundos de la
  llegada) y `supabase/migrations/20261105120000_sillas_puerta.sql`. **Antes de instalar**, con el OK del usuario y la foto de la mora.
  Sin el de las sillas, lo que se anote queda trabado en la cola **y "Lista para trabajar sin internet" no queda lista**:
  `sillas_puerta` está en `tablasDeLaPuerta`, y si no baja, la puesta al día dice que falta.
- **La traba de la oficina rige recién con la versión instalada.** Los sorteos empiezan el 10-nov y esta versión espera a la barra:
  hasta instalarla, no sumar sillas extra al contrato en una fiesta ya sorteada es una regla que la oficina respeta a mano.
  **Decidido por el usuario el 6-nov:** "mientras respetaremos a mano". Capaz se publica antes que la barra, pero **no antes de
  asegurarse de que todo está bien**: primero la prueba de punta a punta.
- La base local pasa a la v78 (`sillas_puerta`), probada sobre la copia de la base real.

## La prueba de punta a punta, hecha (6-nov, en el sandbox)

Con `tool/puerta_sandbox_test.dart`: la central de verdad escuchando solo en esta PC, la base en memoria (sin la base real ni la
nube), la página del celular armada (`build/puesto`) y dos pestañas del navegador como dos celulares ("Juli" en `127.0.0.1`, "Pato"
en `localhost`: cada una guarda su nombre), más la PC sumando por el mismo candado (órdenes por archivo).

| Qué | Salió |
|---|---|
| Dos celulares suman a la vez a una familia con un lugar | Entra una; el otro, con la hoja vieja todavía abierta ("Le queda 1"), recibe "PÉREZ, JULIANA ya no puede agregar: 2 extra por mesa." Una sola fila en la base. |
| El mismo vale dos veces, escrito distinto ("2 0040", "2-0040", "Caja-3-N°-101") | "El vale 2-40 ya se usó para PÉREZ, JULIANA." Desde la PC, igual. |
| Quitar desde el otro celular | QUITAR apagado sin motivo; con motivo, la línea queda tachada con "quitada por Pato 12:58: devolvieron el vale" y la familia recupera el lugar. |
| El conteo de la noche | Se actualiza al instante en los dos celulares ("4 sillas sumadas · vales … · 1 quitada"). |
| La PC suma con los celulares conectados | Les llega al instante ("vale 3-101 · PC"); en el tope, "ya no puede agregar". |
| El reloj desde el celular | La PC recibe los segundos (6 s + 8 s). |
| La central se corta | El celular dice "Sin conexión con la PC · 1 por mandar"; al volver la manda sola y dice "Conectado · se mandó 1". |

**Lo que encontró y se arregló:** (1) después de mandar una silla anotada sin conexión, seguía diciendo "se manda sola al volver",
y en verde: ahora eso va en ámbar y, al confirmarlo la central, dice en verde "Silla sumada a la mesa 15 de ACOSTA, LUCÍA."
(`ClienteCentral.hechos`, `AccionesPuerta.hechos`); (2) una mesa que no es de la familia se decía "ya estaba llena"; (3) la pista
del vale no entraba en el celular ("Caja y número: 2 0017"). Probado de nuevo en el sandbox después del arreglo.

## El vale de la silla y la silla en rojo (6-nov, cuatro commits más)

Lo que el usuario decidió el 6-nov, ya hecho y probado:

- **Cobra la caja de la Encargada de barra** (la que ve todas las cajas; la tilde todavía no existe, va en las etapas de la barra).
  La vende como el producto "Silla extra" e imprime el vale. **La familia lleva el vale a la recepcionista**, que suma la silla con
  ese número y **se queda el papel**.
- **Qué producto es una silla, por el nombre** (`esSillaDeLaPuerta`, `barra/cuentas/silla_de_la_puerta.dart`): "Silla extra",
  "SILLA", "Sillas extra"; sin columna nueva en el catálogo.
- **Una silla, un vale** (`ElegirVales`, `Vale.deUnaSilla`): las sillas salen aparte de las bebidas, de a una y cada una con su
  número ("N° 0017-1", "N° 0017-2"), aunque la cajera elija TODO JUNTO. Así la puerta anota cada silla con un número distinto.
- **El pie del vale de la silla** (`ModeloTicket.deVale`): "Llevá este vale a la recepcionista · Ella suma la silla y se queda el
  vale", en vez de "El barman se queda el vale".
- **Si la barra anula esa venta, la silla va en rojo** en Recepción, en la PC y en los celulares: "vale anulado en la barra:
  revisar" (`ValesAnulados`, `recepcion/services/vales_anulados.dart`; `valesAnuladosDelEventoProvider`, que lee la barra de la
  PC por `barraDelJefeProvider` y relee cuando baja algo de la barra). El conteo de la noche dice "1 con el vale anulado". **No se
  saca sola**: sigue ocupando lugar hasta que la recepcionista la quite con motivo. Sumar otra silla con un vale anulado no entra.
  Si dos cajas comparten número y una no está anulada, no se marca (nunca acusar por error); un vale sin la caja ("17") nunca.
- **De qué depende el rojo:** de que la notebook de la puerta tenga lo de la barra. Con internet, a los pocos segundos de que la
  tablet sube la anulación. Sin internet entre las dos notebooks, al volver (o, más adelante, por la central de la barra). Si no, lo
  ve la oficina al otro día (`docs/pendientes/sillas-barra-vs-puerta.md`).

**Probado en el sandbox** (`tool/puerta_sandbox_test.dart`, que ahora también vende y anula en la barra): la caja 1 vendió dos sillas
y salió el vale (abajo); Juli sumó una con el vale 1-1; la barra la anuló y en los dos celulares se puso en rojo con el conteo; sumar
otra con el 1-1 se rechazó ("El vale 1-1 está anulado en la barra"); Pato la quitó con motivo y dejó de estar en rojo; el 1-2, que no
se anuló, entró. Encontró que la ayuda de la hoja de quitar se cortaba en el celular: arreglado.

```
PROMOCIÓN DE PRUEBA
Vie 06/11/2026 - 14:08
Caja 1 · Encargada · N° 0001
VALE POR 1            (grande)
SILLA EXTRA           (grande)
Llevá este vale a la
recepcionista
Ella suma la silla y se queda el
vale
```

La foto del papel impreso de verdad necesita la impresora (la TP-POS58): queda para cuando el usuario quiera.

## Lo que falta

- **Para la barra (sus etapas, no acá):** cargar "Silla extra" en el catálogo con su precio por fiesta (etapa 7: hoy no hay
  pantalla), la tilde "Encargada de barra", "Silla extra: N vendidas" en el cierre, y la comparación de la oficina sillas vendidas
  contra sumadas (`docs/pendientes/sillas-barra-vs-puerta.md`).
- Después, la etapa 5 de la barra: `docs/CONTEXTO_BARRA_2026-11-02.md`, "Para retomar en otro chat". **Antes, la 6.3.2 y la
  6.3.3** (ver arriba).
