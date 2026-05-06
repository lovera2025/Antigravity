-- Script de setup del módulo "Cierre de caja".
-- Correr manualmente en el SQL editor de Supabase.
-- No se aplica desde la app: el repo solo lo lee como referencia.

-- 1) Permiso granular para que un asesor (no admin) pueda ver "Cierre de caja"
--    en su panel y entrar a la pantalla desde el drawer del Dashboard.
ALTER TABLE permisos_usuario
  ADD COLUMN IF NOT EXISTS puede_cierre_caja BOOLEAN DEFAULT FALSE;

-- 2) (No requiere cambios) Los retiros se persisten en la tabla `egresos` con:
--      categoria   = 'Retiro de caja'
--      medio_pago  IN ('efectivo', 'transferencia')
--    No se crea tabla nueva: la lógica financiera trata el retiro como un egreso
--    sin evento_id, alineado con `registrarEgresoSinEvento`.
