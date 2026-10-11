// La historia entera de "sortear a los que faltan", de punta a punta, con plano
// y sin plano: el primer sorteo, los que llegan después, su planilla, un cambio
// de mesa, deshacer solo a los últimos, restaurar, volver a sortear y deshacer
// todo.
//
// No hay pantalla ni base: cada paso usa las mismas cuentas que la app (el
// motor del sorteo, el registro, los últimos sorteados, la copia y la
// planilla), y cada renglón del registro pasa por el formato en que se guarda.
// Después de cada paso se controla lo que no puede fallar nunca: nadie comparte
// mesa, los del primer sorteo no se movieron y el registro explica las mesas de
// hoy.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/registro_sorteo.dart';
import 'package:arguello_events/features/eventos/services/respaldo_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/divisiones.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

// 12/11/2026 21:00 en Argentina.
final _inicio = DateTime.utc(2026, 11, 13);

/// Una fiesta en memoria: los alumnos con sus mesas, el registro, los cambios
/// con motivo, el plano (si tiene) y la copia del último deshacer. Cada cosa
/// que se le pide hace lo mismo que la pantalla de la fiesta.
class _Fiesta {
  _Fiesta({this.armado})
      : plano = armado == null
            ? null
            : PlanoEvento.nuevo(
                eventoId: 'e1',
                armado: armado,
                estilo: EstiloPlano.arquitecto,
                modo: ModoSorteo.bloques,
                ahora: _inicio,
              );

  final ArmadoSalon? armado;
  PlanoEvento? plano;
  final _fichas = <String, ({String division, int extras})>{};
  final _mesas = <String, String>{};
  final registros = <SorteoMesasRegistro>[];
  final movimientos = <MovimientoMesas>[];
  RespaldoSorteo? copia;
  var _reloj = _inicio;
  var _renglones = 0;

  DateTime _ahora() => _reloj = _reloj.add(const Duration(hours: 1));

  ConfigPlano get config => plano?.config ?? ConfigPlano.vacia;
  List<BloqueDivision> get bloques => config.bloques;

  List<ContratoAlumno> get alumnos => [
        for (final e in _fichas.entries)
          ContratoAlumno(
            id: e.key,
            eventoId: 'e1',
            nombreAlumno: 'FAMILIA ${e.key}',
            cantidadAcompanantes: 0,
            montoTotalPactado: 300000,
            saldoDeudor: 0,
            mesaExtraPrecio: 70000.0 * e.value.extras,
            mesaExtraCantidad: e.value.extras,
            numeroMesa: _mesas[e.key],
            cursoDivision: e.value.division,
          ),
      ];

  /// Las mesas de cada uno, en números.
  Map<String, Set<int>> get mesas => {
        for (final e in _mesas.entries)
          e.key: MesasExtraUtils.numerosMesaDesdeTexto(e.value),
      };

  void sumar(String id, String division, {int extras = 0}) =>
      _fichas[id] = (division: division, extras: extras);

  void compraOtraMesa(String id) => _fichas[id] = (
        division: _fichas[id]!.division,
        extras: _fichas[id]!.extras + 1,
      );

  void _guardar(Map<String, String?> numeros) {
    for (final e in numeros.entries) {
      final valor = e.value;
      if (valor == null) {
        _mesas.remove(e.key);
      } else {
        _mesas[e.key] = valor;
      }
    }
  }

  /// Agrega el renglón tal como vuelve de la base.
  void _registrar(
    TipoRegistroSorteo tipo,
    Map<String, String> resultado, {
    Map<String, String>? antes,
    Map<String, String>? quedan,
  }) {
    final renglon = SorteoMesasRegistro(
      id: 'r${(++_renglones).toString().padLeft(3, '0')}',
      eventoId: 'e1',
      tipo: tipo,
      resultado: resultado,
      antes: antes,
      quedan: quedan,
      hechoPor: 'Jefe',
      createdAt: _ahora(),
    );
    registros.add(SorteoMesasRegistro.fromMap(renglon.toMap()));
  }

