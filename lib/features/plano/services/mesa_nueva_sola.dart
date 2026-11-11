import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/pago_para_sorteo.dart';
import '../../eventos/services/sorteo_mesas_motor.dart';
import 'cambios_de_mesa.dart';
import 'mesas_nuevas_al_fondo.dart';
import 'sorteo_con_plano.dart';

/// Con esto en false, el programa no le da mesa sola a nadie: queda el botón
/// SORTEO del jefe, que ofrece la mesa nueva al fondo. Un solo lugar para
/// apagarlo.
const kMesaNuevaSolaHabilitada = true;

/// Lo que la mesa nueva sola necesita del programa: leer y guardar. En la app
/// son los repositorios; en las pruebas, dos PCs en memoria con una nube de
/// mentira entre las dos.
abstract class PuertosDeLaMesaNueva {
  /// Los alumnos del evento, como están en esta PC.
  Future<List<ContratoAlumno>> alumnos(String eventoId);

  /// Los pagos de esos alumnos, por alumno, como están en esta PC.
  Future<Map<String, List<Map<String, dynamic>>>> pagos(
    List<ContratoAlumno> alumnos,
  );

  /// El registro de sorteos del evento, como está en esta PC.
  Future<List<SorteoMesasRegistro>> registros(String eventoId);

  /// El plano que tiene esta PC, sin pedirle nada a la nube. Null: no tiene.
  Future<PlanoEvento?> planoDeEstaPc(String eventoId);

  /// Cuántos alumnos tienen en la nube otra mesa que acá, sin un cambio propio
  /// esperando subir. Null: no hay internet.
  Future<int?> mesasDeOtraPcSinBajar(String eventoId);

  /// El plano como está en la nube. Null: la fiesta no tiene. **Lanza** si no
  /// se pudo leer.
  Future<PlanoEvento?> planoDeLaNube(String eventoId);

  /// Los números, el renglón del registro y el plano, en una sola transacción,
  /// y a subir.
  Future<void> guardar({
    required Map<String, String> numeros,
    required SorteoMesasRegistro registro,
    required PlanoEvento plano,
  });

  /// La lista de la puerta, al día para esos alumnos.
  Future<void> puertaAlDia(String eventoId, Iterable<String> alumnos);

  DateTime ahora();
  String nuevoId();
}

/// Qué pasó al revisar un evento.
enum EstadoMesaNueva {
  /// No había nada que hacer.
  nada,

  /// Hay alguien esperando su mesa y no hay internet: se le da al volver.
  sinInternet,

  /// Otra PC cambió mesas que todavía no bajaron: se vuelve a mirar después.
  esperar,

  /// Se le dio la mesa a alguien.
  dio,

  /// La cuenta no cerró: no se guardó nada.
  fallo,
}

class ResultadoMesaNueva {
  final EstadoMesaNueva estado;

  /// Alumno → las mesas que recibió (una nueva, o una fijada que lo esperaba).
  final Map<String, List<int>> dadas;

  /// Alumno → su apellido, para decirlo.
  final Map<String, String> apellidos;

  /// Por qué no se pudo, o quién quedó esperando.
  final String? detalle;

  const ResultadoMesaNueva(
    this.estado, {
    this.dadas = const {},
    this.apellidos = const {},
    this.detalle,
  });

  static const nada = ResultadoMesaNueva(EstadoMesaNueva.nada);

  /// Lo que se le dice a quien está en la pantalla. Null si no hay nada que
  /// decir.
  String? get aviso {
    switch (estado) {
      case EstadoMesaNueva.dio:
        final partes = [
          for (final e in dadas.entries)
            'A ${apellidos[e.key] ?? 'una familia'} se le dio la '
                '${e.value.length == 1 ? 'mesa' : 'mesas'} '
                '${e.value.join(' y ')}',
        ];
        return '${partes.join('. ')}.';
      case EstadoMesaNueva.sinInternet:
        return 'A ${detalle ?? 'una familia'} le falta el número de su mesa: '
            'se le da solo cuando vuelva internet.';
      case EstadoMesaNueva.fallo:
        return 'No se le pudo dar la mesa sola a ${detalle ?? 'una familia'}: '
            'el jefe se la da con SORTEO.';
      case EstadoMesaNueva.nada:
      case EstadoMesaNueva.esperar:
        return null;
    }
  }
}

/// Lo que hay que guardar para darle la mesa a quienes la esperan.
class CuentaMesaNueva {
  /// Alumno → todos sus números, como quedan.
  final Map<String, List<int>> asignaciones;

  /// Alumno → los números que tenía antes.
  final Map<String, List<int>> antes;

  /// Las mesas que se agregan al salón (vacío si alcanzó con las fijadas).
  final PlanMesasNuevas nuevas;

