import '../services/productos_para_vender.dart' show paraBuscar;

/// Si un producto de la barra es una silla de la noche (6.4.0, decisión del 6-nov).
///
/// La noche de la fiesta la familia paga la silla extra en la caja de la Encargada de
/// barra, que la vende como un producto más ("Silla extra", con su precio en la
/// fiesta). Su vale **no es para el barman**: la familia lo lleva a la recepcionista,
/// que suma la silla con ese número (`SillaPuerta`) y se queda el papel.
///
/// Se sabe por el nombre, como las fotos (`FotoDeLaBarra.para`): sin columna nueva en
/// el catálogo. "Silla extra", "SILLA", "Sillas extra" lo son; "Fernet" no.
bool esSillaDeLaPuerta(String nombre) =>
    RegExp(r'(^|[^a-z])sillas?([^a-z]|$)').hasMatch(paraBuscar(nombre));

/// Si es una **silla suelta** (6.5.0, pedido del usuario el 9-nov): una silla de la
/// noche que no va a una mesa. La familia que ya tiene las 2 extra en sus mesas, o
/// que quiere una al lado o en otro lugar, la compra igual. Sale una por vale, como
/// las otras, y la recepcionista la anota con SILLA SUELTA, sin tope.
///
/// "Silla suelta", "SILLAS SUELTAS" lo son; "Silla extra" no.
bool esSillaSuelta(String nombre) =>
    esSillaDeLaPuerta(nombre) &&
    RegExp(r'(^|[^a-z])sueltas?([^a-z]|$)').hasMatch(paraBuscar(nombre));
