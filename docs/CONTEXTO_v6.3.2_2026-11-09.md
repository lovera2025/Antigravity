# La 6.3.2: la mora adelantada (parche sobre la 6.3.1)

6 a 9-nov-2026. Rama **`release/6.3.x`** (creada desde el tag `v6.3.1`, en la carpeta `..\arguello_events_6.3.x`), con cada commit
de código también en `feature/v4.6-cierre-por-sesiones`. **Los documentos (este, el plan, `CLAUDE.md`) viven solo en la rama
feature**, que es la de la carpeta del proyecto. El plan: `docs/PLAN_MORA_ADELANTADA_2026-11-06.md`. Meta: **publicar el lunes 9-nov.**

## Para retomar en otro chat

**Estado al 7-nov (mañana): PUBLICADO dentro de la 6.3.3** (un solo instalador con la mora y el sync en reposo; ver el CONTEXTO de
la 6.3.3). No hubo instalador de la 6.3.2: el tag `v6.3.2` marca el commit `2789053`. **El simulacro, repetido el 7-nov** sobre una
copia de la base de las 07:26 (igual a la nube: último pago el 6-nov 19:59): los mismos 4 alumnos, a los 4 les baja (-$65.500 a la
fecha), nadie en el grupo B, ningún perdón cambiado, la revisión de verdad los deja como dice la regla. Foto "antes de 6.3.3" sacada
(7-nov 07:47). **Instalada en las tres PCs el 7-nov** (la casa 07:53, la oficina 08:18) y la foto "después" (08:26): cambian solo los
4 del simulacro, con sus números, y nadie más. Cerrada.

Lo de abajo es el estado al 6-nov: el arreglo, las pruebas y el simulacro están hechos y en las dos
ramas. Lo que queda, en orden, está en "Lo que falta" (abajo). **Ningún instalador de la 6.3.x sale de la rama feature**: esa tiene la
v78 de la base y dos SQL sin correr.

> Frase para retomar: "Seguimos con la 6.3.2: leé 'Para retomar en otro chat' de docs/CONTEXTO_v6.3.2_2026-11-09.md y decime en qué
> paso estamos."

## Qué pasaba

**LOPEZ, MORENA AILEN** (GREGORIA MORALES, contrato `31f442c5…`) pagó el 6/11 la cuota 2 completa, la 3, $9.100 a cuenta de la 4 y
$130.900 de mora de las cuotas 2, 3 y 4. Se cerraron la 2 y la 3 ($98.000 de mora); los $32.900 de la 4 eran un adelanto.

El "ya usado" (`mora_cobrada_offset`) se quedaba con los $130.900 enteros. El crédito de la 4 desaparecía y la app le volvía a pedir
esa mora: **$268.100 en vez de $235.200**. El operador cobró bien. **La mora congelada no tenía nada que ver.**

Y al revés (el segundo problema): $15.000 de mora pagados sobre una cuota que todavía no se completaba seguían como crédito cuando la
cuota se completaba sin mora, y se descontaban **también** de la siguiente. Se cobraba de menos.

## Qué cambió

Una sola función: `MoraCuotaCalculator.postCobroTrackedOffset`, la rama de las cuotas que se liquidan en el cobro. La usan el cobro, la
revisión de la mora al abrir, anular un cobro y el rótulo de la ficha: todos quedan iguales.

- El "ya usado" se queda solo con la mora de **lo que se cierra**: (a) el crédito que ya cubría esas cuotas, (b) lo cobrado que va a
  ellas y al arrastre, y (c) lo que sobra **solo si cubre todas las cuotas abiertas**. Si no las cubre, es un adelanto y queda como
  crédito de la cuota abierta más vieja.
- La regla que cumple después de cualquier cobro: `historial − offset` es exactamente la mora pagada por adelantado de cuotas que
  siguen abiertas.
- La función ahora lee el desglose bruto, y un `assert` frena si un llamador lo pasa vacío.
- **La costura `cuenta`** (`CuentaPostCobro`, en `mora_tracked_recovery.dart`): el repaso del historial puede correr con otra regla,
  solo para que una herramienta compare. La app nunca la pasa (un test lo vigila).

**No deja ninguna nota en la app** (pedido del usuario). Lo único que queda escrito es lo de siempre: `revision_mora.txt` junto a la base
y `mora_cambios` en la nube, que la app no muestra.

## Las pruebas

- **`test/mora_adelantada_cuota_abierta_test.dart`, 10 casos**, con los pagos reales de Morena (sacados de la nube, solo lectura) y su
  mora congelada desde el 2/11. **8 se vieron en rojo antes del arreglo**, con los números del caso (130.900 en vez de 98.000; 32.900
  pedidos de nuevo al completar la 4). Los otros dos vigilan lo que ya andaba (el adelanto que cubre todo y los orígenes de la ficha).
- Las **153 pruebas de la mora que ya había pasan sin tocar ninguna** (las de caracterización incluidas).
- `test/revision_mora_test.dart`: la prueba que cuenta las llamadas con el historial ahora cuenta también las de la costura, y una
  nueva exige que la costura traiga siempre la cuenta de la calculadora y que la revisión no la elija.
- **Las 3.720 del proyecto en verde** en la rama feature.

## El simulacro

