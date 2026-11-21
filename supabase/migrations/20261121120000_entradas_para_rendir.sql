-- 2026-11-21 — Una tabla nueva: las entradas para rendir (consignación). Va con
-- la v82 de la base local (`entradas_para_rendir`).
--
-- Pedido del usuario (20-nov): "se le entrega a ciertas personas X cantidad de
-- entradas y ellos venden; después de esas entradas se sabe cuánto vendieron".
-- El jefe le da a alguien (un alumno de la fiesta o alguien de afuera) un bloque
-- numerado de entradas, al precio que rige ese día (la anticipada si todavía
-- vale, si no la general), que queda fijo. Esa persona las vende por su cuenta
-- y después rinde la plata de las que vendió y devuelve las que no. Lo decidido
-- está en `docs/SPEC_entradas_para_rendir_2026-11-20.md`.
--
-- Cada cosa que pasa con un bloque es un renglón de esta tabla, con el mismo
-- `bloque_id` (el id del renglón que lo dio):
--   - `dio`: el jefe dio el bloque: a quién, cuántas, los números, el precio y
--     su nombre ("Entrada anticipada" o el de la general);
--   - `vendio`: rindió la plata de algunas. **La plata no va acá**: es una venta
--     común de `entradas_ventas` (`venta_id` la nombra), así que el cierre de la
--     caja que cobró la cuenta sin saber nada de esto;
--   - `devolvio`: devolvió algunas sin vender, con sus números (quedan libres);
--   - `no_volvieron`: el jefe da por perdidas algunas, con motivo;
--   - `anulo`: el jefe anuló un bloque sin movimientos, un `devolvio` o un
--     `no_volvieron`, con motivo (`anula_id`). Tiene id fijo: dos equipos que
--     anulan lo mismo dejan una sola fila. Lo vendido se anula anulando su
--     venta, como cualquier venta.
-- Un `que` que esta versión no conoce lo anota una versión más nueva: la app lo
-- conserva y no lo cuenta.
--
-- **Lo que alguien debe de entradas para rendir no es deuda del contrato**: nada
-- de esto toca `contratos_alumnos`, `pagos_contrato_alumno` ni `sesiones_caja`.
-- `contrato_alumno_id` es solo para mostrar a qué alumno se le dieron.
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. Las versiones anteriores
-- no conocen esta tabla, así que se puede correr a cualquier hora antes de
-- instalar sin que las PCs ni las tablets lo noten (una 6.9.2 ve las
-- rendiciones como ventas y su cierre cuadra). **Tiene que estar corrido antes
-- de instalar la versión que la usa**, junto con el de `entradas_entregas`
-- (`20261120120000_entradas_entregas.sql`): si no, cada PC falla al bajar en
-- cada pasada, lo dado y lo rendido quedan trabados en la cola de subida y
-- "Lista para trabajar sin internet" no queda lista.
--
-- **Nada se borra ni se edita.** Solo se agregan renglones: anular es otro
-- renglón.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Los valores de `que` los controla la app, no este
-- archivo, y ningún test los compara. Lo que sí compara
-- `test/sync_tablas_v82_test.dart` contra la app: las mismas columnas, cada una
-- con su tipo, obligatoria en las dos o en ninguna, los mismos índices (ninguno
-- único) y los vínculos en null o con un id de verdad. Los vínculos
-- (`contrato_alumno_id`, `venta_id`, `caja_entradas_id`, `anula_id`) van vacíos
-- (null) cuando no hay, nunca con texto vacío. La plata va en `numeric` y la
-- casilla en `integer` (0 y 1), como en la venta de entradas.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. entradas_para_rendir: cada cosa que pasa con un bloque ───────────────
--
-- `numeros`: con el mismo formato que `entradas_retiro.tramos`
-- ("1201-1220,1301-1305"). En el `dio`, el bloque; en el `devolvio`, los que
-- volvieron; en el `no_volvieron`, si se saben. Un `anulo` no lleva: son los del
-- renglón que anula.
-- `precio` y `nombre_precio`: los del día en que se las llevó. Se rinde a ese
-- precio aunque venza la anticipada o el jefe cambie los precios.
-- `con_pulseras`: siempre 0 por ahora (la pulsera no se vende); queda la columna
-- porque después no se puede sumar.
--
-- ROLLBACK: drop table if exists public.entradas_para_rendir;

