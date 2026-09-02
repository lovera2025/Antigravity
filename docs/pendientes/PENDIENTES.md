# Pendientes

Trabajo que **se decidió hacer** y se postergó a propósito. Un pendiente por
archivo.

Es la carpeta hermana de [ideas/](../ideas/IDEAS.md), y la diferencia importa:
una idea puede no hacerse nunca; un pendiente ya se analizó, se acordó, y quedó
afuera por una razón concreta —falta de tiempo, riesgo mal ubicado, una fecha de
entrega encima—. Está acá para poder volver dentro de seis meses y preguntar
"¿qué faltaba de aquel día?" sin tener que reconstruirlo leyendo el código.

## Cómo se usa

- Un pendiente = un archivo `.md` en esta carpeta, en kebab-case.
- Cada archivo arranca con un encabezado de **estado** (pendiente / en curso /
  hecho / descartado) y la **fecha en que se postergó**.
- Adentro va, sí o sí, **por qué se postergó**. Eso es lo primero que se olvida
  y lo único que no se puede recuperar mirando el repo.
- Después: qué habría que hacer y dónde tocar, con rutas y líneas.
- Cuando se resuelve no se borra: se marca `hecho` con la fecha y, si hubo
  sorpresas, se anota qué salió distinto de lo previsto.

## Los pendientes

- [Cadencia del pull por niveles](pull-cadencia-por-niveles.md) — hoy las 16
  tablas bajan cada 10 s; separarlas en 10/30/60 s según cuánto se mueven.
- [Que el pull diga cuántas filas bajó](pull-devolver-cambios-reales.md) — sin
  eso, el caché de la proyección financiera se anula cada 10 segundos aunque no
  haya cambiado nada.
- [Chequeo de salud de saldos](chequeo-salud-saldos.md) — auditar saldos contra
  Supabase en vez de la base local. Incluye cuál es la herramienta buena
  (`tool/recalcular_contrato.dart --dry-run`) y cuál es una trampa.
- [Watermark del reloj del servidor](watermark-reloj-del-servidor.md) — el pull
  incremental confía en la hora de cada PC, y una PC atrasada rebaja siempre lo
  mismo.
- [Tablas que quedaron en sync manual](tablas-en-sync-manual.md) — alquileres,
  rentabilidad, obligaciones, caja fuerte e invitados siguen cruzando solo a
  mano.
