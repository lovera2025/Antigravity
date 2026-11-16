import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../plano/services/mesas_nuevas_al_fondo.dart';
import '../../plano/services/orden_en_el_salon.dart';
import '../../plano/services/sorteo_con_plano.dart';
import 'mesas_extra_utils.dart';
import 'pago_para_sorteo.dart';
import 'sorteo_mesas_motor.dart';

/// De lo que se eligió en el cartel del SORTEO a lo que se sortea sobre el
/// plano (16-nov-2026): un solo camino, sin pantalla ni base.
///
/// Lo usan la pantalla de la fiesta (`_ejecutarSorteoConPlano`), la ventana de
/// prueba del plano y las pruebas de punta a punta. Así una prueba que tilda
/// en el cartel y aprieta SORTEAR recorre el mismo código que la app: antes la
/// ventana de prueba lo repetía a mano, y podía quedar distinto.
///
/// La pantalla sigue haciendo lo suyo: leer la nube, guardar, poner la puerta
/// al día y anotar el registro.
class SorteoDelCartel {
  /// Por qué no se puede sortear así ("Cumplimiento debido" sin lugar). Si
  /// está, no hay [entrada].
  final String? problema;

  /// Con "Cumplimiento debido": quién va a qué mesa.
  final OrdenParaElSorteo? orden;

  /// Con el sorteo ya hecho: las mesas nuevas al fondo para los que faltan.
  final PlanMesasNuevas? nuevas;

  /// Lo que se guarda del plano con el sorteo.
  final ConfigPlano? configDelPlano;

  /// Lo que se le pide al sorteo.
  final EntradaSorteoPlano? entrada;

  const SorteoDelCartel._({
    this.problema,
    this.orden,
    this.nuevas,
    this.configDelPlano,
    this.entrada,
  });

  bool get sePuede => problema == null && entrada != null;

  /// Arma el sorteo con lo elegido en el cartel ([config]) y los datos de
  /// ahora (recién leídos: [alumnos], [pagos] y [pagosCrudos]).
  static SorteoDelCartel armar({
    required String eventoId,
    required PlanoEvento plano,
    required List<ContratoAlumno> alumnos,
    required SorteoMesasDialogResult config,
    required ExclusionSorteo exclusion,
    required Map<String, PagoAlumno> pagos,
    required Map<String, List<Map<String, dynamic>>> pagosCrudos,
    required DateTime hoyAr,
    required DateTime ahora,
    String? por,
  }) {
    // Lo que dejó el tilde de la 6.7.0 (fijaba las mesas antes de sortear, a
    // la vista) no entra al sorteo ni se vuelve a guardar.
    final configBase =
        OrdenEnElSalon.sinFijadasDelOrden(plano.config) ?? plano.config;
    // "Cumplimiento debido" (6.7.1): se calcula al sortear, con lo recién
    // leído. Le fija a cada familia su mesa solo para esta corrida; el sorteo
    // de siempre se las entrega. Con el sorteo ya hecho, reacomoda.
    OrdenParaElSorteo? orden;
    if (config.porCumplimiento) {
      orden = OrdenEnElSalon.paraElSorteo(
        eventoId: eventoId,
        armado: plano.armado,
        config: configBase,
        alumnos: alumnos,
        pagos: pagosCrudos,
        hoyAr: hoyAr,
        ahora: ahora,
        exclusion: exclusion,
        modo: config.modo!,
        recorrido: config.recorrido,
        usarPasto: config.usarPasto,
        adicionalesAlFinal: config.adicionalesAlFinal,
        juntasConLaPrincipal: config.juntasConLaPrincipal,
        unaMesaPrimero: config.unaMesaPrimero,
        por: por,
      );
      if (!orden.sePuede) return SorteoDelCartel._(problema: orden.problema);
    }
    // Con el sorteo ya hecho, las mesas que faltan van en mesas nuevas, al
    // fondo (6.5.1): se agregan al salón y quedan fijadas para su familia, y el
    // sorteo de siempre se las entrega. Es la misma cuenta que mostró el
    // cartel, con los datos recién leídos.
    PlanMesasNuevas? nuevas;
    if (orden == null &&
        config.mesasNuevasAlFondo &&
        MesasNuevasAlFondo.motivoSinMesasNuevas(plano.armado, alumnos) ==
            null) {
      final plan = MesasNuevasAlFondo.planear(
        armado: plano.armado,
        config: configBase,
        alumnos: alumnos,
        pedidos: SorteoMesasMotor.pedidos(
          alumnos,
          separaciones: config.separaciones,
          sinMesa: exclusion.sinMesa,
          soloBase: exclusion.soloBase,
        ),
        llegada: llegadaPorPago(pagos),
        por: por,
        ahora: ahora,
      );
      if (!plan.vacio) nuevas = plan;
    }
    // Lo que se guarda del plano. Un sorteo entero sin el tilde no deja escrito
    // el porqué de otro.
    final nadieTeniaMesa = alumnos.every(
      (a) => MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isEmpty,
    );
    final sinOrden = nuevas?.config ?? configBase;
    final configDelPlano = orden?.configAGuardar ??
        (nadieTeniaMesa
            ? OrdenEnElSalon.apagado(sinOrden) ?? sinOrden
            : sinOrden);
    final entrada = orden != null
        ? OrdenEnElSalon.entrada(
            orden,
            armado: plano.armado,
            usarPasto: config.usarPasto,
          )
        : EntradaSorteoPlano(
            armado: nuevas?.armado ?? plano.armado,
            config: sinOrden,
            alumnos: alumnos,
            exclusion: exclusion,
            separaciones: config.separaciones,
            distancias: config.distancias,
            modo: config.modo!,
            ordenDivisiones: config.ordenDivisiones,
            usarPasto: config.usarPasto,
            hastaMesa: config.hastaMesa,
            zonas: config.zonas,
            alFinal: config.alFinal,
            unaMesaPrimero: config.unaMesaPrimero,
          );
    return SorteoDelCartel._(
      orden: orden,
      nuevas: nuevas,
      configDelPlano: configDelPlano,
      entrada: entrada,
    );
  }

  /// Sortea con lo armado. Tira [StateError] si no entra (el cartel no deja
  /// llegar acá; si igual pasa, la pantalla lo dice).
  ResultadoSorteoPlano sortear({Random? random}) =>
      SorteoConPlano.sortear(entrada!, random: random);

  /// El control final antes de guardar: [SorteoConPlano.validar] y, con
  /// "Cumplimiento debido", que cada familia esté en la mesa que le tocó. Null
  /// si está todo bien; si no, el motivo, y no se guarda nada.
  String? controlFinal(ResultadoSorteoPlano r) =>
      SorteoConPlano.validar(entrada!, r) ??
      (orden == null ? null : OrdenEnElSalon.noCumple(orden!, r));
}
