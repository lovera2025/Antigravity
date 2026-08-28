# Junior Eventos v4.9.3 — el perdón de mora cruza entre las dos PCs

**Fecha:** 2026-08-28
**Rama:** `feature/v4.6-cierre-por-sesiones`
**CON migración de base.** `supabase/migrations/20260828000000_mora_exencion_columns.sql`
agrega cuatro columnas a `contratos_alumnos`. Es aditiva y no toca datos, pero
**la migración va antes que el instalador**: ver "El orden importa", abajo.

**Novedades publicadas:**
```
- El perdón de mora que hace el jefe ahora también se ve en la PC de operarios.
- Antes quedaba guardado solo en la máquina donde se hacía.
```

---

## De dónde salió

MOREIRA, FACUNDO N (Técnica Pinaroli). El jefe le perdonó la mora en la PC de
oficina y la ficha quedó en $0. En la notebook de operarios el mismo alumno seguía
mostrando la mora corriendo: 89 días, **$92.783**. Las dos máquinas con la 4.9.2
instalada.

No era frescura de datos. `OperationalSyncCoordinator` baja `contratos_alumnos`,
`pagos_contrato_alumno` y `notas_operativas_contrato` **cada 10 segundos** mientras
haya rol elegido y la ventana en foco. La notebook estaba al día. El problema era
que el dato **no tenía a dónde viajar**.

---

## LA CAUSA: CUATRO COLUMNAS QUE NUNCA SE CREARON EN LA NUBE

El perdón vive en cinco campos. En Supabase existían **dos**:

| Columna | ¿Estaba en Supabase? |
|---|---|
| `mora_pendiente_tracked` | sí |
| `mora_tracked_ajuste` | sí — la agregó v4.7.8 |
| `mora_exenta_hasta` | **no** |
| `mora_exencion_reinicia` | **no** |
| `mora_cobrada_offset` | **no** |
| `mora_fecha_referencia` | **no** |

Las cuatro se agregaron al SQLite local en las migraciones v44, v52, v56 y v61 de
`local_database.dart`. **La contraparte de Supabase nunca se escribió** — no había
un solo `.sql` en el repo que las mencionara.

Y `SyncEngine._cleanForRemote` las borraba del payload antes de subir:

```dart
copy.remove('mora_cobrada_offset');
copy.remove('mora_exenta_hasta');      // ← el corazón del perdón
copy.remove('mora_exencion_reinicia'); // ← lo que lo hace permanente
copy.remove('mora_fecha_referencia');
```

Eso era **correcto** mientras las columnas no existieran: sin ese filtro, PostgREST
habría rechazado el update entero con PGRST204 y se habría frenado la sincronización
de todos los contratos, cobros incluidos. El agujero no era el filtro, era la
migración que faltaba del otro lado.

Resultado: subía `mora_tracked_ajuste` —la única de las cinco que sí existía— y la
exención se perdía **sin un solo error**. El pendiente bajaba a cero y todo parecía
bien. El jefe veía la mora perdonada, el operario la veía corriendo, y los dos
tenían razón sobre su propia base.

---

## POR QUÉ EL AJUSTE SOLO NO ALCANZA

`mora_tracked_ajuste` protege la **ficha** (que el recovery post-sync no resucite el
remanente). Lo que apaga el **calendario** es la exención, y son cosas distintas.

En `pendienteDisplay`, con `tracked = 0` el `if (t > 0.01 && t < f - 0.01)` nunca
entra, así que devuelve `max(f, 0) = f` — la fórmula pura. Poner la ficha en cero no
perdona nada por sí solo. Lo que lleva `f` a cero es
`_vencimientoEfectivoConExencion` (corre el vencimiento hasta `mora_exenta_hasta`) y,
pasada esa fecha, `_omitirCuotaExencionPermanente` (que exige `reinicia == false`).

De ahí que **la exención viaje como par indivisible**: la fecha sin la permanencia no
alcanza, porque la mora vuelve apenas la fecha pasa.

---

