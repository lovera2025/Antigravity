-- ============================================================================
-- MIGRACIÓN: Tótem editable por evento + presencia y permisos confiables
-- Fecha: 3 Septiembre 2026
-- ============================================================================
-- Ejecutar en el SQL Editor de Supabase.
--
-- GARANTÍA DE SEGURIDAD DE DATOS
--   Este archivo NO contiene ningún DELETE, DROP TABLE ni DROP COLUMN.
--   No modifica una sola fila de: eventos, eventos_servicios, clientes,
--   presupuestos, presupuesto_servicios, transacciones, egresos,
--   contratos_alumnos, pagos_contrato_alumno, invitados ni accesos.
--   El único DROP es de policies (reglas de seguridad), que se recrean
--   inmediatamente debajo.
--
-- CONTEO BASE antes de aplicar (3 Sep 2026):
--   accesos 0 · clientes 49 · contratos_alumnos 642 · egresos 120
--   eventos 23 · eventos_servicios 68 · invitados 3
--   pagos_contrato_alumno 3121 · perfiles 3 · permisos_usuario 1
--   presupuesto_servicios 197 · presupuestos 29 · transacciones 20
--   Volver a correr el conteo al terminar: debe dar exactamente lo mismo.
--
-- Cada bloque lleva su ROLLBACK escrito arriba, comentado.
-- ============================================================================


-- ── 1. TABLA totem_config ───────────────────────────────────────────────────
-- Config visual del tótem, una fila por evento. Empieza vacía: mientras un
-- evento no tenga fila, el tótem se ve exactamente como hoy.
--
-- ROLLBACK: DROP TABLE IF EXISTS public.totem_config;

CREATE TABLE IF NOT EXISTS public.totem_config (
  evento_id          UUID PRIMARY KEY REFERENCES public.eventos(id) ON DELETE CASCADE,
  titulo             TEXT,
  subtitulo          TEXT,
  mensaje_bienvenida TEXT,
  mensaje_qr         TEXT,
  imagen_url         TEXT,
  color_acento       TEXT DEFAULT '#D4AF37',
  updated_at         TIMESTAMPTZ DEFAULT now(),
  updated_by         UUID REFERENCES auth.users(id)
);

COMMENT ON TABLE public.totem_config IS
  'Identidad visual del tótem por evento (foto, textos, color). Sin fila = valores por defecto de la app.';

ALTER TABLE public.totem_config ENABLE ROW LEVEL SECURITY;

-- Lectura pública: el tótem web (?totem) y la pantalla del invitado (/lista)
-- corren con la anon key, sin login. Mismo criterio que ya se aplica a
-- invitados y eventos.
DROP POLICY IF EXISTS "Lectura publica totem_config" ON public.totem_config;
CREATE POLICY "Lectura publica totem_config" ON public.totem_config
  FOR SELECT TO anon, authenticated
  USING (true);

-- Escritura: Admin, o Asesor con puede_totem.
-- Esto convierte a puede_totem en el primer permiso con RLS real; hasta hoy
-- era solo cosmético del lado cliente.
DROP POLICY IF EXISTS "Escritura totem_config con permiso" ON public.totem_config;
CREATE POLICY "Escritura totem_config con permiso" ON public.totem_config
  FOR ALL TO authenticated
  USING (
    public.is_admin() OR EXISTS (
      SELECT 1 FROM public.permisos_usuario
      WHERE user_id = auth.uid() AND puede_totem = true
    )
  )
  WITH CHECK (
    public.is_admin() OR EXISTS (
      SELECT 1 FROM public.permisos_usuario
      WHERE user_id = auth.uid() AND puede_totem = true
    )
  );


