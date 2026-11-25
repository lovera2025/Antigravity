import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/pago_para_sorteo.dart';
import '../../eventos/services/salon_mesas.dart';
import '../../eventos/services/sorteo_mesas_motor.dart';
import 'cambios_de_mesa.dart';
import 'mesa_nueva_sola.dart';
import 'mesas_nuevas_al_fondo.dart';
import 'sorteo_con_plano.dart';

/// DAR MESA, en la grilla de la fiesta (6.9.4): **el jefe le da la mesa** a
/// quien no la tiene porque no pagó, uno por uno o a todos juntos, y el número
/// aparece al instante, como cuando la familia paga una cuota.
///
/// Lo pidió el usuario el 25-nov-2026 con el caso de la Técnica: cuatro
/// familias sin nada pagado con su mesa fijada por el jefe esperándolas, y
/// una con la 107, a la que le faltaba la adicional.
///
/// Qué número le toca a cada uno, en este orden (decidido con él):
/// 1. la mesa fijada que lo esperaba;
/// 2. una mesa del fondo que quedó vacía ([MesasNuevasAlFondo.vaciasDelFondo]):
///    a quien ya tiene mesa, la más cerca de las suyas (la 106, al
///    lado de su 107); con más familias que vacías, el azar decide quién la
///    recibe;
/// 3. si no, una mesa nueva al fondo con el número que sigue.
///
/// **Nadie más se mueve**: el sorteo de siempre corre solo para las familias
/// elegidas y les entrega sus fijadas, como en [MesaNuevaSola]. La principal de
/// cada familia queda primera (`SalonMesas.principal`): la de la 107 queda "107,
/// 106". Lo que deben sigue en su cuenta: no toca plata.
///
/// Es cuenta pura: la pantalla lee la nube, guarda con la llave del modo jefe
/// y pone la puerta al día.
class MesaQueDaElJefe {
  MesaQueDaElJefe._();

  /// Cuántas mesas le faltan a la familia para tener todas las de su cuenta.
  /// Cero si tiene todas, si es de baja o si su número no se entiende (eso no
  /// lo toca nadie).
  static int leFaltan(ContratoAlumno a) {
    if (a.esBajaTemporal) return 0;
    final texto = a.numeroMesa?.trim() ?? '';
    final numeros = MesasExtraUtils.numerosMesaDesdeTexto(texto);
    if (texto.isNotEmpty && numeros.isEmpty) return 0;
    return max(0, SalonMesas.mesas(a) - numeros.length);
  }

  /// Quiénes pueden recibir DAR MESA: con el sorteo ya hecho, los activos a
  /// los que les falta alguna mesa. Por apellido.
  static List<ContratoAlumno> aQuienes(Iterable<ContratoAlumno> alumnos) {
    if (!MesasNuevasAlFondo.haySorteo(alumnos)) return const [];
    return [
      for (final a in alumnos)
        if (leFaltan(a) > 0) a,
    ]..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
  }

