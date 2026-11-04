# La 6.3.1: las entradas sin cargo son solo las de la mesa del contrato

4-nov-2026. Rama `feature/v4.6-cierre-por-sesiones`. Sale sobre la 6.3.0 (`docs/CONTEXTO_v6.3.0_2026-11-02.md`), publicada el mismo
día. **Sin SQL y sin migración.**

## Qué pasó

El usuario miró ENTRADAS de Puerto Viejo y vio "0 de 280". Él contaba 21 alumnos por 8 entradas: 168. La diferencia eran las 14
mesas adicionales (8 lugares cada una). Aclaró la regla:

> "la mesa de contrato, la que trae una mesa con 8 sillas, se le dan 8 entradas 'gratis' podríamos decir... la mesa adicional tiene
> un valor $70.000, mesa con 8 sillas misma que la de contrato, salvo que esas entradas no se le dan gratis: tiene que pagar el 50 % su
> valor original... lo mismo con las sillas extras."

Los $10.000 de la entrada que usó fueron un ejemplo: **el precio de la entrada todavía no se sabe**.

**Hasta la 6.3.0 el retiro daba sin cargo las entradas de todos los lugares**: GAUNA, GERALDINE, con 4 mesas adicionales, se habría
llevado 40. **No se había entregado ninguna** (`entradas_retiro` vacía en la nube el 4-nov), así que no hay nada que corregir en los
datos.

## Qué cambia

| | Antes | Ahora |
|---|---|---|
| Lo que se entrega en la oficina | VIP + generales de todos los lugares | VIP + generales de la mesa del contrato (8) |
| La mesa adicional y las sillas extra | entraban en las generales | "al 50 %, se compran aparte": no se entregan |
| Arriba, en ENTRADAS | "Entradas entregadas: 0 de 280" | "Sin cargo entregadas: 0 de 168" y "Al 50 %, aparte: 112" |
| Cada familia | "mesa 12 · 16 entradas (3 VIP + 13 generales)" | "mesa 12 · 8 sin cargo (3 VIP + 5 generales) · 8 al 50 %" |
| El diálogo de entrega | — | "Las 8 entradas de su mesa adicional no van sin cargo: se compran aparte, al 50 %." |
| La planilla de entrega en papel | — | columna "Al 50 %", el total en el encabezado y la explicación en el pie |

Todo sale de `EntradasDeAlumno` (`eventos/services/retiro_entradas.dart`): `generales` son las sin cargo que no son VIP,
`sinCargo` = VIP + generales, `alCincuenta` = los lugares que pasan de la mesa del contrato. **Si una familia tiene más VIP que los 8
de su mesa (con excepción), los que sobran ocupan primero la adicional, sin cobrarles la entrada:** su cena ya está en la cuenta.

**No se guarda nada nuevo.** La entrega guarda VIP y generales como antes (las generales ahora son menos), y "al 50 %" se calcula de la
cuenta del alumno en cada PC.

**Lo que no hace: cobrar las del 50 %.** Hasta que esté la venta de entradas (sección 8 de `docs/PLAN_MODO_ENTRADAS_2026-10-30.md`)
se venden a mano, fuera de la app; la pantalla dice cuántas puede comprar cada familia. El precio lo ponen ellos por fiesta cuando
salga.

## Pruebas

- `test/retiro_entradas_test.dart`: la cuenta con mesa adicional, con sillas extra (también en la mesa del contrato), con 4
  adicionales, con más VIP que la mesa del contrato, y **Puerto Viejo entero: 168 sin cargo y 112 al 50 %**; comprar una silla
  después de retirar ya no deja entradas pendientes (esa va al 50 %); sumar un acompañante sí (un VIP más, una general menos).
- `test/entrega_entradas_dialog_test.dart`: el diálogo muestra 5 generales y el aviso de las 11 al 50 %; el talonario pide 5 números.
- **Roturas a propósito, vistas en rojo:** las generales de todos los lugares (10 tests), el total con todos los lugares y la columna de
  la planilla en cero.
- **La planilla de muestra** (`tool/planilla_entrega_muestra_test.dart`), mirada en el navegador: la columna entra, "RETIRÓ" y
  "Hermano/a mayor" siguen en un renglón y una división de 26 sigue entrando en una hoja.
