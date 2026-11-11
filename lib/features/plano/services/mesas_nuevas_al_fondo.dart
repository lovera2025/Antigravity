import 'dart:math' as math;

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/sorteo_mesas_motor.dart';
import '../modelo/armado_salon.dart';
import '../modelo/medidas_salon.dart';
import 'editar_armado.dart';

/// Una mesa que se agrega al salón para una familia.
class MesaNueva {
  final int numero;
  final String alumnoId;

  const MesaNueva(this.numero, this.alumnoId);
}

/// El salón con las mesas nuevas ya puestas, y para quién es cada una.
class PlanMesasNuevas {
  /// El salón como queda guardado, con las mesas nuevas.
  final ArmadoSalon armado;

  /// La configuración del plano, con cada mesa nueva fijada para su familia.
  final ConfigPlano config;

  /// Las mesas nuevas, en el orden en que se dieron.
  final List<MesaNueva> mesas;

  const PlanMesasNuevas({
    required this.armado,
    required this.config,
    required this.mesas,
  });

  bool get vacio => mesas.isEmpty;

  /// Familia → sus mesas nuevas, en orden.
  Map<String, List<int>> get porAlumno {
    final r = <String, List<int>>{};
    for (final m in mesas) {
      r.putIfAbsent(m.alumnoId, () => []).add(m.numero);
    }
    return r;
  }
}

/// Las mesas que llegan después del sorteo van al fondo (6.5.1).
///
/// Lo pidió el jefe el 10-nov-2026: a la familia que confirma una mesa con el
/// sorteo ya hecho no se le da un hueco del salón, se le agrega una mesa con
/// **el número que sigue** (102, 103…), al fondo a la derecha, donde hay lugar,
/// por orden de llegada.
///
/// Todo es cuenta pura: no lee ni guarda nada. La mesa nueva queda **fijada**
/// para su familia: el sorteo de siempre se la entrega (le da a cada familia sus
/// fijadas antes que nada, sin mover a nadie), y si el sorteo se deshace y se
/// vuelve a hacer, le toca la misma.
class MesasNuevasAlFondo {
  MesasNuevasAlFondo._();

  /// El motivo de la mesa fijada: se lee al tocarla en el plano.
  static const motivo = 'Mesa nueva: llegó después del sorteo';

  /// ¿Alguna familia activa ya tiene mesa? Las mesas nuevas son para después
  /// del sorteo: antes, el salón se arma con las mesas que hacen falta.
  static bool haySorteo(Iterable<ContratoAlumno> alumnos) => alumnos.any(
        (a) =>
            !a.esBajaTemporal &&
            MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isNotEmpty,
      );

  /// Por qué no se pueden agregar mesas nuevas para los que faltan, o null si
  /// se puede.
  static String? motivoSinMesasNuevas(
    ArmadoSalon armado,
    Iterable<ContratoAlumno> alumnos,
  ) {
    if (!haySorteo(alumnos)) {
      return 'Todavía no hay familias con mesa: primero se sortea.';
    }
    if (!EditarArmado.conBordeDelPlayon(armado)) {
      return 'Este armado es del Canva: las mesas se agregan en Personalizar '
          '→ Acomodar.';
    }
    return null;
  }

  /// Cuántas mesas nuevas le hacen falta a cada familia de [pedidos]: las que
  /// le faltan, menos las fijadas que ya tiene esperándola. Solo las familias
  /// a las que les falta alguna.
  ///
  /// Una familia con un número que no está en el plano no entra: el sorteo
  /// tampoco la toca.
  static Map<String, int> faltantes({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required Iterable<PedidoSorteo> pedidos,
  }) {
    final fijadas = config.fijadasPorAlumno;
    final r = <String, int>{};
    for (final p in pedidos) {
      if (p.actuales.any((n) => !armado.existe(n))) continue;
      final propias = [
        for (final n in fijadas[p.alumnoId] ?? const <int>[])
          if (armado.existe(n) && !p.actuales.contains(n)) n,
      ];
      final faltan = p.faltan - propias.length;
      if (faltan > 0) r[p.alumnoId] = faltan;
    }
    return r;
  }

