-- 2026-10-16 — Cerrar la lista de la puerta a los anónimos. Va con la 6.0.0
-- (sección 8).
--
-- Saca los tres permisos que dejan a cualquiera con la clave pública de la web:
--   - leer `invitados` entera, de todos los eventos, DNI incluido;
--   - cambiar cualquier fila de `invitados`;
--   - anotar lo que quiera en `accesos`.
-- Los que no tienen usuario pasan a las funciones de
-- `20261016120000_puerta_funciones.sql`. Las PCs, la web con usuario y los
-- asesores siguen igual: tienen sus propios permisos, que esto no toca.
--
-- **VA ÚLTIMO AL PUBLICAR, y en este orden:**
--   1. `20261016120000_puerta_funciones.sql` (solo agrega);
--   2. la 6.0.0 instalada en **todas** las PCs;
--   3. la web nueva publicada;
--   4. recién ahí, este archivo.
-- Si se corre antes, el tótem de una PC con la versión vieja y la página del QR
-- vieja quedan sin nadie en la lista: leen la tabla directo.
--
-- Cómo correrlo (SQL Editor):
--   1. Correr la consulta "ANTES" de la sección 2 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 2 y comparar.
-- Para volver atrás: correr las tres líneas ROLLBACK de abajo (sin el "--").

-- ── 1. Los permisos ─────────────────────────────────────────────────────────
--
-- ROLLBACK: create policy lectura_publica_invitados on public.invitados for select to anon using (true);
drop policy if exists lectura_publica_invitados on public.invitados;

-- ROLLBACK: create policy actualizacion_publica_invitados on public.invitados for update to anon using (true) with check (true);
drop policy if exists actualizacion_publica_invitados on public.invitados;

-- ROLLBACK: create policy "Permitir inserción de accesos" on public.accesos for insert to public with check (true);
drop policy if exists "Permitir inserción de accesos" on public.accesos;

-- ── 2. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual.
-- Borrar un permiso no toca filas.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.notas_operativas_contrato) as notas,
--     (select count(*) from public.invitados)                 as invitados,
--     (select count(*) from public.accesos)                   as accesos,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: a `invitados` y `accesos` no les queda ningún permiso para anónimos
-- (tiene que devolver cero filas):
--
--   select tablename, policyname, roles::text, cmd from pg_policies
--   where schemaname = 'public' and tablename in ('invitados', 'accesos')
--     and (roles::text like '%anon%' or roles::text like '%public%')
--     and cmd <> 'SELECT';
--   -- ("Permitir lectura de accesos" es de `public` pero pide usuario: queda.)
--
-- Y la prueba como anónimo, adentro de una transacción que se deshace. Tiene que
-- dar 0 filas, y la función del tótem tiene que seguir contestando (con una
-- clave mala, un error "La clave del tótem no es la de este evento"):
--
--   begin;
--   set local role anon;
--   select count(*) from public.invitados;                          -- 0
--   update public.invitados set numero_mesa = numero_mesa;          -- UPDATE 0
--   select public.puerta_buscar(
--     (select id from public.eventos limit 1), 'abc');              -- anda
--   rollback;
