# Cerrar la lista de la puerta a los anónimos

**Estado:** pendiente
**Postergado el:** 2026-09-25

## Por qué se postergó

Cerrar los permisos cambia cómo lee el tótem, y el tótem se rehace en diciembre
([totem-comunicacion.md](totem-comunicacion.md), [totem-apariencias.md](totem-apariencias.md)).
Hacerlo antes era tocar el tótem dos veces, y es la única pieza que rompe la
versión anterior: con los permisos cerrados, el tótem de una PC con la versión
vieja queda en blanco. El usuario eligió dejarlo para diciembre, junto con el
tótem, el 25-sep.

**Regla hasta que esté: no pasar la lista de la puerta de ninguna fiesta de
egresados** (⋮ → "Pasar a la lista de la puerta"). Hoy la tabla tiene 7 filas
de prueba; con la lista pasada serían los alumnos de toda la institución.

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
