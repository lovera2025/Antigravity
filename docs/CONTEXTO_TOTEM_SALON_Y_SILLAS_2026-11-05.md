# El salón en el tótem y las sillas de la noche (5-nov-2026)

Rama `feature/v4.6-cierre-por-sesiones`. Plan aprobado: `docs/PLAN_TOTEM_SALON_Y_SILLAS_2026-11-05.md`. Va **antes** de
la etapa 5 de la barra (decisión del usuario). **Nada publicado:** se programa en la rama y se publica con todo lo
demás (o antes), preguntando. Lleva **dos SQL nuevos, sin correr**.

## Para retomar en otro chat

**Estado al 5-nov, tarde:** la **Parte 1 (el tótem) está hecha**, con muestras que el usuario vio y aprobó sobre la
marcha, y subida a la rama (6 commits, de `3f4b821` a `8ddfd6e`). La **Parte 2 (las sillas de la noche) está
empezada**: solo los datos (2.1), **sin enchufar al sync** (ver "Lo que falta", punto 1). Falta también el reloj de
los segundos **en el celular** de la puerta (va con el protocolo de la Parte 2).

> Frase para Claude Code: "Seguimos con las sillas de la noche: leé 'Para retomar en otro chat' de
> docs/CONTEXTO_TOTEM_SALON_Y_SILLAS_2026-11-05.md y docs/PLAN_TOTEM_SALON_Y_SILLAS_2026-11-05.md (Parte 2) y seguí
> desde el punto 1 de 'Lo que falta'."

**Antes de seguir:** `git pull`, `flutter analyze` y `flutter test` en verde.

## Lo que quedó hecho (Parte 1, el tótem)

En un **evento masivo ya sorteado**, la tele del tótem muestra **el salón entero, claro** (mesas blancas, números
negros y grandes) toda la espera. Cuando la recepcionista marca un ingreso:
1. **el nombre salta en grande** (casi toda la pantalla, sobre el salón apagado) los segundos que eligió el jefe;
2. **se acomoda** (0,8 s): la tarjeta grande se achica y se desvanece hacia su lugar y aparece la acomodada, sin verse
   las dos a la vez;
3. **acomodada**: la mesa se enciende, se dibuja el camino desde el Ingreso y **el borde del salón late** (pedido del
   usuario: "efecto pulso los bordes del plano"); queda los segundos del camino.

| Qué | Dónde | Detalle |
|---|---|---|
| Dónde van el salón y el cuadro | `totem/services/cuadro_del_salon.dart` (`CuadroDelSalon`, `LugarElegido`) | Automático: **la pista** si entra lo resumido (9u × 5u); si no, donde mejor se lea (hueco o franja arriba/izquierda); si no, una franja forzada. En la Normal: apaisada → pista; vertical → arriba (la pista queda muy chica). Elegido: pista, arriba, abajo, izquierda, derecha. |
| La tarjeta en la pista | `ResumenEnElSalon` en `estilos/escena_totem.dart` | **Resumida**: en la espera, título, subtítulo y saludo; en la llegada, el nombre y "MESA 12", en la letra de la apariencia. Cartel **opaco** (si no, se transparentaba "PISTA DE BAILE"). Fuera del salón (franjas), lo de siempre de la apariencia, armado a su medida y achicado entero (no se parte en renglones). |
| Las fases | `EscenaTotem`: `_conElSalon`, `FaseLlegada`, `faseFija`, `acomodoFijo` (muestras), `acomodo` 800 ms | El acomodo arranca a los `llegadaNombreSeg` de `empezo` (un `Timer`); el camino, a mitad del acomodo. Sin plano (particular, antes del sorteo, la web): todo como antes. |
| El salón claro | `temaPlanoDelTotem(…, claro: true)` en `estilos/plano_del_totem.dart` | Dibujo de Arquitecto, sin sillas ni grilla; `TemaPlano.escalaNumero` (nuevo, 1,15 en el tótem). El camino en el color del evento oscurecido si es claro. `claro: false` queda para comparar. |
| El borde que late | `PanelPlano.pulsar` | Ahora `PanelPlano` es Stateful; `PanelPlano.deLaLlegada(guia)` para las muestras. |
| La tarjeta sin sillas | `ContenidoBienvenida` ya no tiene `sillas`; `sillasYMusica` → `musicaDeLaLlegada` | `PersonaFicha.sillas` sigue en la ficha (dato), sin mostrarse. |
| El salón solo sorteado | `FichaTotem.desdePuerta` pasa el plano solo si `puerta.sorteado` | `FichaTotem.conPlanoDe(anterior)`: la ficha de cada minuto conserva la instancia del mismo salón (si no, se rearmaba todo). |
| Los tiempos | `TiemposDeBienvenida` en `services/bienvenidas_totem.dart` | Con el salón: `llegadaNombreSeg + llegadaCaminoSeg` (4 + 8 de entrada) y **con cola no se acorta** (decisión del usuario, 4-nov). Sin el salón: 7 s y 3 s con cola, como antes. `ReproductorBienvenidas.tiempos` (no avisa: lo pone la pantalla al dibujar). |
| La config | `TotemConfig`: `llegadaNombreSeg` (2–10), `llegadaCaminoSeg` (3–30), `llegadaLugar` | SQL **`supabase/migrations/20261105100000_totem_config_llegada.sql`, sin correr**. `conFondoDe` los conserva. |
| Personalizar | sección "LA LLEGADA" (solo masivo) en `totem_config_sheet.dart` | Dos barras en segundos (`BarraDeTamano` ahora acepta `paso` y `unidad`) y las fichas de dónde va el nombre. La vista muestra el salón de la fiesta; "Ver una llegada" enciende una mesa que existe (`LlegadaDeEjemplo.mesaDe`) y dura lo elegido. |
| Los segundos a mano esa noche | `TiemposAMano`, `tiemposAManoProvider`, `totemConfigDeLaNocheProvider`, `segundos_de_la_llegada.dart` | En Recepción, en un masivo, un **reloj** al lado de la paleta (para cualquiera, sin el permiso del tótem). Vive en la PC (SharedPreferences), llega a la ventana del tótem al instante (`KioskLauncher.notifyTiempos`, método `tiempos_totem`) y en la ficha de cada minuto (`FichaTotem.tiempos`), y sube a la nube a mejor esfuerzo (`TotemConfigRepository.guardarTiempos`, solo esas dos columnas). Guardar Personalizar parte de esos segundos y después los olvida. |

