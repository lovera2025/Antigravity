-- 2026-11-13 — El link del delegado: acompañantes y música desde el celular, además
-- del Excel. Va con la 6.8.0.
--
-- **Solo agrega: tres tablas nuevas y funciones.** No toca ninguna fila ni ningún
-- permiso de lo que ya existe. Las tablas no son de la base de las PCs: no se
-- sincronizan. Nadie las lee ni las escribe directo: solo las funciones de abajo.
--
--   links_delegado      un link por evento masivo: la clave, el límite, el cupo.
--   celulares_delegado  cada celular que entró: quién dijo ser, si envió, si lo sacaron.
--   cargas_delegado     lo que cargó cada uno, por alumno. Una fila por alumno.
--
-- Sin usuario (la página del delegado):
--   delegado_lista     con la clave y la sesión: la fiesta y sus alumnos activos.
--   delegado_entrar    con la clave y un nombre: da la sesión de ese celular.
--   delegado_guardar   guarda un alumno. Acá viven las trabas.
--   delegado_entregar  el envío, una sola vez por celular.
-- Con usuario (el programa):
--   delegado_link_crear · delegado_link · delegado_link_cambiar · delegado_cargas ·
--   delegado_pendientes
--
-- Correrlo dos veces es inocuo: `if not exists` y `create or replace`. Sin CHECK,
-- sin nada en la publicación de Realtime y sin extensiones.
--
-- **Hay que correrlo antes de instalar la 6.8.0**: sin las funciones, la sección del
-- link dice que no se pudo y el Excel sigue andando igual. Una versión anterior no las
-- conoce.
--
-- Las reglas están probadas contra este mismo archivo, en un Postgres de prueba:
-- `tool/delegado_sandbox/pruebas.mjs`.
--
-- Cómo correrlo (SQL Editor):
--   1. Correr la consulta "ANTES" de la sección 6 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 6 y comparar.

-- ── 1. Las tablas ───────────────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.cargas_delegado;
--           drop table if exists public.celulares_delegado;
--           drop table if exists public.links_delegado;
create table if not exists public.links_delegado (
  evento_id  uuid primary key references public.eventos(id) on delete cascade,
  clave      text not null unique
               default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  -- El nombre de la fiesta como lo muestra el programa. Lo manda el programa al crear
  -- el link: así las funciones no dependen de ninguna columna de `eventos`.
  fiesta     text not null,
  vence_at   timestamptz not null,
  cupo       integer not null default 1,
  apagado    boolean not null default false,
  traido_at  timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.celulares_delegado (
  id           uuid primary key default gen_random_uuid(),
  evento_id    uuid not null references public.links_delegado(evento_id) on delete cascade,
  sesion_hash  text not null unique,
  nombre       text not null,
  entro_at     timestamptz not null default now(),
  entregado_at timestamptz,
  sacado_at    timestamptz
);

create table if not exists public.cargas_delegado (
  evento_id    uuid not null references public.links_delegado(evento_id) on delete cascade,
  alumno_id    uuid not null,
  -- Null: lo cargó alguien a quien después se sacó dejando lo cargado. Queda libre.
  celular_id   uuid references public.celulares_delegado(id) on delete set null,
  acompanantes jsonb not null default '[]'::jsonb,
  musica       text not null default '',
  updated_at   timestamptz not null default now(),
  -- Cuándo el jefe lo trajo a la grilla. Null: todavía no se trajo.
  traido_at    timestamptz,
  primary key (evento_id, alumno_id)
);

-- Sin políticas: nadie las lee ni las escribe directo.
alter table public.links_delegado     enable row level security;
alter table public.celulares_delegado enable row level security;
alter table public.cargas_delegado    enable row level security;
revoke all on table public.links_delegado     from anon, authenticated;
revoke all on table public.celulares_delegado from anon, authenticated;
revoke all on table public.cargas_delegado    from anon, authenticated;

-- ── 2. Lo de adentro ────────────────────────────────────────────────────────

-- El reloj de la nube. Todo límite se decide con este, nunca con el del celular.
-- ROLLBACK: drop function if exists public.delegado_ahora();
create or replace function public.delegado_ahora()
returns timestamptz
language sql
stable
set search_path = public
as $$ select now() $$;

-- Para ordenar: sin acentos ni mayúsculas.
-- ROLLBACK: drop function if exists public.delegado_llave(text);
create or replace function public.delegado_llave(p_texto text)
returns text
language sql
immutable
set search_path = public
as $$
  select lower(translate(
    coalesce(p_texto, ''),
    'ÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇáàäâãéèëêíìïîóòöôõúùüûñç',
    'AAAAAEEEEIIIIOOOOOUUUUNCaaaaaeeeeiiiiooooouuuunc'
  ));
$$;

-- ROLLBACK: drop function if exists public.delegado_un_espacio(text);
create or replace function public.delegado_un_espacio(p_texto text)
returns text
language sql
immutable
set search_path = public
as $$ select btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')) $$;

-- Los nombres con algo escrito, sin espacios de más, en su orden.
-- ROLLBACK: drop function if exists public.delegado_nombres(jsonb);
create or replace function public.delegado_nombres(p_lista jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_agg(s.n order by s.ord), '[]'::jsonb)
  from (
    select public.delegado_un_espacio(t.e) as n, t.ord
    from jsonb_array_elements_text(
      case when jsonb_typeof(p_lista) = 'array' then p_lista else '[]'::jsonb end
    ) with ordinality as t(e, ord)
  ) s
  where s.n <> '';
$$;

-- "jueves 19/11 a las 20:00", siempre en hora de Argentina.
-- ROLLBACK: drop function if exists public.delegado_texto_fecha(timestamptz);
create or replace function public.delegado_texto_fecha(p_momento timestamptz)
returns text
language sql
stable
set search_path = public
as $$
  select (array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])
           [extract(isodow from (p_momento at time zone 'America/Argentina/Buenos_Aires'))::int]
         || ' ' || to_char(p_momento at time zone 'America/Argentina/Buenos_Aires', 'DD/MM')
         || ' a las ' || to_char(p_momento at time zone 'America/Argentina/Buenos_Aires', 'HH24:MI');
