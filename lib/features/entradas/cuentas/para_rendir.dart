import 'dart:math';

import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../barra/cuentas/pesos.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/services/retiro_entradas.dart' show RetiroEntradas;
import '../datos/entradas_repositorio.dart';
import 'lugares_de_la_familia.dart' show anulacionesPorVenta;
import 'numeros_de_entradas.dart';
import 'pedido_de_entradas.dart' show PedidoDeEntradas;
import 'precio_de_entradas.dart';

// ── Los números como tramos, sin pasarlos a uno por uno ─────────────────────
//    (una fila rara con un tramo enorme no puede llenar la memoria).

/// [tramos] ordenados y sin pisarse: los que se pisan o se tocan van en uno.
/// Uno al revés no tiene números y se descarta.
List<TramoTalonario> _unidos(Iterable<TramoTalonario> tramos) {
  final orden = [
    for (final t in tramos)
      if (t.hasta >= t.desde) t,
  ]..sort((a, b) => a.desde.compareTo(b.desde));
  final out = <TramoTalonario>[];
  for (final t in orden) {
    if (out.isNotEmpty && t.desde <= out.last.hasta + 1) {
      final u = out.removeLast();
      out.add(TramoTalonario(u.desde, max(u.hasta, t.hasta)));
    } else {
      out.add(t);
    }
  }
  return out;
}

/// Los números de [a] que no están en [b], unidos.
List<TramoTalonario> _sin(
  Iterable<TramoTalonario> a,
  Iterable<TramoTalonario> b,
) {
  var quedan = _unidos(a);
  for (final s in _unidos(b)) {
    quedan = [
      for (final t in quedan)
        if (!t.seCruzaCon(s))
          t
        else ...[
          if (t.desde < s.desde) TramoTalonario(t.desde, s.desde - 1),
          if (t.hasta > s.hasta) TramoTalonario(s.hasta + 1, t.hasta),
        ],
    ];
  }
  return quedan;
}

bool _esta(int n, Iterable<TramoTalonario> en) =>
    en.any((t) => t.desde <= n && n <= t.hasta);

int _cuantos(Iterable<TramoTalonario> tramos) =>
    tramos.fold(0, (s, t) => s + t.cantidad);

/// Los últimos [n] números de [tramos] (unidos), como tramos.
List<TramoTalonario> _ultimos(List<TramoTalonario> tramos, int n) {
  final out = <TramoTalonario>[];
  var faltan = n;
  for (final t in tramos.reversed) {
    if (faltan <= 0) break;
    if (t.cantidad <= faltan) {
      out.insert(0, t);
      faltan -= t.cantidad;
    } else {
      out.insert(0, TramoTalonario(t.hasta - faltan + 1, t.hasta));
      faltan = 0;
    }
  }
  return out;
}

/// "1 entrada", "3 entradas".
String _entradas(int n) => n == 1 ? '1 entrada' : '$n entradas';

/// Cómo se agrupa a alguien de afuera por su nombre: minúsculas, sin acentos, y
/// lo que no es letra ni número pasa a ser un espacio ("PÉREZ, JUAN" y
/// "Perez Juan" son la misma persona).
String _nombreParaAgrupar(String nombre) => normalizarTextoBusqueda(nombre)
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// El orden en que pasaron las cosas, el mismo en todos los equipos: por la
/// hora y, a la misma hora, por el id (como `EntradasLocal`: `created_at, id`).
int _enOrden(MovimientoParaRendir a, MovimientoParaRendir b) {
  final porHora = a.createdAt.compareTo(b.createdAt);
  return porHora != 0 ? porHora : a.id.compareTo(b.id);
}

/// Un renglón de lo que pasó con un bloque: lo que rindió (`vendio`), lo que
/// devolvió o lo que no volvió, con si hoy cuenta y por qué no.
class MovimientoDelBloque {
  final MovimientoParaRendir movimiento;

  /// El renglón `anulo` que lo anuló (un "devolvió" o un "no volvieron"), o
  /// null. **Lo vendido no se anula acá**: ver [anulacionDeLaVenta].
  final MovimientoParaRendir? anulacion;

  /// Lo vendido: su venta, si ya está en este equipo. Null: todavía no bajó
  /// (la plata está en camino) o el renglón no la nombra.
  final VentaEntradas? venta;

  /// Lo vendido: la anulación de su venta en VENTAS. Esas entradas vuelven a
  /// quedar a cargo de quien las llevó.
  final AnulacionEntradas? anulacionDeLaVenta;

  /// Si hoy cuenta para el bloque: lo vendido cuya venta no se anuló, y lo
  /// devuelto o perdido sin anular. Es lo mismo que dice
  /// `MovimientoParaRendir.vigentesDe`, el freno del repositorio.
  final bool cuenta;

  const MovimientoDelBloque._({
    required this.movimiento,
    required this.anulacion,
    required this.venta,
    required this.anulacionDeLaVenta,
    required this.cuenta,
  });

