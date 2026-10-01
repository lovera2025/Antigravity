import 'dart:math' as math;

import '../modelo/armado_salon.dart';
import '../modelo/medidas_salon.dart';
import 'medir_salon.dart';

/// Con qué se arma el salón a medida del playón.
class OpcionesAMedida {
  final PlayonReal playon;

  /// Cuántas mesas hacen falta.
  final int cantidad;

  /// De centro a centro de mesa.
  final double lugarM;

  /// El ancho de la pasarela. Cero: sin pasarela.
  final double pasarelaM;
  final double largoPasarelaM;

  /// Lo que queda libre a cada lado de la pasarela (en el Canva del jefe son
  /// unos 2,5 m).
  final double despejePasarelaM;

  /// Lo que queda libre contra el borde del hormigón.
  final double margenM;

  /// Lo que queda libre entre el escenario y la primera fila.
  final double despejeEscenarioM;

  /// La fila donde empieza la hoja B. Null: todo en una hoja.
  final int? partirEnFila;

  const OpcionesAMedida({
    required this.playon,
    required this.cantidad,
    this.lugarM = MedidasPlano.lugarPorDefectoM,
    this.pasarelaM = 2.1,
    this.largoPasarelaM = 14,
    this.despejePasarelaM = 2.5,
    this.margenM = 0.5,
    this.despejeEscenarioM = 0.5,
    this.partirEnFila,
  });

  OpcionesAMedida conCantidad(int cantidad) => OpcionesAMedida(
        playon: playon,
        cantidad: cantidad,
        lugarM: lugarM,
        pasarelaM: pasarelaM,
        largoPasarelaM: largoPasarelaM,
        despejePasarelaM: despejePasarelaM,
        margenM: margenM,
        despejeEscenarioM: despejeEscenarioM,
        partirEnFila: partirEnFila,
      );
}

/// El salón armado a medida, y cómo salió la cuenta.
class ArmadoAMedida {
  final ArmadoSalon armado;
  final int pedidas;

  /// Cuántas entran como mucho en el playón, a esa distancia.
  final int capacidad;

  /// Las mesas de cada fila, desde el escenario.
  final List<int> mesasPorFila;

  const ArmadoAMedida({
    required this.armado,
    required this.pedidas,
    required this.capacidad,
    required this.mesasPorFila,
  });

  int get puestas => armado.mesas.length;

  /// Las que no entraron en el hormigón.
  int get faltan => math.max(0, pedidas - puestas);
}

/// Una fila del salón: a qué profundidad está y qué columnas tiene de cada
/// lado. La columna 0 es la de adentro en las filas de la pasarela; pasada la
/// pasarela hay columnas negativas, que llenan el medio.
class _Fila {
  final double profundidad;
  final int desde;
  int hastaIzq;
  int hastaDer;

  _Fila(this.profundidad, this.desde, int hasta)
      : hastaIzq = hasta,
        hastaDer = hasta;

  int get izq => math.max(0, hastaIzq - desde + 1);
  int get der => math.max(0, hastaDer - desde + 1);
  int get total => izq + der;
}

/// Arma el salón sobre el playón: filas desde el escenario hacia el fondo,
/// simétricas, con las mesas numeradas en serpentina como las del jefe.
///
/// Todo es cuenta pura: no lee ni guarda nada.
class ArmarAMedida {
  ArmarAMedida._();

  static const claveArmado = 'a_medida@1';

  /// Alrededor del dibujo, para que entren los rótulos y las medidas.
  static const double _borde = 60;
  static const double _altoEscenario = 50;
  static const double _radio = 38;
  static const double _mu = kMetrosPorUnidadCanva;

  /// A cuántos pasos de distancia dos mesas siguen contando como pegadas: la
  /// diagonal (1,41) sí, saltearse una mesa (2) no.
  static const double pegadasHastaPasos = 1.5;

  static double _u(double metros) => metros / _mu;

  /// La distancia entre mesas no puede ser menos que la mesa.
  static double _lugar(OpcionesAMedida o) =>
      math.max(o.lugarM, MedidasPlano.lugarMinimoM);

  /// El medio del salón queda libre hasta acá (media pasarela más su despeje).
  static double _adentro(OpcionesAMedida o) =>
      o.pasarelaM > 0 ? o.pasarelaM / 2 + o.despejePasarelaM : 0;