$$;

-- "2026-11-19 20:00" (hora de Argentina) → el momento. Null si no es una fecha.
-- ROLLBACK: drop function if exists public.delegado_vence(text);
create or replace function public.delegado_vence(p_local text)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
begin
  if p_local is null or p_local !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$' then
    return null;
  end if;
  return (p_local::timestamp) at time zone 'America/Argentina/Buenos_Aires';
exception when others then
  return null;
end;
$$;

-- Los alumnos de la fiesta que van al link: los activos (sin los de baja temporal
-- ni los sin nombre), con qué tiene ya cargado cada uno en el programa.
-- ROLLBACK: drop function if exists public.delegado_alumnos(uuid);
create or replace function public.delegado_alumnos(p_evento uuid)
returns table (id uuid, nombre text, division text, prog_acomp boolean, prog_musica boolean)
language sql
stable
security definer
set search_path = public
as $$
  select c.id,
         public.delegado_un_espacio(c.nombre_alumno),
         public.delegado_un_espacio(c.curso_division),
         jsonb_array_length(public.delegado_nombres(to_jsonb(c.nombres_acompanantes))) > 0,
         btrim(coalesce(c.musica_elegida, '')) <> ''
  from public.contratos_alumnos c
  where c.evento_id = p_evento
    and btrim(c.nombre_alumno) <> ''
    and btrim(c.nombre_alumno) not like '[BAJA]%';
$$;

