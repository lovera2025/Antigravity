import 'dart:math';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../../eventos/services/cobro_abono_acumulado.dart';
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
  /// y a subir. [plano] es null si el salón no cambió (la familia recibió una
  /// mesa que ya tenía fijada): la fila del plano sube entera, y no hay por
  /// qué volver a subirla.
  Future<void> guardar({
    required Map<String, String> numeros,
    required SorteoMesasRegistro registro,
    PlanoEvento? plano,
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

  /// Quién quedó esperando su mesa (los apellidos), si se sabe.
  final String? detalle;

  /// Qué falló, para dejarlo escrito. No se le muestra a nadie.
  final String? error;

  /// Quedó esperando, y **el programa se la va a dar solo más tarde** (cuando
  /// vuelva internet, o cuando baje lo de la otra PC). En false, no: la
  /// familia solo agregó la mesa, y eso no queda anotado. Se la da el jefe con
  /// SORTEO, o el programa cuando la pague.
  final bool alVolver;

  const ResultadoMesaNueva(
    this.estado, {
    this.dadas = const {},
    this.apellidos = const {},
    this.detalle,
    this.error,
    this.alVolver = true,
  });

  static const nada = ResultadoMesaNueva(EstadoMesaNueva.nada);

  /// Lo que se le dice a quien está en la pantalla. Null si no hay nada que
  /// decir.
  String? get aviso {
    switch (estado) {
      case EstadoMesaNueva.dio:
        final partes = [
          for (final e in dadas.entries)
            'A ${apellidos[e.key] ?? 'una familia'} '
                '${e.value.length == 1 ? 'se le dio la mesa' : 'se le dieron las mesas'} '
                '${e.value.join(' y ')}',
        ];
        return '${partes.join('. ')}.';
      case EstadoMesaNueva.sinInternet:
        return alVolver
            ? 'A ${detalle ?? 'una familia'} le falta el número de su mesa: '
                'se le da solo cuando vuelva internet.'
            : 'A ${detalle ?? 'una familia'} no se le pudo dar la mesa ahora: '
                'no hay internet. El jefe se la da con SORTEO.';
      case EstadoMesaNueva.fallo:
        // Sin saber a quién le tocaba no hay nada útil que decir en pantalla.
        return detalle == null
            ? null
            : 'No se le pudo dar la mesa sola a $detalle: el jefe se la da '
                'con SORTEO.';
      case EstadoMesaNueva.esperar:
        // Lo de quien pagó se vuelve a mirar cuando baje lo de la otra PC.
        return alVolver || detalle == null
            ? null
            : 'A $detalle no se le pudo dar la mesa ahora: la otra PC cambió '
                'mesas que todavía no bajaron. El jefe se la da con SORTEO.';
      case EstadoMesaNueva.nada:
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
/// - solo a quien **le tocó la mesa por un pago posterior** al último sorteo,
///   deshacer o restaurar que hizo el jefe: con lo pagado hasta ahí no le
///   tocaba, y ahora sí. Si el jefe deshace un sorteo, esas familias no
///   vuelven a recibir mesa solas, aunque paguen otra cuota;
/// - **o a quien acaba de agregar una mesa** con el sorteo ya hecho (regla del
///   usuario, 11-nov-2026): con **una cuota entera** de su contrato paga
///   ([tieneUnaCuotaPaga]) la recibe en el momento de cargarla, aunque esa
///   mesa no esté paga. La paga antes de retirar las entradas. Solo si tenía
///   todas las suyas ([agregoUnaMesa]);
/// - fuera de eso, la mesa adicional sin pagar sigue con candado, y quien no
///   pagó nada de su contrato no entra nunca: es la misma cuenta del sorteo
///   ("solo a lo que tiene algo pagado"), sin excepciones tildadas;
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
  ///
  /// [agregaron]: las familias que **acaban de agregar una mesa** a su cuenta
  /// ([agregoUnaMesa]). Con una cuota entera de su contrato paga la reciben
  /// aunque esa mesa todavía no esté paga (regla del usuario, 11-nov-2026:
  /// "solo agrego al sistema, ya debería darle"); la pagan antes de retirar las
  /// entradas, que ya frena a quien debe algo.
  static CuentaMesaNueva? calcular({
    required PlanoEvento plano,
    required List<ContratoAlumno> alumnos,
    required Map<String, List<Map<String, dynamic>>> pagos,
    required Iterable<SorteoMesasRegistro> registros,
    Set<String> agregaron = const {},
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
    // "Llegó después" no es haber pagado algo después del sorteo: es que **con
    // lo pagado hasta el sorteo no le tocaba esa mesa, y ahora sí**. Si ya le
    // tocaba y no la tiene (el jefe deshizo su sorteo para rehacerlo, por
    // ejemplo), que pague otra cuota no se la da sola: la decide el jefe.
    final loPagadoEntonces = pagosPorAlumno(vistos, {
      for (final e in pagos.entries)
        e.key: [
          for (final p in e.value)
            if (!_esPosterior(p, desde)) p,
        ],
    });
    int leTocan(ContratoAlumno a, Map<String, PagoAlumno> pagado) =>
        ExtrasSegunPago.de(a, pagado[a.id] ?? PagoAlumno.nada)
            .mesasConElSorteoDeHoy;
    // Quien acaba de agregar una mesa, con una cuota entera de su contrato
    // paga.
    final conAgregada = {
      for (final id in agregaron)
        if (_alumno(vistos, id) case final a?)
          if (tieneUnaCuotaPaga(a, pagos[id] ?? const [])) id,
    };
    bool llegoDespues(String id) {
      if (sinRepetidos.perdieron.contains(id)) return true;
      if (conAgregada.contains(id)) return true;
      final a = _alumno(vistos, id);
      return a != null && leTocan(a, loPagado) > leTocan(a, loPagadoEntonces);
    }

    // El candado de la adicional sin pagar no corre para quien la acaba de
    // agregar, ni para quien perdió un número repetido: a ese el programa ya
    // le había dado su mesa, y hay que devolvérsela con otro número.
    final soloBase = exclusion.soloBase
        .difference({...conAgregada, ...sinRepetidos.perdieron});
    final todos = SorteoMesasMotor.pedidos(
      vistos,
      sinMesa: exclusion.sinMesa,
      soloBase: soloBase,
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
        soloBase: soloBase,
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

  /// ¿Tiene **al menos una cuota entera** de su contrato paga? Es lo que se le
  /// pide a quien agrega una mesa sin pagarla (regla del usuario, 11-nov-2026:
  /// "una cuota entera"; una entrega parcial no alcanza). Sale de los pagos,
  /// con la misma cuenta del saldo, no de los campos de la ficha.
  static bool tieneUnaCuotaPaga(
    ContratoAlumno a,
    Iterable<Map<String, dynamic>> pagos,
  ) =>
      recalcularSaldoDesdePagos(
        montoTotalPactado: a.montoTotalPactado,
        totalCuotas: a.totalCuotas,
        mesaExtraPrecio: a.mesaExtraPrecio,
        sillasExtraPrecioTotal: a.sillasExtraPrecioTotal,
        precioUnitarioMesaExtra: a.precioUnitarioMesaExtra,
        mesaExtraCuotas: a.mesaExtraCuotas,
        mesaExtraCantidad: a.mesaExtraCantidad,
        sillasExtraCuotas: a.sillasExtraCuotas,
        pagos: pagos,
      ).cuotasBase >=
      1;

  /// ¿Esta edición del alumno es **agregar una mesa** a una familia que tenía
  /// todas las suyas? Es lo que se le pasa a [revisar] en `agregaron`.
  ///
  /// - Tenía mesa, y tantos números como mesas cargadas: si le faltaba alguna
  ///   (la tenía con candado, o el jefe deshizo su sorteo), agregar otra no le
  ///   da ninguna sola. Lo decide el jefe con SORTEO.
  /// - Ahora tiene más mesas cargadas que antes. Una mesa cargada sin precio
  ///   no cuenta, como en todo el salón.
  static bool agregoUnaMesa({
    required ContratoAlumno antes,
    required ContratoAlumno despues,
  }) {
    if (despues.esBajaTemporal) return false;
    final tenia =
        MesasExtraUtils.numerosMesaDesdeTexto(antes.numeroMesa).length;
    final cargadasAntes = MesasExtraUtils.cantidadMesasFisicasSorteo(antes);
    final cargadasAhora = MesasExtraUtils.cantidadMesasFisicasSorteo(despues);
    return tenia >= 1 && tenia == cargadasAntes && cargadasAhora > cargadasAntes;
  }

  /// ¿El pago se cargó después de [desde]? Uno sin hora que se pueda leer
  /// cuenta como de antes: ante la duda, no se da una mesa sola.
  static bool _esPosterior(Map<String, dynamic> pago, DateTime desde) {
    for (final clave in const ['created_at', 'fecha_pago']) {
      final v = pago[clave];
      final cuando = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
      if (cuando != null) return cuando.isAfter(desde);
    }
    return false;
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
  ///
  /// [agregaron]: las familias que acaban de agregar una mesa en esta PC (ver
  /// [calcular]). No queda anotado en ningún lado que la agregaron: si ahora
  /// no se puede (sin internet), no se les da sola más tarde, salvo que la
  /// paguen. Por eso el aviso de ese caso manda al SORTEO del jefe.
  Future<ResultadoMesaNueva> revisar(
    String eventoId, {
    Set<String> agregaron = const {},
  }) async {
    if (!kMesaNuevaSolaHabilitada) return ResultadoMesaNueva.nada;
    try {
      return await _revisar(eventoId, agregaron);
    } catch (e) {
      return ResultadoMesaNueva(EstadoMesaNueva.fallo, error: '$e');
    }
  }

  Future<ResultadoMesaNueva> _revisar(
    String eventoId,
    Set<String> agregaron,
  ) async {
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
        agregaron: agregaron,
      );
    } on StateError catch (e) {
      return ResultadoMesaNueva(EstadoMesaNueva.fallo, error: e.message);
    }
    if (previa == null) return ResultadoMesaNueva.nada;
    final esperan = _apellidos(alumnos, previa.asignaciones.keys);
    // Lo de quien pagó se vuelve a ver solo cuando haya internet. Lo de quien
    // solo agregó la mesa, no: no queda anotado en ningún lado.
    bool alVolver() {
      if (agregaron.isEmpty) return true;
      try {
        return calcular(
              plano: planoLocal,
              alumnos: alumnos,
              pagos: pagos,
              registros: registros,
            ) !=
            null;
      } on StateError {
        return false;
      }
    }

    // 2. Hay alguien esperando: ahora sí, con la nube. Sin internet no se da.
    final distintos = await _puertos.mesasDeOtraPcSinBajar(eventoId);
    if (distintos == null) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.sinInternet,
        detalle: esperan.values.join(', '),
        alVolver: alVolver(),
      );
    }
    if (distintos > 0) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.esperar,
        detalle: esperan.values.join(', '),
        alVolver: alVolver(),
      );
    }
    final PlanoEvento? plano;
    try {
      plano = await _puertos.planoDeLaNube(eventoId);
    } catch (_) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.sinInternet,
        detalle: esperan.values.join(', '),
        alVolver: alVolver(),
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
        agregaron: agregaron,
        por: 'El programa',
        ahora: ahora,
      );
    } on StateError catch (e) {
      return ResultadoMesaNueva(
        EstadoMesaNueva.fallo,
        detalle: esperan.values.join(', '),
        error: e.message,
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
      plano: cuenta.nuevas.vacio
          ? null
          : plano.copyWith(
              armado: cuenta.nuevas.armado,
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
