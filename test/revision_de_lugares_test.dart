import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/revision_de_lugares.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

import 'helpers/revision_en_memoria.dart';

// La lista de PRECIOS de una fiesta sorteada antes de la regla del descuento
// (17-nov-2026): el programa propone por las huellas y el jefe acepta. Aceptar
// pide internet y relee todo antes de guardar: lo anotado decide, en todas las
// PCs, qué entradas van con descuento.

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otra = 'e0000000-0000-4000-8000-000000000002';

// 12/11/2026 21:40 en Argentina.
final _sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);

ContratoAlumno _alumno(
  String id, {
  int extras = 0,
  int sillas = 0,
  String? mesa,
  String evento = _fiesta,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: evento,
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
      createdAt: DateTime.utc(2026, 3, 1),
    );

SorteoMesasRegistro _r(
  String id,
  Map<String, String> resultado, {
  int horas = 0,
  Map<String, String>? antes,
  Map<String, String>? lugares,
  bool auto = false,
  String evento = _fiesta,
}) =>
    SorteoMesasRegistro(
      id: id,
      eventoId: evento,
      tipo: TipoRegistroSorteo.sorteo,
      resultado: resultado,
      antes: antes,
      lugares: lugares,
      automatico: auto,
      hechoPor: auto ? null : 'Jefe',
      createdAt: _sorteoEl.add(Duration(hours: horas)),
    );

/// Una fiesta sorteada sin anotar:
/// - "a" tenía su adicional en el sorteo (12 y 13) y después el programa le dio
///   sola otra (151), sin ningún pago: vino después;
/// - "b" tiene 2 sillas sin ninguna huella: para revisar;
/// - "c" tiene solo su mesa.
RevisionEnMemoria _fiestaSinAnotar() => RevisionEnMemoria(
      alumnosDeLaFiesta: [
        _alumno('a', extras: 2, mesa: '12, 13, 151'),
        _alumno('b', sillas: 2, mesa: '14'),
        _alumno('c', mesa: '15'),
        _alumno('z', extras: 1, mesa: '1, 2', evento: _otra),
      ],
      registrosDeLaFiesta: [
        _r('auto0', const {'c': '15'}, horas: -3, antes: const {}, auto: true),
        _r('sorteo', const {'a': '12, 13', 'b': '14'}, antes: const {}),
        _r(
          'auto1',
          const {'a': '12, 13, 151'},
          horas: 50,
          antes: const {'a': '12, 13'},
          auto: true,
        ),
        _r('otra', const {'z': '1, 2'}, evento: _otra),
      ],
    );

void main() {
  group('lo que tiene que estar al día', () {
    test('para aceptar: los alumnos, sus pagos, los repartos y el registro', () {
      expect(SyncEngine.tablasDeLosLugares.toSet(), {
        'contratos_alumnos',
        'pagos_contrato_alumno',
        'sillas_reparto',
        'sorteos_mesas',
      });
    });

    test('la tablet que vende sin internet se lleva el registro de sorteos', () {
      // Sin él, `fotoDeLosLugaresProvider` no sabe qué tenía cada familia al
      // sorteo y le daría el descuento a todo.
      expect(SyncEngine.tablasDeLaPuerta, contains('sorteos_mesas'));
    });

    test('aceptar baja todo antes de leer, y no sigue si no bajó', () {
      final motor = File('lib/core/services/sync_engine.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final i = motor.indexOf('Future<bool> bajarParaLosLugares() async {');
      expect(i, greaterThanOrEqualTo(0));
      final cuerpo = motor.substring(i, motor.indexOf('\n  }', i));
      expect(cuerpo, contains('AppConnectivity.offline) return false;'));
      expect(cuerpo, contains('for (final tabla in tablasDeLosLugares)'));
      expect(cuerpo, contains('return bien.every((b) => b);'));

      final adaptador = File(
        'lib/features/eventos/repositories/revision_de_lugares_de_la_app.dart',
      ).readAsStringSync();
      expect(adaptador, contains('bajarParaLosLugares()'));
    });
  });

  group('la lista', () {
    test('una fiesta sin sorteo no tiene nada para revisar', () async {
      final m = RevisionEnMemoria(
        alumnosDeLaFiesta: [_alumno('a', extras: 1)],
        registrosDeLaFiesta: [],
      );
      expect(await m.revision.leer(_fiesta), isNull);
    });

    test('una fiesta con los lugares ya anotados, tampoco', () async {
      final m = RevisionEnMemoria(
        alumnosDeLaFiesta: [_alumno('a', extras: 1, mesa: '12')],
        registrosDeLaFiesta: [_r('s', const {'a': '12'}, lugares: const {})],
      );
      expect(await m.revision.leer(_fiesta), isNull);
    });

    test('sorteada sin anotar: el renglón del jefe, los alumnos de esa fiesta '
        'y lo que está en duda', () async {
      final lista = (await _fiestaSinAnotar().revision.leer(_fiesta))!;
      expect(lista.sorteo.id, 'sorteo');
      expect(lista.alumnos.map((a) => a.id), ['a', 'b', 'c']);
      expect(lista.enDuda.map((d) => d.clave), ['a|m|d', 'b|s|r']);
    });

    test('viene tildado solo lo que tiene huella de después', () async {
      final lista = (await _fiestaSinAnotar().revision.leer(_fiesta))!;
      expect(lista.tildadosDeEntrada, {'a|m|d'});
      expect(lista.pagaEntera(lista.tildadosDeEntrada),
          (entradas: 8, familias: 1));
      expect(lista.pagaEntera({'a|m|d', 'b|s|r'}), (entradas: 10, familias: 2));
      expect(lista.pagaEntera(const {}), (entradas: 0, familias: 0));
    });

    test('sin nadie con adicionales no se leen los pagos', () async {
      final m = RevisionEnMemoria(
        alumnosDeLaFiesta: [_alumno('a', mesa: '12')],
        registrosDeLaFiesta: [_r('s', const {'a': '12'})],
      );
      final lista = (await m.revision.leer(_fiesta))!;
      expect(lista.enDuda, isEmpty);
      expect(m.lecturasDePagos, 0);
    });

    test('la firma cambia si cambia el sorteo, un lugar o su cantidad', () async {
      final m = _fiestaSinAnotar();
      final antes = (await m.revision.leer(_fiesta))!.firma;
      expect((await m.revision.leer(_fiesta))!.firma, antes);

      m.alumnosDeLaFiesta[1] = _alumno('b', sillas: 1, mesa: '14');
      final conUnaSilla = (await m.revision.leer(_fiesta))!.firma;
      expect(conUnaSilla, isNot(antes));

      m.alumnosDeLaFiesta[2] = _alumno('c', sillas: 1, mesa: '15');
      expect((await m.revision.leer(_fiesta))!.firma, isNot(conUnaSilla));
    });
  });

  group('aceptar', () {
    test('guarda en el renglón del sorteo lo de hoy menos lo tildado', () async {
      final m = _fiestaSinAnotar();
      final lista = (await m.revision.leer(_fiesta))!;
      final r = await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: lista.tildadosDeEntrada,
      );
      expect(r.resultado, ResultadoDeAceptar.aceptado);
      expect(m.puestasAlDia, 1);
      expect(m.guardados.single.registroId, 'sorteo');
      expect(m.guardados.single.lugares, {'a': '2,0', 'b': '1,2'});

      // Desde ahí rige la regla, y no queda nada para revisar.
      final foto = LugaresAlSorteo.vigente(await m.registros(_fiesta));
      expect(foto.estado, EstadoDeLosLugares.anotados);
      expect(foto.de('a'), const LugaresCargados(2, 0));
      expect(foto.de('c'), LugaresCargados.soloElContrato);
      expect(await m.revision.leer(_fiesta), isNull);
      // La otra fiesta no se tocó.
      expect(m.registrosDeLaFiesta.last.lugares, isNull);
    });

    test('tildando también lo que estaba para revisar', () async {
      final m = _fiestaSinAnotar();
      final lista = (await m.revision.leer(_fiesta))!;
      await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: {'a|m|d', 'b|s|r'},
      );
      expect(m.guardados.single.lugares, {'a': '2,0'});
    });

    test('sin tildar nada: todo lo de hoy queda con descuento', () async {
      final m = _fiestaSinAnotar();
      final lista = (await m.revision.leer(_fiesta))!;
      await m.revision.aceptar(_fiesta, mostrada: lista, pagaEntera: const {});
      expect(m.guardados.single.lugares, {'a': '3,0', 'b': '1,2'});
    });

    test('sin internet no guarda nada', () async {
      final m = _fiestaSinAnotar()..hayInternet = false;
      final lista = (await m.revision.leer(_fiesta))!;
      final r = await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: lista.tildadosDeEntrada,
      );
      expect(r.resultado, ResultadoDeAceptar.sinInternet);
      expect(m.guardados, isEmpty);
      expect(m.registrosDeLaFiesta[1].lugares, isNull);
    });

    test('al poner al día, otra PC había cargado algo: no guarda y devuelve la '
        'lista nueva', () async {
      final m = _fiestaSinAnotar();
      final lista = (await m.revision.leer(_fiesta))!;
      m.alPonerAlDia = (m) =>
          m.alumnosDeLaFiesta[2] = _alumno('c', sillas: 1, mesa: '15');
      final r = await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: lista.tildadosDeEntrada,
      );
      expect(r.resultado, ResultadoDeAceptar.cambio);
      expect(r.lista!.enDuda.map((d) => d.clave), ['a|m|d', 'b|s|r', 'c|s|r']);
      expect(m.guardados, isEmpty);

      // Con la lista nueva a la vista, acepta.
      m.alPonerAlDia = null;
      final otra = await m.revision.aceptar(
        _fiesta,
        mostrada: r.lista!,
        pagaEntera: const {'a|m|d'},
      );
      expect(otra.resultado, ResultadoDeAceptar.aceptado);
      expect(m.guardados.single.lugares, {'a': '2,0', 'b': '1,2', 'c': '1,1'});
    });

    test('al poner al día, otra PC ya la había aceptado: no pisa nada', () async {
      final m = _fiestaSinAnotar();
      final lista = (await m.revision.leer(_fiesta))!;
      m.alPonerAlDia = (m) => m.registrosDeLaFiesta[1] = _r(
            'sorteo',
            const {'a': '12, 13', 'b': '14'},
            antes: const {},
            lugares: const {'a': '3,0'},
          );
      final r = await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: lista.tildadosDeEntrada,
      );
      expect(r.resultado, ResultadoDeAceptar.yaNoHaceFalta);
      expect(m.guardados, isEmpty);
      expect(m.registrosDeLaFiesta[1].lugares, {'a': '3,0'});
    });

    test('lo que cambió sin tocar la lista entra como está hoy', () async {
      // "a" sacó una adicional que no estaba en duda: la lista es la misma y
      // se anota lo que tiene hoy.
      final m = RevisionEnMemoria(
        alumnosDeLaFiesta: [
          _alumno('a', extras: 1, mesa: '12, 13'),
          _alumno('b', sillas: 2, mesa: '14'),
        ],
        registrosDeLaFiesta: [
          _r('sorteo', const {'a': '12, 13', 'b': '14'}, antes: const {}),
        ],
      );
      final lista = (await m.revision.leer(_fiesta))!;
      m.alPonerAlDia = (m) => m.alumnosDeLaFiesta[0] = _alumno('a', mesa: '12');
      final r = await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: const {},
      );
      expect(r.resultado, ResultadoDeAceptar.aceptado);
      expect(m.guardados.single.lugares, {'b': '1,2'});
    });

    test('si la base no guarda, lo dice', () async {
      final m = _fiestaSinAnotar()..guarda = false;
      final lista = (await m.revision.leer(_fiesta))!;
      final r = await m.revision.aceptar(
        _fiesta,
        mostrada: lista,
        pagaEntera: lista.tildadosDeEntrada,
      );
      expect(r.resultado, ResultadoDeAceptar.noSeGuardo);
      expect(m.registrosDeLaFiesta[1].lugares, isNull);
    });
  });
}