-- El aviso para el programa. Null si no hay nada que avisar.
-- Salta cuando alguien envió después de la última vez que se trajo, o cuando el
-- link venció y alguien que no envió dejó algo cargado que todavía no se trajo.
-- Nunca por un guardado suelto.
-- ROLLBACK: drop function if exists public.delegado_aviso(uuid);
create or replace function public.delegado_aviso(p_evento uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_link     public.links_delegado%rowtype;
  v_fiesta   text;
  v_desde    timestamptz;
  v_vencido  boolean;
  v_enviaron text;
  v_no       text;
  v_faltan   integer;
  v_nuevo    boolean;
begin
  select * into v_link from public.links_delegado l where l.evento_id = p_evento;
  if not found then return null; end if;
  v_desde   := coalesce(v_link.traido_at, '-infinity'::timestamptz);
  v_vencido := public.delegado_ahora() >= v_link.vence_at;

  select string_agg(c.nombre || ' (' || n.cuantos || ')', ', ' order by c.entregado_at)
    into v_enviaron
  from public.celulares_delegado c
  join lateral (
    select count(*) as cuantos from public.cargas_delegado g where g.celular_id = c.id
  ) n on true
  where c.evento_id = p_evento and c.entregado_at is not null and c.entregado_at > v_desde;

  select string_agg(c.nombre || ' (cargó ' || n.cuantos || ')', ', ' order by c.entro_at)
    into v_no
  from public.celulares_delegado c
  join lateral (
    select count(*) as cuantos
    from public.cargas_delegado g where g.celular_id = c.id and g.traido_at is null
  ) n on true
  where c.evento_id = p_evento and c.entregado_at is null and c.sacado_at is null
    and n.cuantos > 0;

  v_nuevo := v_enviaron is not null or (v_vencido and v_no is not null);
  if not v_nuevo then return null; end if;

  v_fiesta := v_link.fiesta;
  select count(*) into v_faltan
  from public.delegado_alumnos(p_evento) a
  left join public.cargas_delegado g on g.evento_id = p_evento and g.alumno_id = a.id
  where not (a.prog_acomp and a.prog_musica) and g.alumno_id is null;

  return 'Acompañantes y música para traer: ' || v_fiesta
      || case when v_enviaron is not null then ' · envió ' || v_enviaron else '' end
      || case when v_vencido and v_no is not null then ' · venció sin enviar: ' || v_no else '' end
      || case when v_faltan = 0 then ' · no falta nadie'
              when v_faltan = 1 then ' · falta 1 alumno'
              else ' · faltan ' || v_faltan || ' alumnos' end;
end;
$$;

-- ── 3. La página del delegado (sin usuario) ─────────────────────────────────

-- La fiesta y sus alumnos. Sin una sesión de este link no da ningún nombre de
-- alumno: solo de qué fiesta es, para la pantalla de entrada.
-- ROLLBACK: drop function if exists public.delegado_lista(text, text);
create or replace function public.delegado_lista(p_clave text, p_sesion text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_link     public.links_delegado%rowtype;
  v_cel      public.celulares_delegado%rowtype;
  v_ahora    timestamptz := public.delegado_ahora();
  v_base     jsonb;
  v_activos  integer;
  v_alumnos  jsonb;
  v_total    integer;
  v_cargados integer;
  v_mios     integer;
begin
  select * into v_link from public.links_delegado l where l.clave = p_clave;
  if p_clave is null or not found then
    return jsonb_build_object('ok', false, 'motivo', 'link');
  end if;

  v_base := jsonb_build_object(
    'fiesta',      v_link.fiesta,
    'vence_texto', public.delegado_texto_fecha(v_link.vence_at),
    'vencido',     v_ahora >= v_link.vence_at
  );
  if v_link.apagado then
    return v_base || jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;

  select * into v_cel from public.celulares_delegado c
  where c.evento_id = v_link.evento_id
    and p_sesion is not null
    and c.sesion_hash = encode(sha256(convert_to(p_sesion, 'UTF8')), 'hex');
  if not found then
    select count(*) into v_activos from public.celulares_delegado c
    where c.evento_id = v_link.evento_id and c.sacado_at is null;
    return v_base || jsonb_build_object(
      'ok', false, 'motivo', 'entrar', 'lleno', v_activos >= v_link.cupo);
  end if;
  if v_cel.sacado_at is not null then
    return v_base || jsonb_build_object('ok', false, 'motivo', 'sacado');
  end if;

  select coalesce(jsonb_agg(x.j order by x.sin_div, x.k_div, x.k_nom), '[]'::jsonb),
         count(*),
         count(*) filter (where x.cargado),
         count(*) filter (where x.mio)
    into v_alumnos, v_total, v_cargados, v_mios
  from (
    select
      (a.division = '')                 as sin_div,
      public.delegado_llave(a.division) as k_div,
      public.delegado_llave(a.nombre)   as k_nom,
      ((a.prog_acomp and a.prog_musica) or g.alumno_id is not null) as cargado,
      (not (a.prog_acomp and a.prog_musica) and g.celular_id = v_cel.id) as mio,
      jsonb_build_object(
        'id',          a.id,
        'nombre',      a.nombre,
        'division',    a.division,
        'prog_acomp',  a.prog_acomp,
        'prog_musica', a.prog_musica,
        'de', case
                when a.prog_acomp and a.prog_musica then 'programa'
                when g.alumno_id is null            then 'libre'
                when g.celular_id is null           then 'suelto'
                when g.celular_id = v_cel.id        then 'mio'
                else 'otro'
              end,
        'cargo', case when g.celular_id is not null and g.celular_id <> v_cel.id
                      then o.nombre end,
        -- Lo cargado se le muestra solo a quien lo cargó, o a cualquiera si quedó suelto.
        'acompanantes', case when g.alumno_id is not null
                              and (g.celular_id is null or g.celular_id = v_cel.id)
                             then g.acompanantes end,
        'musica',       case when g.alumno_id is not null
                              and (g.celular_id is null or g.celular_id = v_cel.id)
                             then g.musica end
      ) as j
    from public.delegado_alumnos(v_link.evento_id) a
    left join public.cargas_delegado g
           on g.evento_id = v_link.evento_id and g.alumno_id = a.id
    left join public.celulares_delegado o on o.id = g.celular_id
  ) x;

  return v_base || jsonb_build_object(
    'ok',       true,
    'yo',       jsonb_build_object('nombre', v_cel.nombre, 'entregado', v_cel.entregado_at is not null),
    'total',    v_total,
    'cargados', v_cargados,
    'faltan',   v_total - v_cargados,
    'mios',     v_mios,
    'alumnos',  v_alumnos
  );
end;
$$;

-- Entrar: un celular más para este link, mientras haya lugar.
-- ROLLBACK: drop function if exists public.delegado_entrar(text, text);
create or replace function public.delegado_entrar(p_clave text, p_nombre text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link    public.links_delegado%rowtype;
  v_ahora   timestamptz := public.delegado_ahora();
  v_nombre  text := upper(public.delegado_un_espacio(p_nombre));
  v_activos integer;
  v_sesion  text;
begin
  -- La fila del link se toma para escribir: todo lo de un link va de a uno.
  select * into v_link from public.links_delegado l where l.clave = p_clave for update;
  if p_clave is null or not found then
    return jsonb_build_object('ok', false, 'motivo', 'link');
  end if;
  if v_link.apagado then
    return jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;
  if v_ahora >= v_link.vence_at then
    return jsonb_build_object('ok', false, 'motivo', 'vencido');
  end if;
  if char_length(v_nombre) < 5 or char_length(v_nombre) > 60
     or v_nombre !~ '[A-ZÁÉÍÓÚÜÑ]{2}' or position(' ' in v_nombre) = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'nombre');
  end if;
  select count(*) into v_activos from public.celulares_delegado c
  where c.evento_id = v_link.evento_id and c.sacado_at is null;
  if v_activos >= v_link.cupo then
    return jsonb_build_object('ok', false, 'motivo', 'lleno');
  end if;

  v_sesion := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.celulares_delegado (evento_id, sesion_hash, nombre, entro_at)
  values (v_link.evento_id, encode(sha256(convert_to(v_sesion, 'UTF8')), 'hex'), v_nombre, v_ahora);
  return jsonb_build_object('ok', true, 'sesion', v_sesion);
end;
$$;

-- Guardar un alumno. Las trabas, en orden:
--   el link (existe, prendido, a tiempo) · el celular (de este link, sin sacar, sin
--   haber enviado) · el alumno (activo y de esta fiesta) · lo ya cargado en el
--   programa no se toca · hasta 2 acompañantes de hasta 80 letras · música de hasta
--   300 · lo que cargó otro no se pisa.
-- Vaciar los dos casilleros de un alumno propio lo deja libre.
-- ROLLBACK: drop function if exists public.delegado_guardar(text, text, uuid, jsonb, text);
create or replace function public.delegado_guardar(
  p_clave text, p_sesion text, p_alumno uuid, p_acompanantes jsonb, p_musica text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link    public.links_delegado%rowtype;
  v_cel     public.celulares_delegado%rowtype;
  v_carga   public.cargas_delegado%rowtype;
  v_hay     boolean;
  v_ahora   timestamptz := public.delegado_ahora();
  v_al      record;
  v_nombres jsonb;
  v_musica  text;
begin
  select * into v_link from public.links_delegado l where l.clave = p_clave for update;
  if p_clave is null or not found then
    return jsonb_build_object('ok', false, 'motivo', 'link');
  end if;
  if v_link.apagado then
    return jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;
  if v_ahora >= v_link.vence_at then
    return jsonb_build_object('ok', false, 'motivo', 'vencido');
  end if;

  select * into v_cel from public.celulares_delegado c
  where c.evento_id = v_link.evento_id
    and p_sesion is not null
    and c.sesion_hash = encode(sha256(convert_to(p_sesion, 'UTF8')), 'hex');
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sesion');
  end if;
  if v_cel.sacado_at is not null then
    return jsonb_build_object('ok', false, 'motivo', 'sacado');
  end if;
  if v_cel.entregado_at is not null then
    return jsonb_build_object('ok', false, 'motivo', 'entregado');
  end if;

  select * into v_al from public.delegado_alumnos(v_link.evento_id) a where a.id = p_alumno;
  if p_alumno is null or not found then
    return jsonb_build_object('ok', false, 'motivo', 'alumno');
  end if;
  if v_al.prog_acomp and v_al.prog_musica then
    return jsonb_build_object('ok', false, 'motivo', 'ya_cargado');
  end if;

  if p_acompanantes is not null and jsonb_typeof(p_acompanantes) <> 'array' then
    return jsonb_build_object('ok', false, 'motivo', 'formato');
  end if;
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_acompanantes, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'string'
  ) then
    return jsonb_build_object('ok', false, 'motivo', 'formato');
  end if;
  v_nombres := public.delegado_nombres(coalesce(p_acompanantes, '[]'::jsonb));
  if jsonb_array_length(v_nombres) > 2 then
    return jsonb_build_object('ok', false, 'motivo', 'tope');
  end if;
  if exists (select 1 from jsonb_array_elements_text(v_nombres) e where char_length(e) > 80) then
    return jsonb_build_object('ok', false, 'motivo', 'largo', 'campo', 'acompanantes');
  end if;
  -- En un solo renglón, como la música que entra por el Excel.
  v_musica := public.delegado_un_espacio(p_musica);
  if char_length(v_musica) > 300 then
    return jsonb_build_object('ok', false, 'motivo', 'largo', 'campo', 'musica');
  end if;

  if v_al.prog_acomp and jsonb_array_length(v_nombres) > 0 then
    return jsonb_build_object('ok', false, 'motivo', 'ya_cargado', 'campo', 'acompanantes');
  end if;
  if v_al.prog_musica and v_musica <> '' then
    return jsonb_build_object('ok', false, 'motivo', 'ya_cargado', 'campo', 'musica');
  end if;

  select * into v_carga from public.cargas_delegado g
  where g.evento_id = v_link.evento_id and g.alumno_id = p_alumno;
  v_hay := found;
  if v_hay and v_carga.celular_id is not null and v_carga.celular_id <> v_cel.id then
    return jsonb_build_object(
      'ok', false, 'motivo', 'otro',
      'cargo', (select c.nombre from public.celulares_delegado c where c.id = v_carga.celular_id));
  end if;

  if jsonb_array_length(v_nombres) = 0 and v_musica = '' then
    if v_hay then
      delete from public.cargas_delegado g
      where g.evento_id = v_link.evento_id and g.alumno_id = p_alumno;
      return jsonb_build_object('ok', true, 'libre', true);
    end if;
    return jsonb_build_object('ok', false, 'motivo', 'vacio');
  end if;

  insert into public.cargas_delegado (evento_id, alumno_id, celular_id, acompanantes, musica, updated_at)
  values (v_link.evento_id, p_alumno, v_cel.id, v_nombres, v_musica, v_ahora)
  on conflict (evento_id, alumno_id) do update
    set celular_id   = excluded.celular_id,
        acompanantes = excluded.acompanantes,
        musica       = excluded.musica,
        updated_at   = excluded.updated_at,
        traido_at    = null;
  return jsonb_build_object('ok', true);
end;
$$;

-- El envío: una sola vez por celular. La segunda no cambia nada.
-- ROLLBACK: drop function if exists public.delegado_entregar(text, text);
create or replace function public.delegado_entregar(p_clave text, p_sesion text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link  public.links_delegado%rowtype;
  v_cel   public.celulares_delegado%rowtype;
  v_ahora timestamptz := public.delegado_ahora();
begin
  select * into v_link from public.links_delegado l where l.clave = p_clave for update;
  if p_clave is null or not found then
    return jsonb_build_object('ok', false, 'motivo', 'link');
  end if;
  if v_link.apagado then
    return jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;
  if v_ahora >= v_link.vence_at then
    return jsonb_build_object('ok', false, 'motivo', 'vencido');
  end if;

  select * into v_cel from public.celulares_delegado c
  where c.evento_id = v_link.evento_id
    and p_sesion is not null
    and c.sesion_hash = encode(sha256(convert_to(p_sesion, 'UTF8')), 'hex');
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sesion');
  end if;
  if v_cel.sacado_at is not null then
    return jsonb_build_object('ok', false, 'motivo', 'sacado');
  end if;
  if v_cel.entregado_at is not null then
    return jsonb_build_object('ok', true, 'ya', true);
  end if;
  if not exists (select 1 from public.cargas_delegado g where g.celular_id = v_cel.id) then
    return jsonb_build_object('ok', false, 'motivo', 'nada');
  end if;

  update public.celulares_delegado set entregado_at = v_ahora where id = v_cel.id;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── 4. El programa (solo con usuario) ───────────────────────────────────────

-- ROLLBACK: drop function if exists public.delegado_link_crear(uuid, text, text, integer);
create or replace function public.delegado_link_crear(
  p_evento uuid, p_fiesta text, p_vence_local text, p_cupo integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vence  timestamptz := public.delegado_vence(p_vence_local);
  v_fiesta text := public.delegado_un_espacio(p_fiesta);
  v_clave  text;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'El link del delegado se maneja con usuario' using errcode = '42501';
  end if;
  if not exists (select 1 from public.eventos e where e.id = p_evento) then
    return jsonb_build_object('ok', false, 'motivo', 'evento');
  end if;
  if v_fiesta = '' or char_length(v_fiesta) > 120 then
    return jsonb_build_object('ok', false, 'motivo', 'fiesta');
  end if;
  if v_vence is null then
    return jsonb_build_object('ok', false, 'motivo', 'fecha');
  end if;
  if v_vence <= public.delegado_ahora() then
    return jsonb_build_object('ok', false, 'motivo', 'pasada');
  end if;
  if p_cupo is null or p_cupo < 1 or p_cupo > 5 then
    return jsonb_build_object('ok', false, 'motivo', 'cupo');
  end if;
  if exists (select 1 from public.links_delegado l where l.evento_id = p_evento) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_existe');
  end if;

  insert into public.links_delegado (evento_id, fiesta, vence_at, cupo)
  values (p_evento, v_fiesta, v_vence, p_cupo)
  returning clave into v_clave;
  return jsonb_build_object(
    'ok', true, 'clave', v_clave, 'vence_texto', public.delegado_texto_fecha(v_vence));
end;
$$;

-- Cómo está el link: el límite, los celulares, cuánto hay cargado y el aviso.
-- ROLLBACK: drop function if exists public.delegado_link(uuid);
create or replace function public.delegado_link(p_evento uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_link      public.links_delegado%rowtype;
  v_ahora     timestamptz := public.delegado_ahora();
  v_celulares jsonb;
  v_total     integer;
  v_programa  integer;
  v_cargados  integer;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'El link del delegado se maneja con usuario' using errcode = '42501';
  end if;
  select * into v_link from public.links_delegado l where l.evento_id = p_evento;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sin_link');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',              c.id,
           'nombre',          c.nombre,
           'entro_texto',     public.delegado_texto_fecha(c.entro_at),
           'cargados',        (select count(*) from public.cargas_delegado g where g.celular_id = c.id),
           'entregado',       c.entregado_at is not null,
           'entregado_texto', case when c.entregado_at is not null
                                   then public.delegado_texto_fecha(c.entregado_at) end,
           'sacado',          c.sacado_at is not null
         ) order by c.entro_at, c.nombre), '[]'::jsonb)
    into v_celulares
  from public.celulares_delegado c where c.evento_id = p_evento;

  select count(*),
         count(*) filter (where a.prog_acomp and a.prog_musica),
         count(*) filter (where not (a.prog_acomp and a.prog_musica) and g.alumno_id is not null)
    into v_total, v_programa, v_cargados
  from public.delegado_alumnos(p_evento) a
  left join public.cargas_delegado g on g.evento_id = p_evento and g.alumno_id = a.id;

  return jsonb_build_object(
    'ok',          true,
    'clave',       v_link.clave,
    'vence_texto', public.delegado_texto_fecha(v_link.vence_at),
    'vence_local', to_char(v_link.vence_at at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI'),
    'estado',      case when v_link.apagado then 'apagado'
                        when v_ahora >= v_link.vence_at then 'vencido'
                        else 'abierto' end,
    'cupo',        v_link.cupo,
    'celulares',   v_celulares,
    'total',       v_total,
    'en_programa', v_programa,
    'cargados',    v_cargados,
    'faltan',      v_total - v_programa - v_cargados,
    'aviso',       public.delegado_aviso(p_evento)
  );
end;
$$;

-- Lo que cambia el jefe: apagar, prender, el límite, el cupo, sacar un celular
-- (dejando o borrando lo que cargó), reabrirle el envío, y anotar qué trajo.
-- ROLLBACK: drop function if exists public.delegado_link_cambiar(uuid, text, text);
create or replace function public.delegado_link_cambiar(p_evento uuid, p_accion text, p_valor text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link  public.links_delegado%rowtype;
  v_ahora timestamptz := public.delegado_ahora();
  v_vence timestamptz;
  v_cupo  integer;
  v_cel   uuid;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'El link del delegado se maneja con usuario' using errcode = '42501';
  end if;
  select * into v_link from public.links_delegado l where l.evento_id = p_evento for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sin_link');
  end if;

  if p_accion in ('sacar_dejando', 'sacar_borrando', 'reabrir') then
    if p_valor is null or p_valor !~ '^[0-9a-fA-F-]{36}$' then
      return jsonb_build_object('ok', false, 'motivo', 'celular');
    end if;
    select c.id into v_cel from public.celulares_delegado c
    where c.id = p_valor::uuid and c.evento_id = p_evento;
    if not found then
      return jsonb_build_object('ok', false, 'motivo', 'celular');
    end if;
  end if;

  if p_accion = 'apagar' then
    update public.links_delegado set apagado = true where evento_id = p_evento;
  elsif p_accion = 'prender' then
    update public.links_delegado set apagado = false where evento_id = p_evento;
  elsif p_accion = 'vence' then
    v_vence := public.delegado_vence(p_valor);
    if v_vence is null then
      return jsonb_build_object('ok', false, 'motivo', 'fecha');
    end if;
    update public.links_delegado set vence_at = v_vence where evento_id = p_evento;
  elsif p_accion = 'cupo' then
    if p_valor is null or p_valor !~ '^[1-5]$' then
      return jsonb_build_object('ok', false, 'motivo', 'cupo');
    end if;
    v_cupo := p_valor::integer;
    update public.links_delegado set cupo = v_cupo where evento_id = p_evento;
  elsif p_accion = 'sacar_dejando' then
    update public.celulares_delegado set sacado_at = v_ahora where id = v_cel;
    update public.cargas_delegado set celular_id = null where celular_id = v_cel;
  elsif p_accion = 'sacar_borrando' then
    update public.celulares_delegado set sacado_at = v_ahora where id = v_cel;
    delete from public.cargas_delegado where celular_id = v_cel;
  elsif p_accion = 'reabrir' then
    update public.celulares_delegado set entregado_at = null
    where id = v_cel and sacado_at is null;
  elsif p_accion = 'traido' then
    -- p_valor: los alumnos que se trajeron a la grilla, como lista JSON de ids.
    if p_valor is not null then
      begin
        update public.cargas_delegado g set traido_at = v_ahora
        where g.evento_id = p_evento
          and g.alumno_id in (select e::uuid from jsonb_array_elements_text(p_valor::jsonb) e);
      exception when others then
        return jsonb_build_object('ok', false, 'motivo', 'alumnos');
      end;
    end if;
    update public.links_delegado set traido_at = v_ahora where evento_id = p_evento;
  else
    return jsonb_build_object('ok', false, 'motivo', 'accion');
  end if;

  update public.links_delegado set updated_at = v_ahora where evento_id = p_evento;
  return jsonb_build_object('ok', true);
end;
$$;

-- Lo cargado, para traer: un renglón por alumno, con quién lo cargó, si lo envió
-- y si el alumno sigue activo en la fiesta.
-- ROLLBACK: drop function if exists public.delegado_cargas(uuid);
create or replace function public.delegado_cargas(p_evento uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'El link del delegado se maneja con usuario' using errcode = '42501';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'alumno_id',    g.alumno_id,
             'alumno',       coalesce(a.nombre, public.delegado_un_espacio(k.nombre_alumno)),
             'division',     coalesce(a.division, public.delegado_un_espacio(k.curso_division)),
             'activo',       a.id is not null,
             'acompanantes', g.acompanantes,
             'musica',       g.musica,
             'cargo',        c.nombre,
             'entregado',    c.entregado_at is not null,
             'suelto',       g.celular_id is null
           ) order by (coalesce(a.division, '') = ''),
                      public.delegado_llave(coalesce(a.division, k.curso_division)),
                      public.delegado_llave(coalesce(a.nombre, k.nombre_alumno))),
           '[]'::jsonb)
    from public.cargas_delegado g
    left join public.delegado_alumnos(p_evento) a on a.id = g.alumno_id
    left join public.contratos_alumnos k on k.id = g.alumno_id
    left join public.celulares_delegado c on c.id = g.celular_id
    where g.evento_id = p_evento
  );
end;
$$;

-- Los avisos para el inicio del programa: uno por fiesta, nunca más.
-- ROLLBACK: drop function if exists public.delegado_pendientes();
create or replace function public.delegado_pendientes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'El link del delegado se maneja con usuario' using errcode = '42501';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('evento_id', s.evento_id, 'texto', s.texto)
                              order by s.texto), '[]'::jsonb)
    from (
      select l.evento_id, public.delegado_aviso(l.evento_id) as texto
      from public.links_delegado l
    ) s
    where s.texto is not null
  );