  QueParaRendir? get que => movimiento.que;
  int get cantidad => movimiento.cantidad;
  List<TramoTalonario> get tramos => movimiento.tramos;

  /// Lo vendido que cuenta y cuya venta todavía no está en este equipo: la
  /// plata está en camino (otro equipo la cobró y todavía no subió o no bajó).
  bool get plataEnCamino => cuenta && movimiento.esVendio && venta == null;
}

/// Un bloque de entradas para rendir (uno por cada `dio`): lo que se llevó
/// alguien, lo que rindió, lo que devolvió, lo que no volvió y lo que le queda.
///
/// **Toda cuenta mira qué es cada renglón antes de sumar** (revisión del
/// 20-nov-2026): la cantidad de un `anulo` no es de nadie, y los números del
/// bloque salen de su `dio` y de sus devueltas y perdidas que cuentan, nunca de
/// juntar los números de todos los renglones del bloque.
///
/// **El precio es el del día en que se las llevó** ([precioDeCadaUna]): nunca
/// se vuelve a leer de PRECIOS, que se sobrescribe.
class BloqueParaRendir {
  /// El renglón `dio`: a quién, cuántas, qué números y a qué precio.
  final MovimientoParaRendir dio;

  /// El `anulo` del bloque, o null. Un bloque anulado no tiene nada para
  /// rendir ni ocupa ningún número.
  final MovimientoParaRendir? anulacion;

  /// Lo que pasó después, en orden: lo rendido, lo devuelto y lo que no
  /// volvió (las anulaciones van adentro de cada uno).
  final List<MovimientoDelBloque> movimientos;

  /// Lo vendido que cuenta: el de las ventas que no se anularon (también la que
  /// todavía no bajó: ver [plataEnCamino]).
  final int vendidas;

  /// Lo devuelto sin anular.
  final int devueltas;

  /// Lo que no volvió, sin anular.
  final int noVolvieron;

  /// La plata de lo vendido que cuenta: lo de su venta, o, si todavía no bajó,
  /// las que vendió al precio del bloque. Sin recargos.
  final double plataRendida;

  /// Los números del bloque, unidos.
  final List<TramoTalonario> tramos;

  /// Los números que devolvió (sin anular): esos quedan libres.
  final List<TramoTalonario> numerosDevueltos;

  /// Los números de lo que no volvió, si se anotaron (sin anular): siguen
  /// ocupados. Si aparecen, el jefe anula ese "no volvieron" y vuelven a
  /// [numerosQueTiene].
  final List<TramoTalonario> numerosNoVolvieron;

  /// Los números que nadie más puede vender ni dar: los del bloque menos los
  /// devueltos. **Lo vendido y lo que no volvió siguen ocupados**, y un bloque
  /// anulado no ocupa nada.
  final List<TramoTalonario> numerosOcupados;

  /// Los números que todavía puede devolver: los del bloque menos los
  /// devueltos y los que no volvieron. (Lo vendido no lleva números: sigue acá
  /// hasta que devuelva el resto.)
  final List<TramoTalonario> numerosQueTiene;

  const BloqueParaRendir._({
    required this.dio,
    required this.anulacion,
    required this.movimientos,
    required this.vendidas,
    required this.devueltas,
    required this.noVolvieron,
    required this.plataRendida,
    required this.tramos,
    required this.numerosDevueltos,
    required this.numerosNoVolvieron,
    required this.numerosOcupados,
    required this.numerosQueTiene,
  });

  String get id => dio.id;

  /// Quién se las llevó: el nombre del alumno o el que se escribió.
  String get persona => dio.personaNombre ?? '';
  String? get contacto => dio.personaContacto;

  /// Si se las llevó un alumno de la fiesta. Solo para mostrar y agrupar: lo
  /// que rinde **nunca** va a su familia.
  String? get contratoAlumnoId => dio.contratoAlumnoId;
  bool get esDeUnAlumno => contratoAlumnoId != null;

  /// Las que se llevó.
  int get cantidad => dio.cantidad;

  /// Cuándo se las llevó (como se guardó).
  String get dadoAt => dio.createdAt;

  /// El nombre del precio del día en que se las llevó ("Entrada anticipada").
  String? get nombrePrecio => dio.nombrePrecio;

  bool get tienePrecio => (dio.precio ?? 0) > 0;

  /// Lo que rinde por cada una: el precio del día en que se las llevó, sin
  /// descuento ni comisión. Es lo que cobra la rendición ([ParaRendir.renglon]).
  double get precioDeCadaUna => RenglonEntradas.precioCon(dio.precio ?? 0, 0);

  bool get anulado => anulacion != null;

  int get _rendidas => vendidas + devueltas + noVolvieron;

  /// Las que le quedan sin rendir. **Nunca menos de 0** (si rindió de más, lo
  /// dice [rindioDeMas]), y 0 en un bloque anulado. Da lo mismo que
  /// `MovimientoParaRendir.quedanSinRendir`, el freno del repositorio.
  int get sinRendir => anulado ? 0 : max(0, cantidad - _rendidas);