  /// SORTEO → Sortear mesas. Devuelve a quiénes les dio o les sumó mesa.
  Map<String, String> sortear({
    Set<String> sinPagar = const {},
    required int semilla,
  }) {
    final hoy = alumnos;
    final Map<String, List<int>> asignaciones;
    final armado = this.armado;
    if (armado != null) {
      final entrada = EntradaSorteoPlano(
        armado: armado,
        config: config,
        alumnos: hoy,
        exclusion: ExclusionSorteo(sinMesa: sinPagar),
        modo: ModoSorteo.bloques,
        ordenDivisiones: Divisiones.ordenNatural(
          hoy.map((a) => Divisiones.clave(a.cursoDivision)),
        ),
      );
      final resultado = SorteoConPlano.sortear(entrada, random: Random(semilla));
      expect(SorteoConPlano.validar(entrada, resultado), isNull);
      asignaciones = resultado.asignaciones;
      plano = plano!.copyWith(
        config: config.copyWith(
          bloques: resultado.bloques.isNotEmpty ? resultado.bloques : bloques,
        ),
        ahora: _reloj,
      );
    } else {
      final pedidos = SorteoMesasMotor.pedidos(hoy, sinMesa: sinPagar);
      final ocupadas = SorteoMesasMotor.ocupadas(hoy);
      final capacidad = SorteoMesasMotor.capacidadMinima(
        pedidos: pedidos,
        ocupadas: ocupadas,
      );
      asignaciones = SorteoMesasMotor.sortear(
        pedidos: pedidos,
        ocupadas: ocupadas,
        capacidad: capacidad,
        random: Random(semilla),
      );
      expect(
        SorteoMesasMotor.validar(
          pedidos: pedidos,
          ocupadas: ocupadas,
          capacidad: capacidad,
          asignaciones: asignaciones,
        ),
        isNull,
      );
    }
    final numeros = {
      for (final e in asignaciones.entries)
        e.key: MesasExtraUtils.formatearAsignacionMesas(e.value),
    };
    _registrar(
      TipoRegistroSorteo.sorteo,
      numeros,
      antes: UltimosSorteados.antesDe(hoy, numeros),
    );
    _guardar(numeros);
    return numeros;
  }

  UltimosSorteados? get ultimos =>
      UltimosSorteados.de(registros, alumnos, movimientos: movimientos);

  /// SORTEO → Deshacer sorteo de mesas, con lo que se elige en el aviso.
  void deshacer({required bool soloUltimos}) {
    final que = soloUltimos
        ? LoQueSeDeshace.soloUltimos(ultimos!)
        : LoQueSeDeshace.todo(alumnos);
    final seVan = que.seVanLosBloques ? bloques : const <BloqueDivision>[];
    // La copia, como queda escrita en el archivo.
    copia = RespaldoSorteo.deJson(
      jsonDecode(
        jsonEncode(
          RespaldoSorteo.aJson(
            _ahora(),
            que.tenian,
            bloques: seVan,
            quedaron: que.quedan ?? const {},
          ),
        ),
      ),
    );
    _registrar(TipoRegistroSorteo.deshacer, que.tenian, quedan: que.quedan);
    _guardar(que.numeros);
    if (plano != null && seVan.isNotEmpty) {
      plano = plano!.copyWith(
        config: config.copyWith(bloques: const []),
        ahora: _reloj,
      );
    }
  }

  /// SORTEO → Restaurar sorteo anterior. Devuelve cuántos no se restauraron.
  int restaurar() {
    final hoy = alumnos;
    final plan = RespaldoSorteo.planRestauracion(copia!, hoy);
    final vuelven = RespaldoSorteo.bloquesARestaurar(copia!, plano);
    _registrar(
      TipoRegistroSorteo.restaurar,
      plan.aRestaurar,
      antes: UltimosSorteados.antesDe(hoy, plan.aRestaurar),
    );
    _guardar(plan.aRestaurar);
    if (vuelven != null) {
      plano = plano!.copyWith(
        config: config.copyWith(bloques: vuelven),
        ahora: _reloj,
      );
    }
    return plan.omitidos;
  }