## EL FIX

**1. `supabase/migrations/20260828000000_mora_exencion_columns.sql`** — las cuatro
columnas. `mora_exencion_reinicia` va `smallint` y **no `boolean`** a propósito:
`ContratoAlumno.payloadForRemote` manda `1`/`0` y PostgREST rechaza un entero contra
una columna booleana. Los defaults replican el esquema local (`0` y `1`).

**2. `_cleanForRemote`** — se quitan los cuatro `remove`. Queda `line_kind`, que sí
es local-only (verificado: no existe en `pagos_contrato_alumno`).

**3. Merge del pull (`_pullTable`)** — forzar el valor local era correcto cuando la
nube no tenía las columnas; ahora es justo lo que impediría que el perdón cruce.
Pasa a mandar la nube. Las filas con cambios locales sin subir siguen protegidas por
el guard de `pendingIds`, que las saca del pull antes de llegar acá.

La única excepción es la exención: si la nube no la trae, es un perdón viejo que el
filtro anterior nunca dejó subir, y pisarlo sería perderlo de la única máquina que lo
tiene. En ese caso se conserva el par local completo.

**4. `contratos_repository._pullByEvento`** — reescribía el contrato desde la nube
sin preservar nada. Como `toJson` **omite la clave** cuando no hay fecha, el
`INSERT OR REPLACE` dejaba la columna en su default y **borraba el perdón en la
propia PC del jefe** cada vez que se refrescaba la pantalla de masivos. Mismo
criterio que el punto 3.

---

## EL ORDEN IMPORTA

**La migración va antes que el instalador, siempre.** Si la 4.9.3 llega a una máquina
antes de que existan las columnas, la app empieza a mandar `mora_exenta_hasta` a una
tabla que no la tiene y PostgREST rechaza el update completo. No se rompe solo el
perdón: se frena la sincronización de **todos** los contratos, cobros incluidos.

En esta tanda la migración se aplicó a producción varias horas antes de publicar el
release, así que el riesgo no existió.

---

## LOS DATOS, HOY

Sobre 643 contratos, **14** tienen perdón registrado (`mora_tracked_ajuste < 0`). De
esos, solo **2** le mostraban mora al operario el 28-ago:

| Alumno | Institución | Vto. | Días | Mora que veía el operario |
|---|---|---|---|---|
| MOREIRA, FACUNDO N | TECNICA PINAROLI | 2026-05-31 | 89 | $92.783 |
| ARRIETA, BRENDA ANAHI | COLEGIO NACIONAL | 2026-05-31 | 89 | $75.027 |

Los otros 12 tienen la próxima cuota sin vencer (31/8 o 30/9), así que jefe y
operario coincidían en $0. Son **latentes**: divergen cuando pase el vencimiento si
el perdón sigue sin estar en la nube.

**Reparación de los 2, por SQL y no por la app.** La build instalada *lee* esas
columnas —el allowlist de `_cleanForSqlite` ya las incluía— pero no las escribe, así
que rehacer el perdón desde la app no habría servido hasta tener la 4.9.3 puesta. Se
escribió lo mismo que escribe `payloadPerdonMora`: `mora_exenta_hasta = 2026-08-31`
(fin de mes, `calcularFechaExencion`) y `mora_exencion_reinicia = 0`.
`mora_pendiente_tracked` ya estaba en 0 y `mora_tracked_ajuste` ya estaba en la nube.

Verificado replicando la lógica del calculador en SQL: los dos dan **0 días y $0**,
hoy porque el vencimiento efectivo se corre al 31/8, y desde el 1/9 porque entra la
exención permanente.

---

## LO QUE NO SE TOCÓ

- **El cálculo de mora.** Ni una línea de `mora_cuota_calculator.dart`. El bug era de
  transporte, no de cuentas.
- **`mora_tracked_ajuste`** conserva su guarda de "nube en 0 no pisa un perdón local".
  No había valores varados ahí —esa columna sí existía—, pero cambiarla no aportaba
  nada y sí agregaba riesgo.