  /// Familias que perdieron un número repetido antes de recibir el suyo: dos
  /// PCs le habían dado la misma mesa nueva a dos familias.
  final Set<String> repetidos;

  const CuentaMesaNueva({
    required this.asignaciones,
    required this.antes,
    required this.nuevas,
    this.repetidos = const {},
  });

  /// Alumno → solo las mesas que recibe ahora.
  Map<String, List<int>> get dadas => {
        for (final e in asignaciones.entries)
          e.key: [
            for (final n in e.value)
              if (!(antes[e.key] ?? const <int>[]).contains(n)) n,
          ],
      };
}

/// La mesa nueva se da sola (6.5.1, pedido del usuario el 10-nov-2026: "¿por
/// qué tendría que apretar?").
///
/// Con el sorteo ya hecho, a la familia que **pagó después del último sorteo**
/// y le falta el número de una mesa que tiene algo pagado, el programa le da
/// la mesa sin que el jefe apriete SORTEO: su mesa fijada, si tenía una
/// esperándola, o una mesa nueva al fondo con el número que sigue
/// ([MesasNuevasAlFondo]).
///
/// **Es lo único del salón que el programa hace sin modo jefe**, y por eso es
/// angosto a propósito:
/// - solo **agrega**: nunca mueve ni saca una mesa de nadie;
/// - solo a quien pagó **después** del último sorteo, deshacer o restaurar que
///   hizo el jefe: si el jefe deshace un sorteo, esas familias no vuelven a
///   recibir mesa solas;
/// - la mesa adicional sin pagar sigue con candado, y quien no pagó nada de su
///   contrato tampoco entra: es la misma cuenta del sorteo ("solo a lo que
///   tiene algo pagado"), sin excepciones tildadas;
/// - solo **con internet** y con el plano recién leído de la nube: sin eso, dos
///   PCs podrían darle el mismo número a dos familias;
/// - queda anotado en el registro como automático, y el jefe lo deshace con
///   DESHACER → "solo los últimos sorteados".
class MesaNuevaSola {
  final PuertosDeLaMesaNueva _puertos;

  MesaNuevaSola(this._puertos);

  /// Cuándo fue el último sorteo, deshacer o restaurar **que hizo el jefe**
  /// (los renglones automáticos no cuentan). Null: la fiesta no tiene registro,
  /// y ahí no se puede saber quién llegó después.
  static DateTime? ultimoDelJefe(Iterable<SorteoMesasRegistro> registros) {
    DateTime? ultimo;
    for (final r in registros) {
      if (r.automatico) continue;
      if (ultimo == null || r.createdAt.isAfter(ultimo)) ultimo = r.createdAt;
    }
    return ultimo;
  }

