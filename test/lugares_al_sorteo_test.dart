import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/registro_sorteo.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/plano/services/mesa_nueva_sola.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

// La regla (17-nov-2026): el descuento de PRECIOS es para la mesa adicional y
// las sillas extra que la familia tenía cargadas al sorteo, pagadas o no. Lo
// que agrega después paga la entrada entera. En una fiesta sorteada antes de la
// regla, el programa propone por las huellas y el jefe acepta; lo que no deja
// huella queda para revisar, sin cobrarle entera a nadie por una duda.

// 12/11/2026 21:40 en Argentina.
final _sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);

DateTime _mas(int horas) => _sorteoEl.add(Duration(hours: horas));

String _fecha(DateTime d) => ArTime.formatFechaHora(d);

ContratoAlumno _alumno(
  String id, {
  int extras = 0,
  int sillas = 0,
  String? mesa,
  DateTime? creado,
  String? nombre,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre ?? 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa: mesa,
      createdAt: creado ?? DateTime.utc(2026, 3, 1),
    );

SorteoMesasRegistro _r(
  String id,
  Map<String, String> resultado, {
  int horas = 0,
  TipoRegistroSorteo tipo = TipoRegistroSorteo.sorteo,
  Map<String, String>? antes,
  Map<String, String>? quedan,
  Map<String, String>? lugares,
  DateTime? lugaresEl,
  bool auto = false,
}) =>
    SorteoMesasRegistro(
      id: id,
      eventoId: 'e',
      tipo: tipo,
      resultado: resultado,
      antes: antes,
      quedan: quedan,
      lugares: lugares,
      lugaresEl: lugaresEl,
      automatico: auto,
      hechoPor: auto ? null : 'Jefe',
      createdAt: _mas(horas),
    );

SorteoMesasRegistro _deshacerTodo(String id, {required int horas}) =>
    _r(id, const {'a': '12'}, horas: horas, tipo: TipoRegistroSorteo.deshacer);

SorteoMesasRegistro _deshacerUltimos(String id, {required int horas}) => _r(
      id,
      const {'a': '12'},
      horas: horas,
      tipo: TipoRegistroSorteo.deshacer,
      quedan: const {},
    );

Map<String, dynamic> _pago(
  String concepto,
  double monto,
  DateTime? cuando, {
  bool anulado = false,
}) =>
    {
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': anulado ? 1 : 0,
      if (cuando != null) 'created_at': cuando.toIso8601String(),
    };

SillasReparto _reparto(
  String alumnoId, {
  required int sillas,
  required DateTime creado,
  DateTime? tocado,
}) =>
    SillasReparto(
      id: 'rep-$alumnoId',
      contratoAlumnoId: alumnoId,
      sillasPrincipal: sillas,
      sillasExtra: sillas,
      mesas: 1,
      createdAt: creado,
      updatedAt: tocado ?? creado,
    );

/// Las dudas de una fiesta sorteada el 12/11 sin anotar los lugares.
List<LugarEnDuda> _duda(
  List<ContratoAlumno> alumnos, {
  Map<String, String> sorteo = const {'x': '1'},
  List<SorteoMesasRegistro> despues = const [],
  Map<String, List<Map<String, dynamic>>> pagos = const {},
  Map<String, SillasReparto> repartos = const {},
}) =>
    LugaresAlSorteo.enDuda(
      registros: [_r('s', sorteo), ...despues],
      alumnos: alumnos,
      pagos: pagos,
      repartos: repartos,
    );

void main() {
  group('lo cargado de una familia', () {
    test('solo la mesa del contrato: no tiene adicionales', () {
      final l = LugaresCargados.de(_alumno('a'));
      expect(l, LugaresCargados.soloElContrato);
      expect(l.tieneAdicionales, isFalse);
    });

    test('una adicional y dos sillas: "2,2"', () {
      final l = LugaresCargados.de(_alumno('a', extras: 1, sillas: 2));
      expect(l, const LugaresCargados(2, 2));
      expect(l.tieneAdicionales, isTrue);
      expect(l.texto, '2,2');
    });

    test('el texto se lee de vuelta', () {
      expect(LugaresCargados.deTexto('2,1'), const LugaresCargados(2, 1));
      expect(LugaresCargados.deTexto(' 3 , 0 '), const LugaresCargados(3, 0));
    });

    test('un texto que no se entiende da null: decide quien lo lee', () {
      for (final malo in [null, '', '2', '1,2,3', 'a,b', '0,1', '1,-1', '2;1']) {
        expect(LugaresCargados.deTexto(malo), isNull, reason: '"$malo"');
      }
    });
  });

  group('lo que se anota al sortear', () {
    test('figura solo quien tiene algo más que la mesa del contrato', () {
      final lugares = LugaresAlSorteo.sacar([
        _alumno('a'),
        _alumno('b', extras: 1),
        _alumno('c', sillas: 2),
        _alumno('d', extras: 2, sillas: 1),
      ]);
      expect(lugares, {'b': '2,0', 'c': '1,2', 'd': '3,1'});
    });

    test('lo cargado cuenta aunque no tenga número de mesa ni esté pago', () {
      // La adicional cargada y sin pagar no recibe mesa en el sorteo, pero la
      // tenía: sus entradas van con descuento.
      final lugares = LugaresAlSorteo.sacar([_alumno('a', extras: 1, mesa: '12')]);
      expect(lugares, {'a': '2,0'});
    });

    test('sin nadie con adicionales queda vacío, no null', () {
      expect(LugaresAlSorteo.sacar([_alumno('a'), _alumno('b')]), isEmpty);
    });
  });

  group('qué rige para la fiesta', () {
    test('sin registro: no hay sorteo y todo va con descuento', () {
      final foto = LugaresAlSorteo.vigente(const []);
      expect(foto.estado, EstadoDeLosLugares.sinSorteo);
      expect(foto.de('a'), isNull);
      expect(foto.sorteoEl, isNull);
    });

    test('un sorteo de antes de la regla: sin anotar, todo con descuento', () {
      final foto = LugaresAlSorteo.vigente([_r('s', const {'a': '12'})]);
      expect(foto.estado, EstadoDeLosLugares.sinAnotar);
      expect(foto.de('a'), isNull);
      expect(foto.sorteoEl, _sorteoEl);
    });

    test('con los lugares anotados: cada uno lo suyo, y quien no figura, solo su mesa', () {
      final foto = LugaresAlSorteo.vigente([
        _r('s', const {'a': '12, 13', 'b': '14'}, lugares: const {'a': '2,1'}),
      ]);
      expect(foto.estado, EstadoDeLosLugares.anotados);
      expect(foto.de('a'), const LugaresCargados(2, 1));
      expect(foto.de('b'), LugaresCargados.soloElContrato);
      // Quien entró a la fiesta después del sorteo tampoco figura.
      expect(foto.de('nuevo'), LugaresCargados.soloElContrato);
      expect(foto.sorteoEl, _sorteoEl);
      expect(foto.del, _sorteoEl);
    });

    test('anotado y vacío no es "sin anotar": nadie tenía adicionales', () {
      final foto =
          LugaresAlSorteo.vigente([_r('s', const {'a': '12'}, lugares: const {})]);
      expect(foto.estado, EstadoDeLosLugares.anotados);
      expect(foto.de('a'), LugaresCargados.soloElContrato);
    });

    test('un texto roto no le saca el descuento a nadie', () {
      final foto = LugaresAlSorteo.vigente([
        _r('s', const {'a': '12'}, lugares: const {'a': 'cualquier cosa'}),
      ]);
      final e = RetiroEntradas.entradasDe(
        _alumno('a', extras: 2, sillas: 4),
        foto: foto,
      );
      expect(e.sinDescuento, 0);
      expect(e.conDescuento, 20);
    });

    test('la mesa que el programa dio sola no es el sorteo de la fiesta', () {
      final foto = LugaresAlSorteo.vigente([
        _r('auto', const {'z': '90'}, horas: -5, auto: true),
        _r('s', const {'a': '12'}, lugares: const {'a': '2,0'}),
      ]);
      expect(foto.estado, EstadoDeLosLugares.anotados);
      expect(foto.sorteoEl, _sorteoEl);
      expect(foto.de('a'), const LugaresCargados(2, 0));
    });

    test('solo con renglones automáticos no hay sorteo', () {
      final foto = LugaresAlSorteo.vigente([
        _r('auto', const {'z': '90'}, auto: true),
      ]);
      expect(foto.estado, EstadoDeLosLugares.sinSorteo);
    });

    test('"los que faltaban" no mueve el día del sorteo: rige el primero', () {
      final foto = LugaresAlSorteo.vigente([
        _r('s1', const {'a': '12'}, lugares: const {'a': '1,2'}),
        _r(
          's2',
          const {'b': '20, 21'},
          horas: 48,
          lugares: const {'a': '2,2', 'b': '2,0'},
        ),
      ]);
      expect(foto.sorteoEl, _sorteoEl);
      expect(foto.de('a'), const LugaresCargados(1, 2));
      // Al primer sorteo "b" tenía solo su mesa: la adicional vino después.
      expect(foto.de('b'), LugaresCargados.soloElContrato);
    });

    test('deshacer todo y sortear otro día: cuenta el sorteo nuevo', () {
      final registros = [
        _r('s1', const {'a': '12'}, lugares: const {}),
        _deshacerTodo('d', horas: 24),
      ];
      expect(
        LugaresAlSorteo.vigente(registros).estado,
        EstadoDeLosLugares.sinSorteo,
      );
      final foto = LugaresAlSorteo.vigente([
        ...registros,
        _r('s2', const {'a': '12, 13'}, horas: 72, lugares: const {'a': '2,0'}),
      ]);
      expect(foto.sorteoEl, _mas(72));
      expect(foto.de('a'), const LugaresCargados(2, 0));
    });

    test('deshacer solo los últimos deja en pie el primer sorteo', () {
      final foto = LugaresAlSorteo.vigente([
        _r('s1', const {'a': '12'}, lugares: const {'a': '1,1'}),
        _r('s2', const {'b': '20'}, horas: 24, lugares: const {'b': '2,0'}),
        _deshacerUltimos('d', horas: 25),
      ]);
      expect(foto.sorteoEl, _sorteoEl);
      expect(foto.de('a'), const LugaresCargados(1, 1));
    });

    test('deshacer los últimos cuando era el único: no queda sorteo', () {
      final foto = LugaresAlSorteo.vigente([
        _r('s1', const {'a': '12'}, lugares: const {'a': '1,1'}),
        _deshacerUltimos('d', horas: 1),
      ]);
      expect(foto.estado, EstadoDeLosLugares.sinSorteo);
    });

    test('restaurar: sigue contando el sorteo que se restaura', () {
      final foto = LugaresAlSorteo.vigente([
        _r('s1', const {'a': '12, 13'}, lugares: const {'a': '2,0'}),
        _deshacerTodo('d', horas: 24),
        _r(
          'rest',
          const {'a': '12, 13'},
          horas: 30,
          tipo: TipoRegistroSorteo.restaurar,
          lugares: const {'a': '2,0'},
          lugaresEl: _sorteoEl,
        ),
      ]);
      expect(foto.estado, EstadoDeLosLugares.anotados);
      expect(foto.sorteoEl, _mas(30));
      expect(foto.del, _sorteoEl, reason: 'lo anotado es del sorteo original');
      expect(foto.de('a'), const LugaresCargados(2, 0));
    });
  });

  group('lo que lleva una restauración', () {
    test('los lugares del sorteo que se había deshecho', () {
      final r = LugaresAlSorteo.paraRestaurar([
        _r('s1', const {'a': '12, 13'}, lugares: const {'a': '2,0'}),
        _deshacerTodo('d', horas: 24),
      ]);
      expect(r, isNotNull);
      expect(r!.lugares, {'a': '2,0'});
      expect(r.del, _sorteoEl);
    });

    test('con el sorteo en pie no lleva nada', () {
      final r = LugaresAlSorteo.paraRestaurar([
        _r('s1', const {'a': '12'}, lugares: const {'a': '2,0'}),
      ]);
      expect(r, isNull);
    });

    test('si aquel sorteo no los había anotado, tampoco', () {
      final r = LugaresAlSorteo.paraRestaurar([
        _r('s1', const {'a': '12'}),
        _deshacerTodo('d', horas: 24),
      ]);
      expect(r, isNull);
    });

    test('sin registro no lleva nada', () {
      expect(LugaresAlSorteo.paraRestaurar(const []), isNull);
    });

    test('restaurar, deshacer y restaurar de nuevo: el día sigue siendo el primero', () {
      final r = LugaresAlSorteo.paraRestaurar([
        _r('s1', const {'a': '12'}, lugares: const {'a': '2,0'}),
        _deshacerTodo('d1', horas: 24),
        _r(
          'rest',
          const {'a': '12'},
          horas: 30,
          tipo: TipoRegistroSorteo.restaurar,
          lugares: const {'a': '2,0'},
          lugaresEl: _sorteoEl,
        ),
        _deshacerTodo('d2', horas: 40),
      ]);
      expect(r!.lugares, {'a': '2,0'});
      expect(r.del, _sorteoEl);
    });

    test('se deshizo de a uno hasta el primero: se restaura el primero', () {
      final r = LugaresAlSorteo.paraRestaurar([
        _r('auto', const {'z': '90'}, horas: -5, auto: true),
        _r('s1', const {'a': '12'}, lugares: const {'a': '1,2'}),
        _r('s2', const {'b': '20'}, horas: 24, lugares: const {'b': '2,0'}),
        _deshacerUltimos('d1', horas: 25),
        _deshacerUltimos('d2', horas: 26),
      ]);
      expect(r!.lugares, {'a': '1,2'});
      expect(r.del, _sorteoEl);
    });

    test('dos sorteos deshechos: vale el más nuevo', () {
      final r = LugaresAlSorteo.paraRestaurar([
        _r('s1', const {'a': '12'}, lugares: const {'a': '1,2'}),
        _deshacerTodo('d1', horas: 24),
        _r('s2', const {'a': '12'}, horas: 48, lugares: const {'a': '2,2'}),
        _deshacerTodo('d2', horas: 50),
      ]);
      expect(r!.lugares, {'a': '2,2'});
      expect(r.del, _mas(48));
    });
  });

  group('cómo viaja en el renglón', () {
    test('ida y vuelta: los lugares y de cuándo son', () {
      final ida = _r(
        'rest',
        const {'a': '12, 13'},
        tipo: TipoRegistroSorteo.restaurar,
        antes: const {},
        lugares: const {'a': '2,1'},
        lugaresEl: _mas(-48),
      );
      final vuelta = SorteoMesasRegistro.fromMap(ida.toMap());
      expect(vuelta.resultado, {'a': '12, 13'});
      expect(vuelta.lugares, {'a': '2,1'});
      expect(vuelta.lugaresEl, _mas(-48));
      expect(vuelta.alumnos, 1, reason: 'la clave no cuenta como una familia');
    });

    test('vacío viaja como vacío: es lo que dice que el sorteo los anotó', () {
      final ida = _r('s', const {'a': '12'}, lugares: const {});
      final texto = jsonDecode(ida.toMap()['resultado'] as String) as Map;
      expect(texto[SorteoMesasRegistro.claveLugares], isEmpty);
      final vuelta = SorteoMesasRegistro.fromMap(ida.toMap());
      expect(vuelta.lugares, isNotNull);
      expect(vuelta.lugares, isEmpty);
    });

    test('un renglón sin lugares no lleva la clave', () {
      final texto =
          jsonDecode(_r('s', const {'a': '12'}).toMap()['resultado'] as String)
              as Map;
      expect(texto.containsKey(SorteoMesasRegistro.claveLugares), isFalse);
      expect(texto.containsKey(SorteoMesasRegistro.claveLugaresEl), isFalse);
    });

    test('agregarle los lugares a un renglón ya escrito no pierde nada, '
        'tampoco una clave que esta versión no conoce', () {
      final crudo = jsonEncode({
        'a': '12, 13',
        'b': '14',
        '_antes': {'a': '12'},
        '_nuevas': {'a': '13'},
        '_auto': 1,
        '_de_otra_version': {'x': 'y'},
      });
      final nuevo = SorteoMesasRegistro.resultadoConLugares(
        crudo,
        const {'a': '2,0'},
      );
      final antes = jsonDecode(crudo) as Map;
      final despues = jsonDecode(nuevo!) as Map;
      expect(despues[SorteoMesasRegistro.claveLugares], {'a': '2,0'});
      despues.remove(SorteoMesasRegistro.claveLugares);
      expect(despues, antes);

      final leido = SorteoMesasRegistro.fromMap({
        'id': 's',
        'evento_id': 'e',
        'tipo': 'sorteo',
        'resultado': nuevo,
        'created_at': _sorteoEl.toIso8601String(),
      });
      expect(leido.resultado, {'a': '12, 13', 'b': '14'});
      expect(leido.antes, {'a': '12'});
      expect(leido.nuevas, {'a': '13'});
      expect(leido.automatico, isTrue);
      expect(leido.lugares, {'a': '2,0'});
    });

    test('aceptar de nuevo reemplaza lo anotado', () {
      final crudo = jsonEncode({
        'a': '12',
        '_lugares': {'a': '3,0'},
      });
      final nuevo =
          SorteoMesasRegistro.resultadoConLugares(crudo, const {'a': '2,0'});
      expect((jsonDecode(nuevo!) as Map)['_lugares'], {'a': '2,0'});
    });

    test('un texto que no se lee no se reescribe', () {
      expect(SorteoMesasRegistro.resultadoConLugares('no es json', const {}),
          isNull);
      expect(SorteoMesasRegistro.resultadoConLugares('[1, 2]', const {}), isNull);
      expect(SorteoMesasRegistro.resultadoConLugares(null, const {}), isNull);
    });
  });

  group('convivencia: con y sin los lugares, el registro dice lo mismo', () {
    List<SorteoMesasRegistro> registros({required bool conLugares}) {
      final crudos = [
        _r('auto', const {'z': '90'}, horas: -5, antes: const {}, auto: true),
        _r(
          's1',
          const {'a': '12, 13', 'b': '14'},
          antes: const {},
          lugares: conLugares ? const {'a': '2,0', 'c': '2,2'} : null,
        ),
        _r(
          's2',
          const {'c': '15, 16'},
          horas: 48,
          antes: const {},
          lugares: conLugares ? const {'a': '2,0', 'c': '2,2'} : null,
        ),
      ];
      // Como los lee la app: de la base.
      return [for (final r in crudos) SorteoMesasRegistro.fromMap(r.toMap())];
    }

    final alumnos = [
      _alumno('a', extras: 1, mesa: '12, 13'),
      _alumno('b', mesa: '14'),
      _alumno('c', extras: 1, sillas: 2, mesa: '15, 16'),
      // Cargada a mano después: un cambio que el registro no vio.
      _alumno('d', mesa: '30'),
      _alumno('z', mesa: '90'),
    ];

    final sin = registros(conLugares: false);
    final con = registros(conLugares: true);

    test('los sorteos en pie', () {
      expect(
        RegistroSorteo.sorteosEnPie(con).map((r) => r.id),
        RegistroSorteo.sorteosEnPie(sin).map((r) => r.id),
      );
      expect(con.map((r) => r.alumnos), sin.map((r) => r.alumnos));
    });

    test('lo que cada familia debería tener', () {
      expect(RegistroSorteo.esperado(con), RegistroSorteo.esperado(sin));
    });

    test('el resumen y la línea de los papeles', () {
      final a = RegistroSorteo.resumir(sin, alumnos);
      final b = RegistroSorteo.resumir(con, alumnos);
      expect(b.ultimo?.id, a.ultimo?.id);
      expect(b.cambiosAMano, a.cambiosAMano);
      expect(a.cambiosAMano, 1);
      expect(b.cambiosConMotivo, a.cambiosConMotivo);
      expect(b.enPie.map((r) => r.id), a.enPie.map((r) => r.id));
      expect(
        RegistroSorteo.lineaParaPlanilla(b),
        RegistroSorteo.lineaParaPlanilla(a),
      );
      expect(RegistroSorteo.lineaParaPlanilla(b), contains('Los que faltaban'));
    });

    test('deshacer solo los últimos', () {
      final a = UltimosSorteados.de(sin, alumnos)!;
      final b = UltimosSorteados.de(con, alumnos)!;
      expect(b.sorteo.id, a.sorteo.id);
      expect(b.familias, a.familias);
      expect(a.familias, {'c'});
      expect(b.aGuardar, a.aGuardar);
      expect(b.tenian, a.tenian);
      expect(b.quedan, a.quedan);
      expect(b.otrosConMesa, a.otrosConMesa);
    });

    test('el último movimiento del jefe, para la mesa que se da sola', () {
      expect(MesaNuevaSola.ultimoDelJefe(con), MesaNuevaSola.ultimoDelJefe(sin));
      expect(MesaNuevaSola.ultimoDelJefe(con), _mas(48));
    });

    test('sin nada aceptado, las entradas de todos dan igual que antes', () {
      final foto = LugaresAlSorteo.vigente(sin);
      expect(foto.estado, EstadoDeLosLugares.sinAnotar);
      for (final a in alumnos) {
        final antes = RetiroEntradas.entradasDe(a);
        final ahora = RetiroEntradas.entradasDe(a, foto: foto);
        expect(ahora.conDescuento, antes.conDescuento, reason: a.id);
        expect(ahora.sinDescuento, 0, reason: a.id);
        expect(ahora.generales, antes.generales, reason: a.id);
      }
    });
  });

  group('las huellas de una fiesta ya sorteada', () {
    test('sin sorteo del jefe no hay nada que revisar', () {
      final alumnos = [_alumno('a', extras: 1)];
      expect(
        LugaresAlSorteo.enDuda(registros: const [], alumnos: alumnos),
        isEmpty,
      );
      expect(
        LugaresAlSorteo.enDuda(
          registros: [_r('auto', const {'a': '12'}, auto: true)],
          alumnos: alumnos,
        ),
        isEmpty,
      );
    });

    test('con los lugares ya anotados no hay nada que revisar', () {
      expect(
        LugaresAlSorteo.enDuda(
          registros: [_r('s', const {'a': '12'}, lugares: const {})],
          alumnos: [_alumno('a', extras: 1, mesa: '12')],
        ),
        isEmpty,
      );
    });

    test('quien tiene solo la mesa del contrato no figura', () {
      expect(_duda([_alumno('a', mesa: '12')], sorteo: const {'a': '12'}), isEmpty);
    });

    group('la mesa adicional', () {
      test('salió con número en el sorteo: ya la tenía', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12, 13')],
          sorteo: const {'a': '12, 13'},
        );
        expect(d, isEmpty);
      });

      test('la mudaron después con Mover: el número nuevo cuenta como del sorteo', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '40, 41')],
          sorteo: const {'a': '12, 13'},
        );
        expect(d, isEmpty);
      });

      test('sin número, con un pago de mesa anterior al sorteo: ya la tenía', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [_pago('Mesa Extra 1', 20000, _mas(-72))],
          },
        );
        expect(d, isEmpty);
      });

      test('un pago sin fecha que se pueda leer cuenta como de antes', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [_pago('Mesa Extra 1', 70000, null)],
          },
        );
        expect(d, isEmpty);
      });

      test('sin número ni pago: para revisar, sin tildar', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
        );
        expect(d, hasLength(1));
        expect(d.single.esMesa, isTrue);
        expect(d.single.cantidad, 1);
        expect(d.single.entradas, 8);
        expect(d.single.despues, isFalse);
        expect(d.single.huellas, [
          'Una mesa adicional cargada, todavía sin número.',
          'Sin pagos de mesa adicional.',
        ]);
      });

      test('un pago anulado no es huella', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [_pago('Mesa Extra 1', 70000, _mas(-72), anulado: true)],
          },
        );
        expect(d.single.despues, isFalse);
        expect(d.single.huellas.last, 'Sin pagos de mesa adicional.');
      });

      test('la mora de una mesa no es un pago de mesa', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [
              {
                ..._pago('Interés por mora · Mesa Extra 1', 5000, _mas(-72)),
                'line_kind': 'interes_mora',
              },
            ],
          },
        );
        expect(d, hasLength(1));
        expect(d.single.despues, isFalse);
      });

      test('un pago posterior al sorteo no alcanza: para revisar, con su fecha', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [_pago('Mesa Extra 1', 70000, _mas(20))],
          },
        );
        expect(d.single.despues, isFalse);
        expect(
          d.single.huellas.last,
          'Primer pago de mesa adicional: ${_fecha(_mas(20))}.',
        );
      });

      test('el programa se la dio sola, sin ningún pago de mesa hasta ahí: '
          'vino después (tildada)', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12, 151')],
          sorteo: const {'a': '12'},
          despues: [
            _r(
              'auto',
              const {'a': '12, 151'},
              horas: 60,
              antes: const {'a': '12'},
              auto: true,
            ),
          ],
        );
        expect(d, hasLength(1));
        expect(d.single.despues, isTrue);
        expect(d.single.cantidad, 1);
        expect(d.single.huellas.single, contains('Mesa 151'));
        expect(d.single.huellas.single, contains(_fecha(_mas(60))));
        expect(d.single.huellas.single, contains('sin ningún pago de mesa'));
      });

      test('el programa se la dio sola por un pago posterior al sorteo: pudo '
          'estar cargada antes sin pagar, para revisar', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12, 151')],
          sorteo: const {'a': '12'},
          despues: [
            _r(
              'auto',
              const {'a': '12, 151'},
              horas: 60,
              antes: const {'a': '12'},
              auto: true,
            ),
          ],
          pagos: {
            'a': [_pago('Mesa Extra 1', 70000, _mas(59))],
          },
        );
        expect(d, hasLength(1));
        expect(d.single.despues, isFalse);
        expect(
          d.single.huellas.first,
          'Mesa 151: recibió el número el ${_fecha(_mas(60))}, con un pago '
          'posterior al sorteo.',
        );
        expect(
          d.single.huellas.last,
          'Primer pago de mesa adicional: ${_fecha(_mas(59))}.',
        );
      });

      test('se la dio el jefe con "los que faltaban": para revisar', () {
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12, 80')],
          sorteo: const {'a': '12'},
          despues: [
            _r('s2', const {'a': '12, 80'}, horas: 48, antes: const {'a': '12'}),
          ],
        );
        expect(d.single.despues, isFalse);
        expect(
          d.single.huellas.first,
          'Mesa 80: recibió el número el ${_fecha(_mas(48))}.',
        );
      });

      test('dos adicionales: una salió en el sorteo y la otra no', () {
        final d = _duda(
          [_alumno('a', extras: 2, mesa: '12, 13')],
          sorteo: const {'a': '12, 13'},
        );
        expect(d, hasLength(1));
        expect(d.single.cantidad, 1);
        expect(d.single.queEs, '1 mesa adicional');
        expect(d.single.despues, isFalse);
      });

      test('dos adicionales después del sorteo: la que se dio sola, tildada; '
          'la que sigue sin número, para revisar', () {
        final d = _duda(
          [_alumno('a', extras: 2, mesa: '12, 151')],
          sorteo: const {'a': '12'},
          despues: [
            _r(
              'auto',
              const {'a': '12, 151'},
              horas: 60,
              antes: const {'a': '12'},
              auto: true,
            ),
          ],
        );
        expect(d, hasLength(2));
        expect(d[0].despues, isTrue);
        expect(d[0].cantidad, 1);
        expect(d[1].despues, isFalse);
        expect(d[1].cantidad, 1);
        expect(d[0].clave, isNot(d[1].clave));
      });

      test('un deshacer posterior nombra a la familia pero no le dio ninguna mesa', () {
        // "Los que faltaban" le dio la 13 y después se deshizo solo eso: hoy
        // tiene la 12, que es del sorteo.
        final d = _duda(
          [_alumno('a', extras: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          despues: [
            _r('s2', const {'a': '12, 13'}, horas: 48, antes: const {'a': '12'}),
            _r(
              'd',
              const {'a': '12, 13'},
              horas: 50,
              tipo: TipoRegistroSorteo.deshacer,
              quedan: const {'a': '12'},
            ),
          ],
        );
        expect(d.single.despues, isFalse);
        expect(
          d.single.huellas.first,
          'Una mesa adicional cargada, todavía sin número.',
        );
      });
    });

    group('el alumno que entró después del sorteo', () {
      test('su adicional y sus sillas vienen tildadas', () {
        final d = _duda(
          [
            _alumno(
              'a',
              extras: 1,
              sillas: 2,
              mesa: '151, 152',
              creado: _mas(30),
            ),
          ],
          despues: [
            _r('s2', const {'a': '151, 152'}, horas: 31, antes: const {}),
          ],
        );
        expect(d, hasLength(2));
        final mesa = d.firstWhere((x) => x.esMesa);
        final sillas = d.firstWhere((x) => !x.esMesa);
        expect(mesa.despues, isTrue);
        expect(mesa.cantidad, 1);
        expect(sillas.despues, isTrue);
        expect(sillas.cantidad, 2);
        expect(sillas.entradas, 2);
        expect(sillas.queEs, '2 sillas extra');
        final porque =
            'El alumno se cargó el ${_fecha(_mas(30))}, después del sorteo.';
        expect(mesa.huellas, [porque]);
        expect(sillas.huellas, [porque]);
      });
    });

    group('las sillas extra', () {
      test('con un pago de sillas anterior al sorteo: ya las tenía', () {
        final d = _duda(
          [_alumno('a', sillas: 2, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [_pago('Sillas Extra', 8000, _mas(-10))],
          },
        );
        expect(d, isEmpty);
      });

      test('eligió el reparto antes del sorteo y no se tocó: tenía esas', () {
        final d = _duda(
          [_alumno('a', sillas: 2, mesa: '12')],
          sorteo: const {'a': '12'},
          repartos: {'a': _reparto('a', sillas: 2, creado: _mas(-10))},
        );
        expect(d, isEmpty);
      });

      test('el reparto de antes era por 1 silla y hoy tiene 2: una en duda', () {
        final d = _duda(
          [_alumno('a', sillas: 2, mesa: '12')],
          sorteo: const {'a': '12'},
          repartos: {'a': _reparto('a', sillas: 1, creado: _mas(-10))},
        );
        expect(d.single.esMesa, isFalse);
        expect(d.single.cantidad, 1);
        expect(d.single.queEs, '1 silla extra');
        expect(d.single.despues, isFalse);
      });

      test('el reparto de antes se volvió a tocar después: no dice cuántas '
          'tenía, y ante la duda el descuento queda', () {
        final d = _duda(
          [_alumno('a', sillas: 2, mesa: '12')],
          sorteo: const {'a': '12'},
          repartos: {
            'a': _reparto('a', sillas: 2, creado: _mas(-10), tocado: _mas(5)),
          },
        );
        expect(d, isEmpty);
      });

      test('un reparto elegido después del sorteo no es huella', () {
        final d = _duda(
          [_alumno('a', sillas: 2, mesa: '12')],
          sorteo: const {'a': '12'},
          repartos: {'a': _reparto('a', sillas: 2, creado: _mas(5))},
        );
        expect(d.single.cantidad, 2);
        expect(d.single.despues, isFalse);
      });

      test('sin pagos ni reparto: para revisar', () {
        final d = _duda(
          [_alumno('a', sillas: 1, mesa: '12')],
          sorteo: const {'a': '12'},
        );
        expect(d.single.despues, isFalse);
        expect(d.single.huellas, ['Sin pagos de sillas extra.']);
      });

      test('el primer pago de sillas fue después: para revisar, con su fecha', () {
        final d = _duda(
          [_alumno('a', sillas: 1, mesa: '12')],
          sorteo: const {'a': '12'},
          pagos: {
            'a': [_pago('Sillas Extra', 8000, _mas(12))],
          },
        );
        expect(d.single.despues, isFalse);
        expect(
          d.single.huellas.single,
          'Primer pago de sillas extra: ${_fecha(_mas(12))}, después del '
          'sorteo.',
        );
      });

      test('un pago de mesa no es huella de las sillas', () {
        final d = _duda(
          [_alumno('a', extras: 1, sillas: 1, mesa: '12, 13')],
          sorteo: const {'a': '12, 13'},
          pagos: {
            'a': [_pago('Mesa Extra 1', 70000, _mas(-10))],
          },
        );
        expect(d.single.esMesa, isFalse);
      });
    });

    test('la lista va por nombre', () {
      final d = _duda([
        _alumno('1', nombre: 'ZARATE, LUZ', sillas: 1),
        _alumno('2', nombre: 'acosta, juan', sillas: 1),
        _alumno('3', nombre: 'Medina, Ana', sillas: 1),
      ]);
      expect(d.map((x) => x.nombre), ['acosta, juan', 'Medina, Ana', 'ZARATE, LUZ']);
    });
  });

  group('lo que queda anotado cuando el jefe acepta', () {
    final alumnos = [
      _alumno('a', extras: 2, mesa: '12, 151'),
      _alumno('b', sillas: 2, mesa: '14'),
      _alumno('c', extras: 1, mesa: '15, 16'),
      _alumno('d', mesa: '17'),
    ];
    final registros = [
      _r('s', const {'a': '12', 'b': '14', 'c': '15, 16', 'd': '17'}),
      _r(
        'auto',
        const {'a': '12, 151'},
        horas: 60,
        antes: const {'a': '12'},
        auto: true,
      ),
    ];
    final enDuda = LugaresAlSorteo.enDuda(registros: registros, alumnos: alumnos);

    test('la propuesta: de "a", una tildada y una para revisar; de "b", sus sillas', () {
      expect(enDuda.map((d) => d.clave), ['a|m|d', 'a|m|r', 'b|s|r']);
    });

    test('sin tildar a nadie: todo lo de hoy queda con descuento', () {
      final lugares = LugaresAlSorteo.alAceptar(
        alumnos: alumnos,
        enDuda: enDuda,
        pagaEntera: const {},
      );
      expect(lugares, {'a': '3,0', 'b': '1,2', 'c': '2,0'});
    });

    test('como viene (solo las que tienen huella de después)', () {
      final lugares = LugaresAlSorteo.alAceptar(
        alumnos: alumnos,
        enDuda: enDuda,
        pagaEntera: {
          for (final d in enDuda)
            if (d.despues) d.clave,
        },
      );
      expect(lugares, {'a': '2,0', 'b': '1,2', 'c': '2,0'});
    });

    test('tildando también las de revisar: quien queda con solo su mesa no figura', () {
      final lugares = LugaresAlSorteo.alAceptar(
        alumnos: alumnos,
        enDuda: enDuda,
        pagaEntera: {for (final d in enDuda) d.clave},
      );
      expect(lugares, {'c': '2,0'});
    });

    test('una clave que no es de la lista no cambia nada', () {
      final lugares = LugaresAlSorteo.alAceptar(
        alumnos: alumnos,
        enDuda: enDuda,
        pagaEntera: const {'c|m|d', 'nadie|s|r'},
      );
      expect(lugares, {'a': '3,0', 'b': '1,2', 'c': '2,0'});
    });

    test('aceptado, el renglón del sorteo dice qué va con descuento y qué no', () {
      final lugares = LugaresAlSorteo.alAceptar(
        alumnos: alumnos,
        enDuda: enDuda,
        pagaEntera: const {'a|m|d', 'b|s|r'},
      );
      final sorteo = registros.first;
      final texto = SorteoMesasRegistro.resultadoConLugares(
        sorteo.toMap()['resultado'],
        lugares,
      );
      final aceptado = SorteoMesasRegistro.fromMap({
        ...sorteo.toMap(),
        'resultado': texto,
      });
      final foto = LugaresAlSorteo.vigente([aceptado, registros.last]);
      expect(foto.estado, EstadoDeLosLugares.anotados);

      final a = RetiroEntradas.entradasDe(alumnos[0], foto: foto);
      expect(a.conDescuento, 8);
      expect(a.sinDescuento, 8);
      final b = RetiroEntradas.entradasDe(alumnos[1], foto: foto);
      expect(b.conDescuento, 0);
      expect(b.sinDescuento, 2);
      final c = RetiroEntradas.entradasDe(alumnos[2], foto: foto);
      expect(c.conDescuento, 8);
      expect(c.sinDescuento, 0);
      final d = RetiroEntradas.entradasDe(alumnos[3], foto: foto);
      expect(d.aComprar, 0);

      // Y ya no queda nada para revisar.
      expect(
        LugaresAlSorteo.enDuda(
          registros: [aceptado, registros.last],
          alumnos: alumnos,
        ),
        isEmpty,
      );
    });
  });
}
