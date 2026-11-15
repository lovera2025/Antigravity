# Anular la misma venta de entradas desde dos PCs a la vez

**Estado:** pendiente
**Postergado el:** 2026-11-15

## Qué pasa

Lo encontró la revisión de VENTAS (etapa 5 de la venta de entradas, 6.9.0, sin publicar). La anulación de una
venta tiene un id fijo por venta (`UuidUtils.entradasAnulacionId`), y "anular dos veces devuelve la que ya había"
mira **solo la base del equipo** (`EntradasLocal.anular`). Si el jefe anula la misma venta en la PC A ("Sí, las
devolvieron") y, antes de que la PC B se entere, también en la PC B ("No las devolvieron"):

- la subida de la B hace `upsert` (`_executeSyncOperation`, `sync_engine.dart`) y **pisa en la nube** la fila de la
  A: se pierden el motivo y quién anuló primero, y `devueltas` cambia;
- la A la baja y la pisa también en su base;
- con `devueltas` en falso, esos números quedan "anulados para siempre" aunque ya se hayan vuelto a entregar, y
  aparece el aviso de número repetido.

Contradice "solo se agregan filas" cuando son dos equipos.

## Por qué se postergó

- Necesita que **el jefe anule la misma venta en dos PCs** dentro de los segundos que tarda el aviso entre equipos
  (o con una PC sin internet). Anular es solo del jefe y se hace desde la oficina.
- El arreglo toca la subida del motor (`sync_engine.dart`), que es de todas las tablas, y pide una prueba de dos
  equipos con la nube de prueba. No conviene meterlo de apuro en la 6.9.0.
- Nada de esto está instalado: la venta de entradas sale en la 6.9.0.

## Qué habría que hacer

1. En la subida de un `insert` de `entradas_anulaciones`, `upsert(payload, onConflict: 'id', ignoreDuplicates:
   true)`: la nube se queda con la primera anulación de cada venta, y la PC que llegó segunda la baja y reemplaza la
   suya. Lo mismo vale para `barra_anulaciones`, que tiene el mismo id fijo por venta: revisarlo junto.
2. En `_anular` de VENTAS (`ventas_de_entradas_screen.dart`), si la anulación que vuelve no es la que se pidió
   (otro `devueltas` u otro equipo), decir "Ya estaba anulada por … : las devolvieron / no las devolvieron" en vez
   de "Venta N anulada.".
3. La prueba: dos equipos con `NubeDePrueba`; la segunda anulación no cambia `devueltas` en la nube ni en la primera
   PC.