  /// Agrega al salón una mesa por cada una que falta, con el número que sigue
  /// al más alto, y la deja fijada para su familia.
  ///
  /// - **El orden es el de llegada** ([llegada], la hora del pago): quien llegó
  ///   primero recibe el número más bajo. Sin hora, al final y por nombre.
  /// - **El lugar:** la primera, a continuación de la última fila del lado
  ///   derecho de la hoja del fondo (donde termina el salón); las siguientes,
  ///   al lado de la anterior. Nunca en el pasillo del medio. Las dos mesas de
  ///   una familia quedan juntas.
  /// - **El número** nunca llena un hueco ni repite uno que ya se dio
  ///   ([EditarArmado.proximoNumero]).
  /// - Ninguna otra mesa se mueve ni cambia de número.
  static PlanMesasNuevas planear({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required Iterable<ContratoAlumno> alumnos,
    required Iterable<PedidoSorteo> pedidos,
    Map<String, DateTime> llegada = const {},
    String? por,
    DateTime? ahora,
  }) {
    final faltan = faltantes(armado: armado, config: config, pedidos: pedidos);
    if (faltan.isEmpty) {
      return PlanMesasNuevas(armado: armado, config: config, mesas: const []);
    }
    final nombres = {for (final a in alumnos) a.id: a.nombreAlumno};
    final enOrden = faltan.keys.toList()
      ..sort((a, b) {
        final la = llegada[a], lb = llegada[b];
        if (la != null && lb != null && la != lb) return la.compareTo(lb);
        if ((la == null) != (lb == null)) return la == null ? 1 : -1;
        final porNombre = (nombres[a] ?? '').compareTo(nombres[b] ?? '');
        return porNombre != 0 ? porNombre : a.compareTo(b);
      });

    // Los números que ya son de alguien, estén o no en el plano.
    final usados = <int>{
      ...SorteoMesasMotor.ocupadas(alumnos),
      ...config.fijadas.keys,
      ...config.libres.keys,
    };

    final hoja = _hojaDelFondo(armado);
    final lugarM = _paso(armado, hoja, config.medidas);
    var salon = armado;
    final fijadas = {...config.fijadas};
    final nuevas = <MesaNueva>[];
    int? anterior;
    for (final id in enOrden) {
      for (var i = 0; i < faltan[id]!; i++) {
        final numero = EditarArmado.proximoNumero(salon, usados);
        final cerca = anterior ?? _referencia(salon, hoja, lugarM)?.numero;
        final lugar = EditarArmado.lugarLibre(
          salon,
          hoja,
          cerca: cerca,
          lugarM: lugarM,
          fueraDelPasillo: cerca != null,
        );
        salon = EditarArmado.agregar(
          salon,
          numero: numero,
          hoja: hoja,
          x: lugar.x,
          y: lugar.y,
        );
        usados.add(numero);
        fijadas[numero] = MesaFijada(
          alumnoId: id,
          motivo: motivo,
          por: por,
          cuando: ahora,
        );
        nuevas.add(MesaNueva(numero, id));
        anterior = numero;
      }
    }
    return PlanMesasNuevas(
      armado: EditarArmado.comoSeGuarda(salon, armado, ordenar: false),
      config: config.copyWith(fijadas: fijadas),
      mesas: nuevas,
    );
  }

  /// La hoja donde termina el salón: la última que tiene mesas comunes (en un
  /// salón de dos hojas, "Al fondo"). Sin mesas, la última.
  static String _hojaDelFondo(ArmadoSalon a) {
    for (final h in a.hojas.reversed) {
      if (a.mesasDeHoja(h.id).any((m) => !m.pasto)) return h.id;
    }
    return a.hojas.last.id;
  }

  /// A cuánto están las mesas de esa hoja, en metros: la mesa nueva queda a la
  /// misma distancia que las demás, aunque el salón se haya estirado después
  /// de armarlo. Sin mesas para medir, la de Medidas.
  static double _paso(ArmadoSalon a, String hoja, MedidasPlano medidas) {
    final medido = EditarArmado.pasoDe(a, [
      for (final m in a.mesasDeHoja(hoja))
        if (!m.pasto) m.numero,
    ]);
    return (medido ?? medidas.lugarMesaM).clamp(
      MedidasPlano.lugarMinimoM,
      MedidasPlano.lugarMaximoM,
    );
  }

  /// La mesa de la que siguen las nuevas: la de más afuera de la última fila
  /// del lado derecho. Null si de ese lado no hay ninguna: ahí la mesa nueva va
  /// a continuación de la última fila, como al agregarla a mano.
  static MesaPlano? _referencia(ArmadoSalon a, String hoja, double lugarM) {
    final medio = EditarArmado.centroX(a, hoja);
    final derecha = [
      for (final m in a.mesasDeHoja(hoja))
        if (!m.pasto && m.x >= medio) m,
    ];
    if (derecha.isEmpty) return null;
    final fondo = derecha.map((m) => m.y).reduce(math.max);
    final medioPaso = a.aUnidades(lugarM) / 2;
    MesaPlano? mejor;
    for (final m in derecha) {
      if (fondo - m.y >= medioPaso) continue;
      if (mejor == null || m.x > mejor.x) mejor = m;
    }
    return mejor;
  }
}
