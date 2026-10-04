import 'dart:convert';
import 'dart:math' as math;

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../modelo/armado_salon.dart';
import '../modelo/armados_predefinidos.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import 'armar_a_medida.dart';
import 'cambios_de_mesa.dart';
import 'medir_salon.dart';

/// Un grupo de mesas que se puede separar o juntar de una vez.
class AlcanceSeparar {
  final String clave;
  final String rotulo;
  final Set<int> numeros;

  const AlcanceSeparar(this.clave, this.rotulo, this.numeros);
}

/// Cómo quedaría el salón si se separan o se juntan unas mesas, antes de
/// aplicarlo.
class VistaPreviaSeparar {
  final ArmadoSalon armado;

  /// La distancia entre mesas que tenía ese grupo, y la que se pidió.
  final double pasoActualM;
  final double pasoNuevoM;

  /// Mesas que quedarían fuera del hormigón (solo en un armado a medida),
  /// medidas con el lugar que pide cada una: lo mismo que avisa el salón
  /// después de aplicar.
  final int fuera;

  /// Pares de mesas que quedarían una encima de la otra.
  final int pisan;

  /// Mesas que quedarían con menos lugar del que piden.
  final int apretadas;

  /// Por qué a esta distancia no se puede aplicar, o null si se puede.
  final String? motivo;

  const VistaPreviaSeparar({
    required this.armado,
    required this.pasoActualM,
    required this.pasoNuevoM,
    required this.fuera,
    required this.pisan,
    this.apretadas = 0,
    this.motivo,
  });

  bool get sePuede => motivo == null;

  bool get entra => sePuede && fuera == 0 && pisan == 0 && apretadas == 0;

  /// "Siguen entrando las 132." o "3 quedan fuera del hormigón y 2 se pisan."
  String get texto {
    if (motivo != null) return motivo!;
    if (entra) {
      final n = armado.mesas.length;
      return n == 1 ? 'Sigue entrando la mesa.' : 'Siguen entrando las $n.';
    }
    final partes = [
      if (fuera > 0)
        fuera == 1
            ? '1 queda fuera del hormigón'
            : '$fuera quedan fuera del hormigón',
      if (pisan > 0) pisan == 1 ? '1 par se pisa' : '$pisan pares se pisan',
      if (apretadas > 0)
        apretadas == 1 ? '1 queda apretada' : '$apretadas quedan apretadas',
    ];
    final ultima = partes.removeLast();
    return partes.isEmpty ? '$ultima.' : '${partes.join(', ')} y $ultima.';
  }
}

/// Acomodar el salón a mano: correr, agregar y sacar mesas, marcar pasto,
/// mover sectores, y separar o juntar un grupo entero.
///
/// Todo es cuenta pura sobre la copia del armado de la fiesta: recibe un
/// armado y devuelve otro. **Nunca cambia el número de una mesa**: lo que se
/// corre es el dibujo, no la familia.
class EditarArmado {
  EditarArmado._();

  /// Al arrastrar, la mesa cae de a un cuarto de metro.
  static const double ajusteM = 0.25;

  /// Lo que queda libre entre la mesa más de afuera y el borde de la hoja.
  static const double _margen = 24;

  static const double separarMinimoM = MedidasPlano.lugarMinimoM;
  static const double separarMaximoM = 4.0;

  /// [v] llevado al cuarto de metro más cercano **contando desde [desde]**:
  /// lo que se ajusta es cuánto se corre, no dónde cae. Así una mesa corrida
  /// sigue alineada con su fila, y se la puede volver justo a donde estaba.
  static double _ajustar(ArmadoSalon a, double v, double desde) {
    final paso = a.aUnidades(ajusteM);
    return desde + ((v - desde) / paso).round() * paso;
  }