- **El filtro `line_kind`** de `_cleanForRemote`, que sigue siendo local-only.
- **Los 12 latentes.** Se dejaron como estaban: no molestan hoy y conviene rehacerlos
  desde la app con las dos máquinas ya actualizadas.

---

## ESTADO

**447 tests**, los mismos de la 4.9.2, todos pasando. `flutter analyze` sobre los dos
archivos tocados: sin errores nuevos (quedan los avisos de siempre —
`curly_braces_in_flow_control_structures` en `sync_engine` y `_connectivity` sin usar
en `contratos_repository`—, ninguno en las líneas de este cambio).

**Sin tests nuevos.** El cambio vive en la capa de sync, que el arnés no cubre: no hay
doble de Supabase ni test que ejercite `_cleanForRemote` ni el merge del pull. Ver
"Pendiente para otra tanda".

**Release publicado:** `v4.9.3` → commit `d5a2585`, asset
`Setup.Junior.Eventos.v4.9.3.exe` (32.611.966 bytes). Cuerpo publicado con
`-SoloNotas`, dos renglones.

---

## FALTA PROBAR EN LA APP

Nada de esto se ejercitó con la app instalada: se hizo desde casa, sin acceso a la PC
de oficina ni a la notebook. La verificación fue por SQL y por el arnés.

Para la primera oportunidad, en este orden:

1. **Antes de instalar nada**, abrir la app y confirmar que MOREIRA y ARRIETA figuran
   sin mora. Eso valida la parte de Supabase por separado del código.
2. Instalar la 4.9.3 en las dos máquinas.
3. Perdonar una mora nueva en la PC de oficina y confirmar que aparece en la notebook
   dentro de los ~10 segundos del coordinador.
4. Confirmar que un perdón viejo que estuviera solo en la máquina del jefe no se
   borra al refrescar masivos (es la excepción del punto 3 del fix).

---

## PENDIENTE PARA OTRA TANDA

**Los 12 latentes**, antes del 31/8. Con ambas PCs en la 4.9.3, comparar jefe vs
operario y rehacer desde la app los que difieran. Consulta de partida: contratos con
`mora_tracked_ajuste < -0.01` y `mora_exenta_hasta IS NULL`.

**Un test del contrato de sync.** Lo que falló acá no fue una cuenta sino un acuerdo
entre dos esquemas, y eso hoy no lo cubre nada. Lo más barato que lo habría agarrado:
un test que compare el allowlist de `_cleanForSqlite` contra las columnas reales de
cada tabla en Supabase, y falle cuando el código mande algo que la nube no tiene.

**La notebook no se está actualizando sola.** Reporte de "error, intenté más tarde" al
entrar o descargar. Ese texto **no existe en el código**: entrar en modo jefe valida
el PIN contra `SharedPreferences` sin tocar la red (su único error es "PIN de jefe
incorrecto"), `AppUpdateChecker.consultar()` devuelve `null` en silencio ante
cualquier falla, y los cuatro errores reales del bajador dicen otra cosa. Sospechas:
SmartScreen o el antivirus sobre el `.exe`, o que el usuario de esa notebook no sea
administrador local y no pueda con el UAC. Falta el cartel exacto. Mientras tanto, el
Setup se copia a mano desde el Release y se corre como administrador.

---

## Documentos relacionados

- **`docs/CONTEXTO_MORA_OPERATIVA.md`** — doc vivo de mora; este incidente quedó como
  el 0.
- **`docs/CONTEXTO_v4.7.8_2026-08-16.md`** — perdón durable (`mora_tracked_ajuste`),
  la única de las cinco columnas que sí llegó a Supabase en su momento.
- **`docs/CONTEXTO_v4.3.0_2026-07-09.md`** — perdón admin por exención; ahí nació
  `mora_exenta_hasta` y la regla de "recovery no degrada exención local" que este
  cambio invierte.
- **`docs/CONTEXTO_SYNC_v4.1.6.md`** — sync offline-first.