`tool/simulacro_mora_adelantada_test.dart`, sobre una **copia** de la base (`VACUUM INTO`, solo lectura; la base real queda con la
misma huella). Para cada alumno que la revisión toca al abrir, repasa su historial con la regla de antes (copiada adentro del tool) y
con la nueva. Saca `simulacro_mora_adelantada.txt` y `.csv` (con `;` para el Excel). Con `--dart-define=detalle=cambios`, explica
cada cambio cobro por cobro. Después corre la revisión de verdad sobre la copia y comprueba que deja a cada uno como dice la regla
nueva y que ningún perdón cambió. **Carga la mora congelada**, como la app; el viejo `tool/simulacro_revision_mora_test.dart` no la
cargaba, y ahora sí.

```
flutter test tool/simulacro_mora_adelantada_test.dart --dart-define=copia=<copia.db> --dart-define=salida=<carpeta> --dart-define=detalle=cambios
```

**El simulacro con la base al día (6-nov, 23 h):** el usuario abrió la app en la casa, bajó todo y la cerró (base de las 22:52, último
pago 19:59). Corrido **desde la rama del parche**, sobre la copia. 461 alumnos revisados, 28 con mora congelada.
**Cambian 4 y a los 4 les baja la mora ($65.850 en total); a ninguno le sube** (grupo B vacío: no hay nada que decidir). La
revisión de verdad los deja como dice la regla nueva, ningún perdón cambió, y en los cuatro la mora que hoy muestra la app es
exactamente la de la regla vieja.

| Alumno | Institución | Mora de hoy | Por qué |
|---|---|---|---|
| LOPEZ, MORENA AILEN | GREGORIA MORALES | $67.200 → $34.300 | El caso: el "ya usado" queda en $98.000 y no en $130.900 (la app muestra $235.200, no $268.100) |
| MELGAREJO, MAIARA | ROTONDA | $40.400 → $14.800 | Lo mismo: el 3/11 pagó $63.600 de mora cerrando solo la 4 ($38.000); los $25.600 de la 5 se le volvían a pedir |
| PAEZ, MARCELO ARIEL | TECNICA PINAROLI | $22.050 → $16.450 | Los dos errores: el 28/09 pagó $7.700 de más que se perdían, y los $7.000 del 20/10 se descontaban de la 3 y otra vez de la 7 |
| ROMERO, THIAGO | GUEMEZ DE TEJADA | $26.950 → $25.200 | El 5/10 pagó $1.750 de más sobre la 2; ahora se descuentan de la 3 |

Cada uno revisado cobro por cobro con `detalle=cambios`: en los cuatro la regla nueva da lo correcto. Una primera mirada a las
15:42, sin el cobro de Morena, había dado los otros tres iguales.

**Hasta instalar, a estos cuatro se les cobra sobre la mora de la regla nueva** (la columna de la derecha).

## Lo que falta (en orden)

1. ~~El simulacro con la base al día~~ **hecho el 6-nov a las 23 h** (arriba): 4 alumnos, a los 4 les baja, nadie en el grupo B.
   **El lunes, antes de instalar, se repite** igual (abrir la app en la casa, cerrarla, copia, simulacro): son 3 segundos, y cubre
   lo que se cobre el sábado. Si aparece alguien en el grupo B, lo decide el jefe antes de instalar.
2. **La versión:** `6.3.2+64` en `pubspec.yaml` y `installer/junior_eventos_setup.iss`, en las dos ramas. Tag `v6.3.2` sobre
   `release/6.3.x`.
3. **Foto de la mora "antes de 6.3.2"** (`supabase/mora_fotos.sql`, sección 1, por el MCP, con el OK).
4. **El instalador**, desde `..\arguello_events_6.3.x`: `powershell -File installer\build_installer.ps1` como proceso aparte. El release
   en GitHub, como en las anteriores.
5. **La web**, desde la misma carpeta: `flutter build web --release`, a `.vercel/output/static` con su `config.json`, y
   `npx vercel deploy --prebuilt --prod`. La carpeta `.vercel` no viaja con git: copiar `.vercel\project.json` de la carpeta del
   proyecto.
6. **Instalar las tres PCs el mismo día** (las hace el usuario): el operario antes de abrir caja, el jefe después. Abrir cada una: la
   revisión de la mora corre al arrancar y corrige a los afectados.
7. **Foto "después"** y la comparación (sección 3 del SQL): lo que aparezca tiene que ser lo del simulacro. Si aparece otra cosa,
   `mora_cambios` dice qué escritura fue.
8. Este CONTEXTO y `CLAUDE.md` al día con lo que pasó.

**Sin SQL en la nube**: no hay tabla nueva.

## Después

La **6.3.3, el sync en reposo**, desde la misma rama: **ya programada y probada el 6-nov** (`docs/CONTEXTO_v6.3.3_2026-11-06.md`).
Ojo: la rama `release/6.3.x` ya tiene los commits de la 6.3.3 encima de los de la 6.3.2. **Para armar el instalador de la 6.3.2
hay que hacerlo desde el commit de la mora** (con un tag `v6.3.2` puesto en ese commit, `2789053`, más el de la versión), **no desde
la punta de la rama**; o publicar las dos juntas si el usuario lo prefiere. Recién después vuelven la barra 5-10 y Entradas 4-6
(la 6.4.0).
