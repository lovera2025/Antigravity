-- SOLO DEL SANDBOX, y solo para las pruebas de reglas: el reloj de la nube se puede
-- poner a mano. En la nube de verdad `delegado_ahora()` es `now()` y nada más.
create or replace function public.delegado_ahora()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select coalesce(nullif(current_setting('prueba.ahora', true), '')::timestamptz, now());
$$;