  /// Cuántas rindió por encima de las que se llevó (dos equipos rindieron lo
  /// mismo sin internet). **Se avisa, no se esconde.**
  int get rindioDeMas => anulado ? 0 : max(0, _rendidas - cantidad);

  /// Las que le quedarían sin rendir si [cuantas] de lo vendido dejaran de
  /// contar: anular en VENTAS una rendición que todavía cuenta (21-nov-2026).
  /// **Si rindió de más, lo de más se descuenta primero**: con 20 y dos
  /// rendiciones de 15 (dos equipos sin internet), anular una deja 5 sin
  /// rendir, no 15. 0 en un bloque anulado.
  int sinRendirSiDejanDeContar(int cuantas) =>
      anulado ? 0 : max(0, cantidad - _rendidas + cuantas);

  /// Si rindió justo lo que se llevó. Quien rindió de más no "rindió todo":
  /// tiene algo para revisar ([rindioDeMas]).
  bool get rindioTodo => !anulado && sinRendir == 0 && rindioDeMas == 0;

  /// Lo máximo que podría deber: las que le quedan al precio del bloque. Es
  /// "hasta", no plata segura: puede devolverlas.
  double get plataQueFalta =>
      deCentavos(sinRendir * centavos(precioDeCadaUna));

  /// Lo que valían las que no volvieron. No entra: es lo que se perdió.
  double get plataNoVolvio =>
      deCentavos(noVolvieron * centavos(precioDeCadaUna));

  /// Si algo de lo rendido se cobró en otro equipo y su venta todavía no está
  /// en este.
  bool get plataEnCamino => movimientos.any((m) => m.plataEnCamino);

  /// Si tiene algo que cuenta (vendido, devuelto o perdido): así no se anula
  /// el bloque entero.
  bool get tieneMovimientos => movimientos.any((m) => m.cuenta);
}

/// Una persona con entradas para rendir: todos sus bloques juntos.
class PersonaParaRendir {
  /// Cómo se la agrupa: el alumno, o el nombre de alguien de afuera.
  final String clave;

  /// Sus bloques, el más viejo primero (también los anulados, para la
  /// historia; las cuentas de acá no los suman).
  final List<BloqueParaRendir> bloques;

  const PersonaParaRendir._(this.clave, this.bloques);

  /// El nombre del bloque más nuevo.
  String get nombre => bloques.last.persona;

  String? get contratoAlumnoId => bloques.last.contratoAlumnoId;
  bool get esDeUnAlumno => contratoAlumnoId != null;

  /// El contacto anotado más nuevo, si hay.
  String? get contacto {
    for (final b in bloques.reversed) {
      if (b.contacto != null) return b.contacto;
    }
    return null;
  }

  Iterable<BloqueParaRendir> get _enPie => bloques.where((b) => !b.anulado);

  int _suma(int Function(BloqueParaRendir b) de) =>
      _enPie.fold(0, (s, b) => s + de(b));

  double _plata(double Function(BloqueParaRendir b) de) =>
      deCentavos(_enPie.fold(0, (s, b) => s + centavos(de(b))));

  int get seLlevo => _suma((b) => b.cantidad);
  int get vendidas => _suma((b) => b.vendidas);
  int get devueltas => _suma((b) => b.devueltas);
  int get noVolvieron => _suma((b) => b.noVolvieron);
  int get sinRendir => _suma((b) => b.sinRendir);
  int get rindioDeMas => _suma((b) => b.rindioDeMas);
  double get plataRendida => _plata((b) => b.plataRendida);
  double get plataQueFalta => _plata((b) => b.plataQueFalta);
  double get plataNoVolvio => _plata((b) => b.plataNoVolvio);

  /// Desde cuándo tiene algo sin rendir: cuándo se llevó el bloque más viejo
  /// que todavía tiene algo. Null si no le queda nada.
  String? get desde {
    for (final b in bloques) {
      if (b.sinRendir > 0) return b.dadoAt;
    }
    return null;
  }

  /// Si rindió justo todo lo que se llevó (y algo se llevó).
  bool get rindioTodo => _enPie.isNotEmpty && _enPie.every((b) => b.rindioTodo);
}

/// Qué avisa PARA RENDIR. **Solo avisan**: nada se corrige solo.
enum QueAvisoParaRendir {
  /// Rindió más de lo que se llevó (dos equipos rindieron lo mismo).
  rindioDeMas,

  /// Un bloque anulado tiene algo rendido después.
  anuladoConMovimientos,

  /// Un número de un bloque está también en una venta o en otro bloque.
  numerosCruzados,

  /// Llegaron renglones de un bloque que todavía no está en este equipo.
  deUnBloqueQueNoBajo,
}

class AvisoParaRendir {
  final QueAvisoParaRendir que;

  /// El bloque del aviso. En uno que todavía no bajó, el id que nombran sus
  /// renglones.
  final String bloqueId;
  final String texto;

  const AvisoParaRendir(this.que, this.bloqueId, this.texto);