  static List<_Fila> _filas(OpcionesAMedida o) {
    final l = _lugar(o);
    final p = o.playon;
    final adentro = _adentro(o);
    final filas = <_Fila>[];
    for (var k = 0;; k++) {
      final d = o.despejeEscenarioM + l / 2 + k * l;
      if (d + l / 2 > p.profundidadM - o.margenM + 1e-9) break;
      // El costado es una línea inclinada: se mide donde el círculo de la mesa
      // queda más cerca de ella.
      final medio =
          p.anchoA(d) / 2 - p.aperturaPorMetro.abs() * l / 2 - o.margenM;
      final enPasarela =
          o.pasarelaM > 0 && d - l / 2 < o.largoPasarelaM - 1e-9;
      final desde = enPasarela ? 0 : -(adentro / l + 1e-9).floor();
      final hasta = ((medio - adentro - l) / l + 1e-9).floor();
      filas.add(_Fila(d, desde, hasta));
    }
    return filas;
  }

  /// Cuántas mesas entran como mucho en el playón con estas opciones.
  static int capacidad(OpcionesAMedida o) =>
      _filas(o).fold(0, (s, f) => s + f.total);

  /// La distancia más grande entre mesas (de a 5 cm) con la que todavía
  /// entran las [OpcionesAMedida.cantidad] pedidas: es "usar todo el playón".
  /// Null si no entran ni a la distancia mínima.
  static double? lugarMasHolgado(OpcionesAMedida o) {
    double? mejor;
    for (var paso = 0;; paso++) {
      final lugar = MedidasPlano.lugarMinimoM + paso * 0.05;
      if (lugar > MedidasPlano.lugarMaximoM + 1e-9) break;
      final entran = capacidad(OpcionesAMedida(
        playon: o.playon,
        cantidad: o.cantidad,
        lugarM: lugar,
        pasarelaM: o.pasarelaM,
        largoPasarelaM: o.largoPasarelaM,
        despejePasarelaM: o.despejePasarelaM,
        margenM: o.margenM,
        despejeEscenarioM: o.despejeEscenarioM,
      ));
      // No es parejo: a veces un poco más de distancia acomoda mejor las
      // filas. Por eso se recorre todo y queda la más grande que sirve.
      if (entran >= o.cantidad) mejor = lugar;
    }
    return mejor == null ? null : (mejor * 100).round() / 100;
  }

