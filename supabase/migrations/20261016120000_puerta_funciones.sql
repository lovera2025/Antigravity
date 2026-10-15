-- 2026-10-16 — La lista de la puerta, por funciones. Va con la 6.0.0 (sección 8).
--
-- Hoy `invitados` deja leer y cambiar todo a cualquiera con la clave pública de la
-- web (DNI incluido), y `accesos` deja anotar a cualquiera. Este archivo prepara
-- el camino para cerrarlos: lo que necesitan los que no tienen usuario (el tótem,
-- la página del QR, `?buscar`) pasa a cuatro funciones que dan solo lo justo. Los
-- permisos se cierran después, con `20261016130000_puerta_cerrar_permisos.sql`.
--
-- **Solo agrega: una tabla nueva y cuatro funciones.** No toca ninguna fila de
-- ninguna tabla que ya exista ni ningún permiso. La 5.0.0 no las conoce. Se puede
-- correr a cualquier hora, y **hay que correrlo antes de instalar la 6.0.0**: sin
-- las funciones, el tótem de la 6.0.0 no lee la nube (sigue con lo de la PC) y la
-- página del QR no encuentra a nadie.
--
--   claves_totem    una clave al azar por evento. La lleva el tótem (por el puente
--                   en el programa, en el link por el navegador) y **no** está en
--                   el QR de los invitados. Sin permisos: solo la usan las
--                   funciones. No es de la base de las PCs: no se sincroniza.
--   totem_clave     con usuario: la clave del evento; la crea si no hay.
--   totem_lista     con la clave: lo que muestra el tótem, sin DNI ni intentos.
--   puerta_buscar   desde 3 letras, hasta 10: nombre, mesa, si entró y si tiene
--                   DNI. En un evento masivo no devuelve a nadie.
--   puerta_checkin  compara el DNI acá, cuenta los intentos, marca el ingreso y
--                   lo anota en `accesos` con el DNI tapado.
--
-- `totem_lista` y `puerta_buscar` devuelven un solo JSON y no filas: así no las
-- corta el tope de 1000 filas de PostgREST.
--
-- Sin CHECK nuevos ni nada en la publicación de Realtime. Correrlo dos veces es
-- inocuo: `if not exists` y `create or replace`.
--
-- Cómo correrlo (SQL Editor):
--   1. Correr la consulta "ANTES" de la sección 6 y anotar los números.
--   2. Correr este archivo entero.
--   3. Correr las consultas de la sección 6 y comparar.

-- ── 1. La clave del tótem ───────────────────────────────────────────────────
--
-- ROLLBACK: drop table if exists public.claves_totem;
create table if not exists public.claves_totem (
  evento_id  uuid primary key references public.eventos(id) on delete cascade,
  clave      text not null default replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now()
);

-- Sin políticas: nadie la lee ni la escribe directo, solo las funciones de abajo.
alter table public.claves_totem enable row level security;
revoke all on table public.claves_totem from anon, authenticated;

-- ── 2. totem_clave: la clave del evento, solo con usuario ───────────────────
--
-- ROLLBACK: drop function if exists public.totem_clave(uuid);
create or replace function public.totem_clave(p_evento uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clave text;
begin
  if auth.role() is distinct from 'authenticated' then
    raise exception 'La clave del tótem se pide con usuario' using errcode = '42501';
  end if;
  insert into public.claves_totem (evento_id) values (p_evento)
    on conflict (evento_id) do nothing;
  select c.clave into v_clave from public.claves_totem c where c.evento_id = p_evento;
  return v_clave;
end;
$$;

revoke all on function public.totem_clave(uuid) from public, anon;
grant execute on function public.totem_clave(uuid) to authenticated;

-- ── 3. totem_lista: lo que muestra el tótem ─────────────────────────────────
--
-- Con una clave que no es la del evento **da error, nunca una lista vacía**: el
-- tótem tomaría la lista vacía por buena y sacaría a todos de la pantalla.
--
-- ROLLBACK: drop function if exists public.totem_lista(uuid, text);
create or replace function public.totem_lista(p_evento uuid, p_clave text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_clave is null or not exists (
    select 1 from public.claves_totem c
    where c.evento_id = p_evento and c.clave = p_clave
  ) then
    raise exception 'La clave del tótem no es la de este evento' using errcode = '28000';
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',              i.id,
          'evento_id',       i.evento_id,
          'nombre_completo', i.nombre_completo,
          'numero_mesa',     i.numero_mesa,
          'estado_ingreso',  i.estado_ingreso,
          'created_at',      i.created_at,
          'updated_at',      i.updated_at
        )
        order by i.nombre_completo
      ),
      '[]'::jsonb
    )
    from public.invitados i
    where i.evento_id = p_evento
  );
