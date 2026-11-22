import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/entradas_retiro.dart';
import '../../barra/cuentas/pesos.dart';
import '../../common/utils/currency_extensions.dart' show numeroALetras;
import '../cuentas/para_rendir.dart' show BloqueParaRendir;
import '../datos/entradas_repositorio.dart';
import 'recibo_de_entradas_pdf.dart';

/// Lo que el comprobante de una **rendición** de entradas para rendir dice de
/// lo que se llevó quien rinde (21-nov-2026,
/// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 6). La plata es la
/// venta de siempre; esto es solo el renglón "Se llevó 20 (1201 al 1220) ·
/// vendió 15 · devolvió 5 (1216 al 1220) · le quedan 0", y **todo sale de
/// `BloqueParaRendir`**: acá no hay cuentas.
class RendicionDelComprobante {
  /// Quién rinde.
  final String persona;

  /// Lo que se llevó: recién rendida, cómo quedó en ese acto; reimpresa, cómo
  /// está en este equipo el día [alDia]. Null: todavía no bajó (o no se pudo
  /// leer); el papel sale con quién rinde y lo vendido, sin el renglón del
  /// bloque.
  final BloqueParaRendir? bloque;

  /// Cuántas devolvió **en esta misma rendición**, con sus números. Null: no se
  /// sabe con certeza (al reimprimir): el renglón no lo dice.
  final int? devolvio;
  final List<TramoTalonario> numerosDevueltos;

  /// Reimpresa: el día en que se saca la copia, en el reloj de Argentina (el
  /// de `hoyEnArgentinaProvider`). Lo que le queda es de ese día, y el papel lo
  /// dice con la fecha ("al 22/11 le quedan 0"): la única fecha de arriba es
  /// la de la rendición, y un "hoy" solo se leería como ese día (22-nov-2026).
  /// Null: recién rendida.
  final DateTime? alDia;

  /// Reimpresa: lo que le queda es del día [alDia], no del de la rendición.
  bool get leQuedanDeHoy => alDia != null;

  /// Recién rendida: lo que devolvió en ese acto se sabe, y "le quedan" es lo
  /// que quedó después. [bloque] es **cómo quedó en ese acto** (lo lee VENDER
  /// una vez, al guardar), no cómo está cuando se saca el papel.
  const RendicionDelComprobante.alRendir({
    required this.persona,
    required this.bloque,
    required int this.devolvio,
    this.numerosDevueltos = const [],
  }) : alDia = null;

  /// Reimpresa desde VENTAS: no se sabe con certeza qué devolvió en ese mismo
  /// acto, así que dice solo lo seguro (se llevó, lo que vendió en esta
  /// rendición y lo que le queda el día [alDia], en que se reimprime).
  const RendicionDelComprobante.reimpresa({
    required this.persona,
    this.bloque,
    required DateTime this.alDia,
  })  : devolvio = null,
        numerosDevueltos = const [];
}

/// Lo que lleva el comprobante de una venta de entradas, además de la venta.
class DatosDelComprobante {
  final VentaEntradas venta;

  /// La escuela (la institución de la fiesta).
  final String fiesta;
  final DateTime? fechaFiesta;

  /// Si compra una familia de la fiesta: el alumno y su mesa ("14 y 15").
  final String? alumno;
  final String? mesa;

  /// Reimpreso: dice COPIA.
  final bool copia;

  /// Anulada: va ANULADA cruzado, con el motivo.
  final AnulacionEntradas? anulacion;

  /// La venta es la plata de una rendición de entradas para rendir: el papel es
  /// el de la rendición (el recibo de quien rinde, con "Rinde" y "Recibió").
  final RendicionDelComprobante? rendicion;

  const DatosDelComprobante({
    required this.venta,
    required this.fiesta,
    this.fechaFiesta,
    this.alumno,
    this.mesa,
    this.copia = false,
    this.anulacion,
    this.rendicion,
  });
}

/// El comprobante de una venta de entradas, **con la forma del "RECIBO DE
/// PAGO" de las cuotas, tal cual** (22-nov-2026, [ReciboDeEntradasPdf]): media
/// hoja A4, "Recibí de" quien compra, "La suma de pesos" lo cobrado, "Concepto:"
/// con lo vendido renglón por renglón y los números del talonario, y el
/// recuadro "TOTAL DE ESTE RECIBO" con el medio de pago (sección 7.4 del spec
/// del 13-nov). **No habla de pulseras**: la pulsera no se vende (el usuario,
/// 20-nov-2026); las VIP se entregan sin cargo, aparte.
///
/// Con [DatosDelComprobante.rendicion] es el de una **rendición** de entradas
/// para rendir: el mismo recibo, de quien rinde, con lo que se llevó, quién
/// recibió la plata y quién rinde (21-nov-2026).
///
/// Todo lo que dice sale de la venta como quedó guardada: no hace ninguna
/// cuenta (el total, el recargo y el vuelto ya están en la fila).
class ComprobanteEntradasPdf {
  ComprobanteEntradasPdf._();

