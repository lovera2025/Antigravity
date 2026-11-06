# La 6.4.0 (en curso): el tótem con el salón y las sillas de la noche

6-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. **En la rama, sin publicar.** Va en la misma versión que lo que falta de la barra y
de Entradas: **se publica cuando esté, sin apuro de fecha** (lo dijo el usuario el 6-nov: "cuando salga nomás, ahora hay más tiempo"),
preguntándole. El plan aprobado es `docs/PLAN_TOTEM_SALON_Y_SILLAS_2026-11-05.md`; lo del tótem (Parte 1, 5-nov) está contado en
`docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md`. Acá, la Parte 2: las sillas de la noche, hechas el 6-nov.

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

## Lo que falta

- **Lo que pasa con el vale** (pregunta del usuario, 6-nov): quién lo imprime, quién se lo queda y qué pasa si la barra anula esa
  venta. Ver "Pregunta abierta: el vale de la silla", abajo.
- ~~**La prueba de punta a punta**~~ (hecha, arriba). Lo que decía: **La hace Claude, en un sandbox, hasta que salga bien**
  (regla del usuario del 6-nov: "las pruebas las haces vos en un sandbox y te aseguras que sale bien"; no se le pide a él que pruebe).
  Aislada: `flutter run -d windows -t tool/central_puerta_prueba.dart` (Recepción en memoria, sin la base real ni la nube), la página
  del celular armada en `build/puesto`, y pestañas del navegador como celulares. Sumar desde dos celulares a la vez a una familia con
  un lugar, el mismo vale dos veces, quitar con motivo, el conteo de la noche y el reloj desde el celular; también con la central
  cortada (la silla queda guardada y se manda al volver). En el arnés las familias pares ya están en el tope y las impares tienen lugar
  para 2. Se le cuenta qué se probó, cómo y qué apareció, con capturas.
- **Para la barra (sus etapas, no acá):** "Silla extra" en el catálogo y en el cierre, quién ve esas ventas (la encargada), y la
  comparación sillas vendidas contra sumadas (`docs/pendientes/sillas-barra-vs-puerta.md`).
- Después, la etapa 5 de la barra: `docs/CONTEXTO_BARRA_2026-11-02.md`, "Para retomar en otro chat".

## Pregunta abierta: el vale de la silla (6-nov)

Lo que está decidido (jefe, 5-nov): la familia paga la silla en **cualquier caja de la barra** (la cajera que cobra; la encargada
también cobra), que la vende como el producto "Silla extra" e imprime su vale como cualquier otro ("Caja 2 · Marta · N° 0017"). La
familia lleva ese vale a la recepcionista de adentro, que suma la silla con ese número.

Lo que **no** está decidido ni programado:
- **Quién se queda el papel.** Con los tragos, el barman se queda el vale y ese es el control. Para la silla, lo lógico es que se lo
  quede la recepcionista.
- **Si la barra anula esa venta**, hoy la silla sigue sumada en la puerta: las dos cosas no se conocen (son dos notebooks, y el vale
  es solo un número). Hoy lo único es que la recepcionista la quite con el motivo, si alguien le avisa, y la comparación de la
  oficina (`docs/pendientes/sillas-barra-vs-puerta.md`) lo mostraría al otro día.
