# Cerrar la lista de la puerta a los anónimos

**Estado:** **programado el 15-oct-2026** (sección 8 de la 6.0.0, sin publicar). Falta correr los dos SQL al
publicar, en orden: `supabase/migrations/20261016120000_puerta_funciones.sql` antes de instalar, y
`20261016130000_puerta_cerrar_permisos.sql` último, con todas las PCs y la web en la 6.0.0. Cómo quedó: "La
sección 8" de `docs/CONTEXTO_v6.0.0_2026-10-11.md`.
**Postergado el:** 2026-09-25

## Qué se hizo el 15-oct-2026

Lo de "Qué hacer", con estos cambios:
- **La función del tótem se llama `totem_lista`** y la clave sale de una tabla nueva, `claves_totem`, que pide con
  usuario la ventana principal (`totem_clave`) y le pasa al tótem por el puente. El tótem por el navegador la lleva
  en el link, que se copia de Personalizar tótem.
- **El tótem relee cada 20 s** (no cada minuto): sin el stream de la tabla, lo que no avisa el canal llega así.
- **`/op` se apagó** (no hizo falta preguntar: ya no andaba y ningún evento tenía PIN).
- **`?buscar` es la misma página que `/lista`.**
- Apareció y se arregló: el aviso de cada ingreso al tótem llevaba el DNI.
- Queda abierto el canal de avisos: [canal-totem-abierto.md](canal-totem-abierto.md).

Lo de abajo es cómo estaba planteado.

## Qué cambió el 13-oct-2026

- **Dejó de ser "para diciembre":** el usuario quiere Recepción y el tótem nuevos dentro de la 6.0.0, y esto con
  ellos. El orden de abajo ("Qué hacer") sigue valiendo, y sigue yendo después del tótem nuevo.
- **La regla de no pasar la lista ya no corre, y la bandera está prendida.** Desde ese día la lista de la puerta
  **sigue al sorteo**: se arma sola al sortear y se vacía sola al deshacer (`PuertaAlDia`, ver `CLAUDE.md`). El
  usuario lo pidió para poder ensayar con una institución real un mes antes. `kListaPuertaHabilitada` quedó en
  `true`; el último paso de este pendiente ya no es prenderla.
- **Por eso esto pasó a importar más:** desde el sorteo de verdad (noviembre) la lista queda cargada hasta la
  fiesta, con el nombre y la mesa de cada alumno y sus acompañantes. Conviene tenerlo cerrado antes de ese sorteo.
- **Apareció otro agujero, del mismo lugar.** `/lista` (`lista_invitados_screen.dart`, `_onSelect`) y `?buscar`
  (`buscar_invitado_screen.dart`, `_onGoToDni`) **saltean la verificación si el invitado no tiene DNI cargado** y
  marcan el ingreso directo. Los alumnos no tienen DNI (sus filas van con `dni` vacío), así que con el QR a la
  vista cualquiera puede marcar a otro desde su celular.
  - No se cerró en la pantalla porque desde la web no hay cómo distinguir a un alumno de un invitado sin DNI de una
    fiesta particular: los ids de la puerta se ven igual que cualquier otro (`UuidUtils` les pone versión 4) y
    `eventos` no es público. Cambiarlo para todos cambiaba las fiestas particulares.
  - Se cierra con dos cosas que ya estaban decididas: el tótem nuevo **no muestra el QR en los masivos**
    (`totem-apariencias.md`), y `puerta_checkin` compara el DNI **en el servidor** y no marca a quien no lo tiene.
  - La app de escritorio ya lo rechaza (`validarDniYMarcarIngreso` devuelve `no_dni`), y `/op` lo deja pasar a
    propósito: es el operador.

## Por qué se postergó

Cerrar los permisos cambia cómo lee el tótem, y el tótem se rehace en diciembre
([totem-comunicacion.md](totem-comunicacion.md), [totem-apariencias.md](totem-apariencias.md)).
Hacerlo antes era tocar el tótem dos veces, y es la única pieza que rompe la
versión anterior: con los permisos cerrados, el tótem de una PC con la versión
vieja queda en blanco. El usuario eligió dejarlo para diciembre, junto con el
tótem, el 25-sep.

**Regla hasta que esté: no pasar la lista de la puerta de ninguna fiesta de
egresados** (MÁS → "Pasar a la lista de la puerta"). Hoy la tabla tiene 7 filas
de prueba; con la lista pasada serían los alumnos de toda la institución.

**Desde la 6.0.0 la app lo traba sola:** `kListaPuertaHabilitada = false` en
`lib/features/recepcion/services/lista_puerta.dart`. El renglón de MÁS queda
apagado con "Se habilita en diciembre, cuando se cierren los permisos de la
lista", y un test falla si alguien prende la bandera. **Al cerrar la RLS, el
último paso es pasarla a `true`** (y ajustar ese test).

## Cómo está (verificado en la base el 25-sep)

- `invitados` tiene dos políticas para `anon` con `true`:
  `lectura_publica_invitados` (SELECT) y `actualizacion_publica_invitados`
  (UPDATE). Con la clave pública, que viaja en la web, **cualquiera lee y
  modifica la lista de todos los eventos, DNI incluido**.
- `accesos` deja insertar a cualquiera (`Permitir inserción de accesos`, rol
  `public`, `with check true`).
- Los que leen como anónimos, no solo la web:
  - el **tótem de escritorio**: la ventana secundaria crea su propio
    `SupabaseClient` con la clave anónima y sin sesión (`main.dart`, rama
    `multi_window`);
  - el tótem web `?totem`;
  - `/lista` (`lista_invitados_screen.dart`): baja la lista entera y compara el
    DNI en el celular (`SupabaseInvitadosRepository.validarDniYMarcarIngreso`);
  - `?buscar` (`totem_checkin_screen.dart`): igual, en el celular;
  - `/op` (`op_checkin_screen.dart`): marca ingresos con un PIN que se compara
    en el cliente. Ningún evento lo usa.

## Qué hacer

1. Funciones `security definer` en Supabase, con `grant execute` a `anon`:
   - `puerta_buscar(evento, texto)`: desde 3 letras, devuelve nombre, mesa y si
     ya ingresó, sin DNI y sin la lista entera. Para `/lista` y `?buscar`.
   - `puerta_checkin(invitado, dni)`: compara el DNI en el servidor, lleva los
     intentos, marca el ingreso y anota en `accesos`.
   - `totem_invitados(evento, clave)`: la lista que necesita el tótem, sin DNI,
     solo con una clave del evento que **no** está en el QR de los invitados
     (va en la URL del tótem y en los argumentos de la ventana secundaria).
2. El tótem deja de escuchar la tabla (sin permiso de lectura, Realtime no le
   manda nada): se entera por el broadcast `totem_<eventoId>` que ya existe y
   relee con `totem_invitados` cada minuto. Todo lo nuevo se corta en
   `_pausar()`.
3. `/lista` pasa a buscar por nombre. `/op` se apaga o pasa a una función con el
   PIN comparado en el servidor (preguntar).
4. **El orden importa:**
   1. el SQL de las funciones, que no rompe nada;
   2. instalar la versión nueva en las dos PCs;
   3. desplegar la web;
   4. esa noche, cerrar los permisos: `drop policy` de las dos de `invitados` y
      de la de `accesos`, cada una con su `ROLLBACK` comentado arriba.

   Si se cierra antes, el tótem de la PC con la versión vieja queda ciego.
5. Verificar con un anónimo (`set local role anon` adentro de una transacción
   que se deshace): `select` sobre `invitados` devuelve cero filas y las
   funciones andan.
