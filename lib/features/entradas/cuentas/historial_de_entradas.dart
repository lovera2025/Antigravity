import '../../../models/entradas_retiro.dart';
import '../datos/entradas_repositorio.dart';
import 'cierre_de_entradas.dart';
import 'lugares_de_la_familia.dart';
import 'numeros_de_entradas.dart';

/// Qué ventas se miran en VENTAS.
enum FiltroDeVentas {
  todas('Todas'),
  verificadas('Verificadas'),
  sinVerificar('Sin verificar');

  const FiltroDeVentas(this.rotulo);
  final String rotulo;
}

/// Una venta en el historial, con lo que le pasó después: si el jefe la anuló
/// y si tildó "Pago verificado". La venta misma nunca cambia.
class VentaDelHistorial {
  final VentaEntradas venta;
  final AnulacionEntradas? anulacion;
  final VerificacionEntradas? verificacion;

  /// La caja donde se hizo. Null si todavía no bajó a este equipo.
  final CajaEntradas? caja;

  const VentaDelHistorial({
    required this.venta,
    this.anulacion,
    this.verificacion,
    this.caja,
  });

  bool get anulada => anulacion != null;

  /// El jefe tildó "Pago verificado". Una anulada no cuenta como verificada:
  /// ya no hay pago que mirar.
  bool get verificada => !anulada && (verificacion?.verificado ?? false);

  /// Quién vendió: el de la venta, o el de su caja.
  String get vendio =>
      (venta.hechoPor ?? '').isNotEmpty ? venta.hechoPor! : (caja?.operadorNombre ?? '');

  bool entraEn(FiltroDeVentas filtro) => switch (filtro) {
        FiltroDeVentas.todas => true,
        FiltroDeVentas.verificadas => verificada,
        // Una anulada no espera verificación.
        FiltroDeVentas.sinVerificar => !anulada && !verificada,
      };
}

/// El historial de ventas de entradas de una fiesta (VENTAS, sección 8 del spec
/// del 13-nov): cada venta con su anulación y su verificación, los totales y
/// los números del talonario que quedaron repetidos.
///
/// **Quien vende ve las de su caja; el jefe, todas las de la fiesta.** Lo
/// decide quien lo arma, con [soloDeLaCaja].
class HistorialDeEntradas {
  /// De la más nueva a la más vieja.
  final List<VentaDelHistorial> ventas;

  /// Las cuentas de lo que se muestra (una caja, o toda la fiesta).
  final CierreDeEntradas totales;

  /// Los números anotados dos veces. **Se buscan en toda la fiesta**, aunque
  /// se mire una sola caja: el choque puede ser con la venta de otro equipo.
  final List<NumeroRepetido> repetidos;

  const HistorialDeEntradas({
    required this.ventas,
    required this.totales,
    this.repetidos = const [],
  });

  factory HistorialDeEntradas.de({
    required Iterable<CajaEntradas> cajas,
    required Iterable<VentaEntradas> ventas,
    required Iterable<AnulacionEntradas> anulaciones,
    Iterable<VerificacionEntradas> verificaciones = const [],
    Map<String, List<TramoTalonario>> entregados = const {},
    String? soloDeLaCaja,
  }) {
    final todas = ventas.toList();
    final listaAnulaciones = anulaciones.toList();
    final listaCajas = cajas.toList();
    final anuladas = anulacionesPorVenta(listaAnulaciones);
    final verificadas = {for (final v in verificaciones) v.ventaId: v};
    final porId = {for (final c in listaCajas) c.id: c};
    final lista = [
      for (final v in todas)
        if (soloDeLaCaja == null || v.cajaEntradasId == soloDeLaCaja)
          VentaDelHistorial(
            venta: v,
            anulacion: anuladas[v.id],
            verificacion: verificadas[v.id],
            caja: porId[v.cajaEntradasId],
          ),
    ]..sort((a, b) {
        final n = b.venta.createdAt.compareTo(a.venta.createdAt);
        return n != 0 ? n : b.venta.numero.compareTo(a.venta.numero);
      });
    final laCaja = soloDeLaCaja == null ? null : porId[soloDeLaCaja];
    return HistorialDeEntradas(
      ventas: List.unmodifiable(lista),
      totales: laCaja != null
          ? CierreDeEntradas.de(laCaja, todas, listaAnulaciones)
          : CierreDeEntradas.deLaFiesta(
              listaCajas,
              [for (final x in lista) x.venta],
              listaAnulaciones,
            ),
      repetidos: NumerosDeEntradas.repetidos(
        ventas: todas,
        anulaciones: listaAnulaciones,
        entregados: entregados,
      ),
    );
  }

  List<VentaDelHistorial> con(FiltroDeVentas filtro) =>
      [for (final v in ventas) if (v.entraEn(filtro)) v];

  /// Las que cuentan (sin las anuladas) y ya tienen el pago verificado.
  int get verificadas => ventas.where((v) => v.verificada).length;

  /// Las que cuentan y todavía esperan que el jefe mire la cuenta.
  int get sinVerificar =>
      ventas.where((v) => !v.anulada && !v.verificada).length;
}
