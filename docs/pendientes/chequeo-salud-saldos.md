# Chequeo de salud de saldos contra Supabase

**Estado:** pendiente
**Postergado el:** 2026-09-02

## Por qué se postergó

El 2026-09-02 se retiró el botón "Auditar y Sincronizar DB", que recalculaba los
saldos del evento entero desde la copia **local** de los pagos y subía el
resultado: una PC desactualizada publicaba su atraso como si fuera una decisión.
Fue lo que revivió una mora ya perdonada por el jefe.

La decisión fue: los datos hoy están bien; si aparece algo torcido se arregla
cuando aparezca. Se prefirió sacar la herramienta peligrosa ese mismo día antes
que esperar a tener lista una mejor.

## Lo que SÍ existe hoy

**`tool/recalcular_contrato.dart` es la herramienta buena.** Con `--dry-run` no
escribe nada (todas sus escrituras están detrás de `if (!dryRun)`), apunta a la
base correcta (`Documents\Junior Eventos\data.db`, con espacio) y filtra por
evento o por alumno:

```
dart run tool/recalcular_contrato.dart --dry-run --evento "SAGRADO CORAZON"
dart run tool/recalcular_contrato.dart --dry-run --nombre "CHAMORRO"
```

Sin `--dry-run` corrige. Ésa es la forma correcta de reparar: mirás el informe
primero, decidís, y recién ahí aplicás.

**Antes de correrlo, sincronizar.** Lee la base local, así que hereda el mismo
punto ciego que tenía el botón: si un pago no bajó todavía, el informe va a
marcar una diferencia que no existe. La diferencia clave es que en `--dry-run`
**no escribe ni encola**, así que no puede propagar el error — solo confundirte.

## Lo que NO sirve, para que nadie se confíe

`scripts/recalculate_all.dart` **no es una red de seguridad**, aunque el nombre
lo sugiera:

1. **No tiene modo informe.** Llama a `recalcularProgresoContrato`
   (`scripts/recalculate_all.dart:46`), que escribe en SQLite y encola a
   Supabase. Es el defecto del botón retirado, pero sobre *todos* los contratos
   de la base.
2. **Apunta a una carpeta que no existe.** Línea 30:
   `C:\Users\lover\Documents\JuniorEventos\data.db`, sin espacio. La base real
   vive en `Junior Eventos`, **con** espacio. Compara con el `_resolveDbPath()`
   de `tool/recalcular_contrato.dart:11`, que lo hace bien.

O se borra, o se le agrega `--dry-run` y se le arregla la ruta. Tal como está,
es una trampa.

## Qué falta, entonces

Lo único que no cubre `recalcular_contrato.dart` es **leer de Supabase en vez de
la base local**. Es la única copia que tiene los pagos de las dos PCs, así que un
informe contra la nube no necesitaría que nadie sincronice antes para ser
confiable.

- Reusar `recalcularSaldoDesdePagos`, la misma función que usan
  `recalcularProgresoContrato` y la migración v54
  (`lib/core/database/local_database.dart:2054`). **No** reescribir la
  matemática en SQL: la clasificación por concepto —plan, mesa extra, sillas
  extra, mora— es demasiado sutil, y una aproximación produciría falsas alarmas
  sobre plata, que es peor que no medir.
- Salida igual a la actual: alumno, institución, saldo guardado, saldo que dan
  sus pagos, diferencia.

Es una mejora, no una urgencia: con sincronizar antes de correr el `--dry-run`
se llega al mismo resultado.