  /// Qué hay que guardar, o null si no hay nada que hacer. Cuenta pura.
  ///
  /// Lanza [StateError] si la cuenta no cierra (el control final del sorteo
  /// encontró algo): no hay que guardar nada.
  static CuentaMesaNueva? calcular({
    required PlanoEvento plano,
    required List<ContratoAlumno> alumnos,
    required Map<String, List<Map<String, dynamic>>> pagos,
    required Iterable<SorteoMesasRegistro> registros,
    String? por,
    DateTime? ahora,
  }) {
    final armado = plano.armadoONull;
    if (armado == null) return null;
    if (MesasNuevasAlFondo.motivoSinMesasNuevas(armado, alumnos) != null) {
      return null;
    }
    final desde = ultimoDelJefe(registros);
    if (desde == null) return null;

    // Dos PCs le dieron la misma mesa nueva a dos familias: se la queda la que
    // figura en el plano de la nube, y la otra vuelve a esperar la suya.
    final sinRepetidos = _sinRepetidos(alumnos, plano.config);
    final vistos = sinRepetidos.alumnos;

    final loPagado = pagosPorAlumno(vistos, pagos);
    final exclusion = exclusionSorteo(
      candidatos: candidatosPorPago(vistos, loPagado),
      soloPagado: true,
    );
    final llegada = llegadaPorPago(loPagado);
    bool llegoDespues(String id) =>
        sinRepetidos.perdieron.contains(id) ||
        (llegada[id]?.isAfter(desde) ?? false);

    final todos = SorteoMesasMotor.pedidos(
      vistos,
      sinMesa: exclusion.sinMesa,
      soloBase: exclusion.soloBase,
    );
    final pedidos = [
      for (final p in todos)
        if (llegoDespues(p.alumnoId)) p,
    ];
    if (pedidos.isEmpty) return null;

    final nuevas = MesasNuevasAlFondo.planear(
      armado: armado,
      config: plano.config,
      alumnos: vistos,
      pedidos: pedidos,
      llegada: llegada,
      por: por,
      ahora: ahora,
    );
    // El sorteo de siempre, solo para esas familias: les entrega sus fijadas
    // (las que ya tenían esperándolas y las nuevas). Los demás que esperan
    // mesa (un sorteo que el jefe deshizo, uno que no pagó nada) no entran.
    final entran = {for (final p in pedidos) p.alumnoId};
    final entrada = EntradaSorteoPlano(
      armado: nuevas.armado,
      config: nuevas.config,
      alumnos: vistos,
      exclusion: ExclusionSorteo(
        sinMesa: {
          ...exclusion.sinMesa,
          for (final p in todos)
            if (!entran.contains(p.alumnoId)) p.alumnoId,
        },
        soloBase: exclusion.soloBase,
      ),
      modo: ModoSorteo.entera,
    );
    final ResultadoSorteoPlano resultado;
    try {
      resultado = SorteoConPlano.sortear(entrada, random: Random(0));
    } on StateError catch (e) {
      throw StateError('no entra (${e.message})');
    }
    final problema = SorteoConPlano.validar(entrada, resultado);
    if (problema != null) throw StateError(problema);

    // Solo se guarda lo que salió de una fijada: una mesa nueva, o una que el
    // jefe le había reservado. Nunca una mesa libre del salón elegida al azar.
    final fijadas = nuevas.config.fijadasPorAlumno;
    final asignaciones = <String, List<int>>{};
    final antes = <String, List<int>>{};
    for (final e in resultado.asignaciones.entries) {
      final tenia = MesasExtraUtils.numerosMesaDesdeTexto(
        _alumno(vistos, e.key)?.numeroMesa,
      ).toList()
        ..sort();
      final recibe = [
        for (final n in e.value)
          if (!tenia.contains(n)) n,
      ];
      if (recibe.isEmpty) continue;
      final suyas = fijadas[e.key] ?? const <int>[];
      if (!recibe.every(suyas.contains)) {
        throw StateError(
          'a ${CambiosDeMesa.apellido(_alumno(vistos, e.key)!)} le tocaba una '
          'mesa que no es la suya',
        );
      }
      asignaciones[e.key] = [...e.value]..sort();
      antes[e.key] = _numerosDe(alumnos, e.key);
    }
    // Quien perdió un número repetido y no recibió otro igual tiene que
    // guardarse sin ese número.
    for (final id in sinRepetidos.perdieron) {
      if (asignaciones.containsKey(id)) continue;
      final a = _alumno(vistos, id);
      if (a == null) continue;
      asignaciones[id] = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)
          .toList()
        ..sort();
      antes[id] = _numerosDe(alumnos, id);
    }
    if (asignaciones.isEmpty) return null;
    return CuentaMesaNueva(
      asignaciones: asignaciones,
      antes: antes,
      nuevas: nuevas,
      repetidos: sinRepetidos.perdieron,
    );
  }

  /// Los números que tiene hoy, como están guardados (con el repetido, si lo
  /// tiene): es lo que el renglón anota como "antes".
  static List<int> _numerosDe(List<ContratoAlumno> alumnos, String id) =>
      MesasExtraUtils.numerosMesaDesdeTexto(_alumno(alumnos, id)?.numeroMesa)
          .toList()
        ..sort();

  static ContratoAlumno? _alumno(List<ContratoAlumno> alumnos, String id) {
    for (final a in alumnos) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Los alumnos, sin los números repetidos de mesas nuevas: si una mesa que
  /// se agregó sola figura en dos familias activas, se la queda la del plano
  /// (la fila del plano sube entera: en la nube quedó una sola dueña) y la otra
  /// la pierde. Solo mira mesas fijadas con el motivo de la mesa nueva: una
  /// mesa repetida a mano no la toca.
  static ({List<ContratoAlumno> alumnos, Set<String> perdieron}) _sinRepetidos(
    List<ContratoAlumno> alumnos,
    ConfigPlano config,
  ) {
    final perdieron = <String>{};
    final quitar = <String, Set<int>>{};
    final porMesa = <int, List<String>>{};
    for (final a in alumnos) {
      if (a.esBajaTemporal) continue;
      for (final n in MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa)) {
        porMesa.putIfAbsent(n, () => []).add(a.id);
      }
    }
    for (final e in porMesa.entries) {
      if (e.value.length < 2) continue;
      final fijada = config.fijadas[e.key];
      if (fijada == null || fijada.motivo != MesasNuevasAlFondo.motivo) {
        continue;
      }
      if (!e.value.contains(fijada.alumnoId)) continue;
      for (final id in e.value) {
        if (id == fijada.alumnoId) continue;
        perdieron.add(id);
        quitar.putIfAbsent(id, () => {}).add(e.key);
      }
    }
    if (perdieron.isEmpty) return (alumnos: alumnos, perdieron: perdieron);
    return (
      alumnos: [
        for (final a in alumnos)
          if (quitar[a.id] case final fuera?)
            a.copyWith(
              numeroMesa: MesasExtraUtils.formatearAsignacionMesas([
                for (final n
                    in MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa))
                  if (!fuera.contains(n)) n,
              ]),
            )
          else
            a,
      ],
      perdieron: perdieron,
    );
  }

  /// Mira un evento y, si a alguien le toca, le da su mesa. **Nunca lanza.**
  Future<ResultadoMesaNueva> revisar(String eventoId) async {
    if (!kMesaNuevaSolaHabilitada) return ResultadoMesaNueva.nada;
    try {
      return await _revisar(eventoId);
    } catch (e) {
      return ResultadoMesaNueva(EstadoMesaNueva.fallo, detalle: '$e');
    }
  }

  Future<ResultadoMesaNueva> _revisar(String eventoId) async {
    // 1. Con lo de esta PC, sin pedirle nada a la nube: casi siempre no hay
    //    nada que hacer, y ahí se termina.
    final planoLocal = await _puertos.planoDeEstaPc(eventoId);
    if (planoLocal == null) return ResultadoMesaNueva.nada;
    var alumnos = await _puertos.alumnos(eventoId);
    var pagos = await _puertos.pagos(alumnos);
    var registros = await _puertos.registros(eventoId);
    final CuentaMesaNueva? previa;
    try {
      previa = calcular(
        plano: planoLocal,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
      );
    } on StateError catch (e) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.fallo,
        detalle: e.message,
      );
    }
    if (previa == null) return ResultadoMesaNueva.nada;
    final esperan = _apellidos(alumnos, previa.asignaciones.keys);

    // 2. Hay alguien esperando: ahora sí, con la nube. Sin internet no se da.
    final distintos = await _puertos.mesasDeOtraPcSinBajar(eventoId);
    if (distintos == null) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.sinInternet,
        detalle: esperan.values.join(', '),
      );
    }
    if (distintos > 0) return const ResultadoMesaNueva(EstadoMesaNueva.esperar);
    final PlanoEvento? plano;
    try {
      plano = await _puertos.planoDeLaNube(eventoId);
    } catch (_) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.sinInternet,
        detalle: esperan.values.join(', '),
      );
    }
    if (plano == null) return ResultadoMesaNueva.nada;

    // 3. La cuenta de verdad, con el plano de la nube y lo de esta PC recién
    //    leído otra vez.
    alumnos = await _puertos.alumnos(eventoId);
    pagos = await _puertos.pagos(alumnos);
    registros = await _puertos.registros(eventoId);
    final ahora = _puertos.ahora();
    final CuentaMesaNueva? cuenta;
    try {
      cuenta = calcular(
        plano: plano,
        alumnos: alumnos,
        pagos: pagos,
        registros: registros,
        por: 'El programa',
        ahora: ahora,
      );
    } on StateError catch (e) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.fallo,
        detalle: '${esperan.values.join(', ')} (${e.message})',
      );
    }
    if (cuenta == null) return ResultadoMesaNueva.nada;

    final numeros = {
      for (final e in cuenta.asignaciones.entries)
        e.key: MesasExtraUtils.formatearAsignacionMesas(e.value),
    };
    final nuevasPorAlumno = cuenta.nuevas.porAlumno;
    await _puertos.guardar(
      numeros: numeros,
      registro: SorteoMesasRegistro(
        id: _puertos.nuevoId(),
        eventoId: eventoId,
        tipo: TipoRegistroSorteo.sorteo,
        resultado: numeros,
        antes: {
          for (final e in cuenta.antes.entries)
            if (e.value.isNotEmpty)
              e.key: MesasExtraUtils.formatearAsignacionMesas(e.value),
        },
        nuevas: nuevasPorAlumno.isEmpty
            ? null
            : {
                for (final e in nuevasPorAlumno.entries)
                  if (numeros.containsKey(e.key)) e.key: e.value.join(', '),
              },
        automatico: true,
        hechoPor: 'El programa',
        createdAt: ahora,
      ),
      plano: plano.copyWith(
        armado: cuenta.nuevas.vacio ? null : cuenta.nuevas.armado,
        config: cuenta.nuevas.config,
        hechoPor: 'El programa',
        ahora: ahora,
      ),
    );
    await _puertos.puertaAlDia(eventoId, numeros.keys);
    final dadas = {
      for (final e in cuenta.dadas.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    return ResultadoMesaNueva(
      EstadoMesaNueva.dio,
      dadas: dadas,
      apellidos: _apellidos(alumnos, dadas.keys),
    );
  }

  static Map<String, String> _apellidos(
    List<ContratoAlumno> alumnos,
    Iterable<String> ids,
  ) =>
      {
        for (final id in ids)
          if (_alumno(alumnos, id) case final a?) id: CambiosDeMesa.apellido(a),
      };
}
