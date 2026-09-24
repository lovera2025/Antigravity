# La puerta con más de 1000 personas en web y tótem

**Estado:** pendiente
**Postergado el:** 2026-09-24

## Por qué se postergó

Hoy no hace falta: la lista de la puerta de cada fiesta tiene a los alumnos y a
sus acompañantes **con nombre**, y al 24-sep no hay un solo acompañante cargado
(0 de 643 alumnos). La institución más grande pide 133 mesas: sin familias son
unos 110 nombres, lejos de 1000.

Pasa a importar recién si se cargan las familias enteras (hasta 10 personas por
mesa). La solución más simple es subir un número de la configuración de
Supabase, y eso lo decide el usuario: no se tocó.

## Qué pasa

PostgREST devuelve **como máximo 1000 filas** por consulta (el "Max rows" de
Supabase → Settings → API). Varias pantallas leen `invitados` de un evento sin
paginar:

- el tótem: el stream en `supabase_service.dart` (`streamInvitados`) y la
  relectura de cada minuto en `totem_display.dart` (`_reconciliar`);
- la lista del QR (`?lista`), la búsqueda (`?buscar`) y el operador (`/op`), por
  `supabase_service.dart` y `supabase_invitados_repository.dart`.

Con más de 1000 personas en un evento, las que queden después de la fila 1000
**no aparecen** en esas pantallas: no se pueden buscar por el QR y el tótem no
les da la bienvenida. No se pierde nada guardado.

Lo que **sí** se arregló en la 4.9.9 es el camino que borraba:
`InvitadosRepository._pullByEvento` pagina y solo poda con la foto completa, por
`filasAPodar`. Antes, con más de 1000, borraba de la base local a los que no
entraban en la primera página.

## Qué habría que hacer

Una de dos, antes de la primera fiesta con familias cargadas:

1. **Subir "Max rows" en Supabase** (por ejemplo a 5000). Un cambio de
   configuración que cubre todas las lecturas de una vez. Lo hace el usuario
   desde el panel.
2. **Paginar cada lectura** con `.range()`. Los streams (`.stream()`) no se pueden
   paginar: habría que reemplazarlos por lectura paginada más el aviso de
   broadcast que ya existe.

Para saber si hace falta, alcanza con mirar cuántos invitados tiene el evento
antes de la fiesta:

```sql
select evento_id, count(*) from invitados group by 1 order by 2 desc;
```