  /// La caja de cada hoja, agrandada si hace falta para que entren todas sus
  /// mesas y sus sectores. Nunca se achica: el dibujo no salta.
  static ArmadoSalon _conCajas(ArmadoSalon a) {
    var cambio = false;
    final hojas = <HojaPlano>[];
    for (final h in a.hojas) {
      var x0 = h.caja.x, y0 = h.caja.y;
      var x1 = h.caja.derecha, y1 = h.caja.abajo;
      for (final m in a.mesasDeHoja(h.id)) {
        x0 = math.min(x0, m.x - a.radio - _margen);
        y0 = math.min(y0, m.y - a.radio - _margen);
        x1 = math.max(x1, m.x + a.radio + _margen);
        y1 = math.max(y1, m.y + a.radio + _margen);
      }
      for (final s in a.sectoresDeHoja(h.id)) {
        x0 = math.min(x0, s.caja.x - _margen);
        y0 = math.min(y0, s.caja.y - _margen);
        x1 = math.max(x1, s.caja.derecha + _margen);
        y1 = math.max(y1, s.caja.abajo + _margen);
      }
      final caja = RectPlano(x0, y0, x1 - x0, y1 - y0);
      if (caja != h.caja) cambio = true;
      hojas.add(caja == h.caja ? h : h.copyWith(caja: caja));
    }
    return cambio ? a.copyWith(hojas: hojas) : a;
  }

  // ── Mesas ───────────────────────────────────────────────────────────────

  /// Corre una mesa a ([x], [y]), en coordenadas del plano, sin salirse de su
  /// hoja. Con [ajustar], se corre de a un cuarto de metro contando desde
  /// [desde] (donde estaba al empezar a arrastrarla) o, si no se da, desde
  /// donde está.
  static ArmadoSalon mover(
    ArmadoSalon a,
    int numero,
    double x,
    double y, {
    bool ajustar = true,
    ({double x, double y})? desde,
  }) {
    final m = a.mesa(numero);
    final h = m == null ? null : a.hoja(m.hoja);
    if (m == null || h == null) return a;
    final c = h.caja;
    final nx = (ajustar ? _ajustar(a, x, desde?.x ?? m.x) : x)
        .clamp(c.x + a.radio, math.max(c.x + a.radio, c.derecha - a.radio))
        .toDouble();
    final ny = (ajustar ? _ajustar(a, y, desde?.y ?? m.y) : y)
        .clamp(c.y + a.radio, math.max(c.y + a.radio, c.abajo - a.radio))
        .toDouble();
    if (nx == m.x && ny == m.y) return a;
    return a.copyWith(mesas: [
      for (final o in a.mesas)
        o.numero == numero ? o.copyWith(x: nx, y: ny) : o,
    ]);
  }

  /// El número para una mesa nueva: **el que sigue al más alto**, contando
  /// también los que ya usa alguna familia o están reservados ([otros]).
  /// Nunca llena un hueco del medio. El de la última mesa solo vuelve a
  /// darse si esa mesa se sacó y nadie lo reservó en [otros]: la sesión
  /// reserva los del salón guardado, que son los que ya se pudieron imprimir.
  static int proximoNumero(ArmadoSalon a, [Iterable<int> otros = const []]) {
    var mayor = 0;
    for (final n in [...a.numeros, ...otros]) {
      if (n > mayor) mayor = n;
    }
    return mayor + 1;
  }

  static bool _lugarLibre(
    ArmadoSalon a,
    HojaPlano h,
    double x,
    double y,
    double lugarU,
  ) {
    // A los costados y hacia el escenario no se sale de la hoja. Hacia el
    // fondo sí: la hoja se agranda y la mesa sigue a la última fila.
    final c = h.caja;
    if (x < c.x + a.radio - 0.01 ||
        x > c.derecha - a.radio + 0.01 ||
        y < c.y + a.radio - 0.01) {
      return false;
    }
    final borde = h.contorno;
    if (borde != null && !borde.contieneCirculo(x, y, a.radio)) return false;
    for (final m in a.mesasDeHoja(h.id)) {
      final d = math.sqrt((m.x - x) * (m.x - x) + (m.y - y) * (m.y - y));
      if (d < lugarU - 0.01) return false;
    }
    for (final s in a.sectoresDeHoja(h.id)) {
      if (s.caja.solapeConCirculo(x, y, a.radio) > 0) return false;
    }
    return true;
  }