  /// Con plano, PLANO → mudar una familia a mesas libres, con motivo. Sin
  /// plano, lo que se puede hacer: escribirle la mesa en Editar alumno, que no
  /// deja registro.
  void mudar(String id, {required int aLaMesa}) {
    final armado = this.armado;
    if (armado == null) {
      _mesas[id] = '$aLaMesa';
      return;
    }
    final cambio = CambiosDeMesa.mover(
      armado: armado,
      config: config,
      alumnos: alumnos,
      alumnoId: id,
      desdeMesa: aLaMesa,
    );
    expect(cambio.sePuede, isTrue, reason: cambio.problema);
    movimientos.add(
      MovimientoMesas.fromMap(
        MovimientoMesas(
          id: 'm${movimientos.length + 1}',
          eventoId: 'e1',
          tipo: cambio.tipo,
          antes: cambio.antes,
          despues: cambio.despues,
          motivo: 'Pidió estar cerca de la pista',
          avisos: cambio.avisos,
          hechoPor: 'Jefe',
          createdAt: _ahora(),
        ).toMap(),
      ),
    );
    _guardar(cambio.despues);
  }

  /// Una mesa que hoy no tiene nadie y que el plano tiene (si hay plano).
  int mesaLibre() {
    final ocupadas = {for (final m in mesas.values) ...m};
    final candidatas = armado?.numeros.toList() ?? [for (var n = 1; n < 400; n++) n];
    candidatas.sort();
    return candidatas.lastWhere((n) => !ocupadas.contains(n));
  }

  /// Lo que va arriba de la planilla.
  String? get lineaDeLaPlanilla => RegistroSorteo.lineaParaPlanilla(
        RegistroSorteo.resumir(registros, alumnos, movimientos: movimientos),
      );

  /// Las familias que salen en la planilla de solo los últimos sorteados.
  Set<String> get enLaPlanillaDeLosUltimos {
    final u = ultimos!;
    final filas = PlanillaSorteo.porDivision(
      alumnos.where((a) => u.familias.contains(a.id)),
    );
    return {for (final f in filas.values.expand((l) => l)) f.alumnoId};
  }

  /// Lo que tiene que valer siempre, pase lo que pase.
  void controlar(String cuando, {int cambiosAMano = 0}) {
    final usadas = <int, String>{};
    for (final e in mesas.entries) {
      for (final n in e.value) {
        expect(usadas.containsKey(n), isFalse,
            reason: '$cuando: la mesa $n es de ${usadas[n]} y de ${e.key}');
        usadas[n] = e.key;
        if (armado != null) {
          expect(armado!.existe(n), isTrue,
              reason: '$cuando: la mesa $n no está en el plano');
        }
      }
    }
    expect(
      RegistroSorteo.resumir(registros, alumnos, movimientos: movimientos)
          .cambiosAMano,
      cambiosAMano,
      reason: '$cuando: el registro no explica las mesas de hoy',
    );
  }
}