end;
$$;

-- ── 5. Quién puede llamar a qué ─────────────────────────────────────────────

-- Lo de adentro: nadie de afuera.
revoke all on function public.delegado_ahora()                 from public, anon, authenticated;
revoke all on function public.delegado_llave(text)             from public, anon, authenticated;
revoke all on function public.delegado_un_espacio(text)        from public, anon, authenticated;
revoke all on function public.delegado_nombres(jsonb)          from public, anon, authenticated;
revoke all on function public.delegado_texto_fecha(timestamptz) from public, anon, authenticated;
revoke all on function public.delegado_vence(text)             from public, anon, authenticated;
revoke all on function public.delegado_alumnos(uuid)           from public, anon, authenticated;
revoke all on function public.delegado_aviso(uuid)             from public, anon, authenticated;

-- La página del delegado.
revoke all on function public.delegado_lista(text, text)                       from public;
revoke all on function public.delegado_entrar(text, text)                      from public;
revoke all on function public.delegado_guardar(text, text, uuid, jsonb, text)  from public;
revoke all on function public.delegado_entregar(text, text)                    from public;
grant execute on function public.delegado_lista(text, text)                      to anon, authenticated;
grant execute on function public.delegado_entrar(text, text)                     to anon, authenticated;
grant execute on function public.delegado_guardar(text, text, uuid, jsonb, text) to anon, authenticated;
grant execute on function public.delegado_entregar(text, text)                   to anon, authenticated;