-- ── 2. BUCKET DE STORAGE 'totem' ────────────────────────────────────────────
-- Guarda la foto principal de cada evento en <evento_id>/portada.<ext>.
-- Público en lectura porque el tótem web y el celular del invitado no tienen
-- sesión. Escritura con el mismo criterio que la tabla.
--
-- ROLLBACK:
--   DELETE FROM storage.objects WHERE bucket_id = 'totem';
--   DELETE FROM storage.buckets WHERE id = 'totem';
--   (las policies de storage.objects se borran con los DROP POLICY de abajo)

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'totem', 'totem', true, 5242880,
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET public = true,
      file_size_limit = 5242880,
      allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp'];

DROP POLICY IF EXISTS "Lectura publica totem bucket" ON storage.objects;
CREATE POLICY "Lectura publica totem bucket" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'totem');

DROP POLICY IF EXISTS "Escritura totem bucket con permiso" ON storage.objects;
CREATE POLICY "Escritura totem bucket con permiso" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'totem' AND (
      public.is_admin() OR EXISTS (
        SELECT 1 FROM public.permisos_usuario
        WHERE user_id = auth.uid() AND puede_totem = true
      )
    )
  )
  WITH CHECK (
    bucket_id = 'totem' AND (
      public.is_admin() OR EXISTS (
        SELECT 1 FROM public.permisos_usuario
        WHERE user_id = auth.uid() AND puede_totem = true
      )
    )
  );


-- ── 3. ARREGLAR EL BORRADO EN EL TÓTEM ──────────────────────────────────────
-- Con REPLICA IDENTITY DEFAULT, el payload de un DELETE en la replicación
-- lógica lleva SOLO la primary key. Toda suscripción filtrada por una columna
-- —el `.stream().eq('evento_id')` del tótem y el PostgresChangeFilter que se le
-- agregó al panel de Recepción el 2026-09-02— queda sin poder evaluar el
-- filtro sobre ese payload pelado, así que el servidor descarta el evento: el
-- invitado borrado sigue proyectado en la pantalla del salón hasta reiniciar.
-- FULL hace que el DELETE viaje con la fila completa y el filtro pueda
-- resolverse.
--
-- SOBRE EL DISK IO (ver docs/CONTEXTO_v4.9.4_2026-09-02.md)
--   FULL agranda el registro de WAL de cada UPDATE/DELETE de esta tabla, y el
--   costo de apply_rls escala con el volumen de WAL. Se acota a `invitados` a
--   propósito: es la única tabla que quedó en la publicación, tiene 8 columnas
--   cortas y unos cientos de filas por evento, contra las 3.121 de
--   pagos_contrato_alumno. Los INSERT —que son la mayoría durante una carga de
--   lista— no se ven afectados: FULL solo agrega la fila vieja, y en un INSERT
--   no hay fila vieja.
--
--   NO se agrega ninguna tabla a la publicación. La v4.9.4 la dejó en una sola
--   (`invitados`) para salir del agotamiento de Disk IO Budget, y eso se
--   respeta: los permisos en vivo y la presencia van por canales de broadcast
--   y presence, que no consultan el WAL ni disparan apply_rls.
--
-- ROLLBACK: ALTER TABLE public.invitados REPLICA IDENTITY DEFAULT;

ALTER TABLE public.invitados REPLICA IDENTITY FULL;


-- ── 4. COLUMNA last_seen_at EN perfiles ─────────────────────────────────────
-- Para que "offline" deje de ser un vacío y diga "hace 8 min".
-- Aditivo: no toca ninguna fila existente, arranca en NULL.
--
-- ROLLBACK: ALTER TABLE public.perfiles DROP COLUMN IF EXISTS last_seen_at;

ALTER TABLE public.perfiles
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;