  /// Un lugar libre en [hoja] para una mesa nueva: a [lugarM] de las demás,
  /// sin tapar un sector y, si la hoja tiene hormigón, adentro.
  ///
  /// - Con [cerca], lo más cerca que se pueda de esa mesa: primero a su lado,
  ///   después atrás, después adelante.
  /// - Sin [cerca], **a continuación de la última fila**: primero lo que le
  ///   queda libre a esa fila hacia los costados y, si está completa, una
  ///   fila nueva detrás. Nunca hacia el escenario ni en el pasillo del medio:
  ///   así varias mesas nuevas quedan una al lado de la otra.
  ///
  /// Con [fueraDelPasillo], tampoco al lado de [cerca] se usa el pasillo del
  /// medio: es para seguir a una mesa que se acaba de agregar, no a una que
  /// eligió la persona.
  ///
  /// Si no hay ninguno, va debajo de la última fila aunque salga del
  /// hormigón: la hoja se agranda y la mesa queda a la vista para arrastrarla.
  static ({double x, double y}) lugarLibre(
    ArmadoSalon a,
    String hoja, {
    int? cerca,
    required double lugarM,
    bool fueraDelPasillo = false,
  }) {
    final h = a.hoja(hoja)!;
    final mesas = a.mesasDeHoja(hoja);
    final paso = a.aUnidades(lugarM);
    MesaPlano? delFondo;
    final medio = centroX(a, hoja);
    // El pasillo del medio: entre la mesa más de adentro de cada lado.
    var pasilloDesde = -double.infinity;
    var pasilloHasta = double.infinity;
    for (final m in mesas) {
      final f = delFondo;
      if (f == null ||
          m.y > f.y + 0.01 ||
          ((m.y - f.y).abs() <= 0.01 &&
              (m.x - medio).abs() < (f.x - medio).abs())) {
        delFondo = m;
      }
      if (m.x < medio) {
        pasilloDesde = math.max(pasilloDesde, m.x);
      } else {
        pasilloHasta = math.min(pasilloHasta, m.x);
      }
    }
    final vecina = cerca == null ? null : a.mesa(cerca);
    final ref = vecina ?? delFondo;
    final rx = ref?.x ?? h.caja.centroX;
    final ry = ref?.y ?? h.caja.centroY;
    const vueltas = 30;
    bool enPasillo(double x) =>
        pasilloDesde.isFinite &&
        pasilloHasta.isFinite &&
        x > pasilloDesde + 0.01 &&
        x < pasilloHasta - 0.01;

    if (vecina == null) {
      for (var j = 0; j <= vueltas; j++) {
        final y = ry + j * paso;
        for (var k = 0; k <= vueltas; k++) {
          // De los dos costados, primero el que queda más cerca del medio:
          // la fila crece pareja.
          final xs = k == 0 ? [rx] : [rx - k * paso, rx + k * paso]
            ..sort((p, q) => (p - medio).abs().compareTo((q - medio).abs()));
          for (final x in xs) {
            if (enPasillo(x)) continue;
            if (_lugarLibre(a, h, x, y, paso)) return (x: x, y: y);
          }
        }
      }
    } else {
      ({double x, double y})? mejor;
      (int, int, int)? mejorOrden;
      for (var i = -vueltas; i <= vueltas; i++) {
        for (var j = -vueltas; j <= vueltas; j++) {
          // A igual distancia: al lado, después atrás, después adelante.
          final orden = (i * i + j * j, j.abs(), j < 0 ? 1 : 0);
          final m = mejorOrden;
          if (m != null &&
              (orden.$1 > m.$1 ||
                  (orden.$1 == m.$1 &&
                      (orden.$2 > m.$2 ||
                          (orden.$2 == m.$2 && orden.$3 >= m.$3))))) {
            continue;
          }
          final x = rx + i * paso;
          final y = ry + j * paso;
          if (fueraDelPasillo && enPasillo(x)) continue;
          if (!_lugarLibre(a, h, x, y, paso)) continue;
          mejor = (x: x, y: y);
          mejorOrden = orden;
        }
      }
      if (mejor != null) return mejor;
    }
    var abajo = h.caja.y;
    for (final m in mesas) {
      abajo = math.max(abajo, m.y);
    }
    return (x: rx, y: abajo + paso);
  }

  /// Agrega una mesa con el número [numero] en ([x], [y]). La hoja se agranda
  /// si hace falta.
  static ArmadoSalon agregar(
    ArmadoSalon a, {
    required int numero,
    required String hoja,
    required double x,
    required double y,
    bool pasto = false,
  }) {
    if (a.existe(numero) || a.hoja(hoja) == null) return a;
    return _conCajas(a.copyWith(mesas: [
      ...a.mesas,
      MesaPlano(numero: numero, hoja: hoja, x: x, y: y, pasto: pasto),
    ]));
  }

