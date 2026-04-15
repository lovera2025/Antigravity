-- ============================================================================
-- FUNCIÓN: purge_business_data
-- Propósito: Botón de Pánico — borra todos los datos de negocio de Supabase.
--            Deja intactos: perfiles, servicios (catálogo), tablas del sistema.
-- AUTOR: Antigravity
-- CÓMO USAR: Ejecutar este script en el SQL Editor de Supabase.
--            Una vez creada la función, el botón de pánico en la app funcionará.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.purge_business_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- ── Orden de borrado respetando restricciones de FK ──────────────────────
  -- Primero las hojas (tablas que referencian a otras), después los padres.

  -- Auditoría de accesos (referencia invitados y eventos)
  DELETE FROM public.accesos WHERE 1=1;

  -- Invitados (referencia eventos)
  DELETE FROM public.invitados WHERE 1=1;

  -- Solicitudes de cotización vía QR
  DELETE FROM public.solicitudes_cotizacion WHERE 1=1;

  -- Pagos individuales de contratos de alumnos (referencia contratos_alumnos)
  DELETE FROM public.pagos_contrato_alumno WHERE 1=1;

  -- Contratos de alumnos (eventos masivos; referencia eventos)
  DELETE FROM public.contratos_alumnos WHERE 1=1;

  -- Transacciones e egresos (referencia eventos)
  DELETE FROM public.transacciones WHERE 1=1;
  DELETE FROM public.egresos WHERE 1=1;

  -- Servicios asociados a eventos (pivot; referencia eventos y servicios)
  DELETE FROM public.eventos_servicios WHERE 1=1;

  -- Eventos (referencia clientes)
  DELETE FROM public.eventos WHERE 1=1;

  -- Clientes (raíz del árbol de negocio)
  DELETE FROM public.clientes WHERE 1=1;

  -- ── Lo que NO se borra ───────────────────────────────────────────────────
  -- public.perfiles  → credenciales del admin, deben sobrevivir
  -- public.servicios → catálogo del sistema, no son datos del cliente
END;
$$;

-- ── Permisos: solo usuarios autenticados pueden ejecutar la función ─────────
-- (La app siempre está autenticada; SECURITY DEFINER la ejecuta como dueño)
GRANT EXECUTE ON FUNCTION public.purge_business_data() TO authenticated;

-- ── Para verificar que quedó correctamente creada ───────────────────────────
-- SELECT proname, prosecdef FROM pg_proc WHERE proname = 'purge_business_data';