  static ArmadoAMedida armar(OpcionesAMedida o) {
    final l = _lugar(o);
    final p = o.playon;
    final adentro = _adentro(o);
    final todas = _filas(o);
    final capacidad = todas.fold(0, (s, f) => s + f.total);

    // Las filas que hacen falta, desde el escenario. A la última se le sacan
    // las de afuera, de a una por lado, hasta quedar en la cantidad pedida.
    final filas = <_Fila>[];
    var puestas = 0;
    for (final f in todas) {
      if (puestas >= o.cantidad) break;
      if (f.total == 0) continue;
      filas.add(f);
      puestas += f.total;
    }
    if (filas.isNotEmpty) {
      final ultima = filas.last;
      var sobran = puestas - o.cantidad;
      var derecha = true;
      while (sobran > 0 && ultima.total > 0) {
        if (derecha && ultima.der > 0) {
          ultima.hastaDer--;
          sobran--;
        } else if (!derecha && ultima.izq > 0) {
          ultima.hastaIzq--;
          sobran--;
        }
        derecha = !derecha;
      }
    }

    // La primera fila de la hoja B. Si no se parte, ninguna.
    var primeraDeB = filas.length;
    final partir = o.partirEnFila;
    if (partir != null && partir > 0 && partir < filas.length) {
      primeraDeB = partir;
    }
    final enDos = primeraDeB < filas.length;
    // El corte entre hojas va a mitad de camino entre dos filas.
    final corte =
        enDos ? filas[primeraDeB].profundidad - l / 2 : p.profundidadM;

    final cx = _borde + _u(math.max(p.frenteM, p.fondoM) / 2);
    const yA = _borde + _altoEscenario;
    const yB = _borde;

    ({String hoja, double y}) lugarDe(int fila) {
      final d = filas[fila].profundidad;
      return fila >= primeraDeB
          ? (hoja: 'B', y: yB + _u(d - corte))
          : (hoja: 'A', y: yA + _u(d));
    }

    double x(int columna, int lado) =>
        cx + lado * _u(adentro + l / 2 + columna * l);

    // La serpentina del jefe: la izquierda desde el escenario y la derecha
    // desde el fondo hasta el escenario, alternando el sentido en cada fila.
    // [ultimaHaciaAdentro] dice para dónde se recorre la última fila de la
    // izquierda (la derecha va al revés).
    final ultimaFila = filas.length - 1;
    List<MesaPlano> numerar(bool ultimaHaciaAdentro) {
      final mesas = <MesaPlano>[];
      void poner(int fila, int columna, int lado) {
        final donde = lugarDe(fila);
        mesas.add(MesaPlano(
          numero: mesas.length + 1,
          hoja: donde.hoja,
          x: x(columna, lado),
          y: donde.y,
        ));
      }

      for (var f = 0; f <= ultimaFila; f++) {
        final fila = filas[f];
        final haciaAdentro = (ultimaFila - f).isEven == ultimaHaciaAdentro;
        for (var k = 0; k < fila.izq; k++) {
          poner(f, haciaAdentro ? fila.hastaIzq - k : fila.desde + k, -1);
        }
      }
      for (var f = ultimaFila; f >= 0; f--) {
        final fila = filas[f];
        final haciaAfuera = (ultimaFila - f).isEven == ultimaHaciaAdentro;
        for (var k = 0; k < fila.der; k++) {
          poner(f, haciaAfuera ? fila.desde + k : fila.hastaDer - k, 1);
        }
      }
      return mesas;
    }

    // El tramo del trapecio entre dos profundidades, dibujado desde [y0].
    ContornoPlano borde(double y0, double desde, double hasta) {
      final arriba = _u(p.anchoA(desde) / 2);
      final abajo = _u(p.anchoA(hasta) / 2);
      final yFin = y0 + _u(hasta - desde);
      return ContornoPlano([
        (x: cx - arriba, y: y0),
        (x: cx + arriba, y: y0),
        (x: cx + abajo, y: yFin),
        (x: cx - abajo, y: yFin),
      ]);
    }

    final ancho = 2 * _borde + _u(math.max(p.frenteM, p.fondoM));
    final hojas = [
      HojaPlano(
        id: 'A',
        titulo: enDos ? 'Cerca del escenario' : 'Playón',
        caja: RectPlano(0, 0, ancho, yA + _u(corte) + _borde),
        contorno: borde(yA, 0, corte),
      ),
      if (enDos)
        HojaPlano(
          id: 'B',
          titulo: 'Al fondo',
          caja: RectPlano(
            0,
            0,
            ancho,
            yB + _u(p.profundidadM - corte) + _borde,
          ),
          contorno: borde(yB, corte, p.profundidadM),
        ),
    ];

    final largoPasarela = math.min(o.largoPasarelaM, p.profundidadM);
    final sectores = [
      SectorPlano(
        tipo: TipoSector.escenario,
        texto: 'Escenario',
        hoja: 'A',
        caja: RectPlano(
          cx - _u(p.frenteM / 2),
          _borde,
          _u(p.frenteM),
          _altoEscenario,
        ),
      ),
      if (o.pasarelaM > 0) ...[
        SectorPlano(
          tipo: TipoSector.pasarela,
          texto: 'Pasarela',
          hoja: 'A',
          caja: RectPlano(
            cx - _u(o.pasarelaM / 2),
            yA,
            _u(o.pasarelaM),
            _u(math.min(largoPasarela, corte)),
          ),
          vertical: true,
        ),
        if (enDos && largoPasarela > corte)
          SectorPlano(
            tipo: TipoSector.pasarela,
            texto: '',
            hoja: 'B',
            caja: RectPlano(
              cx - _u(o.pasarelaM / 2),
              yB,
              _u(o.pasarelaM),
              _u(largoPasarela - corte),
            ),
            vertical: true,
          ),
      ],
    ];

    ArmadoSalon con(List<MesaPlano> mesas) => ArmadoSalon(
          clave: claveArmado,
          nombre: 'A medida del playón',
          descripcion: '${mesas.length} mesas a ${MedirSalon.metros(l)}',
          radio: _radio,
          metrosPorUnidad: _mu,
          distanciaPegadas: pegadasHastaPasos * _u(l),
          hojas: hojas,
          mesas: mesas,
          sectores: sectores,
        );

    // De los dos sentidos queda el que corta menos la serpentina. Terminando
    // adentro, la derecha arranca al lado de la izquierda cuando no hay
    // pasarela; terminando afuera, una última fila incompleta (que conserva
    // las mesas de adentro) sigue pegada a la anterior.
    final adentroPrimero = con(numerar(true));
    final afueraPrimero = con(numerar(false));
    final armado = afueraPrimero.cortes.length < adentroPrimero.cortes.length
        ? afueraPrimero
        : adentroPrimero;

    return ArmadoAMedida(
      armado: armado,
      pedidas: o.cantidad,
      capacidad: capacidad,
      mesasPorFila: [for (final f in filas) f.total],
    );
  }
}