-- El programa.
revoke all on function public.delegado_link_crear(uuid, text, text, integer) from public, anon;
revoke all on function public.delegado_link(uuid)                        from public, anon;
revoke all on function public.delegado_link_cambiar(uuid, text, text)    from public, anon;
revoke all on function public.delegado_cargas(uuid)                      from public, anon;
revoke all on function public.delegado_pendientes()                      from public, anon;
grant execute on function public.delegado_link_crear(uuid, text, text, integer) to authenticated;
grant execute on function public.delegado_link(uuid)                      to authenticated;
grant execute on function public.delegado_link_cambiar(uuid, text, text)  to authenticated;
grant execute on function public.delegado_cargas(uuid)                    to authenticated;
grant execute on function public.delegado_pendientes()                    to authenticated;

-- ── 6. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS: tienen que dar igual. Este archivo no toca ninguna de las dos.
--   select (select count(*) from public.contratos_alumnos) as alumnos,
--          (select count(*) from public.eventos)           as eventos;
--
-- DESPUÉS: las tres tablas, vacías, y las trece funciones.
--   select (select count(*) from public.links_delegado)     as links,
--          (select count(*) from public.celulares_delegado) as celulares,
--          (select count(*) from public.cargas_delegado)    as cargas;
--   select count(*) as funciones from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname like 'delegado\_%';
--
-- DESPUÉS: un anónimo no lee las tablas (tiene que dar "permission denied").
--   set role anon; select * from public.links_delegado; reset role;