create table if not exists public.entradas_para_rendir (
  id uuid primary key,
  evento_id uuid not null,
  bloque_id uuid not null,
  que text not null,
  persona_nombre text,
  persona_contacto text,
  contrato_alumno_id uuid,
  cantidad integer not null default 0,
  numeros text,
  precio numeric,
  nombre_precio text,
  con_pulseras integer not null default 0,
  venta_id uuid,
  caja_entradas_id uuid,
  anula_id uuid,
  motivo text,
  nota text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_entradas_para_rendir_evento
  on public.entradas_para_rendir(evento_id);

create index if not exists idx_entradas_para_rendir_bloque
  on public.entradas_para_rendir(bloque_id);

create index if not exists idx_entradas_para_rendir_venta
  on public.entradas_para_rendir(venta_id);

create index if not exists idx_entradas_para_rendir_updated
  on public.entradas_para_rendir(updated_at desc);

-- ── 2. RLS y disparadores ───────────────────────────────────────────────────
--
-- RLS: igual que las de la venta de entradas, cualquier usuario logueado. Un
-- anónimo no ve nada.
--
-- Disparadores: los mismos de `20260908120000_updated_at_trigger.sql`. Sin ellos
-- un renglón nuevo no cruza nunca al otro equipo, porque el pull filtra por
-- `updated_at` y el motor no lo rellena.
--
-- ROLLBACK (lo borra solo el `drop table` de arriba). Si se deshace solo esta
-- sección y la tabla queda, van las cuatro líneas: sin la última, la tabla queda
-- con RLS prendida y sin policy, y la app no puede subir nada.
--   drop policy if exists "entradas_para_rendir_all_authenticated" on public.entradas_para_rendir;
--   drop trigger if exists set_updated_at_ins_entradas_para_rendir on public.entradas_para_rendir;
--   drop trigger if exists set_updated_at_upd_entradas_para_rendir on public.entradas_para_rendir;
--   alter table public.entradas_para_rendir disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'entradas_para_rendir'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);

    if not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = t
        and policyname = t || '_all_authenticated'
    ) then
      execute format(
        'create policy %I on public.%I for all '
        'using (auth.role() = ''authenticated'') '
        'with check (auth.role() = ''authenticated'')',
        t || '_all_authenticated', t);
    end if;

    execute format(
      'drop trigger if exists set_updated_at_ins_%1$I on public.%1$I', t);
    execute format(
      'create trigger set_updated_at_ins_%1$I before insert on public.%1$I '
      'for each row execute function public.update_updated_at_column()', t);

    execute format(
      'drop trigger if exists set_updated_at_upd_%1$I on public.%1$I', t);
    execute format(
      'create trigger set_updated_at_upd_%1$I before update on public.%1$I '
      'for each row execute function public.update_updated_at_column()', t);
  end loop;
end $$;

-- ── 3. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual. Si
-- cambia uno solo, algo tocó datos que no debía. (Sin `entradas_entregas`: si
-- este archivo se corre primero, esa tabla todavía no existe.)
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.sesiones_caja)             as sesiones,
--     (select count(*) from public.entradas_retiro)           as retiros,
--     (select count(*) from public.entradas_cajas)            as cajas,
--     (select count(*) from public.entradas_ventas)           as ventas,
--     (select count(*) from public.entradas_anulaciones)      as anulaciones,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: la tabla con RLS prendida, y exactamente un disparador de insert y
-- uno de update. Tiene que devolver una fila, con rls = true, trg_insert = 1 y
-- trg_update = 1:
--
--   select c.relname as tabla,
--          c.relrowsecurity as rls,
--          count(*) filter (where t.tgtype & 4  > 0) as trg_insert,
--          count(*) filter (where t.tgtype & 16 > 0) as trg_update
--   from pg_class c
--   left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
--   where c.relnamespace = 'public'::regnamespace
--     and c.relname = 'entradas_para_rendir'
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename = 'entradas_para_rendir';
--
-- Que nace vacía (tiene que dar 0):
--
--   select count(*) from public.entradas_para_rendir;
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename = 'entradas_para_rendir';