  /// Qué hay que guardar para darles la mesa a [elegidos], o null si no hay
  /// nada que dar. Lanza [StateError] con el motivo, en palabras, si no se
  /// puede (un armado del Canva, o el control final del sorteo encontró algo).
  ///
  /// [azar] decide quién recibe las mesas vacías del fondo cuando son menos
  /// que las familias; en las pruebas va con semilla.
  static CuentaMesaNueva? calcular({
    required PlanoEvento plano,
    required List<ContratoAlumno> alumnos,
    required Map<String, List<Map<String, dynamic>>> pagos,
    required Iterable<SorteoMesasRegistro> registros,
    required Set<String> elegidos,
    Random? azar,
    String? por,
    DateTime? ahora,
  }) {
    if (elegidos.isEmpty) return null;
    final armado = plano.armadoONull;
    if (armado == null) throw StateError('La fiesta no tiene el salón armado.');
    final motivo = MesasNuevasAlFondo.motivoSinMesasNuevas(armado, alumnos);
    if (motivo != null) throw StateError(motivo);

    // Lo de siempre ("solo a lo que tiene algo pagado"), con los elegidos
    // tildados "sortear igual": eso es lo que destraba el jefe.
    final loPagado = pagosPorAlumno(alumnos, pagos);
    final exclusion = exclusionSorteo(
      candidatos: candidatosPorPago(alumnos, loPagado),
      soloPagado: true,
      incluirBase: elegidos,
      incluirExtras: elegidos,
    );
    // A un elegido se le dan todas las que le faltan: también la adicional que
    // no pagó, aunque tampoco haya pagado la base.
    final soloBase = exclusion.soloBase.difference(elegidos);
    final todos = SorteoMesasMotor.pedidos(
      alumnos,
      sinMesa: exclusion.sinMesa,
      soloBase: soloBase,
    );
    final pedidos = [
      for (final p in todos)
        if (elegidos.contains(p.alumnoId) && p.faltan > 0) p,
    ];
    if (pedidos.isEmpty) return null;

    final nuevas = MesasNuevasAlFondo.planear(
      armado: armado,
      config: plano.config,
      alumnos: alumnos,
      pedidos: pedidos,
      vacias: MesasNuevasAlFondo.vaciasDelFondo(
        armado: armado,
        config: plano.config,
        alumnos: alumnos,
        registros: registros,
      ),
      azar: azar ?? Random(),
      por: por,
      ahora: ahora,
    );
    // El sorteo de siempre, solo para los elegidos: les entrega sus fijadas
    // (las que los esperaban, las vacías y las nuevas). Los demás que esperan
    // mesa no entran.
    final entran = {for (final p in pedidos) p.alumnoId};
    final entrada = EntradaSorteoPlano(
      armado: nuevas.armado,
      config: nuevas.config,
      alumnos: alumnos,
      exclusion: ExclusionSorteo(
        sinMesa: {
          ...exclusion.sinMesa,
          for (final p in todos)
            if (!entran.contains(p.alumnoId)) p.alumnoId,
        },
        soloBase: soloBase,
      ),
      modo: ModoSorteo.entera,
    );
    final ResultadoSorteoPlano resultado;
    try {
      resultado = SorteoConPlano.sortear(entrada, random: Random(0));
    } on StateError catch (e) {
      throw StateError('No entra en el salón (${e.message}).');
    }
    final problema = SorteoConPlano.validar(entrada, resultado);
    if (problema != null) throw StateError(problema);

    // Solo se guarda lo que salió de una fijada: nunca una mesa del salón
    // elegida al azar.
    final fijadas = nuevas.config.fijadasPorAlumno;
    final asignaciones = <String, List<int>>{};
    final antes = <String, List<int>>{};
    for (final e in resultado.asignaciones.entries) {
      final a = _alumno(alumnos, e.key);
      if (a == null) continue;
      final tenia = MesasExtraUtils.numerosEnOrdenDelTexto(a.numeroMesa);
      final recibe = [
        for (final n in e.value)
          if (!tenia.contains(n)) n,
      ]..sort();
      if (recibe.isEmpty) continue;
      final suyas = fijadas[e.key] ?? const <int>[];
      if (!recibe.every(suyas.contains)) {
        throw StateError(
          'A ${CambiosDeMesa.apellido(a)} le tocaba una mesa que no es la '
          'suya: no se guardó nada.',
        );
      }
      // La principal primera, y después lo que recibe.
      asignaciones[e.key] = [...tenia, ...recibe];
      antes[e.key] = tenia;
    }
    if (asignaciones.isEmpty) return null;
    return CuentaMesaNueva(
      asignaciones: asignaciones,
      antes: antes,
      nuevas: nuevas,
    );
  }

  static ContratoAlumno? _alumno(List<ContratoAlumno> alumnos, String id) {
    for (final a in alumnos) {
      if (a.id == id) return a;
    }
    return null;
  }
}
