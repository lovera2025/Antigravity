import '../datos/barra_repositorio.dart';

/// Cuánto espera la cajera el OK antes de poder cerrar sin él.
const kEsperaDelOkDeCierre = Duration(minutes: 3);

/// En qué está el cierre de una caja: su último pedido y lo que se le contestó.
class EstadoDelCierre {
  /// El último pedido de la caja. Null: nunca pidió cerrar.
  final PasoDelCierre? pedido;

  /// Lo que se le contestó a ese pedido. Null: sigue en pie.
  final PasoDelCierre? respuesta;

  const EstadoDelCierre({this.pedido, this.respuesta});

  static const nada = EstadoDelCierre();

  /// Hay un pedido y nadie lo contestó: se espera a la encargada.
  bool get esperando => pedido != null && respuesta == null;

  /// La encargada aceptó: la tablet de la cajera cierra la caja.
  bool get aceptado => respuesta?.tipo == TipoPasoDelCierre.ok;

  /// La encargada pide que cuente de nuevo.
  bool get hayQueRecontar => respuesta?.tipo == TipoPasoDelCierre.recontar;

  /// Cerró sin esperar el OK.
  bool get sinOk => respuesta?.tipo == TipoPasoDelCierre.sinOk;
}

/// Un pedido de cierre que espera el OK, con su caja: lo que ve la encargada.
class PedidoEnPie {
  final CajaBarra caja;
  final PasoDelCierre pedido;

  const PedidoEnPie(this.caja, this.pedido);
}

/// La regla del cierre con el OK de la encargada (11-nov-2026), sin pantalla ni base:
/// recibe las filas de `barra_cierres` y dice en qué está cada caja.
///
/// **No compara la hora de un equipo con la de otro** (los relojes de las tablets no
/// coinciden): una respuesta se ata a su pedido por el id, y entre pedidos de una caja
/// —que los anota siempre el mismo equipo— manda la hora de ese equipo.
abstract final class PedidoDeCierre {
  static int _porHora(PasoDelCierre a, PasoDelCierre b) {
    final n = a.createdAt.compareTo(b.createdAt);
    return n != 0 ? n : a.id.compareTo(b.id);
  }

  /// A cuál de las respuestas de un pedido se le hace caso. Lo que anotó la tablet de
  /// la cajera (volvió a vender, o cerró sin esperar) manda sobre lo que contestó otro
  /// equipo: es lo que de verdad pasó con la caja. Entre dos respuestas de la
  /// encargada, la primera.
  static int _peso(PasoDelCierre r) => switch (r.tipo) {
        TipoPasoDelCierre.cancelado || TipoPasoDelCierre.sinOk => 0,
        _ => 1,
      };

  /// En qué está el cierre de la caja [cajaId].
  static EstadoDelCierre de(String cajaId, Iterable<PasoDelCierre> pasos) {
    final suyos = [for (final p in pasos) if (p.cajaBarraId == cajaId) p];
    final pedidos = [for (final p in suyos) if (p.esPedido) p]..sort(_porHora);
    if (pedidos.isEmpty) return EstadoDelCierre.nada;
    final pedido = pedidos.last;
    final respuestas = [
      for (final p in suyos)
        // Una fila de un tipo que esta versión no conoce no contesta nada.
        if (!p.esPedido && p.tipo != null && p.pedidoId == pedido.id) p,
    ]..sort((a, b) {
        final n = _peso(a).compareTo(_peso(b));
        return n != 0 ? n : _porHora(a, b);
      });
    return EstadoDelCierre(
      pedido: pedido,
      respuesta: respuestas.isEmpty ? null : respuestas.first,
    );
  }

  /// Los pedidos que esperan el OK, **de las cajas que siguen abiertas**, por número de
  /// caja: lo que le salta a la encargada. Una caja ya cerrada no pide nada.
  static List<PedidoEnPie> enPie(Iterable<CajaBarra> cajas, Iterable<PasoDelCierre> pasos) {
    final lista = pasos.toList();
    final out = <PedidoEnPie>[];
    for (final c in cajas) {
      if (!c.abierta) continue;
      final e = de(c.id, lista);
      if (e.esperando) out.add(PedidoEnPie(c, e.pedido!));
    }
    out.sort((a, b) => a.caja.numeroCaja.compareTo(b.caja.numeroCaja));
    return out;
  }

  /// Las cajas que cerraron sin el OK de la encargada: para que el jefe las mire.
  static Set<String> cerraronSinOk(Iterable<PasoDelCierre> pasos) => {
        for (final p in pasos)
          if (p.tipo == TipoPasoDelCierre.sinOk) p.cajaBarraId,
      };

  /// Si la cajera ya puede cerrar sin esperar: pasaron [kEsperaDelOkDeCierre] desde su
  /// pedido, **por el reloj de su tablet** (que es el que anotó el pedido).
  static bool yaPuedeCerrarSinEsperar(PasoDelCierre pedido, DateTime ahora) {
    final desde = DateTime.tryParse(pedido.createdAt);
    if (desde == null) return true;
    return !ahora.toUtc().isBefore(desde.toUtc().add(kEsperaDelOkDeCierre));
  }

  /// Cuánto falta para poder cerrar sin esperar. Cero si ya se puede.
  static Duration faltaParaCerrarSinEsperar(PasoDelCierre pedido, DateTime ahora) {
    final desde = DateTime.tryParse(pedido.createdAt);
    if (desde == null) return Duration.zero;
    final falta = desde.toUtc().add(kEsperaDelOkDeCierre).difference(ahora.toUtc());
    return falta.isNegative ? Duration.zero : falta;
  }

  /// La nota con que queda la caja: la de la cajera y quién aceptó. Sin columna nueva:
  /// la nota del cierre ya existe y ya sale en el papel.
  static String notaConElOk({String? notaDeLaCajera, required String acepto}) => [
        if ((notaDeLaCajera ?? '').trim().isNotEmpty) notaDeLaCajera!.trim(),
        'Aceptó: ${acepto.trim().isEmpty ? 'la encargada' : acepto.trim()}',
      ].join(' · ');

  /// La nota de una caja que cerró sin esperar, con el motivo.
  static String notaSinElOk({String? notaDeLaCajera, required String motivo}) => [
        if ((notaDeLaCajera ?? '').trim().isNotEmpty) notaDeLaCajera!.trim(),
        '$_sinElOk${motivo.trim()}',
      ].join(' · ');

  static const _acepto = 'Aceptó: ';
  static const _sinElOk = 'Cerró sin el OK de la encargada: ';

  /// Lo que la nota de una caja dice del OK ("Aceptó: Romi", o que cerró sin él), o
  /// null si no dice nada. Es lo que no se puede perder cuando la cajera cambia su nota.
  static String? marcaDelOk(String? nota) {
    final texto = nota ?? '';
    for (final marca in [_sinElOk, _acepto]) {
      final i = texto.lastIndexOf(marca);
      if (i >= 0) return texto.substring(i).trim();
    }
    return null;
  }

  /// La nota nueva de la cajera sobre una caja ya cerrada, **sin perder quién aceptó**.
  static String? notaNueva({required String? escrita, required String? notaDeAntes}) {
    final partes = [
      if ((escrita ?? '').trim().isNotEmpty) escrita!.trim(),
      ?marcaDelOk(notaDeAntes),
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }
}
