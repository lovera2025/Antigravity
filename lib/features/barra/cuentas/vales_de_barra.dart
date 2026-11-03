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
/// - **Por separado:** para ir retirando de a poco. La cajera arma cada vale a mano: de 10
///   cervezas, uno por 3, otro por 2... hasta que no quede ninguna.
class Vale {
  final List<BebidaDelVale> bebidas;
  final bool porSeparado;

  /// El orden del vale en la venta (por separado): sale como "N° 0017-3". Así no hay dos
  /// vales iguales, aunque sean de bebidas distintas.
  final int numero;

  const Vale({required this.bebidas, required this.porSeparado, this.numero = 1});

  /// Un solo vale con todo lo de la venta.
  factory Vale.todoJunto(VentaBarra venta) => Vale(
        bebidas: [for (final r in venta.renglones) BebidaDelVale(r.cantidad, r.nombre)],
        porSeparado: false,
      );

  /// Un vale por [cantidad] de una bebida, el [numero] de la venta. Una cantidad que no
  /// está en la bebida es un error del programa: la pantalla no la deja pasar.
  factory Vale.deUnaBebida(RenglonVenta renglon, {required int cantidad, required int numero}) {
    if (cantidad < 1 || cantidad > renglon.cantidad) {
      throw ArgumentError.value(cantidad, 'cantidad', 'va de 1 a ${renglon.cantidad}');
    }
    if (numero < 1) throw ArgumentError.value(numero, 'numero', 'va de 1 en adelante');
    return Vale(
      bebidas: [BebidaDelVale(cantidad, renglon.nombre)],
      porSeparado: true,
      numero: numero,
    );
  }
}

/// Si "vale por [valePor]" sirve cuando de una bebida [quedan] sin vale: vacío (un vale
/// por todas las que quedan), o de 1 a las que quedan.
bool valePorValido(int quedan, int? valePor) =>
    quedan > 0 && (valePor == null || (valePor >= 1 && valePor <= quedan));

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