**Muestras** (`tool/totem_muestra_test.dart`, grupo "el salón en el tótem"; `--dart-define=salida=build/muestras_totem_salon`):
la espera, el nombre en grande y acomodada en vertical y horizontal, dónde va el nombre, claro o como antes, y la
tarjeta acomodándose paso a paso. El usuario las vio el 5-nov.

## Lo que quedó a medias (Parte 2, 2.1)

**Escrito, sin commit hasta este cierre, y sin usar todavía en ninguna pantalla:**
- `lib/models/silla_puerta.dart` (`SillaPuerta`: id, evento, contrato, mesa, cantidad, **vale**, anotado por, nota,
  quitada at/por/motivo). **Sin plata**: la cobra la barra.
- La base local pasa a la **v78** (`crearTablasV78`, tabla `sillas_puerta`, dos índices, en `_onCreate`, `_initDb` y
  `_onUpgrade`). `test/migracion_v78_test.dart` en verde; `migracion_v77_test.dart` ajustado a `versionNueva: 77`.
  **Falta** `tool/verificar_migracion_v78_test.dart` sobre una copia de la base real, con la app cerrada (se le pide al
  usuario).
- SQL **`supabase/migrations/20261105120000_sillas_puerta.sql`, sin correr** (copia de `mora_congelada`: RLS,
  disparadores, sin CHECK ni FK ni único, fuera de Realtime).
- `lib/features/recepcion/repositories/sillas_puerta_repository.dart` (`delEvento`, `vigentesDe`, `anotar`,
  `quitar(por, motivo)`, `cambios`). **Nunca borra.**

## Lo que falta, en orden

