import 'dart:math' as math;

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sorteo_mesas_registro.dart';
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

  /// Las mesas del fondo que quedaron vacías (6.9.4): las que se agregaron
  /// como mesa nueva al fondo (la clave `_nuevas` de algún renglón de
  /// [registros]) y hoy no son de nadie: ninguna familia la tiene anotada, no
  /// está fijada ni es libre o reservada.
  ///
  /// Pasa cuando el jefe mueve a esa familia a otra mesa: la 106 de la Técnica
  /// se la dio el programa a una familia el 11-nov-2026, el jefe la pasó a la
  /// 51 el 16-nov y la 106 quedó vacía; a la siguiente el programa le dio la
  /// 107. Un hueco del medio del salón no entra: ese lo acomoda el jefe.
  static Set<int> vaciasDelFondo({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required Iterable<ContratoAlumno> alumnos,
    required Iterable<SorteoMesasRegistro> registros,
  }) {
    final usados = <int>{
      ...SorteoMesasMotor.ocupadas(alumnos),
      ...config.fijadas.keys,
      ...config.libres.keys,
    };
    return {
      for (final r in registros)
        for (final texto in (r.nuevas ?? const <String, String>{}).values)
          for (final n in MesasExtraUtils.numerosMesaDesdeTexto(texto))
            if (armado.existe(n) && !usados.contains(n)) n,
    };
  }

  /// Agrega al salón una mesa por cada una que falta, con el número que sigue
  /// al más alto, y la deja fijada para su familia.
  ///
  /// - **Antes, las [vacias] del fondo** (6.9.4, [vaciasDelFondo]): si hay
  ///   una, la familia recibe esa en vez de una nueva, también fijada. Primero
  ///   las familias que ya tienen mesa, cada una la vacía más cerca de las
  ///   suyas (la 106, al lado de la 107); después las que no tienen ninguna,
  ///   la de número más bajo. Así no queda una mesa vacía en el plano.
  /// - Con [soloSiQuedaEnOrden] (la mesa que el programa da solo), una familia
  ///   con mesa solo recibe una vacía con número más alto que todas las suyas:
  ///   así sus números siguen de menor a mayor y una PC con la 6.9.3 los lee
  ///   igual. DAR MESA, que es del jefe, no lo pide.
  /// - Con [azar], el orden de las familias es al azar en vez del de llegada:
  ///   lo usa DAR MESA A TODOS, que reparte las vacías entre varias a la vez.
  ///
  /// - **El orden es el de llegada** ([llegada], la hora del pago): quien llegó
  ///   primero recibe el número más bajo. Sin hora, al final y por nombre.
  /// - **El lugar:** la primera, a continuación de la última fila del lado
  ///   derecho de la hoja del fondo (donde termina el salón); las siguientes,
  ///   al lado de la anterior. Nunca en el pasillo del medio. Las dos mesas de
  ///   una familia quedan juntas.
  /// - **El número** de una mesa nueva nunca llena un hueco ni repite uno que
  ///   ya se dio ([EditarArmado.proximoNumero]).
  /// - Ninguna otra mesa se mueve ni cambia de número.
  static PlanMesasNuevas planear({
    required ArmadoSalon armado,
    required ConfigPlano config,
    required Iterable<ContratoAlumno> alumnos,
    required Iterable<PedidoSorteo> pedidos,
    Map<String, DateTime> llegada = const {},
    Set<int> vacias = const {},
    bool soloSiQuedaEnOrden = false,
    math.Random? azar,
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
    if (azar != null) enOrden.shuffle(azar);
    final actuales = {for (final p in pedidos) p.alumnoId: p.actuales};

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
    final libres = {
      for (final n in vacias)
        if (armado.existe(n) && !usados.contains(n)) n,
    };
    // Las vacías del fondo, antes que nada: primero a las familias que ya
    // tienen mesa (la más cerca de las suyas), después a las que no tienen.
    final deVacias = <String, List<int>>{};
    void repartirVacias({required bool conMesa}) {
      for (final id in enOrden) {
        final suyas = actuales[id] ?? const <int>[];
        if (suyas.isNotEmpty != conMesa) continue;
        for (var i = 0; i < faltan[id]!; i++) {
          final tope = suyas.isEmpty ? null : suyas.reduce(math.max);
          final candidatas = {
            for (final n in libres)
              if (!soloSiQuedaEnOrden || tope == null || n > tope) n,
          };
          final vacia = _vaciaMasCerca(
            armado,
            candidatas,
            [...suyas, ...?deVacias[id]],
          );
          if (vacia == null) break;
          libres.remove(vacia);
          deVacias.putIfAbsent(id, () => []).add(vacia);
        }
      }
    }

    repartirVacias(conMesa: true);
    repartirVacias(conMesa: false);

    int? anterior;
    for (final id in enOrden) {
      final vaciasSuyas = [...?deVacias[id]];
      for (var i = 0; i < faltan[id]!; i++) {
        final vacia = vaciasSuyas.isEmpty ? null : vaciasSuyas.removeAt(0);
        if (vacia != null) {
          usados.add(vacia);
          fijadas[vacia] = MesaFijada(
            alumnoId: id,
            motivo: motivo,
            por: por,
            cuando: ahora,
          );
          nuevas.add(MesaNueva(vacia, id));
          anterior = vacia;
          continue;
        }
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

  /// De [libres], la que le toca a una familia con estas mesas ([suyas]): la
  /// más cerca de alguna de ellas, en la misma hoja; sin mesas (o ninguna en
  /// esa hoja), la de número más bajo. Null si no queda ninguna.
  static int? _vaciaMasCerca(
    ArmadoSalon armado,
    Set<int> libres,
    List<int> suyas,
  ) {
    if (libres.isEmpty) return null;
    final ordenadas = libres.toList()..sort();
    int? mejor;
    var mejorDistancia = double.infinity;
    for (final n in ordenadas) {
      final m = armado.mesa(n);
      if (m == null) continue;
      for (final s in suyas) {
        final o = armado.mesa(s);
        if (o == null || o.hoja != m.hoja) continue;
        final d = math.sqrt(math.pow(m.x - o.x, 2) + math.pow(m.y - o.y, 2));
        if (d < mejorDistancia) {
          mejorDistancia = d;
          mejor = n;
        }
      }
    }
    return mejor ?? ordenadas.first;
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