void main() {
  for (final conPlano in [false, true]) {
    test('la historia entera, ${conPlano ? 'con plano' : 'sin plano'}', () {
      final fiesta = _Fiesta(
        armado: conPlano ? ArmadosPredefinidos.normal2aPagina3() : null,
      );
      // Treinta familias en tres divisiones; cuatro con una mesa extra.
      for (final (division, cuantas) in [('5° A', 12), ('5° B', 10), ('5° C', 8)]) {
        for (var i = 0; i < cuantas; i++) {
          final id = '${Divisiones.clave(division)}-${i.toString().padLeft(2, '0')}';
          fiesta.sumar(id, division, extras: i % 7 == 3 ? 1 : 0);
        }
      }
      const sinPagar = '5B-02'; // todavía no pagó nada: no entra al sorteo
      const compra = '5A-05'; // después va a comprar otra mesa

      // ── 1. El primer sorteo ──────────────────────────────────────────────
      final primero = fiesta.sortear(sinPagar: {sinPagar}, semilla: 11);
      expect(primero, hasLength(29));
      expect(fiesta.mesas.containsKey(sinPagar), isFalse);
      fiesta.controlar('primer sorteo');
      final delPrimero = Map.of(fiesta.mesas);
      final bloquesDelPrimero = [
        for (final b in fiesta.bloques) (b.division, b.desde, b.hasta),
      ];
      expect(bloquesDelPrimero, conPlano ? hasLength(3) : isEmpty);
      expect(fiesta.ultimos!.deshacerSoloCambiaAlgo, isFalse,
          reason: 'con un solo sorteo que es de todos, no hay qué elegir');
      expect(fiesta.lineaDeLaPlanilla, isNot(contains('\n')));

      /// Los del primer sorteo siguen con sus mismas mesas. [compra] puede
      /// tener además la que se le sumó.
      void nadieDelPrimeroSeMovio(String cuando, {bool compraTieneOtra = false}) {
        for (final e in delPrimero.entries) {
          final hoy = fiesta.mesas[e.key] ?? const <int>{};
          if (e.key == compra && compraTieneOtra) {
            expect(hoy.containsAll(e.value), isTrue, reason: '$cuando: ${e.key}');
            expect(hoy.length, e.value.length + 1, reason: '$cuando: ${e.key}');
          } else {
            expect(hoy, e.value, reason: '$cuando: ${e.key}');
          }
        }
        expect(
          [for (final b in fiesta.bloques) (b.division, b.desde, b.hasta)],
          bloquesDelPrimero,
          reason: '$cuando: los bloques',
        );
      }

      // ── 2. Llegan los que faltaban ───────────────────────────────────────
      // Tres que se sumaron tarde, el que terminó de pagar y uno que compró
      // otra mesa.
      fiesta
        ..sumar('tarde-A', '5° A')
        ..sumar('tarde-B', '5° B')
        ..sumar('tarde-C', '5° C')
        ..compraOtraMesa(compra);
      const faltaban = {'tarde-A', 'tarde-B', 'tarde-C', sinPagar, compra};

      final segundo = fiesta.sortear(semilla: 22);
      expect(segundo.keys.toSet(), faltaban,
          reason: 'el mismo botón sortea solo a los que faltan');
      nadieDelPrimeroSeMovio('los que faltaban', compraTieneOtra: true);
      fiesta.controlar('los que faltaban');
      // El sorteo dejó anotado lo que ya tenía el que compró otra mesa.
      expect(
        MesasExtraUtils.numerosMesaDesdeTexto(fiesta.registros.last.antes![compra]),
        delPrimero[compra],
      );
      expect(fiesta.registros.last.antes!.keys, [compra]);
      final conLosQueFaltaban = Map.of(fiesta.mesas);

      // ── 3. La planilla solo de ellos ─────────────────────────────────────
      final ultimos = fiesta.ultimos!;
      expect(ultimos.planillaSolaCambiaAlgo, isTrue);
      expect(fiesta.enLaPlanillaDeLosUltimos, faltaban);
      final linea = fiesta.lineaDeLaPlanilla!.split('\n');
      expect(linea, hasLength(2));
      expect(linea.first, startsWith('Sorteo del 12/11/2026'));
      expect(linea.first, endsWith('· Jefe · 29 familias'));
      expect(linea.last, startsWith('Los que faltaban: '));
      expect(linea.last, endsWith('· Jefe · 5 familias'));

      // ── 4. A uno de los que faltaban lo mudan de mesa ────────────────────
      final aDonde = fiesta.mesaLibre();
      fiesta.mudar('tarde-A', aLaMesa: aDonde);
      expect(fiesta.mesas['tarde-A'], {aDonde});
      // Con plano queda registrado con su motivo; sin plano es un cambio a
      // mano, y el registro lo cuenta como tal.
      final aMano = conPlano ? 0 : 1;
      fiesta.controlar('la mudanza', cambiosAMano: aMano);
      final conLaMudanza = Map.of(fiesta.mesas);

      // ── 5. Deshacer solo a los últimos sorteados ─────────────────────────
      final antesDeDeshacer = fiesta.ultimos!;
      expect(antesDeDeshacer.deshacerSoloCambiaAlgo, isTrue);
      expect(antesDeDeshacer.aGuardar.keys.toSet(), faltaban.difference({'tarde-A'}));
      expect(antesDeDeshacer.noSeTocan.single.alumnoId, 'tarde-A');
      expect(antesDeDeshacer.eraElUnico, isFalse);

      fiesta.deshacer(soloUltimos: true);
      nadieDelPrimeroSeMovio('deshacer solo los últimos');
      for (final id in ['tarde-B', 'tarde-C', sinPagar]) {
        expect(fiesta.mesas.containsKey(id), isFalse, reason: id);
      }
      expect(fiesta.mesas['tarde-A'], {aDonde}, reason: 'al mudado no se lo toca');
      expect(fiesta.registros.last.esDeshacerDeUltimos, isTrue);
      expect(UltimosSorteados.sorteosEnPie(fiesta.registros), hasLength(1));
      fiesta.controlar('deshacer solo los últimos', cambiosAMano: aMano);
      final sinLosUltimos = Map.of(fiesta.mesas);

      // ── 6. Fue un error: restaurar ───────────────────────────────────────
      expect(fiesta.restaurar(), 0);
      expect(fiesta.mesas, conLaMudanza,
          reason: 'restaurar deja todo como antes de deshacer');
      nadieDelPrimeroSeMovio('restaurar', compraTieneOtra: true);
      expect(fiesta.registros.last.tipo, TipoRegistroSorteo.restaurar);
      expect(UltimosSorteados.sorteosEnPie(fiesta.registros), hasLength(2));
      fiesta.controlar('restaurar', cambiosAMano: aMano);
      expect(fiesta.lineaDeLaPlanilla, contains('Los que faltaban, restaurados el'));

      // ── 7. Era lo que quería: deshacerlos de nuevo y volver a sortear ────
      fiesta.deshacer(soloUltimos: true);
      expect(fiesta.mesas, sinLosUltimos);
      fiesta.controlar('deshacer otra vez', cambiosAMano: aMano);

      final tercero = fiesta.sortear(semilla: 33);
      expect(tercero.keys.toSet(), faltaban.difference({'tarde-A'}),
          reason: 'el mudado ya tiene su mesa: no vuelve a entrar');
      nadieDelPrimeroSeMovio('volver a sortear', compraTieneOtra: true);
      expect(fiesta.mesas['tarde-A'], {aDonde});
      fiesta.controlar('volver a sortear', cambiosAMano: aMano);
      expect(fiesta.mesas.length, conLosQueFaltaban.length);

      // ── 8. Deshacer todo ─────────────────────────────────────────────────
      fiesta.deshacer(soloUltimos: false);
      expect(fiesta.mesas, isEmpty);
      expect(fiesta.bloques, isEmpty);
      expect(fiesta.registros.last.esDeshacerDeUltimos, isFalse);
      expect(UltimosSorteados.sorteosEnPie(fiesta.registros), isEmpty);
      expect(fiesta.ultimos, isNull);
      fiesta.controlar('deshacer todo');
      expect(fiesta.lineaDeLaPlanilla, startsWith('Sorteo deshecho el '));

      // ── 9. Y restaurar todo ──────────────────────────────────────────────
      expect(fiesta.restaurar(), 0);
      nadieDelPrimeroSeMovio('restaurar todo', compraTieneOtra: true);
      expect(fiesta.mesas.length, conLosQueFaltaban.length);
      // Queda un solo sorteo en pie, de todos: ya no hay "últimos" aparte.
      expect(UltimosSorteados.sorteosEnPie(fiesta.registros), hasLength(1));
      expect(fiesta.ultimos!.deshacerSoloCambiaAlgo, isFalse);
      // Vuelve a ser un cambio a mano solo donde lo era: restaurar repone lo
      // que había, mudanza incluida.
      fiesta.controlar('restaurar todo');
    });
  }

  test('una mesa cargada a mano antes del sorteo no se pierde al deshacer solo '
      'a los últimos', () {
    // El jefe le escribió la mesa a mano (Editar alumno): el registro nunca la
    // vio. Después esa familia compró otra y el sorteo se la sumó.
    final fiesta = _Fiesta()
      ..sumar('uno', '5° A')
      ..sumar('dos', '5° A')
      ..sumar('a-mano', '5° A');
    fiesta.sortear(sinPagar: {'a-mano'}, semilla: 1);
    final libre = fiesta.mesaLibre();
    fiesta
      ..mudar('a-mano', aLaMesa: libre)
      ..compraOtraMesa('a-mano');

    final segundo = fiesta.sortear(semilla: 2);
    expect(segundo.keys, ['a-mano']);
    expect(fiesta.mesas['a-mano'], hasLength(2));
    expect(fiesta.mesas['a-mano'], contains(libre));

    fiesta.deshacer(soloUltimos: true);
    expect(fiesta.mesas['a-mano'], {libre},
        reason: 'se le saca solo la que le sumó el sorteo');
    expect(fiesta.mesas['uno'], isNotNull);
    expect(fiesta.mesas['dos'], isNotNull);
  });
}
