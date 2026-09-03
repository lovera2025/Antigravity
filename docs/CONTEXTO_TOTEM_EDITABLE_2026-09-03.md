# Tótem editable por evento — el salón deja de decir "Junior Eventos"

**Fecha:** 2026-09-03
**Rama:** `claude/session-r5lh1d` (sale de `feature/v4.6-cierre-por-sesiones`, v4.9.4)
**CON migración de base.** `supabase/migracion_totem_config.sql` — **no aplicada
todavía**, a pedido. Cada sentencia lleva su `ROLLBACK` comentado arriba.

**En curso, no publicado.** Este documento se escribe a mitad del trabajo porque
aparecieron dos hallazgos que cambian decisiones ya tomadas y conviene que
queden anotados antes de que se pierdan.

**Novedades previstas:**
```
- El tótem muestra la foto y el saludo del evento: para un quince, la foto de la quinceañera, no el logo de la empresa.
- La pantalla se da vuelta entre vertical y horizontal desde un botón en el propio tótem.
- Un invitado borrado en Recepción ahora desaparece del tótem en el momento.
```

---

## De dónde salió

El tótem se lleva a una pantalla vertical y queda de cara a los invitados toda la
noche, pero muestra el logo del proveedor y dice "JUNIOR EVENTOS". Para un quince
el cliente quiere ver a la quinceañera y su saludo. Todo eso estaba escrito a
mano en el código (`totem_display.dart:575`, `:637`, `:647`, y el dorado
`_gold = 0xFFD4AF37` en `:35`), así que cambiarlo era recompilar.

Dos cosas más salieron a la luz mirando eso:

- **El modo vertical nunca se activaba.** El layout portrait existe desde
  siempre en el código, pero la ventana nace en 1280x720 (`kiosk_launcher.dart:24`)
  y el umbral `maxWidth > maxHeight * 1.2` la mandaba siempre a la rama widescreen.
- **Un invitado borrado seguía en pantalla** hasta reiniciar la ventana.

---

## EL BORRADO: EL FILTRO DEL 2 DE SEPTIEMBRE LO EMPEORÓ SIN QUE SE VIERA

Verificado contra `bucnrydgojyzntgesxqb`:

```
tabla=invitados · replica_identity = DEFAULT (solo PK en DELETE) · en_realtime = true
```

Con `REPLICA IDENTITY DEFAULT`, el payload de un DELETE en la replicación lógica
lleva **solo la primary key**. Una suscripción filtrada por columna no puede
evaluar su filtro contra ese payload pelado, así que **el servidor descarta el
evento**. La lógica de remoción del lado cliente ya estaba bien escrita
(`totem_display.dart:314-325`): nunca se ejecutaba porque el stream no emitía.

Lo que importa del orden en que pasó:

| Cuándo | Tótem (`.stream().eq('evento_id')`) | Panel de Recepción (`onPostgresChanges`) |
|---|---|---|
| Antes del 2026-09-02 | ciego al DELETE | **veía el DELETE** — no tenía filtro |
| Desde el 2026-09-02 | ciego al DELETE | **ciego también** |

El filtro `eq('evento_id')` que la v4.9.4 le agregó al panel
(`invitados_repository.dart:604`) es correcto y necesario —sin él un check-in
refrescaba todos los eventos abiertos—, pero de paso le sacó al panel la única
razón por la que funcionaba. Nadie lo hubiera notado leyendo ese diff.

**Agregar un filtro a una suscripción de Realtime es gratis en apariencia y
rompe los DELETE en silencio.** Es el tipo de cosa que conviene tener escrita.

El arreglo es una línea: `ALTER TABLE public.invitados REPLICA IDENTITY FULL;`

### Y el Disk IO

`REPLICA IDENTITY FULL` agranda el registro de WAL de cada UPDATE/DELETE, y el
costo de `apply_rls` escala con el volumen de WAL — justo lo que la v4.9.4 vino a
bajar. Por eso se acota a `invitados` y a nada más:

- Es la única tabla que quedó en la publicación.
- Tiene 8 columnas cortas y unos cientos de filas por evento, contra las 3.121 de
  `pagos_contrato_alumno`.
- Los INSERT no se ven afectados: FULL solo agrega la fila vieja al registro, y
  en un INSERT no hay fila vieja. Durante una carga de lista —que es cuando más
  se escribe— el costo no se mueve.

**No se agrega ninguna tabla a la publicación.** El plan original decía sumar
`permisos_usuario` y `perfiles` para los permisos en vivo y la lista de
operadores. Leer este contexto lo frenó a tiempo: habría deshecho parte del
arreglo del incidente de Disk IO Budget, dos días después. Ambas cosas se
resuelven por **broadcast** y **presence**, que no consultan el WAL.

---

## QUÉ SE HIZO

### 1. `totem_config`: una fila por evento, o ninguna

```sql
CREATE TABLE public.totem_config (
  evento_id UUID PRIMARY KEY REFERENCES public.eventos(id) ON DELETE CASCADE,
  titulo TEXT, subtitulo TEXT, mensaje_bienvenida TEXT, mensaje_qr TEXT,
  imagen_url TEXT, color_acento TEXT DEFAULT '#D4AF37',
  updated_at TIMESTAMPTZ DEFAULT now(), updated_by UUID REFERENCES auth.users(id)
);
```

`TotemConfig.defaults()` devuelve **exactamente los literales que hoy están en el
código**. Un evento sin fila se ve idéntico a como se veía siempre: la tabla
empieza vacía y nada cambia hasta que alguien configure algo.