  static String numero(VentaEntradas v) =>
      'N° ${v.numero.toString().padLeft(4, '0')}';

  /// "14/11/2026 11:32 hs", en hora de Argentina. Vacío si no se entiende.
  static String cuando(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null
        ? ''
        : '${ArTime.formatFechaCorta(t)} ${ArTime.formatHora(t)}';
  }

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  static String _pct(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  /// Lo que dice un renglón a la izquierda: "8 × Entrada · $ 10.000 c/u".
  static String renglon(RenglonEntradas r) {
    final descuento = r.tipo == TipoRenglonEntradas.suelta && r.descuentoPct > 0
        ? ' · descuento ${_pct(r.descuentoPct)} %'
        : '';
    return '${r.cantidad} × ${r.nombre} · ${pesos(r.precio)} c/u$descuento';
  }

  /// Cómo pagó, en palabras. En el mixto, cuánto de cada uno.
  static String comoPago(VentaEntradas v) => switch (v.medio) {
        MedioBarra.efectivo => 'Efectivo',
        MedioBarra.transferencia => 'Transferencia',
        MedioBarra.mixto =>
          'Mixto · efectivo ${pesos(v.efectivo)} · transferencia ${pesos(v.transferencia)}',
        MedioBarra.otro => '—',
      };

  /// Lo que dice el recibo debajo del total: "Medio de pago: Efectivo",
  /// "Medio de pago: Mixto (efectivo $ 10.000 · transferencia $ 50.500)".
  static String medioDePago(VentaEntradas v) => 'Medio de pago: ${switch (v.medio) {
        MedioBarra.efectivo => 'Efectivo',
        MedioBarra.transferencia => 'Transferencia',
        MedioBarra.mixto =>
          'Mixto (efectivo ${pesos(v.efectivo)} · transferencia ${pesos(v.transferencia)})',
        MedioBarra.otro => '—',
      }}';

  /// Los números del talonario, o null si no se anotaron.
  static String? talonario(VentaEntradas v) {
    final tramos = TramoTalonario.deTexto(v.numeros);
    return tramos.isEmpty ? null : TramoTalonario.legible(tramos);
  }

  /// "16/11", en hora de Argentina. Vacío si no se entiende.
  static String _diaYMes(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null ? '' : ArTime.formatFechaCorta(t).substring(0, 5);
  }

  /// "22/11", de un momento que ya viene en el reloj de Argentina (el de
  /// `hoyEnArgentinaProvider`): se leen sus números, sin volver a correrlo.
  static String diaYMesDeArgentina(DateTime ar) =>
      '${ar.day.toString().padLeft(2, '0')}/${ar.month.toString().padLeft(2, '0')}';

  /// El renglón de cómo quedó lo que se llevó quien rinde: "Se llevó 20 (1201
  /// al 1220) el 16/11 · vendió 15 · devolvió 5 (1216 al 1220) · le quedan 0".
  /// [vendio]: lo de esta rendición (la cantidad de su venta). Reimpresa, sin
  /// lo devuelto (no se sabe con certeza) y con el día de la copia: "al 22/11
  /// le quedan 0". Null si el bloque todavía no está en este equipo: no se
  /// inventa.
  static String? lineaDeLaRendicion(RendicionDelComprobante r, int vendio) {
    final b = r.bloque;
    if (b == null) return null;
    final dia = _diaYMes(b.dadoAt);
    final devolvio = r.devolvio;
    final alDia = r.alDia;
    return [
      'Se llevó ${b.cantidad} (${TramoTalonario.legible(b.tramos)})'
          '${dia.isEmpty ? '' : ' el $dia'}',
      alDia != null ? 'vendió $vendio en esta rendición' : 'vendió $vendio',
      if (devolvio != null && devolvio > 0)
        r.numerosDevueltos.isEmpty
            ? 'devolvió $devolvio'
            : 'devolvió $devolvio (${TramoTalonario.legible(r.numerosDevueltos)})',
      alDia != null
          ? 'al ${diaYMesDeArgentina(alDia)} le quedan ${b.sinRendir}'
          : 'le quedan ${b.sinRendir}',
    ].join(' · ');
  }

  /// Lo que dice el papel de una rendición anulada: la plata se devolvió y
  /// esas entradas dejaron de contar como vendidas (vuelven a quedar a cargo
  /// de quien las llevó). Nunca "devolvieron las entradas": no volvió nada a
  /// la oficina.
  static String _rendicionAnulada(int cantidad) => cantidad == 1
      ? 'la entrada dejó de contar como vendida'
      : 'las $cantidad dejaron de contar como vendidas';

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    DatosDelComprobante d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) =>
      ReciboDeEntradasPdf.armar(contenido(d), fuentes: fuentes, logo: logo);

  /// Lo que dice el papel, con la forma del recibo de las cuotas: de quién se
  /// recibió, la suma, el concepto con sus renglones, el total y el pie.
  static ContenidoDelRecibo contenido(DatosDelComprobante d) {
    final v = d.venta;
    final rinde = d.rendicion;
    final anulacion = d.anulacion;
    final fiesta = [
      d.fiesta.trim().toUpperCase(),
      if (d.fechaFiesta != null) 'fiesta ${_dia(d.fechaFiesta!)}',
    ].where((s) => s.isNotEmpty).join(' · ');

    final renglones = [
      for (final r in v.renglones)
        RenglonDelRecibo(
          rinde == null ? renglon(r) : '${renglon(r)} · precio fijo',
          monto: pesos(r.subtotal),
        ),
      if (v.renglones.isEmpty)
        RenglonDelRecibo('${v.cantidad} entradas', monto: pesos(v.total)),
      if (v.recargo > 0)
        RenglonDelRecibo(
          v.recargoPct == null
              ? 'Recargo por transferencia'
              : 'Recargo por transferencia (${_pct(v.recargoPct!)} %)',
          monto: pesos(v.recargo),
        ),
    ];
    final enElTotal = [
      medioDePago(v),
      if (v.recibe != null && v.vuelto > 0)
        'Entregó ${pesos(v.recibe!)} · Vuelto ${pesos(v.vuelto)}',
    ];
    final enRojo = [
      if (anulacion != null)
        'ANULADA el ${cuando(anulacion.createdAt)}'
            '${(anulacion.hechoPor ?? '').isEmpty ? '' : ' por ${anulacion.hechoPor}'}'
            ' · ${anulacion.motivo} · '
            '${rinde != null ? _rendicionAnulada(v.cantidad) : anulacion.devueltas ? 'devolvieron las entradas' : 'NO devolvieron las entradas'}',
    ];

    if (rinde == null) {
      final numeros = talonario(v);
      final familia = (d.alumno ?? '').trim();
      final mesa = (d.mesa ?? '').trim();
      final vendio = (v.hechoPor ?? '').trim();
      return ContenidoDelRecibo(
        titulo: 'RECIBO DE PAGO',
        bajoElTitulo: numero(v),
        copia: d.copia,
        fecha: cuando(v.createdAt),
        recibiDe: v.compradorNombre,
        alLadoDelNombre: v.compradorDni == null ? null : ' · DNI ${v.compradorDni}',
        sumaEnLetras: numeroALetras(v.cobrado),
        concepto: 'Entradas · $fiesta',
        debajoDelConcepto: [
          if (familia.isNotEmpty)
            mesa.isEmpty ? 'Familia: $familia' : 'Familia: $familia · mesa $mesa',
        ],
        renglones: renglones,
        // Lo vendido son solo entradas: la pulsera no se vende (20-nov-2026).
        notas: [
          '${v.cantidad == 1 ? '1 entrada' : '${v.cantidad} entradas'} · '
              '${numeros == null ? 'Sin números del talonario anotados' : 'Talonario: $numeros'}',
        ],
        total: pesos(v.cobrado),
        enElTotal: enElTotal,
        pie: [if (vendio.isNotEmpty) 'Vendió: $vendio'],
        enRojo: enRojo,
        marcaDeAgua: anulacion == null ? null : 'ANULADA',
      );
    }

    // Una rendición: se recibe de quien rinde. La plata la recibió quien cobró
    // (el que anotó la venta) y la rinde quien se llevó las entradas. Los
    // números son los del bloque, que van en su renglón: la venta no los lleva.
    final quienRinde =
        rinde.persona.trim().isEmpty ? v.compradorNombre : rinde.persona.trim();
    final recibio = (v.hechoPor ?? '').trim();
    final delBloque = lineaDeLaRendicion(rinde, v.cantidad);
    return ContenidoDelRecibo(
      titulo: 'RECIBO DE PAGO',
      bajoElTitulo: numero(v),
      copia: d.copia,
      fecha: cuando(v.createdAt),
      recibiDe: quienRinde,
      sumaEnLetras: numeroALetras(v.cobrado),
      concepto: 'Rendición de entradas para rendir · $fiesta',
      renglones: renglones,
      notas: [?delBloque],
      total: pesos(v.cobrado),
      enElTotal: enElTotal,
      pie: ['Rinde: $quienRinde${recibio.isEmpty ? '' : ' · Recibió: $recibio'}'],
      enRojo: enRojo,
      marcaDeAgua: anulacion == null ? null : 'ANULADA',
    );
  }

  /// Cómo se llama el archivo. El de una rendición, "Rendicion_0007_…".
  static String nombreDelArchivo(DatosDelComprobante d) {
    final limpio = d.venta.compradorNombre
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final que = d.rendicion == null ? 'Entradas' : 'Rendicion';
    return '${que}_${d.venta.numero.toString().padLeft(4, '0')}_$limpio.pdf';
  }
}
