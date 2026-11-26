// La principal de una familia es la mesa que recibió primero, la primera
// anotada (6.9.4), no la de número más bajo.
//
// El caso: RIVAS, TOMÁS (Técnica) tenía la 107, que el programa le dio
// sola el 24-nov, y el jefe le da la adicional que le falta: la 106, vacía al
// lado. Su principal sigue siendo la 107 y la adicional "a confirmar" es la
// 106. Con la regla de antes, la principal pasaba a la 106 y la puerta decía
// que la 107 estaba "a confirmar" (el tótem no la encendía).
//
// La parte de la base corre contra una SQLite **temporal** (el directorio de
// documentos redirigido): nunca toca la base de producción.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/services/adicional_a_confirmar.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/features/plano/modelo/estado_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _alumno(
  String mesa, {
  int extras = 0,
  int sillas = 0,
  String id = 'a',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'RIVAS, TOMÁS',
      cantidadAcompanantes: 1,
      montoTotalPactado: 315000,
      saldoDeudor: 115000,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
    );

const _ev = 'eeeeeeee-0000-4000-8000-000000000094';
const _rivas = 'c1000000-0000-4000-8000-000000000107';
const _perez = 'c2000000-0000-4000-8000-000000000012';

void main() {
  group('los números en el orden en que están escritos', () {
    test('la primera escrita va primero, aunque sea más alta', () {
      expect(MesasExtraUtils.numerosEnOrdenDelTexto('107, 106'), [107, 106]);
      expect(MesasExtraUtils.numerosEnOrdenDelTexto('12, 13, 14'), [12, 13, 14]);
    });

    test('un rango va en su lugar, de menor a mayor', () {
      expect(
        MesasExtraUtils.numerosEnOrdenDelTexto('40, 12-14'),
        [40, 12, 13, 14],
      );
      expect(
        MesasExtraUtils.numerosEnOrdenDelTexto('12 al 14 y 40'),
        [12, 13, 14, 40],
      );
    });

    test('lee lo mismo que numerosMesaDesdeTexto, sin repetidos ni paréntesis',
        () {
      for (final t in [
        '12',
        '12, 13',
        '12-14 (2 extra)',
        '40 al 42',
        '40 y 41',
        '40/41',
        '9, 102',
        '4-400',
        '12, 12, 13',
        '0, 5',
        '',
      ]) {
        final enOrden = MesasExtraUtils.numerosEnOrdenDelTexto(t);
        expect(enOrden.toSet(), MesasExtraUtils.numerosMesaDesdeTexto(t),
            reason: t);
        expect(enOrden.length, enOrden.toSet().length, reason: t);
      }
      expect(MesasExtraUtils.numerosEnOrdenDelTexto(null), isEmpty);
    });
  });

  group('lo que se escribe conserva la principal', () {
    test('RIVAS: con la 107 y la 106 nueva, queda "107, 106"', () {
      expect(
        MesasExtraUtils.conLaPrincipalDeAntes('107', '106, 107'),
        '107, 106',
      );
    });

    test('una adicional con número más chico va detrás de la principal', () {
      expect(
        MesasExtraUtils.conLaPrincipalDeAntes('12, 13', '11, 12, 13'),
        '12, 11, 13',
      );
    });

    test('si ya no tiene la que tenía primero, queda como vino', () {
      expect(MesasExtraUtils.conLaPrincipalDeAntes('107, 106', '50, 51'),
          '50, 51');
    });

    test('lo de siempre no cambia ni una letra', () {
      expect(MesasExtraUtils.conLaPrincipalDeAntes('12', '12, 13'), '12, 13');
      expect(MesasExtraUtils.conLaPrincipalDeAntes(null, '12, 13'), '12, 13');
      expect(MesasExtraUtils.conLaPrincipalDeAntes('', '12, 13'), '12, 13');
      expect(MesasExtraUtils.conLaPrincipalDeAntes('12, 13', null), isNull);
      expect(MesasExtraUtils.conLaPrincipalDeAntes('12, 13', ''), '');
      expect(
        MesasExtraUtils.conLaPrincipalDeAntes('107, 106', '107, 106'),
        '107, 106',
      );
    });
  });

  group('la principal en el salón, la puerta y el papel', () {
    test('la principal es la primera anotada', () {
      final q = _alumno('107, 106', extras: 1);
      expect(SalonMesas.principal(q), 107);
      expect(SalonMesas.enOrdenDelContrato(q), [107, 106]);
      expect(SalonMesas.mesasEnOrden(q), [107, 106]);
      expect(SalonMesas.principal(_alumno('')), isNull);
    });

    test('para lo sorteado da lo mismo que antes', () {
      for (final t in ['12', '12, 13, 14', '9, 102', '12, 13, 40', '5, 6, 31']) {
        final a = _alumno(t, extras: 2);
        final viejo = MesasExtraUtils.numerosMesaDesdeTexto(t).toList()..sort();
        expect(SalonMesas.enOrdenDelContrato(a), viejo, reason: t);
        expect(
          SalonMesas.mesasEnOrden(a),
          [for (final x in SalonMesas.tramos(a)) ...x],
          reason: t,
        );
      }
    });

    test('la adicional sin pagar "a confirmar" es la 106, no la 107', () {
      final q = _alumno('107, 106', extras: 1);
      // Pagó cuotas del contrato, nada de la mesa adicional.
      final pagos = [
        {'monto': 200000.0, 'concepto': 'Cuota Base (1/9)', 'anulado': 0},
      ];
      expect(AdicionalesDeLaFamilia.mesas(q, pagos), {106});
    });

    test('la columna MESA de la grilla dice primero la principal', () {
      expect(SalonMesas.textoMesas(_alumno('107, 106', extras: 1)),
          '107 y 106 (1 extra)');
      expect(SalonMesas.textoMesas(_alumno('12, 67, 68', extras: 2)),
          '12 + 67-68 (separada)');
      // Lo sorteado, como siempre.
      expect(SalonMesas.textoMesas(_alumno('12, 13, 14', extras: 2)),
          '12-14 (2 extra)');
      expect(SalonMesas.textoMesas(_alumno('12, 13, 40', extras: 2)),
          '12-13 + 40 (separada)');
    });

    test('las sillas extra van primero a la principal', () {
      final q = _alumno('107, 106', extras: 1, sillas: 3);
      expect(SalonMesas.repartoSillas(q), [(107, 2), (106, 1)]);
    });

    test('la planilla: principal 107 y adicional 106', () {
      final f = PlanillaSorteo.fila(_alumno('107, 106', extras: 1));
      expect(f.mesaPrincipal, '107');
      expect(f.adicional, '106');
      expect(f.alertaMesas, isNull);
    });

    test('la planilla con las adicionales al final: la principal es la 12', () {
      final f = PlanillaSorteo.fila(_alumno('12, 67, 68', extras: 2));
      expect(f.mesaPrincipal, '12');
      expect(f.adicional, '67-68 (separada)');
    });
  });

  group('el plano, la puerta y mover una sola mesa', () {
    final armado = ArmarAMedida.armar(
      const OpcionesAMedida(
        playon: PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8),
        cantidad: 110,
      ),
    ).armado;

    test('el plano pone la principal en la 107, no en la 106', () {
      final q = _alumno('107, 106', extras: 1);
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [PlanoDeLaFiesta.ocupanteDe(q, null)],
      );
      expect(estado.info(107).principal, isTrue);
      expect(estado.info(106).principal, isFalse);
    });

    test('para lo sorteado el plano sigue igual: la primera de su bloque', () {
      final a = _alumno('12, 13, 14', extras: 2);
      final estado = EstadoPlano.desde(
        armado: armado,
        ocupantes: [PlanoDeLaFiesta.ocupanteDe(a, null)],
      );
      expect(estado.info(12).principal, isTrue);
      expect(estado.info(13).principal, isFalse);
    });

    test('la puerta le pasa la principal al plano de la recepcionista, '
        'también por la central', () {
      final q = _alumno('107, 106', extras: 1);
      final puerta = PuertaDelEvento.masivo(alumnos: [q], invitados: const []);
      expect(puerta.grupos.single.principal, 107);
      final vuelta = PuertaDelEvento.fromJson(
        jsonDecode(jsonEncode(puerta.toJson())) as Map<String, dynamic>,
        eventoId: 'e',
      );
      expect(vuelta.grupos.single.principal, 107);
    });

    test('mover la principal: la mesa nueva sigue siendo la principal', () {
      final q = _alumno('107, 106', extras: 1);
      final c = CambiosDeMesa.moverUna(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [q],
        alumnoId: q.id,
        mesa: 107,
        aMesa: 108,
      );
      expect(c.antes[q.id], '107, 106');
      expect(c.despues[q.id], '108, 106');
    });

    test('mover una mesa de lo sorteado sigue como siempre: de menor a mayor',
        () {
      final a = _alumno('79, 80', extras: 1);
      final c = CambiosDeMesa.moverUna(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [a],
        alumnoId: a.id,
        mesa: 79,
        aMesa: 81,
      );
      expect(c.despues[a.id], '80, 81');
    });

    test('cambiar una sola mesa con otra familia: cada una en su lugar', () {
      final q = _alumno('107, 106', extras: 1);
      final otra = _alumno('108', id: 'b');
      final c = CambiosDeMesa.intercambiarUna(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [q, otra],
        alumnoId: q.id,
        mesa: 107,
        otraMesa: 108,
      );
      expect(c.despues[q.id], '108, 106');
      expect(c.despues['b'], '107');
    });
  });

  group('en la base', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late Directory docs;
    late ContratosRepository repo;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('principal');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
      repo = ContratosRepository(
        SupabaseClient('http://localhost:1', 'anon-de-test'),
        ConnectivityService(),
      );
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    Future<void> sembrar(String id, String nombre, String mesa) async {
      final db = await LocalDatabase.instance;
      await db.insert('contratos_alumnos', {
        'id': id,
        'evento_id': _ev,
        'nombre_alumno': nombre,
        'monto_total_pactado': 315000,
        'saldo_deudor': 115000,
        'cuotas_pagadas': 5,
        'total_cuotas': 9,
        'numero_mesa': mesa,
        'created_at': DateTime.utc(2026, 3, 30, 12).toIso8601String(),
      });
    }

    Future<String?> mesaDe(String id) async {
      final db = await LocalDatabase.instance;
      final filas = await db.query(
        'contratos_alumnos',
        columns: ['numero_mesa'],
        where: 'id = ?',
        whereArgs: [id],
      );
      return filas.single['numero_mesa'] as String?;
    }

    Future<String?> mesaEnLaCola(String id) async {
      final db = await LocalDatabase.instance;
      final filas = await db.query(
        '_sync_queue',
        where: 'registro_id = ?',
        whereArgs: [id],
      );
      return filas.isEmpty ? null : filas.single['payload'] as String?;
    }

    test('lo que llega ordenado se guarda con la principal primera, y sube así',
        () async {
      await sembrar(_rivas, 'RIVAS, TOMÁS', '107');
      await sembrar(_perez, 'PEREZ, PABLO ALEJANDRO', '9');
      await repo.asignarNumerosMesa({
        _rivas: '106, 107',
        _perez: '9, 102',
      });
      expect(await mesaDe(_rivas), '107, 106');
      expect(await mesaDe(_perez), '9, 102');
      expect(await mesaEnLaCola(_rivas), contains('107, 106'));
    });

    test('mover a otras mesas o dejar sin mesa no se toca', () async {
      await sembrar(_rivas, 'RIVAS, TOMÁS', '107, 106');
      await repo.asignarNumerosMesa({_rivas: '50, 51'});
      expect(await mesaDe(_rivas), '50, 51');
      await repo.asignarNumerosMesa({_rivas: null});
      expect(await mesaDe(_rivas), isNull);
    });
  });
}
