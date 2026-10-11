# Que una nota borrada también se vaya de la PC que estaba cerrada

**Estado:** pendiente
**Postergado el:** 2026-10-11

## Por qué se postergó

Apareció el 11-oct, el mismo día en que se estaba por publicar la 6.0.0. Arreglarlo es **agregar un camino que
borra** en la sincronización, y eso no se hace apurado ni el día de publicar: es la clase de cambio que ya vació los
presupuestos de una PC (ver "Nada se borra de la base local" en `CLAUDE.md`). Ese día se limpió a mano lo que
había y se dejó esto anotado.

## El problema

Una nota de un alumno se borra con el botón Eliminar de la nota. El borrado sube a la nube y les llega a las otras
PCs por el aviso entre PCs (`_aplicarBorrados`), que lleva los ids borrados. **Una PC que estaba cerrada en ese
momento no se entera nunca**: la nota le queda para siempre.

La red para ese caso es la reconciliación de borrados (`_reconcileDeletes`), pero mira solo las tablas padre
(`_tablasAReconciliar`: clientes, eventos, presupuestos, contratos, préstamos y servicios). Las notas son hijas de
`contratos_alumnos` y solo caerían si se borrara el alumno.

**Lo que se vio el 11-oct:** en la PC de desarrollo había 14 notas que alguien había borrado desde otra PC entre el
4-sep y el 11-oct. Se sacaron a mano, con `tool/ordenar_notas_operativas_test.dart` (ver "Las notas operativas que
no están en la nube" en [CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26](../CONTEXTO_FASE3_PLANO_SORTEO_2026-09-26.md)).

## Por qué no alcanza con sumar las notas a la lista

Comparar "lo que hay acá contra lo que hay en la nube" **no distingue una nota borrada de una que nunca subió**.
Ese mismo día había, mezcladas con las 14, otras 17 que estaban solo en esa PC porque nunca habían subido. Una
reconciliación ingenua las habría borrado también, sin avisar.

Desde el 11-oct la nota y su entrada en la cola se guardan juntas, en una transacción
(`NotasOperativasContratoRepository.guardarEn`), así que ya no debería quedar una nota guardada sin su subida. Pero
"no debería" no alcanza para borrar.

## Qué habría que hacer

Opciones, de la más segura a la más cómoda:

1. **Que el borrado deje rastro.** En vez de borrar la fila, marcarla (`borrada_at`) y que viaje como una edición:
   las ediciones cruzan bien aunque la PC esté cerrada, porque bajan por `updated_at`. Es la más segura y la que
   más toca: una columna nueva en una tabla que ya existe, en la base local y en la nube.
2. **Reconciliar las notas, pero solo las que alguna vez estuvieron en la nube.** Guardar en la PC qué ids se
   vieron bajar, y borrar solo esos cuando ya no están. Pasa por `filasAPodar`, con una foto completa y contada.
3. **No hacer nada y limpiar a mano** cuando moleste, con la herramienta del 11-oct como modelo.

Antes de elegir: preguntarle al usuario cuánto borran notas en el día a día. El 11-oct opinó que prefiere marcar
"resuelto" antes que borrar, y con eso el problema casi no aparece.

## Dónde tocar

- `lib/core/services/sync_engine.dart` → `_tablasAReconciliar`, `_reconcileDeletes` y `filasAPodar`.
- `lib/features/eventos/repositories/notas_operativas_contrato_repository.dart` → `eliminarEn`.
- `test/filas_a_podar_test.dart` y `test/notas_operativas_contrato_test.dart`.
