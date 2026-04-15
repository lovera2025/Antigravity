-- ============================================================================
-- FIX: Auto-crear perfil cuando un usuario se registra
-- Fecha: 25 Marzo 2026
-- Motivo: Los usuarios nuevos no tienen fila en 'perfiles', lo que causa
--         "new row violates row-level security policy for table servicios"
-- ============================================================================
-- IMPORTANTE: Los nuevos usuarios entran como 'Asesor' (acceso limitado).
-- Solo el dueño (Adri) es 'Admin'.
-- ============================================================================

-- ── PASO 1: Crear trigger para auto-crear perfiles en futuros registros ────

-- Función que se ejecuta al crear un nuevo usuario en auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.perfiles (id, rol, nombre)
  VALUES (
    NEW.id,
    'Asesor',  -- Rol por defecto: acceso básico/operador
    COALESCE(
      NEW.raw_user_meta_data->>'nombre',
      SPLIT_PART(NEW.email, '@', 1)
    )
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger que se dispara después de cada INSERT en auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── PASO 2: Crear perfiles para usuarios existentes que no lo tengan ───────
-- Todos entran como 'Asesor' por defecto
INSERT INTO perfiles (id, rol, nombre)
SELECT
  u.id,
  'Asesor',
  SPLIT_PART(u.email, '@', 1)
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1 FROM perfiles p WHERE p.id = u.id
)
ON CONFLICT (id) DO NOTHING;

-- ── PASO 3: Poner a Adri como Admin (el dueño del negocio) ─────────────────
UPDATE perfiles
SET rol = 'Admin', nombre = 'Adrian'
WHERE id = (SELECT id FROM auth.users WHERE email ILIKE '%juntor%');

-- ── PASO 5: Verificación ────────────────────────────────────────────────────
SELECT
  u.email,
  p.rol,
  p.nombre
FROM auth.users u
LEFT JOIN perfiles p ON u.id = p.id
ORDER BY u.created_at;

-- ============================================================================
-- RESULTADO ESPERADO: Todos los usuarios deben tener un perfil con rol 'Admin'
-- ============================================================================
