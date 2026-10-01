import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';

void main() {
  const evento = 'e0000000-0000-4000-8000-000000000001';
  final ahora = DateTime.utc(2026, 9, 26, 15);

  PlanoEvento plano({ConfigPlano config = ConfigPlano.vacia}) => PlanoEvento.nuevo(
        eventoId: evento,
        armado: ArmadosPredefinidos.normal2aPagina3(),
        estilo: EstiloPlano.arquitecto,
        modo: ModoSorteo.bloques,
        hechoPor: 'Jefe',
        ahora: ahora,
      ).copyWith(config: config, ahora: ahora);

  group('PlanoEvento', () {
    test('el id es fijo por fiesta y distinto entre fiestas', () {
      expect(UuidUtils.planoEventoId(evento), UuidUtils.planoEventoId(evento));
      expect(
        UuidUtils.planoEventoId(evento),
        isNot(UuidUtils.planoEventoId('e0000000-0000-4000-8000-000000000002')),
      );
      expect(UuidUtils.planoEventoId(evento).length, 36);
    });

    test('el plano nuevo lleva el id fijo sin que nadie lo elija', () {
      final p = plano();
      expect(p.id, UuidUtils.planoEventoId(evento));
      expect(p.tieneIdFijo, isTrue);
      // Cambiarlo no cambia el id, y lo que baja de la nube tampoco.
      expect(p.copyWith(estilo: EstiloPlano.neon, ahora: ahora).tieneIdFijo,
          isTrue);
      expect(PlanoEvento.fromMap(p.toMap()).tieneIdFijo, isTrue);
    });

    test('un plano armado a mano con otro id se reconoce', () {
      final m = plano().toMap()..['id'] = UuidUtils.generate();
      expect(PlanoEvento.fromMap(m).tieneIdFijo, isFalse);
    });

    test('ida y vuelta por la fila, con el armado entero', () {
      final p = plano(
        config: ConfigPlano(
          fijadas: {
            47: MesaFijada(
              alumnoId: 'a1',
              motivo: 'Silla de ruedas',
              por: 'Jefe',
              cuando: ahora,
            ),
          },
          libres: {50: const MesaLibre(motivo: 'Columna'), 51: const MesaLibre()},
          ordenDivisiones: const ['5° B', '5° A'],
          bloques: const [BloqueDivision('5° B', 1, 20)],
          colores: const {'5° A': 3},
          titulo: 'Promoción 2026',
        ),
      );
      final b = PlanoEvento.fromMap(jsonDecode(jsonEncode(p.toMap())));
      expect(b.toMap(), p.toMap());
      expect(b.estiloPlano, EstiloPlano.arquitecto);
      expect(b.modoSorteo, ModoSorteo.bloques);
      expect(b.armado.numeros.length, 78);
      expect(b.config.fijadas[47]!.motivo, 'Silla de ruedas');
      expect(b.config.libres.keys, {50, 51});
      expect(b.config.bloques.single.contiene(20), isTrue);
      expect(b.config.colores['5° A'], 3);
      expect(b.config.titulo, 'Promoción 2026');
      expect(b.config.fijadasPorAlumno, {'a1': [47]});
    });

    test('ninguna columna obligatoria va vacía', () {
      final m = plano().toMap();
      for (final c in const [
        'id', 'evento_id', 'armado', 'armado_json', 'estilo', 'modo_sorteo',
        'config', 'created_at', 'updated_at',
      ]) {
        expect(m[c], isNotNull, reason: c);
      }
    });

    test('una clave que esta versión no conoce se conserva al guardar', () {
      final crudo = jsonEncode({
        'libres': {'5': {}},
        'algo_de_diciembre': {'ruta': [1, 2, 3]},
      });
      final c = ConfigPlano.fromJson(crudo);
      expect(c.libres.keys, {5});
      final vuelta = jsonDecode(c.toJson()) as Map;
      expect(vuelta['algo_de_diciembre'], {'ruta': [1, 2, 3]});
    });

    test('las medidas de fábrica no se guardan; las corregidas, sí', () {
      expect(ConfigPlano.vacia.medidas, const MedidasPlano());
      expect(ConfigPlano.vacia.medidas.playon, PlayonReal.costaSurubi);
      expect(jsonDecode(ConfigPlano.vacia.toJson()) as Map,
          isNot(contains('medidas')));

      const corregidas = MedidasPlano(
        lugarMesaM: 2.2,
        extraPorSillaM: 0.2,
        playon: PlayonReal(frenteM: 31.5, fondoM: 44, profundidadM: 40.2),
      );
      final c = ConfigPlano.vacia.copyWith(medidas: corregidas);
      final vuelta = ConfigPlano.fromJson(c.toJson());
      expect(vuelta.medidas, corregidas);
      expect(vuelta.medidas.playon.aproximado, isFalse);
      // Cambiar otra cosa no las pierde.
      expect(vuelta.copyWith(titulo: 'x').medidas, corregidas);
    });

    test('unas medidas rotas o sin sentido quedan en las de fábrica', () {
      for (final m in [
        4,
        'dos metros',
        {'lugar': 'x', 'playon': 7},
        {'lugar': 0.2, 'extra_silla': -1},
        {'playon': {'frente': 30, 'fondo': 46}},
        {'playon': {'frente': 30, 'fondo': 46, 'profundidad': 0}},
      ]) {
        final c = ConfigPlano.fromJson(jsonEncode({'medidas': m}));
        expect(c.medidas, const MedidasPlano(), reason: '$m');
      }
      // Un dato malo no arrastra a los buenos.
      final c = ConfigPlano.fromJson(jsonEncode({
        'medidas': {'lugar': 2.4, 'playon': 'x'},
      }));
      expect(c.medidas.lugarMesaM, 2.4);
      expect(c.medidas.playon, PlayonReal.costaSurubi);
    });

    test('un config roto o raro no rompe: queda vacío', () {
      for (final t in [null, '', 'no es json', '[1,2]', '{"libres": 4}']) {
        final c = ConfigPlano.fromJson(t);
        expect(c.libres, isEmpty, reason: '$t');
        expect(c.fijadas, isEmpty, reason: '$t');
      }
      final raro = ConfigPlano.fromJson(jsonEncode({
        'fijadas': {'x': {'alumno': 'a'}, '3': {'sin': 'alumno'}, '4': {'alumno': 'b'}},
        'bloques': [{'division': '5A'}, 7, {'division': '5B', 'desde': 1, 'hasta': 2}],
        'colores': {'5A': 'rojo', '5B': 2},
      }));
      expect(raro.fijadas.keys, {4});
      expect(raro.bloques.single.division, '5B');
      expect(raro.colores, {'5B': 2});
    });

    test('un dato del tipo equivocado no tira: se ignora ese dato', () {
      // Un número donde va un texto tiraba un TypeError al leer la fila, y con
      // eso quedaba trabado el sorteo de la fiesta en las dos PCs.
      final c = ConfigPlano.fromJson(jsonEncode({
        'titulo': 2026,
        'subtitulo': ['x'],
        'fijadas': {
          '12': {'alumno': 'a', 'motivo': 5, 'por': true, 'cuando': 7},
        },
        'libres': {
          '20': {'motivo': 9, 'por': {'x': 1}},
        },
      }));
      expect(c.titulo, isNull);
      expect(c.subtitulo, isNull);
      expect(c.fijadas[12]!.alumnoId, 'a');
      expect(c.fijadas[12]!.motivo, isNull);
      expect(c.fijadas[12]!.por, isNull);
      expect(c.fijadas[12]!.cuando, isNull);
      expect(c.libres.keys, {20});
      expect(c.libres[20]!.motivo, isNull);
    });

    test('un armado que no se puede leer no tira: no hay armado', () {
      for (final roto in ['{roto', '[1, 2]', '"texto"', '{}', '{"mesas": []}']) {
        final p = PlanoEvento.fromMap(plano().toMap()..['armado_json'] = roto);
        expect(p.armadoONull, isNull, reason: roto);
        expect(() => p.armado, throwsStateError, reason: roto);
      }
      // Sin la columna, lo mismo.
      final sin = PlanoEvento.fromMap(plano().toMap()..['armado_json'] = null);
      expect(sin.armadoONull, isNull);
      // Y uno bueno se lee.
      expect(plano().armadoONull!.numeros.length, 78);
    });

    test('un estilo desconocido no se pierde al guardar', () {
      final m = plano().toMap()..['estilo'] = 'cristal';
      final b = PlanoEvento.fromMap(m);
      expect(b.estiloPlano, isNull);
      expect(b.toMap()['estilo'], 'cristal');
    });

    test('la huella cambia si cambia la configuración o el armado', () {
      final a = plano();
      final b = a.copyWith(
        config: const ConfigPlano(libres: {5: MesaLibre()}),
        ahora: ahora,
      );
      final c = a.copyWith(
        armado: ArmadosPredefinidos.normal2aPaginas45(),
        ahora: ahora,
      );
      expect(b.huella, isNot(a.huella));
      expect(c.huella, isNot(a.huella));
    });

    test('la huella no cambia por la fecha: la reescribe la nube al subir', () {
      final a = plano();
      final subido = PlanoEvento.fromMap(
        a.toMap()..['updated_at'] = '2026-10-05T12:34:56.789Z',
      );
      expect(subido.updatedAt, isNot(a.updatedAt));
      expect(subido.huella, a.huella);
    });

    test('un modo desconocido cae en entera, como antes del plano', () {
      expect(ModoSorteo.deClave('otro'), ModoSorteo.entera);
      expect(ModoSorteo.deClave(null), ModoSorteo.entera);
    });
  });

  group('MovimientoMesas', () {
    final m = MovimientoMesas(
      id: UuidUtils.generate(),
      eventoId: evento,
      tipo: TipoMovimientoMesas.intercambio,
      antes: const {'a': '12, 13', 'b': '30, 31'},
      despues: const {'a': '30, 31', 'b': '12, 13'},
      motivo: 'Pidieron estar cerca de la pista',
      avisos: const ['a ya retiró entradas'],
      hechoPor: 'Jefe',
      createdAt: ahora,
    );

    test('ida y vuelta por la fila', () {
      final b = MovimientoMesas.fromMap(jsonDecode(jsonEncode(m.toMap())));
      expect(b.toMap(), m.toMap());
      expect(b.despues['a'], '30, 31');
      expect(b.avisos, ['a ya retiró entradas']);
    });

    test('sin mesa viaja como null', () {
      final x = MovimientoMesas(
        id: 'x',
        eventoId: evento,
        tipo: TipoMovimientoMesas.mover,
        antes: const {'a': '5'},
        despues: const {'a': null},
        motivo: 'm',
        createdAt: ahora,
      );
      final b = MovimientoMesas.fromMap(x.toMap());
      expect(b.despues.containsKey('a'), isTrue);
      expect(b.despues['a'], isNull);
      expect(x.toMap()['avisos'], isNull);
    });

    test('un tipo desconocido se lee como movimiento', () {
      final b = MovimientoMesas.fromMap(m.toMap()..['tipo'] = 'nuevo');
      expect(b.tipo, TipoMovimientoMesas.mover);
    });

    test('updated_at es igual a created_at: nunca se edita', () {
      final f = m.toMap();
      expect(f['updated_at'], f['created_at']);
    });
  });
}
