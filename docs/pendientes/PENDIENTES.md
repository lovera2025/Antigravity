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

- [La puerta con más de 1000 personas en web y tótem](invitados-mas-de-1000-en-web.md)
  — el QR y el tótem leen hasta 1000 invitados por evento. Hoy no llega ni cerca;
  importa si se cargan las familias enteras. Se resuelve subiendo "Max rows" en
  Supabase.
- [Que el pull diga cuántas filas bajó](pull-devolver-cambios-reales.md) — sin
  eso, el caché de la proyección financiera se anula cada 10 segundos aunque no
  haya cambiado nada.
- [Chequeo de salud de saldos](chequeo-salud-saldos.md) — auditar saldos contra
  Supabase en vez de la base local. Incluye cuál es la herramienta buena
  (`tool/recalcular_contrato.dart --dry-run`) y cuál es una trampa.

### Tótem y Recepción para las fiestas de diciembre

Diseñados y aprobados con maquetas el 2026-09-24, y postergados porque se
priorizó el sorteo de noviembre. El contexto está en
[CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24](../CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24.md).

- [Que el tótem no se desconecte ni salude tarde](totem-comunicacion.md) — un
  aviso que falla una vez desconecta el tótem por el resto de la noche, y
  después de un corte repite bienvenidas viejas. Va primero: es chico y toca las
  mismas pantallas.
- [El tótem con cuatro apariencias](totem-apariencias.md) — Neón, Cristal,
  Póster y Gala, elegibles por evento, sin "Ya llegaron" y con QR solo en
  particulares. Trae el código de los shaders aprobados y la migración de
  `totem_config.estilo`.
- [Recepción más amigable](recepcion-redisenio.md) — búsqueda con Enter,
  filtros, "Ingresar" por fila, solo la paleta sobre la vista del tótem, y
  cortes para celular, tablet y PC.
- [Modo kiosco en la ventana del tótem](totem-kiosco.md) — pantalla completa
  sin bordes, que se sale con Esc o doble clic. Necesita un canal nativo en el
  runner de Windows.
- [Tótems vinculados a recepcionistas](totems-vinculados.md) — cada tótem da la
  bienvenida a los de su puerta, para que dos recepciones no se pisen con mucha
  gente.

## Hechos

- [Que los borrados crucen solos](borrados-que-cruzan.md) — hecho el
  2026-09-08.
- [Cadencia del pull por niveles](pull-cadencia-por-niveles.md) — hecho el
  2026-09-08, con dos niveles en vez de tres.
- [Watermark del reloj del servidor](watermark-reloj-del-servidor.md) — hecho el
  2026-09-08, por la opción del `updated_at` más alto recibido.
- [Tablas que quedaron en sync manual](tablas-en-sync-manual.md) — hecho el
  2026-09-08; el pull automático pasó de 16 a 24 tablas.