1. **Enchufar `sillas_puerta` al sync** (`sync_engine.dart`), en **las siete listas** (una que falte pisa en
   silencio): `_incrementalColumns`, `_tablasDelCobro`, el bloque de `_pullTable`, la prioridad junto a
   `sillas_reparto`, `_cleanForSqlite` (las 13 columnas), `_tablasSinRevisarBorrados` ('solo se agregan filas: quitar
   le pone quitada_at') y `tablasDeLaPuerta`. **No** en las `relaciones` de `sync_queue.dart`. Test
   `test/sillas_puerta_sql_test.dart` (cada clave de `toMap()` en el SQL y en `crearTablasV78`; sin `check` ni
   `references`; el repositorio sin `delete`).
2. **2.2 Lo puro:** `recepcion/services/sillas_de_la_puerta.dart` (`SillasDeUnaMesa`, `SillasDeLaFamilia`,
   `ConteoDeLaNoche`), `GrupoPuerta` con `contratoId`, `sillasPorMesa` y `movimientos`; `PuertaDelEvento.masivo(…,
   sillasPuerta:)`; `sillasPuertaDelEventoProvider` en `recepcion_provider.dart`. Las sumadas **no** entran en
   `SalonMesas.sillasExtra` ni en `RepartoDeSillas`.
3. **2.3 El candado:** `QuePide.sumarSilla/quitarSilla` (y **`tiemposTotem`**, el reloj del celular de 1.7),
   `decidirSilla` (sin vale no; el mismo vale dos veces no; en el tope no; quitar pide motivo), extraer
   `resolvedor_de_pedidos.dart` de `CentralPuerta` para que la PC pase por la misma fila, `AccionesPuerta.sumarSilla/
   quitarSilla/quienSoy`, `ClienteCentral`.
4. **2.4 El panel:** una línea por mesa ("Mesa 12: 8 sillas + 1 extra · puede agregar 1 más · se cobran en la
   barra"), SUMAR SILLA → `hoja_sumar_silla.dart` (mesa, **número del vale** obligatorio, nota), QUITAR con motivo
   obligatorio (la línea queda tachada), "Esta noche: 4 sillas sumadas · vales …" arriba. En PC y celular. El reloj de
   los segundos también en `PantallaPuesto`.
5. **2.5:** la oficina (grilla "· +1 puerta", Editar alumno una línea), `test/sillas_puerta_no_toca_test.dart`, la
   verificación de la migración sobre copia.
6. **Docs:** CONTEXTO de la versión (propuesta 6.4.0) y CLAUDE.md ("El plano en la llegada" → "El salón en el
   tótem"; Recepción suma las sillas de la noche).

## Decisiones del usuario y del jefe (4 y 5-nov)

- **El tótem:** salón entero y claro en la espera; "salta y se acomoda"; los segundos se eligen en Personalizar y se
  cambian a mano la noche ("debería estar a mano, el recepcionista a cargo debería poder"); **con cola no se acorta**
  ("la otra familia que ingresa se vuelve a mostrar y dura lo que los segundos configurados digan"); **la tarjeta en
  la pista** ("debería mostrarse la pista"); el borde del salón late cuando el camino marca la mesa; sin las sillas en
  la tele.
- **Las sillas de la noche (jefe, 5-nov):** hasta el 10-nov las sillas extra se venden en la oficina; desde que
  empiezan los sorteos, **solo la noche de la fiesta, ya sentados**, a la recepcionista de adentro (una da la
  bienvenida en la puerta, otra guía adentro). **La recepcionista no toca plata:** ve si puede agregar, los manda a
  **la caja de la barra**, que cobra "Silla extra" como un producto (precio por fiesta en el catálogo) y da un vale; la
  recepcionista suma la silla **con el número del vale**. Sumar y quitar dejan huella (quién, hora, motivo).
- **La barra (para sus etapas, no acá):** tilde nueva **"Encargada de barra"** en OPERADORES (ve las cajas de todas,
  cambio inicial y lo generado, anula con motivo, y también cobra); el jefe ve cada sector en **el cierre de caja de hoy
  con un selector COBROS · BARRA · ENTRADAS** (Entradas listo aunque vacío); la noche, routers sin internet, **una
  notebook central para la puerta y otra para la barra**, tapa abierta y prendidas, las tablets con el .apk conectadas
  por QR. Windows 7 (las Conectar Igualdad) no sirve; la Dell con Windows 10 de 64 bits sí.

## Queda para el jefe

- ¿La recepcionista puede quitar una silla sumada (con motivo y huella) o solo el jefe? El plan deja que pueda.
- ¿Quién ve en la barra las ventas de "Silla extra"? Dijo la encargada: va con la etapa de la encargada de barra.
- ¿Desde el 10-nov se traba cargar sillas extra al contrato en la oficina? Hoy no se traba.
- Si una familia quiere otra mesa la noche de la fiesta, ¿cómo se divide? Fuera de este plan.
- ¿Quién toca los segundos del tótem desde el celular? El plan deja que cualquiera.

## Lo que no se tocó

El sorteo, las planillas, el retiro de entradas, la cuenta del alumno y `contratos_alumnos`. Ningún SQL corrido.
Nada instalado.