  @override
  String toString() => texto;
}

/// Las entradas para rendir de una fiesta (consignación,
/// `docs/SPEC_entradas_para_rendir_2026-11-20.md`, sección 4), **sin pantalla
/// ni base**: los bloques que se dieron, por persona, los totales y los avisos.
/// Y las reglas de DAR y RENDIR, con las palabras que lee quien las usa.
///
/// **No se guarda: se cuenta cada vez** de los renglones de
/// `entradas_para_rendir`, las ventas y sus anulaciones. La plata de una
/// rendición es una venta común: el cierre de la caja que cobró la cuenta sin
/// saber nada de esto (`CierreDeEntradas` no se toca).
///
/// **Lo que alguien debe de entradas para rendir no es deuda del contrato y no
/// frena nada.**
class ParaRendir {
  /// Un bloque por cada `dio`, el más viejo primero (también los anulados).
  final List<BloqueParaRendir> bloques;

  /// Una por persona, **primero quien tiene más sin rendir**.
  final List<PersonaParaRendir> porPersona;

  final List<AvisoParaRendir> avisos;

  /// Los números de un bloque que están también en una venta o en otro bloque.
  final List<NumeroCruzado> cruces;

  final List<VentaEntradas> _ventas;
  final List<AnulacionEntradas> _anulaciones;
  final Map<String, BloqueParaRendir> _porVenta;

  const ParaRendir._({
    required this.bloques,
    required this.porPersona,
    required this.avisos,
    required this.cruces,
    required List<VentaEntradas> ventas,
    required List<AnulacionEntradas> anulaciones,
    required Map<String, BloqueParaRendir> porVenta,
  })  : _ventas = ventas,
        _anulaciones = anulaciones,
        _porVenta = porVenta;

  /// Lo que se le agrega al nombre del precio en el renglón de la venta de una
  /// rendición: "Entrada anticipada · para rendir".
  static const kSufijoDelRenglon = MovimientoParaRendir.sufijoDelRenglon;

  /// Lo que dice DAR cuando la fiesta todavía no tiene precio. DAR es del jefe,
  /// que es quien lo carga: se le dice dónde (21-nov-2026), no "el jefe
  /// todavía no puso el precio", que es lo que VENDER le dice a quien vende.
  static const kSinPrecioParaDar =
      'La fiesta todavía no tiene el precio de la entrada. Cargalo en PRECIOS.';

  /// Si [venta] es la de una rendición **por la venta misma**, sin su renglón
  /// `vendio`: sin familia y con todos sus renglones terminados en
  /// [kSufijoDelRenglon] (como los arma [renglon]). Sirve para el rato en que
  /// la venta ya bajó y su `vendio` todavía no (21-nov-2026: la venta sube
  /// antes, prioridad 4 contra 5); con el `vendio`, [bloqueDeLaVenta] dice
  /// además de qué bloque es.
  static bool esVentaDeRendicion(VentaEntradas venta) =>
      venta.contratoAlumnoId == null &&
      venta.renglones.isNotEmpty &&
      venta.renglones.every((r) => r.nombre.endsWith(kSufijoDelRenglon));