end;
$$;

revoke all on function public.totem_lista(uuid, text) from public;
grant execute on function public.totem_lista(uuid, text) to anon, authenticated;

-- ── 4. puerta_buscar: la página del QR busca por nombre ─────────────────────
--
-- Las palabras van en cualquier orden y sin acentos: "gomez lau" encuentra a
-- "GÓMEZ, LAURA". Hacen falta 3 letras entre todas.
--
-- ROLLBACK: drop function if exists public.puerta_normalizar(text);
create or replace function public.puerta_normalizar(p_texto text)
returns text
language sql
immutable
set search_path = public
as $$
  select lower(translate(
    coalesce(p_texto, ''),
    'ÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇáàäâéèëêíìïîóòöôúùüûñç,.;''"',
    'AAAAEEEEIIIIOOOOUUUUNCaaaaeeeeiiiioooouuuunc     '
  ));
$$;

-- ROLLBACK: drop function if exists public.puerta_buscar(uuid, text);
create or replace function public.puerta_buscar(p_evento uuid, p_texto text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_palabras text[];
begin
  -- En un masivo la lista de la puerta son alumnos: no se muestra a nadie.
  if not exists (
    select 1 from public.eventos e
    where e.id = p_evento and coalesce(e.modalidad, '') <> 'masivo'
  ) then
    return '[]'::jsonb;
  end if;

  v_palabras := array_remove(
    regexp_split_to_array(trim(public.puerta_normalizar(p_texto)), '\s+'),
    ''
  );
  if length(array_to_string(v_palabras, '')) < 3 then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',              r.id,
          'nombre_completo', r.nombre_completo,
          'numero_mesa',     r.numero_mesa,
          'ingresado',       r.estado_ingreso = 'ingresado',
          'tiene_dni',       coalesce(trim(r.dni), '') <> ''
        )
        order by r.nombre_completo
      ),
      '[]'::jsonb
    )
    from (
      select i.*
      from public.invitados i
      where i.evento_id = p_evento
        and not exists (
          select 1 from unnest(v_palabras) w
          where position(w in public.puerta_normalizar(i.nombre_completo)) = 0
        )
      order by i.nombre_completo
      limit 10
    ) r
  );
end;
$$;

revoke all on function public.puerta_normalizar(text) from public;
grant execute on function public.puerta_normalizar(text) to anon, authenticated;
revoke all on function public.puerta_buscar(uuid, text) from public;
grant execute on function public.puerta_buscar(uuid, text) to anon, authenticated;

