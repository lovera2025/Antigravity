# El total de un evento particular con extras se calcula distinto según dónde

**Estado:** pendiente, sin decidir. **Fecha:** 24-oct-2026 (revisión de presupuesto → evento, en la 6.2.1).

## Qué pasa

Un renglón marcado como **extra** (opcional) no suma al total del presupuesto ni al del evento: los dos usan la
misma cuenta y coinciden (`presupuesto.dart` `total`, `detalle_evento_particular_screen.dart` `_totalContratado`).
Pero hay otros tres lugares que lo cuentan distinto:

- el Panel suma también los extras y cuenta una sola vez dos renglones idénticos (`dashboard_provider.dart:297-300`);
- el recibo PDF suma los extras en la tabla pero no en el saldo (`pdf_service.dart`, ~8208);
- el recibo que sale de Mi Empresa no tiene en cuenta la cantidad, suma los extras y cuenta los pagos anulados
  (`finanzas_provider.dart:756-761`).

## Por qué se postergó

- Toca recibos y cobros, y eso no se cambia sin que el usuario lo pida (regla de siempre).
- Hoy afecta a **un solo evento**, ya finalizado ($40.000 de extras): no hay ninguno por hacerse con extras.

## Si se retoma

Una sola cuenta del total de un evento particular (la del evento: sin extras, precio × cantidad, sin anulados) y que
el Panel y los dos recibos la usen. Mirar antes con el usuario qué quiere que diga el recibo de un extra: si va en la
tabla "aparte" o no va.