La RLS de escritura es `is_admin() OR puede_totem`, lo que convierte a
`puede_totem` en **el primer permiso con RLS real**. Hasta hoy los ocho flags de
`permisos_usuario` solo escondían tarjetas del menú: no había nada del lado del
servidor.

La lectura es pública (`anon`) porque el tótem web y la pantalla del invitado
corren sin login, igual que ya pasa con `invitados` y `eventos`.

### 2. La config llega por stream, con caché en disco

`totemConfigProvider` (StreamProvider.family) emite primero lo que haya en
SharedPreferences y después lo del stream. Dos razones: el tótem se proyecta en
salones donde el wifi es una lotería, y así la ventana **se actualiza sola** al
guardar desde el editor, sin reiniciarla.

Ante cualquier error —tabla que todavía no existe, sin red, evento sin fila—
devuelve los valores por defecto. La pantalla del salón nunca muestra un spinner
ni un error.

Lee `supabaseProvider`, no el singleton: en la ventana secundaria ese provider
está sobreescrito con el cliente standalone (`main.dart:60`).

### 3. La foto y el saludo, en las tres superficies

Tótem del salón, panel embebido en Recepción y celular del invitado
(`/lista?evento=<id>`) muestran la misma foto, el mismo título y el mismo saludo.

El gradiente violeta del panel "YA LLEGARON" **se mantiene con el dorado por
defecto** y solo se deriva del acento si se eligió otro color
(`TotemConfig.gradientePanel`). Sin eso, un tótem sin configurar habría cambiado
de aspecto, y con acento rosa el panel habría quedado violeta.

### 4. El giro, desde la propia pantalla

Botón que cicla auto → vertical → horizontal. En escritorio **da vuelta la
ventana de verdad** (`WindowController.setFrame` a 9:16 o 16:9 ajustado al
monitor), no solo el layout. En web solo cambia el layout, que es justo lo que
hace falta cuando la smart TV ya está rotada pero el navegador informa apaisado.

La elección se recuerda por evento. Los botones flotantes se desvanecen a los 5 s
sin interacción: un botón fijo arruina la proyección.

### 5. Dos números sueltos que no coincidían

El layout horizontal tenía el panel de ingresados en un `Positioned` con ancho
`maxWidth * 0.3` mientras la sección del QR reservaba `padding-right: maxWidth * 0.35`.
Dos constantes que había que mantener sincronizadas a mano y no coincidían, así
que se pisaban al cambiar el tamaño de la ventana. Ahora es un `Row` de dos
`Expanded` 60/40: el reparto lo hace el layout.

La escala tipográfica salía siempre de `maxHeight / 900`, calibrado para 720p. En
una pantalla vertical de 1920 saturaba el clamp y quedaba todo diminuto. Ahora se
calcula sobre la dimensión que limita en cada orientación.

### 6. Que una pantalla de ocho horas no se desfase

- Reconciliación cada 60 s: relee los invitados y los pasa por `_onData`, que ya
  tiene el guard de `_processedIds` para no re-disparar bienvenidas de gente que
  ya entró.
- Refetch al reconectar: el stream solo cuenta lo que pasa de ahí en adelante, y
  si estuvo caído treinta segundos, lo del medio no llega nunca.
- Aviso de borrado por dos vías: puente entre ventanas (`notifyGuestRemoved`,
  latencia cero en la misma PC) y broadcast `guest_removed` para tótems remotos.

El backoff existente solo reacciona a errores explícitos, no a un socket que
quedó mudo. De ahí la reconciliación.

---

## LO QUE FALTA

- **Editor** (`TotemConfigSheet`): subir la foto con `file_picker` (`withData: true`,
  obligatorio para que ande en web) a Storage, campos de texto y paleta de acento,
  con preview en vivo. Es lo único que necesita la tabla nueva.
- **Permisos en vivo**, rediseñado: broadcast en un canal `permisos_<uid>` al
  guardar, más refetch en el tick del pull. **Sin tocar la publicación.**
- **Presencia confiable**, rediseñado: el payload de `online_users` ya trae
  `user_id` y `email`, así que un desconocido conectado se puede mostrar sin
  suscribirse a `perfiles`. Falta presencia global (hoy se publica solo desde
  ciertas pantallas), heartbeat con vencimiento contra el verde fantasma, y
  `last_seen_at`.
- **Filtro particulares/masivos** en el selector de evento del tótem, y separar
  "limpiar pantalla" (volver todos a pendiente, reversible) del "vaciar lista"
  actual, que hace `DELETE FROM invitados` de verdad.
- **Pantalla de la cola de sync**: hoy el Dashboard dice "N cambios pendientes" y
  no hay forma de ver qué son ni por qué están trabados.

---

## EL ORDEN IMPORTA

La migración va primero, pero **solo hace falta para el editor**. El giro, el
layout arreglado y la reconciliación andan con la base como está hoy: sin fila en
`totem_config` el tótem usa los valores de siempre. Se puede probar la pantalla
sin tocar Supabase.

---

## NOTAS

- `flutter analyze` no se corrió: las sesiones remotas de Claude Code no traen
  Flutter ni Dart en el contenedor. Hay que correrlo localmente antes de
  publicar.
- El trabajo arrancó ramificado de `main`, que está 74 commits atrás. Se rebasó
  sobre `feature/v4.6-cierre-por-sesiones` y salió limpio: los archivos del tótem
  son idénticos en las dos ramas. `finanzas_view.dart` sí difiere fuerte
  (+2191/-2068), así que los bloques de permisos y presencia hay que escribirlos
  sobre la versión de v4.6.
