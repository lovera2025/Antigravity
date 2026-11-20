-- 2026-11-20 — Una tabla nueva: la entrega de entradas en dos partes. Va con la
-- v81 de la base local (`entradas_entregas`).
--
-- Pedido del jefe (audio del 20-nov): las pulseras VIP con cena del egresado y
-- sus acompañantes, y las entradas generales que completan la mesa del
-- contrato, llegan en dos tandas. Cada una se entrega cuando llega el material,
-- con su botón y su ✓. Cada entrega (o anulación) de una parte es un renglón de
-- esta tabla: el alumno, la parte (`pulseras` o `generales`), qué se hizo
-- (`entrega` o `anulacion`), cuántas, los números de las generales si vienen
-- numeradas, quién retiró y quién lo anotó.
--
-- **Por qué una tabla aparte y no la fila de `entradas_retiro`.** La subida pisa
-- la fila entera en la nube (es un upsert sin comparar). Una tablet sin internet
-- que entregara las generales en esa fila borraría en la nube las pulseras que
-- dio otra PC. Acá cada parte es su propio renglón: dos equipos que entregan
-- partes distintas, con o sin internet, nunca se pisan.
--
-- `entradas_retiro` se sigue escribiendo como hasta ahora cuando la familia
-- tiene las dos partes (lo escribe el equipo que las ve completas): así una PC
-- con la 6.9.x, el plano y la planilla vieja la ven "Retiró".
--
-- **No toca ninguna tabla existente.** Solo `create table if not exists`, sus
-- índices, su RLS y sus disparadores de `updated_at`. Las versiones anteriores
-- no conocen esta tabla, así que se puede correr a cualquier hora antes de
-- instalar sin que las PCs ni las tablets lo noten. **Tiene que estar corrido
-- antes de instalar la versión que la usa**: si no, cada PC falla al bajar en
-- cada pasada y lo entregado queda trabado en la cola de subida.
--
-- **Nada se borra ni se edita.** Solo se agregan renglones: anular una parte es
-- otro renglón. El estado de cada parte es su último renglón.
--
-- Correrlo dos veces es inocuo: todo es `if not exists` / `drop ... if exists`.
-- **No se agrega nada a la publicación de Realtime.**
--
-- **Sin CHECK, sin clave foránea y sin índice único, a propósito.** El motor de
-- sync de la app toma cualquier "violates" como un padre que falta y la fila
-- queda trabada para siempre. Los valores de `parte` y `accion` los controla la
-- app (y un test compara este archivo con lo que manda). Las casillas van en
-- `integer` (0 y 1), como en la venta de entradas.
--
-- Cómo correrlo (SQL Editor, con el OK del usuario en el momento):
--   1. Correr la consulta "ANTES" de la sección 3 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 3 y comparar.

-- ── 1. entradas_entregas: cada entrega o anulación de una parte ─────────────
--
-- `tramos`: los números de las generales, con el mismo formato que
-- `entradas_retiro.tramos` ("1043-1058,1101-1108"). Vacío si no vienen
-- numeradas, y siempre vacío en las pulseras.
--
-- ROLLBACK: drop table if exists public.entradas_entregas;

create table if not exists public.entradas_entregas (
  id uuid primary key,
  contrato_alumno_id uuid not null,
  evento_id uuid,
  parte text not null,
  accion text not null,
  cantidad integer not null default 0,
  tramos text,
  menores_10 integer not null default 0,
  parentesco text,
  retiro_nombre text,
  otra_persona_motivo text,
  autorizacion_firmada integer not null default 0,
  escribio_en_planilla integer not null default 0,
  motivo text,
  hecho_por text,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_entradas_entregas_contrato
  on public.entradas_entregas(contrato_alumno_id);

create index if not exists idx_entradas_entregas_evento
  on public.entradas_entregas(evento_id);

create index if not exists idx_entradas_entregas_updated
  on public.entradas_entregas(updated_at desc);

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
--   drop policy if exists "entradas_entregas_all_authenticated" on public.entradas_entregas;
--   drop trigger if exists set_updated_at_ins_entradas_entregas on public.entradas_entregas;
--   drop trigger if exists set_updated_at_upd_entradas_entregas on public.entradas_entregas;
--   alter table public.entradas_entregas disable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'entradas_entregas'
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
-- cambia uno solo, algo tocó datos que no debía.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.sesiones_caja)             as sesiones,
--     (select count(*) from public.entradas_retiro)           as retiros,
--     (select count(*) from public.entradas_ventas)           as ventas,
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
--     and c.relname = 'entradas_entregas'
--   group by c.relname, c.relrowsecurity;
--
-- La policy (tiene que devolver una fila):
--
--   select tablename, policyname from pg_policies
--   where schemaname = 'public'
--     and tablename = 'entradas_entregas';
--
-- Que nace vacía (tiene que dar 0):
--
--   select count(*) from public.entradas_entregas;
--
-- Y que no entró a Realtime (tiene que devolver cero filas):
--
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime'
--     and tablename = 'entradas_entregas';
