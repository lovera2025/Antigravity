# Corregir cuántas entradas para rendir se le dieron a alguien

**Estado:** pedido por el usuario el 25-nov-2026, después de equivocarse ese día. Sin plan. Va después de la tele en
la app de verdad.

## Qué pidió

Hoy, en modo jefe, si se le dan a alguien entradas para rendir con un error (otra cantidad), hay que **anular y
cargar de nuevo**. Quiere poder **corregir** cuántas se le dieron a "x" persona.

## Lo que hay que respetar

- `entradas_para_rendir` **solo agrega renglones** (`dio`, `vendio`, `devolvio`, `no_volvieron`, `anulo`): una
  corrección tiene que ser otro renglón (por ejemplo, uno que agregue o quite entradas del bloque), nunca editar el
  `dio`.
- Los números reservados del bloque y el precio fijo del día en que se las llevó: qué pasa con ellos al corregir.
- La constancia firmada: si se corrige, ¿sale otra constancia?
- Quién puede: hoy dar y anular es solo del jefe, con doble llave. Ver también
  [dar-para-rendir-desde-vender.md](dar-para-rendir-desde-vender.md).