  /// Saca una mesa del dibujo. Si se puede o no, lo dice [enUso].
  static ArmadoSalon sacar(ArmadoSalon a, int numero) => a.existe(numero)
      ? a.copyWith(mesas: [
          for (final m in a.mesas)
            if (m.numero != numero) m,
        ])
      : a;

  static ArmadoSalon marcarPasto(ArmadoSalon a, int numero, bool pasto) {
    final m = a.mesa(numero);
    if (m == null || m.pasto == pasto) return a;
    return a.copyWith(mesas: [
      for (final o in a.mesas)
        o.numero == numero ? o.copyWith(pasto: pasto) : o,
    ]);
  }

  /// Por qué no se puede sacar cada mesa que está en uso: la tiene una
  /// familia (también una de baja, que conserva su lugar) o está fijada.
  static Map<int, String> enUso(
    Iterable<ContratoAlumno> alumnos,
    ConfigPlano config,
  ) {
    final r = <int, String>{};
    final apellidos = {
      for (final a in alumnos) a.id: CambiosDeMesa.apellido(a),
    };
    for (final e in config.fijadas.entries) {
      r[e.key] = 'está fijada para '
          '${apellidos[e.value.alumnoId] ?? 'una familia'}';
    }
    for (final a in alumnos) {
      for (final n in MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)) {
        r[n] = a.esBajaTemporal
            ? 'la conserva ${apellidos[a.id]}, que está de baja'
            : 'la tiene ${apellidos[a.id]}';
      }
    }
    return r;
  }

  /// ¿Son las mismas mesas en uso, de las mismas familias? Es comparar dos
  /// resultados de [enUso].
  static bool mismoUso(Map<int, String> a, Map<int, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  // ── Sectores ────────────────────────────────────────────────────────────

  static ArmadoSalon _conSector(
    ArmadoSalon a,
    int indice,
    SectorPlano Function(SectorPlano) cambiar,
  ) {
    if (indice < 0 || indice >= a.sectores.length) return a;
    return _conCajas(a.copyWith(sectores: [
      for (final (i, s) in a.sectores.indexed) i == indice ? cambiar(s) : s,
    ]));
  }

  /// Corre un sector hasta dejar su esquina de arriba a la izquierda en
  /// ([x], [y]), de a un cuarto de metro contando desde [desde] (o desde donde
  /// está).
  static ArmadoSalon moverSector(
    ArmadoSalon a,
    int indice,
    double x,
    double y, {
    ({double x, double y})? desde,
  }) =>
      _conSector(
        a,
        indice,
        (s) => s.copyWith(
          caja: RectPlano(
            _ajustar(a, x, desde?.x ?? s.caja.x),
            _ajustar(a, y, desde?.y ?? s.caja.y),
            s.caja.ancho,
            s.caja.alto,
          ),
        ),
      );

  /// Cambia lo que mide un sector, en metros (medio metro como mínimo), sin
  /// mover su esquina de arriba a la izquierda.
  static ArmadoSalon tamanoSector(
    ArmadoSalon a,
    int indice, {
    required double anchoM,
    required double altoM,
  }) =>
      _conSector(
        a,
        indice,
        (s) => s.copyWith(
          caja: RectPlano(
            s.caja.x,
            s.caja.y,
            a.aUnidades(math.max(0.5, anchoM)),
            a.aUnidades(math.max(0.5, altoM)),
          ),
        ),
      );

  /// Agrega un sector de 4 × 2 m arriba a la izquierda de la hoja, para
  /// arrastrarlo a su lugar.
  static ArmadoSalon agregarSector(
    ArmadoSalon a, {
    required String hoja,
    required TipoSector tipo,
    String texto = '',
  }) {
    final h = a.hoja(hoja);
    if (h == null) return a;
    return _conCajas(a.copyWith(sectores: [
      ...a.sectores,
      SectorPlano(
        tipo: tipo,
        texto: texto,
        hoja: hoja,
        caja: RectPlano(
          h.caja.x + _margen,
          h.caja.y + _margen,
          a.aUnidades(4),
          a.aUnidades(2),
        ),
      ),
    ]));
  }

  static ArmadoSalon sacarSector(ArmadoSalon a, int indice) =>
      indice < 0 || indice >= a.sectores.length
          ? a
          : a.copyWith(sectores: [
              for (final (i, s) in a.sectores.indexed)
                if (i != indice) s,
            ]);

  /// El sector de [hoja] bajo un punto del plano (el de más arriba si hay
  /// varios encimados), o null.
  static int? sectorEn(ArmadoSalon a, String hoja, double x, double y) {
    for (var i = a.sectores.length - 1; i >= 0; i--) {
      final s = a.sectores[i];
      if (s.hoja != hoja) continue;
      final c = s.caja;
      if (x >= c.x && x <= c.derecha && y >= c.y && y <= c.abajo) return i;
    }
    return null;
  }

  // ── Medir ───────────────────────────────────────────────────────────────

  /// Las [cuantas] mesas más cercanas a una, con su distancia en metros: es
  /// la regla que se ve al arrastrar.
  static List<({int numero, double metros})> vecinas(
    ArmadoSalon a,
    int numero, {
    int cuantas = 3,
  }) {
    final m = a.mesa(numero);
    if (m == null) return const [];
    final otras = [
      for (final o in a.mesasDeHoja(m.hoja))
        if (o.numero != numero)
          (numero: o.numero, metros: a.aMetros(m.distanciaA(o))),
    ]..sort((x, y) => x.metros.compareTo(y.metros));
    return otras.take(cuantas).toList();
  }

  /// Los pares de mesas que quedaron una encima de la otra.
  static List<(int, int)> pisadas(ArmadoSalon a) {
    final r = <(int, int)>[];
    for (final h in a.hojas) {
      final mesas = a.mesasDeHoja(h.id);
      for (var i = 0; i < mesas.length; i++) {
        for (var j = i + 1; j < mesas.length; j++) {
          if (mesas[i].distanciaA(mesas[j]) < 2 * a.radio - 0.5) {
            r.add((mesas[i].numero, mesas[j].numero));
          }
        }
      }
    }
    return r;
  }

  /// Lo que no deja guardar el salón así, en palabras. Vacío si se puede.
  static List<String> bloqueos(ArmadoSalon a) => [
        for (final (x, y) in pisadas(a)) 'Las mesas $x y $y se pisan.',
        if (a.mesas.isEmpty) 'El salón quedó sin mesas.',
      ];

  /// La distancia típica entre las mesas de [numeros]: la mediana de lo que
  /// cada una tiene hasta su vecina más cercana del grupo. Null con menos de
  /// dos mesas en una misma hoja.
  static double? pasoDe(ArmadoSalon a, Iterable<int> numeros) {
    final mesas = [
      for (final n in numeros.toSet())
        if (a.mesa(n) != null) a.mesa(n)!,
    ];
    final cercanas = <double>[];
    for (final m in mesas) {
      var mejor = double.infinity;
      for (final o in mesas) {
        if (o.numero == m.numero || o.hoja != m.hoja) continue;
        mejor = math.min(mejor, m.distanciaA(o));
      }
      if (mejor.isFinite) cercanas.add(mejor);
    }
    if (cercanas.isEmpty) return null;
    cercanas.sort();
    return a.aMetros(cercanas[cercanas.length ~/ 2]);
  }

  /// El medio del salón en una hoja: la pasarela, o el escenario, o el medio
  /// de las mesas.
  static double centroX(ArmadoSalon a, String hoja) {
    for (final tipo in [TipoSector.pasarela, TipoSector.escenario]) {
      for (final propia in [true, false]) {
        for (final s in a.sectores) {
          if (s.tipo == tipo && (s.hoja == hoja) == propia) {
            return s.caja.centroX;
          }
        }
      }
    }
    final mesas = a.mesasDeHoja(hoja);
    if (mesas.isEmpty) return a.hoja(hoja)?.caja.centroX ?? 0;
    final xs = [for (final m in mesas) m.x]..sort();
    return (xs.first + xs.last) / 2;
  }

  /// Los grupos que se pueden separar o juntar en una hoja: toda la hoja,
  /// cada lado de la pasarela y, con el sorteo por división ya hecho, el
  /// bloque de cada división.
  static List<AlcanceSeparar> alcances(
    ArmadoSalon a,
    String hoja, {
    List<BloqueDivision> bloques = const [],
    Map<String, String> nombres = const {},
  }) {
    final mesas = a.mesasDeHoja(hoja);
    final cx = centroX(a, hoja);
    final izq = {for (final m in mesas) if (m.x < cx) m.numero};
    final der = {for (final m in mesas) if (m.x >= cx) m.numero};
    return [
      AlcanceSeparar(
        'hoja',
        a.hojas.length == 1 ? 'Todo el salón' : 'Toda la hoja',
        {for (final m in mesas) m.numero},
      ),
      if (izq.length > 1 && der.length > 1) ...[
        AlcanceSeparar('izq', 'Lado izquierdo', izq),
        AlcanceSeparar('der', 'Lado derecho', der),
      ],
      for (final b in bloques)
        if ({for (final m in mesas) if (b.contiene(m.numero)) m.numero}
            case final numeros when numeros.length > 1)
          AlcanceSeparar(
            'div:${b.division}',
            'Bloque de ${nombres[b.division] ?? b.division}',
            numeros,
          ),
    ];
  }

  /// Estira o junta las mesas de [numeros] hasta dejarlas a [pasoNuevoM] entre
  /// sí, **desde el lado del escenario y desde el medio hacia afuera**: la
  /// fila de adelante y la pasarela no se mueven.
  ///
  /// No cambia ningún número y agranda la hoja si hace falta.
  ///
  /// **Tampoco cambia qué mesas están pegadas**: las vecinas siguen siendo
  /// vecinas y los pasillos siguen siendo pasillos, en el grupo y en el resto
  /// del salón. Si a esa distancia no se puede (una vecina quedaría más lejos
  /// que la mesa del otro lado de un pasillo), la vista previa lo dice en
  /// [VistaPreviaSeparar.motivo] y no se aplica.
  ///
  /// Lo que entra y lo que queda apretado se mide con [medidas] y las sillas
  /// extra de cada mesa, como los avisos del salón. Null si no hay nada que
  /// separar (menos de dos mesas).
  static VistaPreviaSeparar? separar(
    ArmadoSalon a,
    Set<int> numeros,
    double pasoNuevoM, {
    MedidasPlano medidas = const MedidasPlano(),
    int Function(int numero)? sillasExtraDe,
  }) {
    final actual = pasoDe(a, numeros);
    if (actual == null || actual <= 0) return null;
    final paso = pasoNuevoM.clamp(separarMinimoM, separarMaximoM).toDouble();
    final estirado = _estirar(a, numeros, actual, paso);
    String? motivo;
    if (!estirado.conserva) {
      // Hasta dónde sí se puede, de a 5 cm hacia la distancia de hoy.
      final sentido = paso > actual ? -1 : 1;
      double? limite;
      for (var k = 1; k <= 60; k++) {
        final p = ((paso + sentido * k * 0.05) * 100).round() / 100;
        if ((p - actual) * sentido >= 0) break;
        if (_estirar(a, numeros, actual, p).conserva) {
          limite = p;
          break;
        }
      }
      final cuanto = MedirSalon.metros(paso, decimales: 2);
      motivo = paso > actual
          ? 'A $cuanto las mesas vecinas quedarían tan lejos como las del '
              'otro lado del pasillo, y el sorteo ya no sabría cuáles van '
              'juntas. ${limite == null ? 'No se pueden separar más.' : 'Se '
                  'puede hasta ${MedirSalon.metros(limite, decimales: 2)}.'}'
          : 'A $cuanto las mesas del otro lado del pasillo quedarían tan '
              'cerca como las vecinas, y el sorteo ya no sabría cuáles van '
              'juntas. ${limite == null ? 'No se pueden juntar más.' : 'Se '
                  'puede desde ${MedirSalon.metros(limite, decimales: 2)}.'}';
    }
    final armado = estirado.armado;
    final lugar = MedirSalon.revisar(armado, medidas, sillasExtraDe ?? (_) => 0);
    return VistaPreviaSeparar(
      armado: armado,
      pasoActualM: actual,
      pasoNuevoM: paso,
      fuera: lugar.fueraDelHormigon.length,
      pisan: pisadas(armado).length,
      apretadas: {for (final p in lugar.apretadas) ...p.sinLugar}.length,
      motivo: motivo,
    );
  }

  /// Las mesas de [numeros] llevadas a [pasoM] entre sí, y si con eso las
  /// mesas pegadas siguen siendo las mismas.
  static ({ArmadoSalon armado, bool conserva}) _estirar(
    ArmadoSalon a,
    Set<int> numeros,
    double actualM,
    double pasoM,
  ) {
    final f = pasoM / actualM;
    final nuevas = <int, MesaPlano>{};
    for (final h in a.hojas) {
      final grupo = [
        for (final m in a.mesasDeHoja(h.id))
          if (numeros.contains(m.numero)) m,
      ];
      if (grupo.isEmpty) continue;
      final cx = centroX(a, h.id);
      var arriba = double.infinity;
      var anclaIzq = -double.infinity;
      var anclaDer = double.infinity;
      for (final m in grupo) {
        arriba = math.min(arriba, m.y);
        if (m.x < cx) {
          anclaIzq = math.max(anclaIzq, m.x);
        } else {
          anclaDer = math.min(anclaDer, m.x);
        }
      }
      for (final m in grupo) {
        final ancla = m.x < cx ? anclaIzq : anclaDer;
        nuevas[m.numero] = m.copyWith(
          x: ancla + (m.x - ancla) * f,
          y: arriba + (m.y - arriba) * f,
        );
      }
    }
    final movido = _conCajas(a.copyWith(
      mesas: [for (final m in a.mesas) nuevas[m.numero] ?? m],
    ));
    final umbral = _umbralQueConserva(
      a,
      movido,
      ArmarAMedida.pegadasHastaPasos * a.aUnidades(pasoM),
    );
    if (umbral == null) return (armado: movido, conserva: false);
    return (
      armado: (umbral - movido.pegadasHastaU).abs() < 1e-9
          ? movido
          : movido.copyWith(distanciaPegadas: umbral),
      conserva: true,
    );
  }

  /// Hasta qué distancia tienen que contar como pegadas las mesas de [nuevo]
  /// para que sus cortes sean los de [antes]. Prueba primero con [sugerido]
  /// (lo que corresponde a la distancia nueva) y con el que ya tenía. Null si
  /// no hay ninguno: una mesa que estaba pegada a la siguiente quedó más lejos
  /// que otra que no lo estaba.
  static double? _umbralQueConserva(
    ArmadoSalon antes,
    ArmadoSalon nuevo,
    double sugerido,
  ) {
    var pegadaMasLejos = 0.0;
    var cortadaMasCerca = double.infinity;
    for (final m in nuevo.mesas) {
      final o = nuevo.mesa(m.numero + 1);
      if (o == null || o.hoja != m.hoja) continue;
      final d = m.distanciaA(o);
      if (antes.cortes.contains(m.numero)) {
        cortadaMasCerca = math.min(cortadaMasCerca, d);
      } else {
        pegadaMasLejos = math.max(pegadaMasLejos, d);
      }
    }
    // El mismo margen de [ArmadoSalon.pegadas], con algo de aire para que un
    // redondeo no cambie nada.
    bool sirve(double t) =>
        pegadaMasLejos <= t + 0.005 && cortadaMasCerca > t + 0.02;
    for (final t in [
      sugerido,
      nuevo.pegadasHastaU,
      if (cortadaMasCerca.isFinite) (pegadaMasLejos + cortadaMasCerca) / 2,
      pegadaMasLejos,
    ]) {
      if (sirve(t)) return t;
    }
    return null;
  }

  // ── Familias ────────────────────────────────────────────────────────────

  /// En cuántos grupos de mesas pegadas están las de una familia: 1 si están
  /// todas juntas.
  static int _grupos(ArmadoSalon a, List<int> numeros) {
    final l = numeros.toSet().toList()..sort();
    var grupos = l.isEmpty ? 0 : 1;
    for (var i = 1; i < l.length; i++) {
      if (l[i] != l[i - 1] + 1 || !a.pegadas(l[i - 1], l[i])) grupos++;
    }
    return grupos;
  }

  /// Las familias que al correr mesas quedaron más separadas que en [antes]:
  /// dos mesas suyas que estaban pegadas ya no lo están. La que ya tenía una
  /// mesa aparte (lo pidió así) cuenta igual si se le separan las otras.
  static List<OcupantePlano> familiasPartidas(
    ArmadoSalon antes,
    ArmadoSalon despues,
    Iterable<OcupantePlano> ocupantes,
  ) =>
      [
        for (final o in ocupantes)
          if (o.numeros.length > 1 &&
              o.numeros.every(despues.existe) &&
              _grupos(despues, o.numeros) > _grupos(antes, o.numeros))
            o,
      ];

  // ── El armado original ──────────────────────────────────────────────────

  /// El armado como venía de fábrica: el del Canva o, si es a medida, armado
  /// de nuevo con el mismo playón, la misma distancia y la misma pasarela (o
  /// sin ella) de la primera vez, y la cantidad de mesas que hay hoy. Null si
  /// no se sabe de dónde salió.
  ///
  /// Puede traer menos mesas que [a] si se agregaron más de las que entran:
  /// quien llama lo tiene que mirar (la sesión de Acomodar no deja volver al
  /// original en ese caso).
  static ArmadoSalon? original(ArmadoSalon a) {
    final fabrica = ArmadosPredefinidos.porClave(a.clave);
    if (fabrica != null) return fabrica;
    final playon = ArmarAMedida.playonDe(a);
    final lugar = ArmarAMedida.lugarDe(a);
    if (playon == null || lugar == null) return null;
    int? partir;
    if (a.hojas.length > 1) {
      final b = a.hojas.first.contorno!.puntos;
      final corte = a.aMetros(b[3].y - b[0].y);
      partir = ((corte - 0.5) / lugar).round();
    }
    return ArmarAMedida.armar(OpcionesAMedida(
      playon: playon,
      cantidad: a.cantidadComunes,
      lugarM: lugar,
      pasarelaM: ArmarAMedida.pasarelaDe(a),
      partirEnFila: partir,
    )).armado;
  }

  // ── Guardar ─────────────────────────────────────────────────────────────

  static String firma(ArmadoSalon a) => jsonEncode(a.toJson());

  /// El salón acomodado, listo para guardar sobre el plano que hay de verdad
  /// ([fresco], recién leído), o por qué no se puede.
  ///
  /// - Si [fresco] ya no es el salón del que se partió ([base]), la otra PC lo
  ///   cambió mientras tanto: no se pisa.
  /// - Una mesa que se sacó y ahora tiene familia o está fijada no se saca.
  /// - Si las mesas en uso ya no son las que se vieron al acomodar
  ///   ([enUsoVisto]: la otra PC sorteó, cambió a una familia o fijó una
  ///   mesa), tampoco se guarda. Lo acomodado se pensó con otro salón: los
  ///   avisos de familias separadas y el permiso para volver al armado
  ///   original salieron de datos que ya no valen.
  /// - Las mesas que se sacaron dejan de figurar como libres.
  static CambioDeConfig paraGuardar({
    required ArmadoSalon base,
    required ArmadoSalon nuevo,
    required ArmadoSalon fresco,
    required ConfigPlano config,
    required Iterable<ContratoAlumno> alumnos,
    required Map<int, String> enUsoVisto,
  }) {
    if (firma(fresco) != firma(base)) {
      return const CambioDeConfig.noSePuede(
        'El salón guardado cambió mientras lo acomodabas. No se guardó nada, '
        'para no pisar ese cambio: mirá cómo quedó y acomodalo de nuevo.',
      );
    }
    final trabas = bloqueos(nuevo);
    if (trabas.isNotEmpty) return CambioDeConfig.noSePuede(trabas.join(' '));
    final usadas = enUso(alumnos, config);
    final sacadas = [
      for (final n in base.numeros)
        if (!nuevo.existe(n)) n,
    ];
    for (final n in sacadas) {
      final porque = usadas[n];
      if (porque != null) {
        return CambioDeConfig.noSePuede(
          'La mesa $n no se puede sacar: $porque. No se guardó nada.',
        );
      }
    }
    if (!mismoUso(enUsoVisto, usadas)) {
      return const CambioDeConfig.noSePuede(
        'Mientras acomodabas cambiaron las mesas de las familias (un sorteo, '
        'un cambio de mesa o una mesa fijada). No se guardó nada, para no '
        'dejar a nadie en un lugar que no viste: tocá DESCARTAR, mirá cómo '
        'quedó y acomodá de nuevo.',
      );
    }
    return CambioDeConfig.ok(
      sacadas.any(config.libres.containsKey)
          ? config.copyWith(libres: {
              for (final e in config.libres.entries)
                if (!sacadas.contains(e.key)) e.key: e.value,
            })
          : config,
      sacadas,
      armado: nuevo,
    );
  }
}
