import '../datos/barra_repositorio.dart';

/// Una bebida de un vale: cuántas y cuál, con el nombre de la venta.
class BebidaDelVale {
  final int cantidad;
  final String nombre;

  const BebidaDelVale(this.cantidad, this.nombre);

  @override
  bool operator ==(Object other) =>
      other is BebidaDelVale && other.cantidad == cantidad && other.nombre == nombre;

  @override
  int get hashCode => Object.hash(cantidad, nombre);
}

/// Un vale de la barra: el papel que el barman entrega y **se queda**. Sale uno solo
/// por papel, sin precios: lo cobrado está en la venta.
///
/// - **Todo junto:** un vale con todas las bebidas de la compra, para quien retira todo
///   de una vez.
/// - **Por separado:** para ir retirando de a poco. Cada bebida tiene su "vale por": 10
///   cervezas y "vale por 3" son 4 vales, de 3, 3, 3 y 1.
class Vale {
  final List<BebidaDelVale> bebidas;
  final bool porSeparado;

  /// "1 de 4": el lugar de este vale entre los de su bebida (o 1 de 1, todo junto).
  final int numero;
  final int de;

  const Vale({
    required this.bebidas,
    required this.porSeparado,
    this.numero = 1,
    this.de = 1,
  });

  /// Un solo vale con todo lo de la venta.
  factory Vale.todoJunto(VentaBarra venta) => Vale(
        bebidas: [for (final r in venta.renglones) BebidaDelVale(r.cantidad, r.nombre)],
        porSeparado: false,
      );

  /// Los vales de una bebida comprada por separado. Sin [valePor], uno con todas.
  static List<Vale> porSeparadoDe(RenglonVenta renglon, {int? valePor}) {
    final partes = partirEnVales(renglon.cantidad, valePor);
    return [
      for (var i = 0; i < partes.length; i++)
        Vale(
          bebidas: [BebidaDelVale(partes[i], renglon.nombre)],
          porSeparado: true,
          numero: i + 1,
          de: partes.length,
        ),
    ];
  }
}

/// Si "vale por [valePor]" sirve para [cantidad] bebidas: vacío (un vale con todas), o
/// de 1 a la cantidad.
bool valePorValido(int cantidad, int? valePor) =>
    valePor == null || (valePor >= 1 && valePor <= cantidad);

/// Por cuánto vale cada vale: 10 y "vale por 3" da 3, 3, 3 y 1 (el último con lo que
/// sobra). Sin [valePor], un vale con todas. Un "vale por" que no sirve es un error del
/// programa: la pantalla no lo deja pasar.
List<int> partirEnVales(int cantidad, int? valePor) {
  if (cantidad < 1) {
    throw ArgumentError.value(cantidad, 'cantidad', 'va de 1 en adelante');
  }
  if (!valePorValido(cantidad, valePor)) {
    throw ArgumentError.value(valePor, 'valePor', 'va de 1 a $cantidad');
  }
  final cada = valePor ?? cantidad;
  return [
    for (var quedan = cantidad; quedan > 0; quedan -= cada) quedan < cada ? quedan : cada,
  ];
}

/// La reimpresión de un vale: sale con COPIA arriba y abajo, con quién, cuándo y por qué.
class CopiaDeVale {
  /// 1 la primera copia, 2 la segunda...
  final int numero;
  final String createdAt;
  final String? hechoPor;
  final String motivo;

  const CopiaDeVale({
    required this.numero,
    required this.createdAt,
    this.hechoPor,
    required this.motivo,
  });
}
