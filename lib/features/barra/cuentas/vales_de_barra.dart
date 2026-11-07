import '../datos/barra_repositorio.dart';
import 'silla_de_la_puerta.dart';

export '../datos/vale_barra.dart' show BebidaDelVale;

/// Un vale de la barra: el papel que el barman entrega y **se queda**. Sale uno solo
/// por papel, sin precios: lo cobrado está en la venta.
///
/// - **Todo junto:** un vale con todas las bebidas de la compra, o con todo lo que quedó
///   si ya salieron algunos por separado.
/// - **Por separado:** para ir retirando de a poco. La cajera arma cada vale a mano: de 10
///   cervezas, uno por 3, otro por 2... hasta que no quede ninguna.
class Vale {
  final List<BebidaDelVale> bebidas;
  final bool porSeparado;

  /// El orden del vale en la venta: sale como "N° 0017-3". Así no hay dos vales iguales,
  /// aunque sean de bebidas distintas. Null: es el único vale de la venta ("N° 0017").
  final int? numero;

  const Vale({required this.bebidas, required this.porSeparado, this.numero});

  /// El único vale de la venta, con todo.
  factory Vale.todoJunto(VentaBarra venta) => Vale(
        bebidas: [for (final r in venta.renglones) BebidaDelVale(r.cantidad, r.nombre)],
        porSeparado: false,
      );

  /// Un vale con todo lo que quedó, después de otros por separado: el [numero] de la
  /// venta. Sin nada que quede es un error del programa.
  factory Vale.conLoQueQueda(List<BebidaDelVale> quedan, {required int numero}) {
    final bebidas = [for (final b in quedan) if (b.cantidad > 0) b];
    if (bebidas.isEmpty) throw ArgumentError.value(quedan, 'quedan', 'no queda nada');
    if (numero < 1) throw ArgumentError.value(numero, 'numero', 'va de 1 en adelante');
    return Vale(bebidas: bebidas, porSeparado: false, numero: numero);
  }

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

  /// El vale de **una** silla de la noche ([esSillaDeLaPuerta]): cada silla sale en su
  /// propio papel, así cada una tiene un número distinto para la puerta. [numero] null:
  /// es el único vale de la venta ("N° 0017").
  factory Vale.deUnaSilla(RenglonVenta renglon, {int? numero}) {
    if (numero != null && numero < 1) {
      throw ArgumentError.value(numero, 'numero', 'va de 1 en adelante');
    }
    return Vale(
      bebidas: [BebidaDelVale(1, renglon.nombre)],
      porSeparado: true,
      numero: numero,
    );
  }

  /// El vale tal como salió y quedó anotado: para la copia, que tiene que decir lo mismo.
  factory Vale.comoSalio(ValeBarra salio) => Vale(
        bebidas: salio.bebidas,
        porSeparado: salio.porSeparado,
        numero: salio.numeroVale,
      );

  /// Si es el vale de una silla: lo que dice abajo cambia (va a la recepcionista).
  bool get esDeSilla =>
      bebidas.isNotEmpty && bebidas.every((b) => esSillaDeLaPuerta(b.nombre));
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
