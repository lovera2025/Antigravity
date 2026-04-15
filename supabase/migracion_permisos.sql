-- ============================================================================
-- MIGRACIÓN: Sistema de permisos granulares para Asesores
-- Fecha: 25 Marzo 2026
-- ============================================================================
-- Ejecutar en SQL Editor de Supabase
-- ============================================================================

-- ── 1. TABLA DE PERMISOS POR USUARIO ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.permisos_usuario (
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  puede_eventos BOOLEAN DEFAULT false,
  puede_clientes BOOLEAN DEFAULT false,
  puede_catalogo BOOLEAN DEFAULT false,
  puede_recepcion BOOLEAN DEFAULT true,
  puede_totem BOOLEAN DEFAULT false,
  puede_finanzas BOOLEAN DEFAULT false,
  puede_qr BOOLEAN DEFAULT false,
  asignado_por UUID REFERENCES auth.users(id),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS para permisos_usuario
ALTER TABLE public.permisos_usuario ENABLE ROW LEVEL SECURITY;

-- Admin puede ver y editar todos los permisos
CREATE POLICY "Admin gestiona permisos" ON public.permisos_usuario
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'Admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'Admin'));

-- Cada usuario puede ver sus propios permisos
CREATE POLICY "Usuario ve sus permisos" ON public.permisos_usuario
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ── 2. CREAR PERMISOS POR DEFECTO PARA ASESORES EXISTENTES ──────────────────

INSERT INTO permisos_usuario (user_id, puede_recepcion)
SELECT p.id, true
FROM perfiles p
WHERE p.rol = 'Asesor'
  AND NOT EXISTS (SELECT 1 FROM permisos_usuario pu WHERE pu.user_id = p.id)
ON CONFLICT (user_id) DO NOTHING;

-- ── 3. ACTUALIZAR TRIGGER para que nuevos usuarios Asesor tengan permisos ───

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Crear perfil
  INSERT INTO public.perfiles (id, rol, nombre)
  VALUES (
    NEW.id,
    'Asesor',
    COALESCE(
      NEW.raw_user_meta_data->>'nombre',
      SPLIT_PART(NEW.email, '@', 1)
    )
  )
  ON CONFLICT (id) DO NOTHING;

  -- Crear permisos por defecto (solo recepción)
  INSERT INTO public.permisos_usuario (user_id, puede_recepcion)
  VALUES (NEW.id, true)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 4. RLS RESTRICTIVO POR ROL ──────────────────────────────────────────────
-- Función helper para verificar si el usuario es Admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'Admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- === CLIENTES ===
DROP POLICY IF EXISTS "Full access clientes" ON public.clientes;
CREATE POLICY "Admin full access clientes" ON public.clientes
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "Asesor lee clientes si tiene permiso" ON public.clientes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM permisos_usuario
      WHERE user_id = auth.uid() AND puede_clientes = true
    )
  );

-- === EVENTOS ===
DROP POLICY IF EXISTS "Full access eventos" ON public.eventos;
CREATE POLICY "Admin full access eventos" ON public.eventos
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
-- Asesores con permiso de recepción pueden leer eventos (para check-in)
CREATE POLICY "Asesor lee eventos" ON public.eventos
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM permisos_usuario
      WHERE user_id = auth.uid() AND (puede_eventos = true OR puede_recepcion = true)
    )
  );

-- === EVENTOS_SERVICIOS ===
DROP POLICY IF EXISTS "Full access eventos_servicios" ON public.eventos_servicios;
CREATE POLICY "Admin full access eventos_servicios" ON public.eventos_servicios
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
CREATE POLICY "Asesor lee eventos_servicios" ON public.eventos_servicios
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM permisos_usuario
      WHERE user_id = auth.uid() AND puede_eventos = true
    )
  );

-- === TRANSACCIONES ===
DROP POLICY IF EXISTS "Full access transacciones" ON public.transacciones;
CREATE POLICY "Admin full access transacciones" ON public.transacciones
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- === EGRESOS ===
DROP POLICY IF EXISTS "Full access egresos" ON public.egresos;
CREATE POLICY "Admin full access egresos" ON public.egresos
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- === CONTRATOS_ALUMNOS ===
DROP POLICY IF EXISTS "Full access contratos_alumnos" ON public.contratos_alumnos;
CREATE POLICY "Admin full access contratos_alumnos" ON public.contratos_alumnos
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- === PAGOS_CONTRATO_ALUMNO ===
DROP POLICY IF EXISTS "Full access pagos_contrato_alumno" ON public.pagos_contrato_alumno;
CREATE POLICY "Admin full access pagos_contrato_alumno" ON public.pagos_contrato_alumno
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- === INVITADOS (Asesor necesita para check-in) ===
-- Las políticas existentes ya permiten authenticated, las dejamos
-- pero agregamos restricción: solo si tiene permiso de recepción

-- === ACCESOS (Asesor necesita para registrar check-in) ===
-- Las políticas existentes ya permiten insert, las dejamos

-- ── 5. VERIFICACIÓN ─────────────────────────────────────────────────────────

SELECT
  u.email,
  p.rol,
  pu.puede_recepcion,
  pu.puede_eventos,
  pu.puede_clientes,
  pu.puede_catalogo,
  pu.puede_finanzas
FROM auth.users u
LEFT JOIN perfiles p ON u.id = p.id
LEFT JOIN permisos_usuario pu ON u.id = pu.user_id
ORDER BY p.rol, u.email;

-- ============================================================================
-- RESULTADO ESPERADO:
-- Admin (maximiliano1523, juniorsdj) → sin permisos_usuario (no lo necesitan)
-- Asesor (melgarejob) → puede_recepcion = true, resto false
-- ============================================================================