  /// [movimientos]: los renglones de `entradas_para_rendir` de la fiesta,
  /// todos. [ventas] y [anulaciones]: las de la fiesta, todas (las de las
  /// rendiciones y las demás: con las demás se ven los números cruzados).
  factory ParaRendir.de({
    required Iterable<MovimientoParaRendir> movimientos,
    required Iterable<VentaEntradas> ventas,
    required Iterable<AnulacionEntradas> anulaciones,
  }) {
    final filas = movimientos.toList()..sort(_enOrden);
    final listaVentas = List<VentaEntradas>.unmodifiable(ventas);
    final listaAnulaciones = List<AnulacionEntradas>.unmodifiable(anulaciones);
    final ventaPorId = {for (final v in listaVentas) v.id: v};
    final anulacionDe = anulacionesPorVenta(listaAnulaciones);
    final ventasAnuladas = anulacionDe.keys.toSet();

    final porBloque = <String, List<MovimientoParaRendir>>{};
    for (final m in filas) {
      porBloque.putIfAbsent(m.bloqueId, () => []).add(m);
    }

    final bloques = <BloqueParaRendir>[];
    final porVenta = <String, BloqueParaRendir>{};
    for (final dio in filas) {
      if (!dio.esDio) continue;
      // Los renglones de este bloque, como los cuenta el repositorio
      // (`bloque_id` = el id del `dio`): la regla del freno es la misma.
      final delBloque = porBloque[dio.id] ?? const <MovimientoParaRendir>[];
      final vigentes = {
        for (final m in MovimientoParaRendir.vigentesDe(
          dio,
          delBloque,
          ventasAnuladas: ventasAnuladas,
        ))
          m.id,
      };
      MovimientoParaRendir? anuloDe(String id) {
        for (final m in delBloque) {
          if (m.esAnulo && m.anulaId == id) return m;
        }
        return null;
      }

      final movs = <MovimientoDelBloque>[];
      var vendidas = 0, devueltas = 0, noVolvieron = 0, plata = 0;
      final devueltos = <TramoTalonario>[];
      final perdidos = <TramoTalonario>[];
      for (final m in delBloque) {
        if (m.id == dio.id) continue;
        if (!m.esVendio && !m.esDevolvio && !m.esNoVolvieron) continue;
        final cuenta = vigentes.contains(m.id);
        final venta = m.esVendio ? ventaPorId[m.ventaId] : null;
        movs.add(MovimientoDelBloque._(
          movimiento: m,
          anulacion: m.esVendio ? null : anuloDe(m.id),
          venta: venta,
          anulacionDeLaVenta: m.esVendio ? anulacionDe[m.ventaId] : null,
          cuenta: cuenta,
        ));
        if (!cuenta) continue;
        if (m.esVendio) {
          vendidas += m.cantidad;
          plata += venta != null
              ? centavos(venta.total)
              : m.cantidad * centavos(RenglonEntradas.precioCon(dio.precio ?? 0, 0));
        } else if (m.esDevolvio) {
          devueltas += m.cantidad;
          devueltos.addAll(m.tramos);
        } else {
          noVolvieron += m.cantidad;
          perdidos.addAll(m.tramos);
        }
      }
      final anulado = MovimientoParaRendir.anuladosEn(delBloque).contains(dio.id);
      final tramos = _unidos(dio.tramos);
      final bloque = BloqueParaRendir._(
        dio: dio,
        anulacion: anulado ? anuloDe(dio.id) : null,
        movimientos: List.unmodifiable(movs),
        vendidas: vendidas,
        devueltas: devueltas,
        noVolvieron: noVolvieron,
        plataRendida: deCentavos(plata),
        tramos: tramos,
        numerosDevueltos: _unidos(devueltos),
        numerosNoVolvieron: _unidos(perdidos),
        numerosOcupados: anulado ? const [] : _sin(tramos, devueltos),
        numerosQueTiene:
            anulado ? const [] : _sin(tramos, [...devueltos, ...perdidos]),
      );
      bloques.add(bloque);
      for (final m in movs) {
        final venta = m.movimiento.ventaId;
        if (m.movimiento.esVendio && venta != null) porVenta[venta] = bloque;
      }
    }

    final cruces =
        NumerosDeEntradas.repetidosConParaRendir(bloques, listaVentas, listaAnulaciones);

    return ParaRendir._(
      bloques: List.unmodifiable(bloques),
      porPersona: List.unmodifiable(_porPersona(bloques)),
      avisos: List.unmodifiable(_avisos(filas, bloques, cruces)),
      cruces: List.unmodifiable(cruces),
      ventas: listaVentas,
      anulaciones: listaAnulaciones,
      porVenta: porVenta,
    );
  }

  /// Por el alumno o, si es de afuera, por el nombre (dos de afuera con el
  /// mismo nombre se juntan: el contacto los distingue en la lista). Primero
  /// quien tiene más sin rendir; después por el nombre y por cuándo se llevó.
  static List<PersonaParaRendir> _porPersona(List<BloqueParaRendir> bloques) {
    final grupos = <String, List<BloqueParaRendir>>{};
    for (final b in bloques) {
      final alumno = b.contratoAlumnoId;
      final clave =
          alumno != null ? 'alumno|$alumno' : 'afuera|${_nombreParaAgrupar(b.persona)}';
      grupos.putIfAbsent(clave, () => []).add(b);
    }
    final personas = [
      for (final e in grupos.entries) PersonaParaRendir._(e.key, List.unmodifiable(e.value)),
    ];
    personas.sort((a, b) {
      final porSinRendir = b.sinRendir.compareTo(a.sinRendir);
      if (porSinRendir != 0) return porSinRendir;
      final porNombre =
          _nombreParaAgrupar(a.nombre).compareTo(_nombreParaAgrupar(b.nombre));
      if (porNombre != 0) return porNombre;
      return a.bloques.first.dadoAt.compareTo(b.bloques.first.dadoAt);
    });
    return personas;
  }

