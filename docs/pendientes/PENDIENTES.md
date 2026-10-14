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
- [Que una nota borrada también se vaya de la PC que estaba cerrada](notas-borradas-en-pc-cerrada.md)
  — el borrado de una nota no le llega a una PC que estaba cerrada, y la
  reconciliación no mira las notas. No se arregló el día de publicar porque es
  agregar un camino que borra.

### Tótem y Recepción para las fiestas de diciembre

**Desde el 13-oct-2026 van en la 6.0.0**, por partes: el usuario los quiere en
esa misma versión. **El 14-oct cambió el objetivo y el orden:** Recepción y el
tótem tienen que distinguir un evento particular de uno masivo. El orden y el
estado de cada sección están en "Qué pasó el 14-oct" de
[CONTEXTO_v6.0.0](../CONTEXTO_v6.0.0_2026-10-11.md).

Diseñados y aprobados con maquetas el 2026-09-24, y postergados porque se
priorizó el sorteo de noviembre. El contexto está en
[CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24](../CONTEXTO_MESAS_PLANO_RECEPCION_2026-09-24.md).

- [El tótem con cuatro apariencias](totem-apariencias.md) — Neón, Cristal,
  Póster y Gala, elegibles por evento, sin "Ya llegaron". Trae el código de los
  shaders aprobados. **Lo común quedó hecho el 14-oct** (sección 2): QR solo en
  particulares, la cola con "N más en camino", la familia junta, las sillas y la
  música, y la columna `totem_config.estilo` creada en la nube. **Hecho entero
  el 14-oct:** el tótem del salón con las cuatro apariencias, Personalizar con
  las cuatro tarjetas, la vista en Recepción y el plano con la mesa y el camino
  en la llegada (3a, 3b, 3c y 4).
- [Recepción más amigable](recepcion-redisenio.md) — **hecho el 14-oct**: el
  panel del operador (búsqueda con Enter, filtros, "Ingresar" por fila, y
  particular o masivo), Personalizar, la vista del tótem al lado (solo la
  paleta) y los cortes para celular, tablet y PC.
- [Modo kiosco en la ventana del tótem](totem-kiosco.md) — pantalla completa
  sin bordes, que se sale con Esc o doble clic. Necesita un canal nativo en el
  runner de Windows.
- [Tótems vinculados a recepcionistas](totems-vinculados.md) — cada tótem da la
  bienvenida a los de su puerta, para que dos recepciones no se pisen con mucha
  gente.
- [Recepción y el tótem sin internet (modo local)](modo-local-sin-internet.md) —
  con los datos ya bajados tienen que seguir andando sin internet. Hoy anda con
  una PC; dos puestos se ven solo por la nube. Pedido el 24-sep y otra vez el
  13-oct; trae **la regla que vale para todas las partes que faltan**.
- [Cerrar la lista de la puerta a los anónimos](rls-invitados.md) — hoy
  cualquiera con la clave pública lee y cambia `invitados`, DNI incluido. Se
  cierra con el tótem, porque el tótem lee como anónimo. **Hasta entonces no se
  pasa la lista de la puerta de ninguna fiesta.**

## Hechos

- [Que el tótem no se desconecte ni salude tarde](totem-comunicacion.md) — hecho
  el 2026-10-13, en la 6.0.0. Apareció una tercera forma de saludar tarde que no
  estaba anotada: lo que se marcaba sin internet se saludaba de nuevo al subir.
- [Que los borrados crucen solos](borrados-que-cruzan.md) — hecho el
  2026-09-08.
- [Cadencia del pull por niveles](pull-cadencia-por-niveles.md) — hecho el
  2026-09-08, con dos niveles en vez de tres.
- [Watermark del reloj del servidor](watermark-reloj-del-servidor.md) — hecho el
  2026-09-08, por la opción del `updated_at` más alto recibido.
- [Tablas que quedaron en sync manual](tablas-en-sync-manual.md) — hecho el
  2026-09-08; el pull automático pasó de 16 a 24 tablas.
