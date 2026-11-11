// La última numeración elegida queda para las fiestas que vienen (6.5.1, pedido
// del usuario el 11-nov-2026: "si yo configuro que quiero al fondo, ya debe
// quedar guardado para cada fiesta, salvo que yo cambie después").
//
// Sin tabla ni SQL: cada elección va anotada en la `config` del plano de su
// fiesta, con su momento, y la recordada es la más nueva de los planos que la
// PC tiene. Acá se prueba la cuenta, lo que hace Acomodar con ella, lo que
// queda al guardar, y dos PCs que se pasan los planos como lo hace la nube.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/numeracion_recordada.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_puerto_viejo.dart';

final _t1 = DateTime.utc(2026, 11, 11, 15);
final _t2 = DateTime.utc(2026, 11, 12, 10);
final _t3 = DateTime.utc(2026, 11, 13, 9);

const _fondo = FinNumeracion.fondo;
const _escenario = FinNumeracion.escenario;

/// El salón de siempre, guardado con la serpentina de siempre.
final _guardado = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;

List<String> _mesaPorMesa(ArmadoSalon a) => [
      for (final m in a.mesas) '${m.numero} ${m.hoja} ${m.x} ${m.y}',
    ];

ContratoAlumno _alumno(String id, {List<int> mesas = const []}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// Lo que hace la pantalla al tocar GUARDAR en Acomodar, con lo que trae la
/// sesión.
CambioDeConfig _guardar(
  SesionAcomodo s, {
  ConfigPlano config = ConfigPlano.vacia,
  List<ContratoAlumno> alumnos = const [],
}) =>
    EditarArmado.paraGuardar(
      base: s.base,
      nuevo: s.actual,
      fresco: s.base,
      config: config,
      alumnos: alumnos,
      enUsoVisto: EditarArmado.enUso(alumnos, config),
      fin: s.fin,
      finEl: s.finEl,
    );

/// La sesión de Acomodar como la arma la pantalla.
SesionAcomodo _sesion({
  ArmadoSalon? base,
  ConfigPlano config = ConfigPlano.vacia,
  NumeracionRecordada? recordada,
  bool haySorteo = false,
}) =>
    SesionAcomodo(
      base: base ?? _guardado,
      haySorteo: haySorteo,
      fin: config.numeracion,
      finEl: config.numeracionEl,
      recordada: config.eligioNumeracion ? null : recordada,
    );

/// Una PC: los planos que tiene en su base, por fiesta, como filas.
class _Pc {
  final filas = <String, Map<String, dynamic>>{};

  ConfigPlano config(String fiesta) {
    final fila = filas[fiesta];
    return fila == null ? ConfigPlano.vacia : PlanoEvento.fromMap(fila).config;
  }

  NumeracionRecordada? get recordada => NumeracionRecordada.de([
        for (final f in filas.values) PlanoEvento.fromMap(f).config,
      ]);

  SesionAcomodo abrir(String fiesta, {bool haySorteo = false}) => _sesion(
        config: config(fiesta),
        recordada: recordada,
        haySorteo: haySorteo,
      );

  /// GUARDAR: la fila entera, como la escribe el repositorio.
  void guardar(String fiesta, SesionAcomodo s, DateTime ahora) {
    final r = _guardar(s, config: config(fiesta));
    expect(r.sePuede, isTrue, reason: r.problema);
    filas[fiesta] = PlanoEvento.nuevo(
      eventoId: fiesta,
      armado: r.armado!,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.entera,
      ahora: ahora,
    ).copyWith(config: r.config, ahora: ahora).toMap();
  }

  /// La fila de una fiesta pasa de [otra] a esta PC, como cuando baja.
  void bajarDe(_Pc otra, String fiesta) => filas[fiesta] = Map.of(
        jsonDecode(jsonEncode(otra.filas[fiesta])) as Map<String, dynamic>,
      );
}

void main() {
  group('lo que queda anotado en la config', () {
    test('una fiesta que nunca eligió no lleva ninguna clave', () {
      expect(ConfigPlano.vacia.eligioNumeracion, isFalse);
      final m = jsonDecode(ConfigPlano.vacia.toJson()) as Map;
      expect(m, isNot(contains('numeracion')));
      expect(m, isNot(contains('numeracion_el')));
    });

    test('elegir "junto al escenario" también queda anotado, con su momento',
        () {
      final c = ConfigPlano(numeracion: _escenario, numeracionEl: _t1);
      expect(c.eligioNumeracion, isTrue);
      final m = jsonDecode(c.toJson()) as Map;
      expect(m['numeracion'], 'escenario');
      expect(m['numeracion_el'], _t1.toIso8601String());
      final vuelta = ConfigPlano.fromJson(c.toJson());
      expect(vuelta.numeracion, _escenario);
      expect(vuelta.numeracionEl, _t1);
      expect(vuelta.eligioNumeracion, isTrue);
      expect(vuelta.otras, isEmpty, reason: 'no quedan como claves raras');
    });

    test('al fondo con su momento va y vuelve igual', () {
      final c = ConfigPlano(numeracion: _fondo, numeracionEl: _t2);
      final vuelta = ConfigPlano.fromJson(c.toJson());
      expect(vuelta.numeracion, _fondo);
      expect(vuelta.numeracionEl, _t2);
    });

    test('un "al fondo" sin momento cuenta como elegido', () {
      final c = ConfigPlano.fromJson('{"numeracion":"fondo"}');
      expect(c.eligioNumeracion, isTrue);
      expect(c.numeracionEl, isNull);
      expect(jsonDecode(c.toJson()) as Map, isNot(contains('numeracion_el')));
    });

    test('un momento sin una elección que se entienda no cuenta', () {
      for (final texto in [
        '{"numeracion_el":"2026-11-11T15:00:00.000Z"}',
        '{"numeracion":"otra","numeracion_el":"2026-11-11T15:00:00.000Z"}',
        '{"numeracion":"escenario","numeracion_el":"no es una fecha"}',
        '{"numeracion":"escenario","numeracion_el":7}',
      ]) {
        final c = ConfigPlano.fromJson(texto);
        expect(c.eligioNumeracion, isFalse, reason: texto);
        expect(c.numeracion, _escenario, reason: texto);
      }
    });

    test('cambiar otra cosa del plano no pierde la elección ni su momento', () {
      final c = ConfigPlano(numeracion: _fondo, numeracionEl: _t1)
          .copyWith(titulo: 'Fiesta', colores: const {'5a': 2});
      expect(c.numeracion, _fondo);
      expect(c.numeracionEl, _t1);
    });

    test('una PC con la versión anterior conserva las dos claves', () {
      // La 6.5.0 no conoce `numeracion` ni `numeracion_el`: las guarda entre
      // las que no entiende y las vuelve a escribir tal cual (se miró su
      // `ConfigPlano` en el tag v6.5.0). Acá, lo mismo: lo que no se conoce
      // vuelve a salir.
      final texto =
          ConfigPlano(numeracion: _escenario, numeracionEl: _t1).toJson();
      final m = jsonDecode(texto) as Map<String, dynamic>;
      const conocidasEnLa650 = {
        'fijadas',
        'libres',
        'orden_divisiones',
        'bloques',
        'colores',
        'titulo',
        'subtitulo',
        'medidas',
      };
      final reescrito = jsonEncode({
        for (final e in m.entries)
          if (!conocidasEnLa650.contains(e.key)) e.key: e.value,
        'fijadas': <String, dynamic>{},
        'libres': <String, dynamic>{},
        'orden_divisiones': <String>[],
        'bloques': <dynamic>[],
        'colores': <String, dynamic>{},
      });
      final vuelta = ConfigPlano.fromJson(reescrito);
      expect(vuelta.numeracion, _escenario);
      expect(vuelta.numeracionEl, _t1);
    });
  });

  group('la última elección, entre todas las fiestas', () {
    test('si nadie eligió nada, no hay nada que recordar', () {
      expect(NumeracionRecordada.de(const []), isNull);
      expect(
        NumeracionRecordada.de([ConfigPlano.vacia, ConfigPlano.vacia]),
        isNull,
      );
    });

    test('gana la más nueva, esté donde esté en la lista', () {
      final fondo = ConfigPlano(numeracion: _fondo, numeracionEl: _t1);
      final escenario = ConfigPlano(numeracion: _escenario, numeracionEl: _t2);
      for (final lista in [
        [fondo, ConfigPlano.vacia, escenario],
        [escenario, fondo, ConfigPlano.vacia],
      ]) {
        expect(
          NumeracionRecordada.de(lista),
          NumeracionRecordada(_escenario, _t2),
        );
      }
      expect(
        NumeracionRecordada.de([
          escenario,
          ConfigPlano(numeracion: _fondo, numeracionEl: _t3),
        ]),
        NumeracionRecordada(_fondo, _t3),
      );
    });

    test('una elección sin momento es la más vieja', () {
      const sinMomento = ConfigPlano(numeracion: _fondo);
      expect(
        NumeracionRecordada.de(const [sinMomento]),
        const NumeracionRecordada(_fondo, null),
      );
      final escenario = ConfigPlano(numeracion: _escenario, numeracionEl: _t1);
      for (final lista in [
        [sinMomento, escenario],
        [escenario, sinMomento],
      ]) {
        expect(
          NumeracionRecordada.de(lista),
          NumeracionRecordada(_escenario, _t1),
        );
      }
    });
  });

  group('en Acomodar', () {
    final alFondo = NumeracionRecordada(_fondo, _t1);

    test('sin nada recordado, todo arranca como siempre', () {
      final s = _sesion();
      expect(s.fin, _escenario);
      expect(s.finEl, isNull);
      expect(s.finDeLaMemoria, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('una fiesta que nunca eligió arranca con la recordada, y solo falta '
        'guardar', () {
      final s = _sesion(recordada: alFondo);
      expect(s.fin, _fondo);
      expect(s.finDeLaMemoria, isTrue);
      expect(s.finEl, _t1, reason: 'es aquella elección, no una nueva');
      expect(s.cambioElFin, isTrue);
      expect(s.faltaOrdenar, isTrue);
      expect(s.puedeGuardar, isTrue);
      expect(s.hayCambios, isFalse, reason: 'ninguna mesa se movió');
    });

    test('la fiesta que ya eligió se queda con la suya', () {
      final config = ConfigPlano(numeracion: _escenario, numeracionEl: _t2);
      final s = _sesion(config: config, recordada: NumeracionRecordada(_fondo, _t3));
      expect(s.fin, _escenario);
      expect(s.finDeLaMemoria, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('con familias con mesa no se toca nada', () {
      final s = _sesion(recordada: alFondo, haySorteo: true);
      expect(s.fin, _escenario);
      expect(s.finDeLaMemoria, isFalse);
      expect(s.finEl, isNull);
      expect(s.puedeGuardar, isFalse);
    });

    test('en un armado del Canva no se toca nada', () {
      final s = _sesion(
        base: ArmadosPredefinidos.todos.first,
        recordada: alFondo,
      );
      expect(s.fin, _escenario);
      expect(s.finDeLaMemoria, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('si lo recordado es lo de siempre, no hay nada que guardar', () {
      final s = _sesion(recordada: NumeracionRecordada(_escenario, _t2));
      expect(s.fin, _escenario);
      expect(s.puedeGuardar, isFalse);
    });

    test('tocar una opción es elegir: lleva el momento de ahora', () {
      final s = _sesion(recordada: alFondo);
      s.elegirFin(_escenario, ahora: _t2);
      expect(s.fin, _escenario);
      expect(s.finEl, _t2);
      expect(s.finDeLaMemoria, isFalse);
    });

    test('DESCARTAR vuelve a como abrió, con la recordada', () {
      final s = _sesion(recordada: alFondo)..elegirFin(_escenario, ahora: _t2);
      s.descartar();
      expect(s.fin, _fondo);
      expect(s.finEl, _t1);
      expect(s.finDeLaMemoria, isTrue);
    });

    test('ACOMODAR LAS MESAS en un salón vacío ya numera como lo recordado',
        () {
      final vacio = ArmarAMedida.vacio(
        const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8),
      );
      final s = _sesion(base: vacio, recordada: alFondo);
      s.acomodar(40);
      expect(
        _mesaPorMesa(s.actual),
        _mesaPorMesa(
          ArmarAMedida.acomodar(vacio, cantidad: 40, fin: _fondo).armado,
        ),
      );
    });
  });

  group('al guardar', () {
    test('la que vino de la memoria queda en la fiesta, con el momento de '
        'aquella elección, y los números al fondo', () {
      final s = _sesion(recordada: NumeracionRecordada(_fondo, _t1));
      final r = _guardar(s);
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.config!.numeracion, _fondo);
      expect(r.config!.numeracionEl, _t1);
      expect(
        _mesaPorMesa(r.armado!),
        _mesaPorMesa(ArmarAMedida.ordenarNumeros(_guardado, fin: _fondo).armado),
      );
    });

    test('la que se tocó queda con el momento de ahora', () {
      final s = _sesion()..elegirFin(_fondo, ahora: _t2);
      final r = _guardar(s);
      expect(r.config!.numeracion, _fondo);
      expect(r.config!.numeracionEl, _t2);
    });

    test('sin nada recordado ni elegido, la fiesta sigue sin elegir', () {
      final s = _sesion();
      final r = _guardar(s);
      expect(r.config!.eligioNumeracion, isFalse);
      expect(
        jsonDecode(r.config!.toJson()) as Map,
        isNot(contains('numeracion')),
      );
    });

    test('una fiesta ya sorteada no anota nada, aunque haya algo recordado',
        () {
      final alumnos = [_alumno('sosa', mesas: [3])];
      final s = _sesion(
        recordada: NumeracionRecordada(_fondo, _t1),
        haySorteo: true,
      );
      final r = _guardar(s, alumnos: alumnos);
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.config!.eligioNumeracion, isFalse);
      expect(_mesaPorMesa(r.armado!), _mesaPorMesa(_guardado));
    });

    test('guardar otra cosa después no cambia el momento de la elección', () {
      final config = ConfigPlano(numeracion: _fondo, numeracionEl: _t1);
      final alFondo =
          ArmarAMedida.ordenarNumeros(_guardado, fin: _fondo).armado;
      final s = _sesion(base: alFondo, config: config);
      final r = _guardar(s, config: config);
      expect(r.config!.numeracion, _fondo);
      expect(r.config!.numeracionEl, _t1);
    });
  });

  group('dos PCs', () {
    test('lo que se elige en una vale en la otra cuando baja el plano', () {
      final oficina = _Pc();
      final casa = _Pc();

      // En la oficina, el jefe elige "Al fondo" en la fiesta A y guarda.
      final a = oficina.abrir('a')..elegirFin(_fondo, ahora: _t1);
      oficina.guardar('a', a, _t1);
      expect(oficina.recordada, NumeracionRecordada(_fondo, _t1));

      // La casa todavía no bajó ese plano: no recuerda nada.
      expect(casa.recordada, isNull);
      expect(casa.abrir('b').fin, _escenario);

      // Baja, y la fiesta B (que nunca eligió) abre con "Al fondo".
      casa.bajarDe(oficina, 'a');
      final b = casa.abrir('b');
      expect(b.fin, _fondo);
      expect(b.finDeLaMemoria, isTrue);
      casa.guardar('b', b, _t2);
      expect(casa.config('b').numeracion, _fondo);
      expect(casa.config('b').numeracionEl, _t1);
    });

    test('cambiar de nuevo queda para las que vienen, y las que ya eligieron '
        'no se tocan', () {
      final oficina = _Pc();
      final casa = _Pc();
      oficina.guardar(
        'a',
        oficina.abrir('a')..elegirFin(_fondo, ahora: _t1),
        _t1,
      );
      casa.bajarDe(oficina, 'a');

      // En la casa se elige "Junto al escenario" para la fiesta C.
      final c = casa.abrir('c');
      expect(c.fin, _fondo);
      c.elegirFin(_escenario, ahora: _t2);
      casa.guardar('c', c, _t2);
      expect(casa.config('c').numeracion, _escenario);
      expect(casa.recordada, NumeracionRecordada(_escenario, _t2));

      // La oficina lo baja: la fiesta D abre como siempre, y la A sigue al
      // fondo.
      oficina.bajarDe(casa, 'c');
      final d = oficina.abrir('d');
      expect(d.fin, _escenario);
      expect(d.puedeGuardar, isFalse);
      expect(oficina.abrir('a').fin, _fondo);
      expect(oficina.config('a').numeracionEl, _t1);
    });

    test('una PC atrasada que guarda con lo que recordaba no le gana a una '
        'elección más nueva', () {
      final oficina = _Pc();
      final casa = _Pc();
      oficina.guardar(
        'a',
        oficina.abrir('a')..elegirFin(_fondo, ahora: _t1),
        _t1,
      );
      casa.bajarDe(oficina, 'a');

      // La casa elige "Junto al escenario" (t2). La oficina todavía no lo bajó
      // y, más tarde (t3), guarda la fiesta E con lo que recordaba: al fondo.
      casa.guardar(
        'c',
        casa.abrir('c')..elegirFin(_escenario, ahora: _t2),
        _t2,
      );
      final e = oficina.abrir('e');
      expect(e.fin, _fondo);
      oficina.guardar('e', e, _t3);
      expect(
        oficina.config('e').numeracionEl,
        _t1,
        reason: 'heredó el momento de aquella elección, no el de ahora',
      );

      // Cuando se cruzan los planos, las dos recuerdan lo último que alguien
      // eligió de verdad.
      oficina.bajarDe(casa, 'c');
      casa.bajarDe(oficina, 'e');
      expect(oficina.recordada, NumeracionRecordada(_escenario, _t2));
      expect(casa.recordada, NumeracionRecordada(_escenario, _t2));
    });
  });
}
