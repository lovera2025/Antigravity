# El repositor de la barra y el stock con reposiciones

**Estado (25-nov, tarde): EN CURSO, para la Técnica del 4-dic.** Plan aprobado, maqueta contestada y la base
programada (tablas, cuenta y tests). Todo lo decidido y lo que falta: `docs/CONTEXTO_PLAN_4DIC_2026-11-25.md`. Lo de
abajo es el pedido original.

## Qué pidió

Un permiso nuevo, **"Repositor de barra"** (él lo llamó "barra-repositor"). Solo él y el jefe tocan el stock:

- **El stock general** de la fiesta lo carga el jefe (como hoy, en PRECIOS).
- **El repositor anota cada reposición**: cuánto repuso, a qué caja, y cómo quedó el stock de cada caja. Con
  notas, "dará detalle de todo". Ejemplo del usuario: hubo tantas cervezas, y si faltan dos es porque se
  congelaron. Tiene que quedar escrito.
- **La encargada de barra ya no toca nada del stock.** Ve todas las cajas y cuánto hizo cada una, y acepta el
  cierre de cada caja (el OK de la 6.6.0). Nada más.

## Cómo está hoy (6.9.3)

- El stock es uno por producto y por fiesta: lo que cargó el jefe en PRECIOS (`barra_precios`, "inicial" y
  "aviso") menos lo vendido sin anular (`StockDeLaBarra`, `cuentas/stock_de_la_barra.dart`). **No frena la venta,
  avisa.**
- No hay reposiciones, ni stock por caja, ni notas.
- La encargada (Barra con un 2 en `permisos_operador.barra`) ve el stock en LAS CAJAS y no lo carga: PRECIOS va con
  `esRolJefeProvider`. **Verificar con él** si ve algo que le deja cambiarlo; él entiende que hoy la encargada lo
  toca.

## Lo que hay que decidir con él (plan y maqueta antes de programar)

- Dónde entra el repositor: con su PIN, como la encargada (otro valor en `permisos_operador.barra`, sin SQL) o un
  permiso aparte.
- **El stock por caja:** ¿cada caja tiene el suyo (lo que se le dio menos lo que vendió) y el general es lo que
  queda en el depósito? ¿La reposición pasa del general a una caja?
- **Las notas:** ¿una por reposición, por producto, o un "ajuste" aparte (faltante, roto, congelado) que resta
  sin ser venta?
- Qué ve el jefe y qué sale en el cierre de la fiesta (stock inicial, repuesto, vendido, ajustes, final).
- **Los datos: solo tablas nuevas** (reposiciones y ajustes, solo se agregan renglones), con su SQL antes de
  instalar. La venta no cambia.
- Que funcione sin internet por la central de la barra (`tablasDeLaRed`).