  static List<AvisoParaRendir> _avisos(
    List<MovimientoParaRendir> filas,
    List<BloqueParaRendir> bloques,
    List<NumeroCruzado> cruces,
  ) {
    final avisos = <AvisoParaRendir>[];
    for (final b in bloques) {
      final legible = TramoTalonario.legible(b.tramos);
      if (b.rindioDeMas > 0) {
        avisos.add(AvisoParaRendir(
          QueAvisoParaRendir.rindioDeMas,
          b.id,
          '${b.persona} rindió ${b.cantidad + b.rindioDeMas} de las ${b.cantidad} que '
          'se llevó ($legible): rindió de más, revisar. Si se cobró dos veces desde '
          'dos equipos, anulá en VENTAS la venta que sobra.',
        ));
      }
      if (b.anulado && b.tieneMovimientos) {
        avisos.add(AvisoParaRendir(
          QueAvisoParaRendir.anuladoConMovimientos,
          b.id,
          'Las entradas que se le dieron a ${b.persona} ($legible) están anuladas, '
          'pero tienen algo rendido, devuelto o perdido: revisar.',
        ));
      }
    }
    for (final c in cruces) {
      avisos.add(AvisoParaRendir(QueAvisoParaRendir.numerosCruzados, c.bloqueId, c.texto));
    }
    // Lo que llegó de un bloque que todavía no está acá. Un renglón que esta
    // versión no conoce no avisa nada (no le cambia nada a nadie), y tampoco lo
    // que cuelga de un renglón así: es de una versión más nueva.
    final dados = {for (final b in bloques) b.id};
    final desconocidos = {
      for (final m in filas)
        if (m.que == null) m.id,
    };
    final huerfanos = <String, List<MovimientoParaRendir>>{};
    for (final m in filas) {
      if (m.que == null || m.esDio) continue;
      if (dados.contains(m.bloqueId) || desconocidos.contains(m.bloqueId)) continue;
      huerfanos.putIfAbsent(m.bloqueId, () => []).add(m);
    }
    for (final e in huerfanos.entries) {
      final persona = e.value
          .map((m) => m.personaNombre)
          .firstWhere((n) => n != null, orElse: () => null);
      avisos.add(AvisoParaRendir(
        QueAvisoParaRendir.deUnBloqueQueNoBajo,
        e.key,
        '${persona ?? 'Alguien'}: llegó lo que rindió de unas entradas para rendir '
        'que todavía no bajaron a este equipo. Se va a ver cuando bajen.',
      ));
    }
    return avisos;
  }