-- ── 5. puerta_checkin: el invitado se anota con su DNI ──────────────────────
--
-- Devuelve `resultado`:
--   ok              marcado. Con `invitado` (sin DNI) para avisarle al tótem.
--   ya_ingresado    ya estaba adentro. Con `invitado`.
--   dni_incorrecto  con `quedan`: los intentos que le quedan.
--   bloqueado       3 intentos fallidos: lo anotan en la recepción.
--   no_dni          no tiene DNI cargado: lo anotan en la recepción.
--   masivo          los de un masivo se anotan en la recepción.
--   no_encontrado
-- El DNI se compara solo por sus números: "30.111.222" es "30111222". Uno sin
-- números no cuenta como intento.
--
-- ROLLBACK: drop function if exists public.puerta_checkin(uuid, text);
create or replace function public.puerta_checkin(p_invitado uuid, p_dni text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inv       public.invitados%rowtype;
  v_modalidad text;
  v_dado      text := regexp_replace(coalesce(p_dni, ''), '\D', '', 'g');
  v_cargado   text;
  v_intentos  int;
  v_tapado    text;
begin
  select * into v_inv from public.invitados i where i.id = p_invitado for update;
  if not found then
    return jsonb_build_object('resultado', 'no_encontrado');
  end if;

  select e.modalidad into v_modalidad from public.eventos e where e.id = v_inv.evento_id;
  if v_modalidad = 'masivo' then
    return jsonb_build_object('resultado', 'masivo');
  end if;

  if v_inv.estado_ingreso = 'ingresado' then
    return jsonb_build_object(
      'resultado', 'ya_ingresado',
      'invitado', jsonb_build_object(
        'id', v_inv.id, 'evento_id', v_inv.evento_id,
        'nombre_completo', v_inv.nombre_completo, 'numero_mesa', v_inv.numero_mesa,
        'estado_ingreso', v_inv.estado_ingreso, 'updated_at', v_inv.updated_at
      )
    );
  end if;

  v_intentos := coalesce(v_inv.intentos_fallidos, 0);
  if v_intentos >= 3 then
    return jsonb_build_object('resultado', 'bloqueado');
  end if;

  v_cargado := regexp_replace(coalesce(v_inv.dni, ''), '\D', '', 'g');
  if v_cargado = '' then
    return jsonb_build_object('resultado', 'no_dni');
  end if;
  if v_dado = '' then
    return jsonb_build_object('resultado', 'dni_incorrecto', 'quedan', 3 - v_intentos);
  end if;

  v_tapado := '***' || right(v_dado, 3);

  if v_dado = v_cargado then
    update public.invitados
       set estado_ingreso = 'ingresado', intentos_fallidos = 0
     where id = v_inv.id
     returning * into v_inv;
    insert into public.accesos (invitado_id, evento_id, dni_ingresado, valido, marcado_por)
    values (v_inv.id, v_inv.evento_id, v_tapado, true, 'qr');
    return jsonb_build_object(
      'resultado', 'ok',
      'invitado', jsonb_build_object(
        'id', v_inv.id, 'evento_id', v_inv.evento_id,
        'nombre_completo', v_inv.nombre_completo, 'numero_mesa', v_inv.numero_mesa,
        'estado_ingreso', v_inv.estado_ingreso, 'updated_at', v_inv.updated_at
      )
    );
  end if;

  v_intentos := v_intentos + 1;
  update public.invitados set intentos_fallidos = v_intentos where id = v_inv.id;
  insert into public.accesos (invitado_id, evento_id, dni_ingresado, valido, marcado_por)
  values (v_inv.id, v_inv.evento_id, v_tapado, false, 'qr');
  if v_intentos >= 3 then
    return jsonb_build_object('resultado', 'bloqueado');
  end if;
  return jsonb_build_object('resultado', 'dni_incorrecto', 'quedan', 3 - v_intentos);
end;
$$;

revoke all on function public.puerta_checkin(uuid, text) from public;
grant execute on function public.puerta_checkin(uuid, text) to anon, authenticated;

-- ── 6. Verificación ─────────────────────────────────────────────────────────
--
-- ANTES y DESPUÉS de correr el archivo: estos conteos tienen que dar igual. Si
-- cambia uno solo, algo tocó datos que no debía.
--
--   select
--     (select count(*) from public.contratos_alumnos)         as contratos,
--     (select count(*) from public.pagos_contrato_alumno)     as pagos,
--     (select count(*) from public.notas_operativas_contrato) as notas,
--     (select count(*) from public.invitados)                 as invitados,
--     (select count(*) from public.accesos)                   as accesos,
--     (select count(*) from public.eventos)                   as eventos;
--
-- DESPUÉS: la tabla, vacía, y las cinco funciones (tiene que devolver cinco filas):
--
--   select count(*) from public.claves_totem;   -- 0
--
--   select p.proname, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('totem_clave', 'totem_lista', 'puerta_normalizar',
--                       'puerta_buscar', 'puerta_checkin')
--   order by 1;
--
-- Y que un anónimo no puede pedir la clave (tiene que dar error de permiso):
--
--   begin;
--   set local role anon;
--   select public.totem_clave('00000000-0000-0000-0000-000000000000');
--   rollback;