-- ── 5. UN USUARIO NUEVO NACE SIN PERMISOS ───────────────────────────────────
-- Hoy el registro está abierto y el trigger le regala puede_recepcion = true,
-- así que cualquiera con un mail se crea la cuenta y ya ve la lista de
-- invitados. A partir de acá nace con todo apagado y espera el pase del jefe.
--
-- IMPORTANTE: esto NO toca a los usuarios que ya existen. Solo cambia el
-- default de los que vengan de ahora en más.
--
-- ROLLBACK:
--   ALTER TABLE public.permisos_usuario ALTER COLUMN puede_recepcion SET DEFAULT true;
--   (y volver a poner `VALUES (NEW.id, true)` con la columna puede_recepcion
--    en handle_new_user, como está en migracion_permisos.sql:47-72)

ALTER TABLE public.permisos_usuario
  ALTER COLUMN puede_recepcion SET DEFAULT false;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
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

  -- Sin permisos: todos los flags quedan en su default (false).
  INSERT INTO public.permisos_usuario (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── 6. FIX: un asesor podía auto-promoverse a Admin ─────────────────────────
-- La policy vigente es FOR ALL con USING (auth.uid() = id) y SIN WITH CHECK,
-- lo que permite:  UPDATE perfiles SET rol='Admin' WHERE id = auth.uid();
-- Es decir, cualquier asesor podía darse acceso a finanzas, caja y todo lo
-- demás. Mientras eso exista, gatear el tótem no significa nada.
--
-- Se parte en SELECT + UPDATE. El usuario sigue editando su nombre y su
-- last_seen_at; lo único que no puede es cambiarse el rol.
--
-- ROLLBACK:
--   DROP POLICY IF EXISTS "Usuario edita su perfil sin cambiar rol" ON public.perfiles;
--   DROP POLICY IF EXISTS "Admin gestiona perfiles" ON public.perfiles;
--   CREATE POLICY "Usuarios gestionan su propio perfil" ON public.perfiles
--     FOR ALL TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Usuarios gestionan su propio perfil" ON public.perfiles;

CREATE POLICY "Usuario edita su perfil sin cambiar rol" ON public.perfiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND rol = (SELECT p.rol FROM public.perfiles p WHERE p.id = auth.uid())
  );

-- El Admin sí puede promover a otros (es lo que hoy se hace por SQL a mano).
CREATE POLICY "Admin gestiona perfiles" ON public.perfiles
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


-- ============================================================================
-- VERIFICACIÓN — correr después de aplicar
-- ============================================================================
--
-- 1) Replicación: `invitados` debe decir FULL, y la publicación de Realtime
--    tiene que seguir teniendo UNA SOLA tabla. Si aparece alguna más, algo
--    revirtió el trabajo de la v4.9.4.
--
--   SELECT c.relname AS tabla,
--          CASE c.relreplident WHEN 'd' THEN 'DEFAULT' WHEN 'f' THEN 'FULL'
--                              WHEN 'n' THEN 'NOTHING' WHEN 'i' THEN 'INDEX' END AS replica_identity
--   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
--   WHERE n.nspname='public' AND c.relname = 'invitados';
--
--   SELECT tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime';   -- esperado: solo `invitados`
--
-- 2) Conteo de control: debe dar idéntico al del encabezado de este archivo.
--
--   SELECT 'eventos' t, count(*) FROM public.eventos
--   UNION ALL SELECT 'eventos_servicios', count(*) FROM public.eventos_servicios
--   UNION ALL SELECT 'clientes', count(*) FROM public.clientes
--   UNION ALL SELECT 'presupuestos', count(*) FROM public.presupuestos
--   UNION ALL SELECT 'transacciones', count(*) FROM public.transacciones
--   UNION ALL SELECT 'egresos', count(*) FROM public.egresos
--   UNION ALL SELECT 'contratos_alumnos', count(*) FROM public.contratos_alumnos
--   UNION ALL SELECT 'pagos_contrato_alumno', count(*) FROM public.pagos_contrato_alumno
--   UNION ALL SELECT 'invitados', count(*) FROM public.invitados
--   UNION ALL SELECT 'perfiles', count(*) FROM public.perfiles
--   ORDER BY 1;
--
-- ============================================================================