  /// Un bloque por su id, o null.
  BloqueParaRendir? bloque(String id) {
    for (final b in bloques) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// El bloque del que se rindió la venta [ventaId] (VENTAS la marca
  /// "RENDICIÓN · de …"), también si esa venta ya se anuló. Null: la venta no
  /// es de una rendición.
  BloqueParaRendir? bloqueDeLaVenta(String ventaId) => _porVenta[ventaId];

  Iterable<BloqueParaRendir> get _enPie => bloques.where((b) => !b.anulado);

  /// Cuántas personas tienen algo sin rendir: lo que dice el aviso de VENDER
  /// ("Entradas para rendir: 3 personas"), sin plata.
  int get personas => porPersona.where((p) => p.sinRendir > 0).length;

  /// Las entradas sin rendir de toda la fiesta.
  int get sinRendir => _enPie.fold(0, (s, b) => s + b.sinRendir);

  bool get hayParaRendir => sinRendir > 0;

  /// "Faltan hasta $X": lo máximo que podrían deber, si no devuelven ninguna.
  double get plataQueFalta =>
      deCentavos(_enPie.fold(0, (s, b) => s + centavos(b.plataQueFalta)));

  /// Las que no volvieron, y lo que valían.
  int get noVolvieron => _enPie.fold(0, (s, b) => s + b.noVolvieron);
  double get plataNoVolvio =>
      deCentavos(_enPie.fold(0, (s, b) => s + centavos(b.plataNoVolvio)));

  /// **Los números de las anticipadas que ya tienen dueño**: lo vendido y lo
  /// que está en manos de alguien para rendir (los dos son el mismo
  /// talonario). Es el `ocupados` de VENDER y el de DAR. Lo entregado sin
  /// cargo es otro talonario y no está acá.
  Map<String, List<TramoTalonario>> get ocupados =>
      NumerosDeEntradas.ocupadosAlVender(_ventas, _anulaciones, bloques);

  // ── DAR ──────────────────────────────────────────────────────────────────

  /// El precio de hoy para dar y su nombre: la anticipada si todavía rige (su
  /// último día entero) y si no la general, como los vende VENDER. **Queda
  /// fijo en el bloque.** Null: la fiesta no tiene precio y no se da.
  ///
  /// El nombre es el del renglón de VENDER ("Entrada" para la general), así
  /// la rendición se lee en VENTAS y en el historial como cualquier venta. Lo
  /// que se muestra (DAR y la constancia) dice "Entrada general" o
  /// "generales", como la maqueta.
  static ({double precio, String nombre})? precioParaDar(
    ConfigEntradas? config,
    DateTime hoyAr,
  ) {
    final precio = PrecioDeEntradas.deHoy(config, hoyAr);
    if (precio == null) return null;
    return (
      precio: precio,
      nombre: PrecioDeEntradas.rigeLaAnticipada(config, hoyAr)
          ? PedidoDeEntradas.nombreAnticipada
          : PedidoDeEntradas.nombreSuelta,
    );
  }

  /// Por qué todavía no se pueden dar, de arriba hacia abajo en la pantalla.
  /// Null: se pueden.
  ///
  /// [deAfuera]: alguien de afuera (lleva nombre y apellido escritos); si no,
  /// un alumno de la fiesta elegido de la lista ([contratoAlumnoId]).
  /// [ocupados]: lo que da [ocupados] (lo vendido y los otros bloques).
  ///
  /// **Los números son obligatorios** (a diferencia de una venta), la cantidad
  /// justa y sin pisar nada del talonario de las anticipadas.
  static String? errorAlDar({
    required ConfigEntradas? config,
    required DateTime hoyAr,
    required bool deAfuera,
    String? contratoAlumnoId,
    required String personaNombre,
    required int cantidad,
    required List<TramoTalonario> tramos,
    required Map<String, List<TramoTalonario>> ocupados,
  }) {
    if (precioParaDar(config, hoyAr) == null) return kSinPrecioParaDar;
    if (deAfuera) {
      final palabras = personaNombre
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .length;
      if (palabras < 2) return 'Escribí nombre y apellido de quien se las lleva.';
    } else if ((contratoAlumnoId ?? '').trim().isEmpty ||
        personaNombre.trim().isEmpty) {
      return 'Elegí al alumno de la lista.';
    }
    if (cantidad < 1) return 'Elegí cuántas entradas se lleva.';
    if (tramos.isEmpty) {
      return 'Escribí el primer número del talonario: son obligatorios.';
    }
    final bienEscritos = tramos.every((t) => t.desde >= 1 && t.hasta >= t.desde);
    if (bienEscritos) {
      final total = _cuantos(tramos);
      if (total != cantidad) {
        return '${total == 1 ? 'Es 1 número' : 'Son $total números'} y se lleva '
            '${_entradas(cantidad)}.';
      }
    }
    // Lo demás (al revés, desde el 1, pisados, ya dados a otro), con las
    // palabras de siempre.
    return RetiroEntradas.errorTramos(
      tramos: tramos,
      generales: cantidad,
      deOtros: ocupados,
    );
  }

  // ── RENDIR ───────────────────────────────────────────────────────────────

  /// El paso que falta para rendir una que no volvió: lo hace el jefe (quien
  /// cobra no puede anular).
  static const _primeroElJefeAnula =
      'primero el jefe tiene que anular ese "no volvieron" en PARA RENDIR.';

  /// Por qué todavía no se puede rendir así, o null. [vendidas] con su plata y
  /// [devueltas] sin vender, con sus números ([numerosDevueltos]). [hayCaja]:
  /// si quien cobra tiene la caja abierta (solo devolver no la pide).
  ///
  /// Lo que devuelve tiene que ser **de lo que todavía tiene**: de las que se
  /// llevó, y que no haya devuelto ni dado por perdido antes.
  ///
  /// **Una que no volvió y después apareció** (la vendió o la trajo) se rinde
  /// como cualquier otra (sección 2 de la SPEC), pero recién cuando el jefe
  /// anula ese "no volvieron" en PARA RENDIR: hasta entonces no le queda. El
  /// mensaje lo dice, así quien cobra sabe a quién pedírselo (21-nov-2026).
  static String? errorAlRendir(
    BloqueParaRendir bloque, {
    required int vendidas,
    required int devueltas,
    List<TramoTalonario> numerosDevueltos = const [],
    required bool hayCaja,
  }) {
    if (bloque.anulado) {
      return 'Estas entradas están anuladas: no hay nada para rendir.';
    }
    if (vendidas < 0 || devueltas < 0 || vendidas + devueltas < 1) {
      return 'Poné cuántas vendió o cuántas devuelve.';
    }
    final quedan = bloque.sinRendir;
    final rinde = vendidas + devueltas;
    if (rinde > quedan) {
      final noLeQuedan =
          '${quedan == 1 ? 'Le queda 1' : 'Le quedan $quedan'}: no puede rendir $rinde.';
      // Solo si anulando lo que no volvió le alcanzaría: si ni así, la guía
      // confundiría. Se compara con lo que le quedaría sin lo que no volvió,
      // no con `quedan + noVolvieron`: si el bloque rindió de más (dos equipos
      // le cobraron lo mismo), `quedan` ya está recortado a 0 y esa suma
      // prometería unas que, anulando, tampoco le quedan (21-nov-2026).
      final sinLoQueNoVolvio =
          max(0, bloque.cantidad - bloque.vendidas - bloque.devueltas);
      if (bloque.noVolvieron > 0 && rinde <= sinLoQueNoVolvio) {
        return '$noLeQuedan Si vendió o trajo alguna de las que no volvieron, '
            '$_primeroElJefeAnula';
      }
      return noLeQuedan;
    }
    if (devueltas == 0 && numerosDevueltos.isNotEmpty) {
      return 'No devuelve ninguna: sacá los números.';
    }
    if (devueltas > 0) {
      if (numerosDevueltos.isEmpty) {
        return 'Escribí los números de las que devuelve.';
      }
      final bienEscritos =
          numerosDevueltos.every((t) => t.desde >= 1 && t.hasta >= t.desde);
      if (bienEscritos) {
        final total = _cuantos(numerosDevueltos);
        if (total != devueltas) {
          return '${total == 1 ? 'Es 1 número' : 'Son $total números'} y '
              '${devueltas == 1 ? 'devuelve 1' : 'devuelve $devueltas'}.';
        }
      }
      // Al revés, desde el 1 y pisados entre sí, con las palabras de siempre.
      final escritos = RetiroEntradas.errorTramos(
        tramos: numerosDevueltos,
        generales: devueltas,
      );
      if (escritos != null) return escritos;
      for (final t in numerosDevueltos) {
        for (var n = t.desde; n <= t.hasta; n++) {
          if (_esta(n, bloque.numerosQueTiene)) continue;
          if (!_esta(n, bloque.tramos)) {
            return 'El $n no es de las que se llevó '
                '(${TramoTalonario.legible(bloque.tramos)}).';
          }
          if (_esta(n, bloque.numerosDevueltos)) return 'El $n ya lo devolvió.';
          return 'El $n está entre las que no volvieron: si la trajo, '
              '$_primeroElJefeAnula';
        }
      }
    }
    if (vendidas > 0) {
      if (!bloque.tienePrecio) {
        return 'Estas entradas no tienen precio: revisalo con el jefe.';
      }
      if (!hayCaja) return 'Para cobrar lo vendido, abrí la caja.';
    }
    return null;
  }

  /// Los números que se proponen para lo que devuelve: **los últimos [n] que
  /// todavía tiene**. Vacío si no tiene tantos (o si [n] es 0).
  static List<TramoTalonario> proponerDevueltos(BloqueParaRendir bloque, int n) {
    if (n < 1 || _cuantos(bloque.numerosQueTiene) < n) return const [];
    return _ultimos(bloque.numerosQueTiene, n);
  }

  // ── NO VOLVIERON ─────────────────────────────────────────────────────────

  /// Por qué todavía no se pueden marcar así las que no volvieron (el jefe, en
  /// PARA RENDIR), o null (21-nov-2026: la ventana de NO VOLVIERON lo dice
  /// antes de guardar, con las palabras de quien la usa, en vez de que el
  /// repositorio tire). [cantidad], de las que le quedan; [numeros],
  /// **opcionales**: si van, la cantidad justa y de los que todavía tiene (no
  /// uno ya devuelto ni uno que ya no volvió). [motivo], obligatorio.
  static String? errorAlMarcarNoVolvieron(
    BloqueParaRendir bloque, {
    required int cantidad,
    List<TramoTalonario> numeros = const [],
    required String motivo,
  }) {
    if (bloque.anulado) {
      return 'Estas entradas están anuladas: no hay nada para marcar.';
    }
    if (cantidad < 1) return 'Elegí cuántas no volvieron.';
    final quedan = bloque.sinRendir;
    if (cantidad > quedan) {
      return '${quedan == 1 ? 'Le queda 1' : 'Le quedan $quedan'} sin rendir: no se '
          '${cantidad == 1 ? 'puede marcar 1' : 'pueden marcar $cantidad'}.';
    }
    if (numeros.isNotEmpty) {
      final bienEscritos = numeros.every((t) => t.desde >= 1 && t.hasta >= t.desde);
      if (bienEscritos) {
        final total = _cuantos(numeros);
        if (total != cantidad) {
          return '${total == 1 ? 'Es 1 número' : 'Son $total números'} y '
              '${cantidad == 1 ? 'no volvió 1' : 'no volvieron $cantidad'}.';
        }
      }
      // Al revés, desde el 1 y pisados entre sí, con las palabras de siempre.
      final escritos = RetiroEntradas.errorTramos(tramos: numeros, generales: cantidad);
      if (escritos != null) return escritos;
      for (final t in numeros) {
        for (var n = t.desde; n <= t.hasta; n++) {
          if (_esta(n, bloque.numerosQueTiene)) continue;
          if (!_esta(n, bloque.tramos)) {
            return 'El $n no es de las que se llevó '
                '(${TramoTalonario.legible(bloque.tramos)}).';
          }
          if (_esta(n, bloque.numerosDevueltos)) return 'El $n ya lo devolvió.';
          return 'El $n ya está entre las que no volvieron.';
        }
      }
    }
    if (motivo.trim().isEmpty) return 'Escribí por qué no volvieron.';
    return null;
  }

  /// El renglón de la venta de una rendición de [vendidas]: **al precio y con
  /// el nombre del día en que se las llevó**, sin descuento ni comisión (rinde
  /// toda la plata). Es lo mismo que arma `EntradasLocal.rendir`; la pantalla
  /// lo usa para "A cobrar" y para el cobro, así los dos dan lo mismo.
  ///
  /// **El precio no se vuelve a leer de PRECIOS**: esa fila se sobrescribe, y
  /// GENERAL borra la anticipada.
  static RenglonEntradas renglon(BloqueParaRendir bloque, int vendidas) =>
      RenglonEntradas.suelta(
        nombre: '${bloque.nombrePrecio ?? 'Entrada'}$kSufijoDelRenglon',
        precioLista: bloque.dio.precio ?? 0,
        descuentoPct: 0,
        cantidad: vendidas,
      );
}
