import 'dart:math' as math;

import '../../../models/plano_evento.dart';
import '../modelo/armado_salon.dart';
import '../modelo/medidas_salon.dart';
import '../modelo/numeracion.dart';
import 'cambios_de_mesa.dart';
import 'editar_armado.dart';
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

  /// Dónde termina la numeración (6.5.1).
  final FinNumeracion fin;

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
    this.fin = FinNumeracion.escenario,
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
        fin: fin,
      );
}

/// Un recorrido posible de la numeración: para dónde va la última fila de la
/// izquierda y, cuando la derecha también sale del escenario
/// ([FinNumeracion.fondo]), para dónde va su última fila. Con [derAfuera] en
/// null la derecha vuelve del fondo al escenario, al revés que la izquierda.
///
/// Con [cruza], fila por fila ([FinNumeracion.filas]): cada fila va entera, de
/// una punta a la otra cruzando el medio, y [izqAdentro] dice si la primera
/// arranca en la punta izquierda. [derAfuera] no se mira.
typedef _Recorrido = ({bool izqAdentro, bool? derAfuera, bool cruza});

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

  /// El salón vacío (6.1.0, "el salón primero"): el playón con el escenario y
  /// el Ingreso, sin mesas. Las mesas se ponen después con [acomodar]. Una PC
  /// con la 6.0.0 no conoce esta clave: abre el salón igual, pero no le ofrece
  /// "Volver al armado original" (ver `test/salon_convivencia_test.dart`).
  static const claveVacio = 'vacio@1';

  static const nombreAMedida = 'A medida del playón';
  static const nombreVacio = 'Salón vacío';

  /// El salón vacío con mesas ya no es un salón vacío: el papel y la ventana de
  /// SORTEO decían "Salón vacío" con 100 mesas (lo vio el usuario el 19-oct).
  /// Con mesas se llama como el armado a medida, y sin mesas vuelve a ser el
  /// salón vacío. La clave no cambia: "Volver al armado original" la sigue
  /// necesitando. Es el valor de `nombre`, que ya existe: la 6.0.0 lo muestra
  /// igual. Los demás armados quedan como están (un predio, con su nombre).
  static ArmadoSalon conNombreSegunMesas(ArmadoSalon a) {
    if (a.clave != claveVacio) return a;
    final nombre = a.mesas.isEmpty ? nombreVacio : nombreAMedida;
    return a.nombre == nombre ? a : a.copyWith(nombre: nombre);
  }

  /// Un salón que salió de un predio (6.1.0) lleva `predio@<id>` en su clave.
  /// No es una clave nueva del JSON: es el valor de `clave`, que ya existe. La
  /// 6.0.0 no lo conoce y lo abre igual que el salón vacío.
  static const prefijoPredio = 'predio@';

  static String claveDePredio(String id) => '$prefijoPredio$id';

  /// El id del predio del que salió [a], o null si no salió de uno.
  static String? idDePredio(ArmadoSalon a) =>
      a.clave.startsWith(prefijoPredio) && a.clave.length > prefijoPredio.length
          ? a.clave.substring(prefijoPredio.length)
          : null;

  /// Las claves de los salones con el borde del playón dibujado a medida.
  static bool _esAMedida(ArmadoSalon a) =>
      a.clave == claveArmado || a.clave == claveVacio || idDePredio(a) != null;

  /// El espacio de [a] para guardarlo como el predio [id]: el borde de cada
  /// hoja y los sectores, sin mesas. Sin la distancia entre mesas ni el último
  /// número dado: son de cada fiesta.
  static ArmadoSalon espacioParaPredio(
    ArmadoSalon a, {
    required String id,
    required String nombre,
  }) =>
      ArmadoSalon(
        clave: claveDePredio(id),
        nombre: nombre,
        descripcion: 'El espacio, sin mesas',
        radio: a.radio,
        metrosPorUnidad: a.metrosPorUnidad,
        pasarelaOriginalM: pasarelaDe(a),
        hojas: a.hojas,
        mesas: const [],
        sectores: a.sectores,
        ingreso: a.ingreso,
      );

  /// El salón de una fiesta que arranca del predio: su espacio, sin mesas, con
  /// la distancia entre mesas de la fiesta ([lugarM]). Las mesas se ponen
  /// después con [acomodar], como en el salón vacío.
  static ArmadoSalon desdePredio(
    ArmadoSalon espacio, {
    required String nombre,
    double lugarM = MedidasPlano.lugarPorDefectoM,
  }) {
    final l = math.max(lugarM, MedidasPlano.lugarMinimoM);
    return ArmadoSalon(
      clave: espacio.clave,
      nombre: nombre,
      descripcion: espacio.descripcion,
      radio: espacio.radio,
      metrosPorUnidad: espacio.metrosPorUnidad,
      distanciaPegadas: pegadasHastaPasos * espacio.aUnidades(l),
      lugarOriginalM: l,
      pasarelaOriginalM: espacio.pasarelaOriginalM ?? pasarelaDe(espacio),
      hojas: espacio.hojas,
      mesas: const [],
      sectores: espacio.sectores,
      ingreso: espacio.ingreso,
    );
  }

  /// Lo que queda libre alrededor de un sector que no es el escenario ni la
  /// pasarela (una pista, una barra, el Ingreso): la mesa no se pone si su
  /// círculo, agrandado esto, lo pisa.
  static const double despejeSectorM = 0.5;

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

  /// El tramo del trapecio entre dos profundidades, dibujado desde [y0] y
  /// centrado en [cx]. Siempre cuatro puntos: arriba a la izquierda, arriba a
  /// la derecha, abajo a la derecha y abajo a la izquierda.
  static ContornoPlano _borde4(
    PlayonReal p,
    double cx,
    double y0,
    double desde,
    double hasta,
  ) {
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

  /// Los bordes de un armado a medida, hoja por hoja. Null si no es un armado
  /// a medida o alguna hoja no trae su trapecio.
  static List<List<({double x, double y})>>? _bordes(ArmadoSalon armado) {
    if (!_esAMedida(armado) || armado.hojas.isEmpty) return null;
    final r = <List<({double x, double y})>>[];
    for (final h in armado.hojas) {
      final puntos = h.contorno?.puntos;
      if (puntos == null || puntos.length != 4) return null;
      r.add(puntos);
    }
    return r;
  }

  /// A qué distancia entre mesas se armó este salón. Null si no es un armado
  /// a medida.
  ///
  /// Es la que quedó guardada al armarlo. Solo si falta se deduce de hasta
  /// dónde cuentan como pegadas, que deja de servir en cuanto se separan o se
  /// juntan las mesas.
  static double? lugarDe(ArmadoSalon armado) {
    if (!_esAMedida(armado)) return null;
    final guardado = armado.lugarOriginalM;
    if (guardado != null) return guardado;
    final pegadas = armado.distanciaPegadas;
    if (pegadas == null) return null;
    return armado.aMetros(pegadas / pegadasHastaPasos);
  }

  /// El ancho de la pasarela con que se armó este salón (cero: sin pasarela).
  /// Si no quedó guardado, el de la pasarela que tiene dibujada.
  static double pasarelaDe(ArmadoSalon armado) {
    final guardado = armado.pasarelaOriginalM;
    if (guardado != null) return guardado;
    for (final s in armado.sectores) {
      if (s.tipo == TipoSector.pasarela) return armado.aMetros(s.caja.ancho);
    }
    return 0;
  }

  /// El playón con el que está dibujado el borde de este armado. Null si no
  /// es un armado a medida.
  static PlayonReal? playonDe(ArmadoSalon armado) {
    final bordes = _bordes(armado);
    if (bordes == null) return null;
    var profundidad = 0.0;
    for (final b in bordes) {
      profundidad += b[3].y - b[0].y;
    }
    return PlayonReal(
      frenteM: armado.aMetros(bordes.first[1].x - bordes.first[0].x),
      fondoM: armado.aMetros(bordes.last[2].x - bordes.last[3].x),
      profundidadM: armado.aMetros(profundidad),
    );
  }

  /// El borde sigue siendo un trapecio parejo: el frente y el fondo derechos y
  /// centrados uno con el otro, como lo dibuja [conPlayon]. Con las manijas
  /// (6.1.0) puede quedar torcido, y ahí las medidas de la pestaña Medidas son
  /// aproximadas: escribirlas lo vuelve a dibujar parejo. Un armado sin borde
  /// (los del Canva) cuenta como parejo: no hay nada que avisar.
  static bool esParejo(ArmadoSalon armado) {
    final bordes = _bordes(armado);
    if (bordes == null) return true;
    const tolerancia = 0.5;
    for (final b in bordes) {
      final (ai, ad, bd, bi) = (b[0], b[1], b[2], b[3]);
      if ((ai.y - ad.y).abs() > tolerancia || (bi.y - bd.y).abs() > tolerancia) {
        return false;
      }
      final arriba = (ai.x + ad.x) / 2, abajo = (bi.x + bd.x) / 2;
      if ((arriba - abajo).abs() > tolerancia) return false;
    }
    return true;
  }

  static bool _mismoPlayon(PlayonReal a, PlayonReal b) =>
      (a.frenteM - b.frenteM).abs() < 0.001 &&
      (a.fondoM - b.fondoM).abs() < 0.001 &&
      (a.profundidadM - b.profundidadM).abs() < 0.001;

  /// El mismo salón con el borde del hormigón redibujado para otro playón
  /// (se midió con cinta y no era el de la foto).
  ///
  /// **Las mesas no se mueven** respecto del escenario ni cambian de número:
  /// la que quede afuera del hormigón nuevo se avisa, no se corre sola. Si el
  /// armado no es a medida, o el playón es el mismo, devuelve el mismo armado.
  ///
  /// **El escenario es un sector como los demás** (6.1.0): queda como está, y
  /// el jefe lo corre o lo agranda en Acomodar. Hasta la 6.0.0 tomaba el
  /// frente nuevo del playón.
  static ArmadoSalon conPlayon(ArmadoSalon armado, PlayonReal p) {
    final bordes = _bordes(armado);
    final actual = playonDe(armado);
    if (bordes == null || actual == null || _mismoPlayon(actual, p)) {
      return armado;
    }
    final cxViejo = (bordes.first[0].x + bordes.first[1].x) / 2;
    // El dibujo sigue centrado y tiene que contener el hormigón nuevo, todas
    // las mesas (aunque alguna haya quedado afuera) y los sectores, escenario
    // incluido.
    var medio = _u(math.max(p.frenteM, p.fondoM) / 2);
    for (final m in armado.mesas) {
      medio = math.max(medio, (m.x - cxViejo).abs() + armado.radio);
    }
    for (final s in armado.sectores) {
      medio = math.max(medio, (s.caja.x - cxViejo).abs());
      medio = math.max(medio, (s.caja.derecha - cxViejo).abs());
    }
    final cx = _borde + medio;
    final dx = cx - cxViejo;

    // Dónde termina cada hoja, en metros desde el escenario: el corte entre
    // hojas no cambia, salvo que el playón nuevo sea más corto.
    final hojas = <HojaPlano>[];
    var desde = 0.0;
    for (final (i, h) in armado.hojas.indexed) {
      final b = bordes[i];
      final ultima = i == armado.hojas.length - 1;
      final largo = armado.aMetros(b[3].y - b[0].y);
      final inicio = math.min(desde, p.profundidadM);
      final hasta =
          ultima ? p.profundidadM : math.min(desde + largo, p.profundidadM);
      final y0 = b[0].y;
      var abajo = y0 + _u(math.max(0.0, hasta - inicio));
      for (final m in armado.mesasDeHoja(h.id)) {
        abajo = math.max(abajo, m.y + armado.radio);
      }
      for (final s in armado.sectoresDeHoja(h.id)) {
        abajo = math.max(abajo, s.caja.abajo);
      }
      hojas.add(HojaPlano(
        id: h.id,
        titulo: h.titulo,
        caja: RectPlano(0, 0, 2 * _borde + 2 * medio, abajo + _borde),
        contorno: _borde4(p, cx, y0, inicio, math.max(inicio, hasta)),
      ));
      desde += largo;
    }

    return armado.copyWith(
      hojas: hojas,
      mesas: [for (final m in armado.mesas) m.copyWith(x: m.x + dx)],
      sectores: [
        for (final s in armado.sectores) s.copyWith(caja: s.caja.mover(dx, 0)),
      ],
    );
  }

  /// Las medidas listas para guardar sobre el plano que hay de verdad
  /// ([armado] y [config], recién leídos), o por qué no se puede.
  ///
  /// [vistas] son las que estaban guardadas cuando se corrigieron. Si la otra
  /// PC las cambió mientras tanto no se guarda nada: las medidas se escriben
  /// todas juntas, y corregir la distancia entre mesas le pisaría el playón
  /// que acaba de medir con cinta.
  ///
  /// En un salón a medida, con otro playón se redibuja el borde del hormigón.
  static CambioDeConfig medidasParaGuardar({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required MedidasPlano vistas,
    required MedidasPlano nuevas,
  }) {
    if (config.medidas != vistas) {
      return const CambioDeConfig.noSePuede(
        'La otra PC cambió las medidas mientras las corregías. No se guardó '
        'nada, para no pisar lo que hizo: mirá cómo quedaron y probá de '
        'nuevo.',
      );
    }
    final redibujado = conPlayon(armado, nuevas.playon);
    return CambioDeConfig.ok(
      config.copyWith(medidas: nuevas),
      const [],
      armado: identical(redibujado, armado) ? null : redibujado,
    );
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
    // desde el fondo hasta el escenario, alternando el sentido en cada fila. O,
    // terminando al fondo, las dos mitades desde el escenario. El recorrido es
    // el de [_enSerpentina]: acá se arma con las columnas de cada fila.
    List<MesaPlano> numerar(_Recorrido r) {
      final lugares = _enSerpentina(
        [
          for (var f = 0; f < filas.length; f++)
            (
              izq: [
                for (var k = 0; k < filas[f].izq; k++)
                  (fila: f, columna: filas[f].desde + k, lado: -1),
              ],
              der: [
                for (var k = 0; k < filas[f].der; k++)
                  (fila: f, columna: filas[f].desde + k, lado: 1),
              ],
            ),
        ],
        r,
      );
      return [
        for (final (i, m) in lugares.indexed)
          MesaPlano(
            numero: i + 1,
            hoja: lugarDe(m.fila).hoja,
            x: x(m.columna, m.lado),
            y: lugarDe(m.fila).y,
          ),
      ];
    }

    ContornoPlano borde(double y0, double desde, double hasta) =>
        _borde4(p, cx, y0, desde, hasta);

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
          nombre: nombreAMedida,
          descripcion: '${mesas.length} mesas a ${MedirSalon.metros(l)}',
          radio: _radio,
          metrosPorUnidad: _mu,
          distanciaPegadas: pegadasHastaPasos * _u(l),
          lugarOriginalM: l,
          pasarelaOriginalM: math.max(0.0, o.pasarelaM),
          hojas: hojas,
          mesas: mesas,
          sectores: sectores,
        );

    // De los sentidos posibles queda el que corta menos la serpentina.
    // Terminando adentro, la derecha arranca al lado de la izquierda cuando no
    // hay pasarela; terminando afuera, una última fila incompleta (que conserva
    // las mesas de adentro) sigue pegada a la anterior.
    final armado = _elQueMenosCorta([
      for (final r in _recorridos(o.fin)) con(numerar(r)),
    ]);

    return ArmadoAMedida(
      armado: armado,
      pedidas: o.cantidad,
      capacidad: capacidad,
      mesasPorFila: [for (final f in filas) f.total],
    );
  }

  // ── El salón primero (6.1.0) ──────────────────────────────────────────────

  /// El playón vacío: el borde del hormigón, el escenario centrado al frente y
  /// el Ingreso al fondo, al medio (4 × 2 m, a medio metro del fondo), sin
  /// mesas. Con el Ingreso, el tótem dibuja el camino a la mesa sin pasos
  /// extra. Las mesas se ponen después con [acomodar].
  static ArmadoSalon vacio(
    PlayonReal p, {
    double lugarM = MedidasPlano.lugarPorDefectoM,
  }) {
    final cx = _borde + _u(math.max(p.frenteM, p.fondoM) / 2);
    const yA = _borde + _altoEscenario;
    final ancho = 2 * _borde + _u(math.max(p.frenteM, p.fondoM));
    final l = math.max(lugarM, MedidasPlano.lugarMinimoM);
    return ArmadoSalon(
      clave: claveVacio,
      nombre: nombreVacio,
      descripcion: 'El espacio, sin mesas',
      radio: _radio,
      metrosPorUnidad: _mu,
      distanciaPegadas: pegadasHastaPasos * _u(l),
      lugarOriginalM: l,
      pasarelaOriginalM: 0,
      hojas: [
        HojaPlano(
          id: 'A',
          titulo: 'Playón',
          caja: RectPlano(0, 0, ancho, yA + _u(p.profundidadM) + _borde),
          contorno: _borde4(p, cx, yA, 0, p.profundidadM),
        ),
      ],
      mesas: const [],
      sectores: [
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
        SectorPlano(
          tipo: TipoSector.ingreso,
          texto: 'Ingreso',
          hoja: 'A',
          caja: RectPlano(
            cx - _u(2),
            yA + _u(math.max(0.0, p.profundidadM - 2.5)),
            _u(4),
            _u(2),
          ),
        ),
      ],
    );
  }

  /// Un punto del plano dentro del borde, o justo sobre él.
  static bool _dentro(ContornoPlano c, double x, double y) =>
      c.contiene(x, y) || c.distanciaAlBorde(x, y) < 1e-6;

  /// Cuánto hay del centro de un círculo a un rectángulo (0 si está adentro).
  static double _distanciaARect(RectPlano r, double x, double y) {
    final dx = math.max(math.max(r.x - x, 0.0), x - r.derecha);
    final dy = math.max(math.max(r.y - y, 0.0), y - r.abajo);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Pone [cantidad] mesas en el salón que el jefe armó: dentro del borde real
  /// del hormigón (que ya no es necesariamente un trapecio parejo) y sin pisar
  /// ningún sector. Es el botón ACOMODAR LAS MESAS (6.1.0, "el salón
  /// primero"). Las mesas que tenía [a] se reemplazan, numeradas de nuevo.
  ///
  /// Las mismas reglas que [armar], para que sobre el mismo playón dé lo mismo:
  /// - filas desde el escenario, a [lugarM] de centro a centro (la distancia
  ///   guardada del salón, si no se da), con medio metro libre delante del
  ///   escenario y contra el borde;
  /// - con pasarela, 2,5 m libres a cada lado mientras la fila la toca, y
  ///   después el medio se llena;
  /// - la serpentina del jefe (la izquierda desde el escenario y la derecha
  ///   desde el fondo), en el sentido que menos la corta; o, con [fin] al
  ///   fondo, las dos mitades desde el escenario.
  ///
  /// Lo nuevo: cada hoja usa su borde (los costados se miden a la altura de
  /// cada fila), y una mesa no se pone si su círculo, más [despejeSectorM],
  /// pisa un sector que no es la pasarela (una pista, una barra, el Ingreso).
  /// Si el escenario no está arriba, hay filas de los dos lados.
  static ArmadoAMedida acomodar(
    ArmadoSalon a, {
    required int cantidad,
    double? lugarM,
    double despejePasarelaM = 2.5,
    double margenM = 0.5,
    double despejeEscenarioM = 0.5,
    FinNumeracion fin = FinNumeracion.escenario,
  }) {
    final lugar = math.max(
      lugarM ?? a.lugarOriginalM ?? MedidasPlano.lugarPorDefectoM,
      MedidasPlano.lugarMinimoM,
    );
    final l = a.aUnidades(lugar);
    final mg = a.aUnidades(margenM);

    // Las posiciones posibles, fila por fila, en el orden en que se llenan.
    final filas = <({String hoja, double y, List<double> izq, List<double> der})>[];
    for (final h in a.hojas) {
      final c = h.contorno ??
          ContornoPlano([
            (x: h.caja.x, y: h.caja.y),
            (x: h.caja.derecha, y: h.caja.y),
            (x: h.caja.derecha, y: h.caja.abajo),
            (x: h.caja.x, y: h.caja.abajo),
          ]);
      final ys = [for (final p in c.puntos) p.y];
      final xs = [for (final p in c.puntos) p.x];
      final arriba = ys.reduce(math.min), abajo = ys.reduce(math.max);
      final izquierda = xs.reduce(math.min), derecha = xs.reduce(math.max);

      final sectores = a.sectoresDeHoja(h.id);
      SectorPlano? deTipo(TipoSector t) {
        for (final s in sectores) {
          if (s.tipo == t) return s;
        }
        return null;
      }

      final escenario = deTipo(TipoSector.escenario);
      final pasarela = deTipo(TipoSector.pasarela);
      final obstaculos = [
        for (final s in sectores)
          if (s.tipo != TipoSector.pasarela)
            (
              caja: s.caja,
              despeje: a.aUnidades(s.tipo == TipoSector.escenario
                  ? despejeEscenarioM
                  : despejeSectorM),
            ),
      ];
      final cx = _centroDeHoja(a, h);
      final adentro = pasarela == null
          ? 0.0
          : pasarela.caja.ancho / 2 + a.aUnidades(despejePasarelaM);

      bool entra(double x, double y) {
        // La celda de la mesa, con el margen a los costados y al fondo: lo
        // mismo que mide [armar] sobre el trapecio.
        final mitad = l / 2;
        for (final (px, py) in [
          (x - mitad - mg, y - mitad),
          (x + mitad + mg, y - mitad),
          (x - mitad - mg, y + mitad),
          (x + mitad + mg, y + mitad),
          (x, y + mitad + mg),
          (x, y - mitad),
        ]) {
          if (!_dentro(c, px, py)) return false;
        }
        for (final o in obstaculos) {
          if (_distanciaARect(o.caja, x, y) < a.radio + o.despeje - 1e-9) {
            return false;
          }
        }
        return true;
      }

      ({String hoja, double y, List<double> izq, List<double> der}) fila(
        double y,
      ) {
        final enPasarela = pasarela != null &&
            y - l / 2 < pasarela.caja.abajo - 1e-9 &&
            y + l / 2 > pasarela.caja.y + 1e-9;
        final desde = enPasarela ? 0 : -(adentro / l + 1e-9).floor();
        List<double> lado(int signo) {
          final r = <double>[];
          for (var col = desde;; col++) {
            final x = cx + signo * (adentro + l / 2 + col * l);
            if (x < izquierda - l || x > derecha + l) break;
            if (entra(x, y)) r.add(x);
          }
          return r;
        }

        return (hoja: h.id, y: y, izq: lado(-1), der: lado(1));
      }

      // Desde el escenario hacia el fondo y, si queda lugar, hacia el frente.
      // Sin escenario, desde arriba.
      final haciaAbajo = <double>[];
      final haciaArriba = <double>[];
      if (escenario != null) {
        for (var y = escenario.caja.abajo + a.aUnidades(despejeEscenarioM) + l / 2;
            y - l / 2 < abajo;
            y += l) {
          haciaAbajo.add(y);
        }
        for (var y = escenario.caja.y - a.aUnidades(despejeEscenarioM) - l / 2;
            y + l / 2 > arriba;
            y -= l) {
          haciaArriba.add(y);
        }
      } else {
        for (var y = arriba + mg + l / 2; y - l / 2 < abajo; y += l) {
          haciaAbajo.add(y);
        }
      }
      final ordenadas = <double>[];
      for (var i = 0; i < math.max(haciaAbajo.length, haciaArriba.length); i++) {
        if (i < haciaAbajo.length) ordenadas.add(haciaAbajo[i]);
        if (i < haciaArriba.length) ordenadas.add(haciaArriba[i]);
      }
      for (final y in ordenadas) {
        final f = fila(y);
        if (f.izq.isNotEmpty || f.der.isNotEmpty) filas.add(f);
      }
    }

    final capacidad =
        filas.fold(0, (s, f) => s + f.izq.length + f.der.length);

    // Las filas que hacen falta. A la última se le sacan las de afuera, de a
    // una por lado (primero la derecha), hasta quedar en la cantidad pedida.
    final usadas = <({String hoja, double y, List<double> izq, List<double> der})>[];
    var puestas = 0;
    for (final f in filas) {
      if (puestas >= cantidad) break;
      usadas.add((hoja: f.hoja, y: f.y, izq: [...f.izq], der: [...f.der]));
      puestas += f.izq.length + f.der.length;
    }
    if (usadas.isNotEmpty) {
      final ultima = usadas.last;
      var sobran = puestas - cantidad;
      var derecha = true;
      while (sobran > 0 && ultima.izq.length + ultima.der.length > 0) {
        if (derecha && ultima.der.isNotEmpty) {
          ultima.der.removeLast();
          sobran--;
        } else if (!derecha && ultima.izq.isNotEmpty) {
          ultima.izq.removeLast();
          sobran--;
        }
        derecha = !derecha;
      }
    }

    // La serpentina del jefe, como en [armar].
    MesaPlano Function(double x) sinNumero(String hoja, double y) =>
        (x) => MesaPlano(numero: 0, hoja: hoja, x: x, y: y);
    final filasDeMesas = [
      for (final f in usadas)
        (
          izq: f.izq.map(sinNumero(f.hoja, f.y)).toList(),
          der: f.der.map(sinNumero(f.hoja, f.y)).toList(),
        ),
    ];
    ArmadoSalon con(List<MesaPlano> mesas) => a.copyWith(
          mesas: mesas,
          distanciaPegadas: pegadasHastaPasos * l,
        );
    final armado = _elQueMenosCorta([
      for (final r in _recorridos(fin))
        con(_numeradas(_enSerpentina(filasDeMesas, r))),
    ]);

    return ArmadoAMedida(
      armado: armado,
      pedidas: cantidad,
      capacidad: capacidad,
      mesasPorFila: [for (final f in usadas) f.izq.length + f.der.length],
    );
  }

  /// El medio de una hoja, de donde salen el lado izquierdo y el derecho: la
  /// pasarela, si no el escenario, si no el medio del borde. No es
  /// `EditarArmado.centroX`, que mira el medio de las mesas: con una fila
  /// recortada daría otro centro.
  static double _centroDeHoja(ArmadoSalon a, HojaPlano h) {
    double? deTipo(TipoSector tipo) {
      for (final s in a.sectoresDeHoja(h.id)) {
        if (s.tipo == tipo) return s.caja.centroX;
      }
      return null;
    }

    final puntos = h.contorno?.puntos;
    final medio = puntos == null
        ? h.caja.centroX
        : (puntos.map((p) => p.x).reduce(math.min) +
                puntos.map((p) => p.x).reduce(math.max)) /
            2;
    return deTipo(TipoSector.pasarela) ?? deTipo(TipoSector.escenario) ?? medio;
  }

  /// Los recorridos que se prueban para [fin], en el orden en que se prefieren
  /// si cortan lo mismo.
  ///
  /// - Junto al escenario, los dos de siempre: la última fila de la izquierda
  ///   hacia adentro o hacia afuera (la derecha vuelve al revés).
  /// - Al fondo, las dos mitades son independientes: primero los que terminan
  ///   en la punta de afuera de la última fila de la derecha, que es donde el
  ///   jefe espera el último número y donde siguen las mesas nuevas.
  /// - Fila por fila, dos: la primera fila arrancando en la punta izquierda
  ///   (el 1 a la izquierda del escenario, como se lee) o en la derecha.
  static List<_Recorrido> _recorridos(FinNumeracion fin) => switch (fin) {
        FinNumeracion.escenario => const [
            (izqAdentro: true, derAfuera: null, cruza: false),
            (izqAdentro: false, derAfuera: null, cruza: false),
          ],
        FinNumeracion.fondo => const [
            (izqAdentro: true, derAfuera: true, cruza: false),
            (izqAdentro: false, derAfuera: true, cruza: false),
            (izqAdentro: true, derAfuera: false, cruza: false),
            (izqAdentro: false, derAfuera: false, cruza: false),
          ],
        FinNumeracion.filas => const [
            (izqAdentro: true, derAfuera: null, cruza: true),
            (izqAdentro: false, derAfuera: null, cruza: true),
          ],
      };

  /// De [candidatos], el que menos corta la serpentina; si cortan lo mismo, el
  /// primero.
  static ArmadoSalon _elQueMenosCorta(List<ArmadoSalon> candidatos) {
    var mejor = candidatos.first;
    var cortes = mejor.cortes.length;
    for (final c in candidatos.skip(1)) {
      final n = c.cortes.length;
      if (n < cortes) {
        mejor = c;
        cortes = n;
      }
    }
    return mejor;
  }

  /// El recorrido de la numeración, alternando el sentido en cada fila. En cada
  /// fila los dos lados van del medio hacia afuera; `r.izqAdentro` dice para
  /// dónde se recorre la última fila de la izquierda.
  ///
  /// - Con `r.derAfuera` en null, la serpentina del jefe: la izquierda desde el
  ///   escenario y la derecha de vuelta, desde el fondo.
  /// - Si no, las dos mitades desde el escenario ([FinNumeracion.fondo]), y
  ///   `r.derAfuera` dice para dónde va la última fila de la derecha.
  /// - Con `r.cruza`, fila por fila ([FinNumeracion.filas]): cada fila entera,
  ///   de una punta a la otra, y la siguiente de vuelta. Cada lado viene del
  ///   medio hacia afuera, así que de izquierda a derecha es la izquierda al
  ///   revés y después la derecha.
  static List<T> _enSerpentina<T>(
    List<({List<T> izq, List<T> der})> filas,
    _Recorrido r,
  ) {
    final orden = <T>[];
    final ultima = filas.length - 1;
    if (r.cruza) {
      for (var f = 0; f <= ultima; f++) {
        final aLaDerecha = f.isEven == r.izqAdentro;
        orden.addAll(
          aLaDerecha
              ? [...filas[f].izq.reversed, ...filas[f].der]
              : [...filas[f].der.reversed, ...filas[f].izq],
        );
      }
      return orden;
    }
    for (var f = 0; f <= ultima; f++) {
      final haciaAdentro = (ultima - f).isEven == r.izqAdentro;
      orden.addAll(haciaAdentro ? filas[f].izq.reversed : filas[f].izq);
    }
    final derAfuera = r.derAfuera;
    if (derAfuera == null) {
      for (var f = ultima; f >= 0; f--) {
        final haciaAfuera = (ultima - f).isEven == r.izqAdentro;
        orden.addAll(haciaAfuera ? filas[f].der : filas[f].der.reversed);
      }
    } else {
      for (var f = 0; f <= ultima; f++) {
        final haciaAfuera = (ultima - f).isEven == derAfuera;
        orden.addAll(haciaAfuera ? filas[f].der : filas[f].der.reversed);
      }
    }
    return orden;
  }

  /// Las mismas mesas, en su mismo lugar, numeradas en ese orden desde [desde].
  static List<MesaPlano> _numeradas(List<MesaPlano> orden, {int desde = 1}) => [
        for (var i = 0; i < orden.length; i++)
          MesaPlano(
            numero: desde + i,
            hoja: orden[i].hoja,
            x: orden[i].x,
            y: orden[i].y,
            pasto: orden[i].pasto,
          ),
      ];

  /// Las [mesas] puestas en filas, en el orden en que [acomodar] las llena:
  /// hoja por hoja y, en cada una, desde el escenario hacia el fondo y hacia el
  /// frente, intercaladas. Sin escenario, de arriba hacia abajo.
  static List<({List<MesaPlano> izq, List<MesaPlano> der})> _filasDe(
    ArmadoSalon a,
    List<MesaPlano> mesas,
  ) {
    final filas = <({List<MesaPlano> izq, List<MesaPlano> der})>[];
    final hojas = <String>{
      for (final h in a.hojas) h.id,
      for (final m in mesas) m.hoja,
    };
    for (final id in hojas) {
      final deLaHoja = [for (final m in mesas) if (m.hoja == id) m]
        ..sort((x, y) => x.y.compareTo(y.y));
      if (deLaHoja.isEmpty) continue;

      final metros = EditarArmado.pasoDe(a, [for (final m in deLaHoja) m.numero]);
      final paso = metros == null ? 2 * a.radio : a.aUnidades(metros);

      // Una mesa es de la fila si está a menos de medio paso de la primera: una
      // mesa corrida a mano sigue en su fila, y la de la fila siguiente no entra.
      final porFila = <List<MesaPlano>>[];
      for (final m in deLaHoja) {
        if (porFila.isNotEmpty && m.y - porFila.last.first.y < paso / 2) {
          porFila.last.add(m);
        } else {
          porFila.add([m]);
        }
      }

      RectPlano? escenario;
      for (final s in a.sectoresDeHoja(id)) {
        if (s.tipo == TipoSector.escenario) {
          escenario = s.caja;
          break;
        }
      }
      if (escenario != null) {
        final e = escenario;
        // Cuántos pasos hay desde el escenario, no qué lugar ocupa la fila: una
        // fila que quedó vacía (la tapa una pista) también cuenta en [acomodar].
        int turno(List<MesaPlano> fila) {
          final y = fila.first.y;
          final debajo = y >= e.centroY;
          final pasos = ((debajo ? y - e.abajo : e.y - y) / paso).floor();
          return 2 * math.max<int>(0, pasos) + (debajo ? 0 : 1);
        }

        porFila.sort((x, y) {
          final porTurno = turno(x).compareTo(turno(y));
          return porTurno != 0
              ? porTurno
              : (x.first.y - e.centroY)
                  .abs()
                  .compareTo((y.first.y - e.centroY).abs());
        });
      }

      final hoja = a.hoja(id);
      final xs = [for (final m in deLaHoja) m.x];
      final cx = hoja != null
          ? _centroDeHoja(a, hoja)
          : (xs.reduce(math.min) + xs.reduce(math.max)) / 2;
      for (final fila in porFila) {
        filas.add((
          izq: [for (final m in fila) if (m.x < cx) m]
            ..sort((x, y) => y.x.compareTo(x.x)),
          der: [for (final m in fila) if (m.x >= cx) m]
            ..sort((x, y) => x.x.compareTo(y.x)),
        ));
      }
    }
    return filas;
  }

  /// [mesas] numeradas desde [desde], en el sentido que menos corta la
  /// serpentina (a igualdad, terminando adentro, como [acomodar]).
  static List<MesaPlano> _ordenadas(
    ArmadoSalon a,
    List<MesaPlano> mesas, {
    int desde = 1,
    FinNumeracion fin = FinNumeracion.escenario,
  }) {
    final filas = _filasDe(a, mesas);
    return _elQueMenosCorta([
      for (final r in _recorridos(fin))
        a.copyWith(
          mesas: _numeradas(_enSerpentina(filas, r), desde: desde),
        ),
    ]).mesas;
  }

  /// Numera el salón de 1 a N siguiendo donde están las mesas, **sin mover
  /// ninguna**: solo cambian los números. Las del pasto van al final.
  ///
  /// Es la misma serpentina de [acomodar], también entre hojas: la izquierda de
  /// la A y de la B, y la derecha de vuelta (o, con [fin] al fondo, la derecha
  /// de la A y de la B). Sobre un salón recién acomodado no cambia nada.
  /// `cambio` dice número viejo → número nuevo, solo de las mesas que cambian,
  /// para que lo que apunta a un número siga a su mesa.
  ///
  /// Solo es para antes del sorteo: `ultimoNumero` vuelve a N porque ningún
  /// número salió impreso con una familia. Decidir cuándo corre es de quien la
  /// llama.
  static ({ArmadoSalon armado, Map<int, int> cambio}) ordenarNumeros(
    ArmadoSalon a, {
    FinNumeracion fin = FinNumeracion.escenario,
  }) {
    if (a.mesas.isEmpty) return (armado: a, cambio: const <int, int>{});

    final comunes = _ordenadas(
      a,
      [for (final m in a.mesas) if (!m.pasto) m],
      fin: fin,
    );
    final pasto = _ordenadas(
      a,
      [for (final m in a.mesas) if (m.pasto) m],
      desde: comunes.length + 1,
      fin: fin,
    );
    final nuevas = [...comunes, ...pasto];

    // La mesa de cada lugar: dos mesas no comparten hoja, x e y.
    String lugar(MesaPlano m) => '${m.hoja}|${m.x}|${m.y}';
    final numeroViejo = <String, int>{
      for (final m in a.mesas) lugar(m): m.numero,
    };
    final cambio = <int, int>{
      for (final m in nuevas)
        if (numeroViejo[lugar(m)] != m.numero) numeroViejo[lugar(m)]!: m.numero,
    };

    final n = nuevas.length;
    if (cambio.isEmpty && (a.ultimoNumero == null || a.ultimoNumero == n)) {
      return (armado: a, cambio: cambio);
    }
    return (armado: a.copyWith(mesas: nuevas, ultimoNumero: n), cambio: cambio);
  }
}
