// "Primero las familias de una sola mesa" (pedido del jefe el 16-nov-2026): con
// el tilde del cartel del SORTEO, las familias de una sola mesa en el contrato
// van en las primeras filas y, detrás, las que tienen adicional. Se combina con
// "Las mesas adicionales: Con su familia · Al final" y con "Cumplimiento
// debido". Cuenta pura: el sorteo de verdad, sin base ni pantalla.
//
// Las filas se miden en el dibujo del salón (`MesasDelPaso`), no por el número
// de mesa: así la prueba dice lo que ve el jefe en el plano.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/mesas_del_paso.dart';
import 'package:arguello_events/features/plano/services/mesas_juntas.dart';
import 'package:arguello_events/features/plano/services/orden_en_el_salon.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/features/eventos/services/cumplimiento_de_cuotas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

/// El playón de Costa Surubí.
const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39);

ArmadoSalon _salon(int mesas, {FinNumeracion fin = FinNumeracion.filas}) =>
    ArmarAMedida.armar(
      OpcionesAMedida(playon: _playon, cantidad: mesas, fin: fin),
    ).armado;

const _evento = 'e0000000-0000-4000-8000-000000000016';

ContratoAlumno _familia(
  String id, {
  int extras = 0,
  List<int> mesas = const [],
  String division = '5° A',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _evento,
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000 + 70000.0 * extras,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      totalCuotas: 9,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

/// La escuela de la prueba del cartel: 15 familias de una sola mesa, tres con
/// una adicional (a1, a2, a3), una con dos (b1) y una con cuatro (c1). 29
/// mesas.
List<ContratoAlumno> _escuela() => [
      _familia('a1', extras: 1),
      _familia('a2', extras: 1),
      _familia('a3', extras: 1, division: '5° B'),
      _familia('b1', extras: 2),
      _familia('c1', extras: 4, division: '5° B'),
      for (var i = 0; i < 15; i++)
        _familia('s$i', division: i.isEven ? '5° A' : '5° B'),
    ];

const _conAdicional = {'a1', 'a2', 'a3', 'b1', 'c1'};

/// La escuela de la ventana de prueba: 24 familias de una sola mesa, cuatro con
/// una adicional y una con dos (ninguna con "lejos"). 35 mesas: en un salón
/// justo, en mesas seguidas las que tienen adicional dejan huecos junto a la
/// pasarela, y alguna los tapa con sus mesas una detrás de la otra.
List<ContratoAlumno> _escuelaJusta() => [
      _familia('a1', extras: 1),
      _familia('a2', extras: 1),
      _familia('a3', extras: 1, division: '5° B'),
      _familia('a4', extras: 1),
      _familia('b1', extras: 2, division: '5° B'),
      for (var i = 0; i < 24; i++)
        _familia('s$i', division: i.isEven ? '5° A' : '5° B'),
    ];

const _conAdicionalJusta = {'a1', 'a2', 'a3', 'a4', 'b1'};

/// Lo que arma el cartel con "Al final" elegido.
Map<String, int> _alFinal(
  List<ContratoAlumno> alumnos, {
  int juntas = 0,
  ExclusionSorteo exclusion = ExclusionSorteo.ninguna,
}) =>
    SorteoConPlano.alFinalSegunElCartel(
      SorteoMesasMotor.pedidos(
        alumnos,
        sinMesa: exclusion.sinMesa,
        soloBase: exclusion.soloBase,
      ),
      juntas: juntas,
    );

/// En qué fila del salón dibujado está cada mesa (1, la del escenario).
Map<int, int> _filas(ArmadoSalon salon) {
  final paso = MesasDelPaso.de(salon, recorrido: RecorridoDelOrden.filas)!;
  return {
    for (final m in salon.mesas)
      if (paso.lugar(m.numero) != null) m.numero: paso.lugar(m.numero)!.fila,
  };
}

/// Las comprobaciones de lo que ve el jefe en el plano: las de una sola mesa
/// en las filas de adelante; detrás las que tienen adicional; las del final, al
/// fondo; y cada familia junta.
///
/// [unaDetrasDeLaOtra]: con el salón justo, una familia puede quedar junta con
/// sus mesas una detrás de la otra ([MesasJuntas]); si no, en un solo tramo de
/// mesas seguidas, como siempre.
void _comprobarGrupos(
  ArmadoSalon salon,
  ResultadoSorteoPlano r, {
  required Map<String, int> alFinal,
  Set<String> conAdicional = _conAdicional,
  bool unaDetrasDeLaOtra = false,
  String razon = '',
}) {
  final fila = _filas(salon);
  final primero = <int>[];
  final segundo = <int>[];
  final ultimo = <int>[];
  for (final x in r.asignaciones.entries) {
    final nums = [...x.value]..sort();
    if (!conAdicional.contains(x.key)) {
      expect(nums, hasLength(1), reason: '$razon ${x.key}');
      primero.addAll(nums);
      continue;
    }
    final atras = alFinal[x.key] ?? 0;
    final adelante = nums.sublist(0, nums.length - atras);
    final delFinal = nums.sublist(nums.length - atras);
    segundo.addAll(adelante);
    ultimo.addAll(delFinal);
    if (unaDetrasDeLaOtra) {
      expect(MesasJuntas.juntas(salon, adelante), isTrue,
          reason: '$razon ${x.key} no quedó junta: $nums');
    } else {
      expect(SorteoConPlano.tramosPegados(salon, adelante), hasLength(1),
          reason: '$razon ${x.key} no quedó junta: $nums');
    }
    if (delFinal.isNotEmpty) {
      expect(SorteoConPlano.tramosPegados(salon, delFinal), hasLength(1),
          reason: '$razon las del final de ${x.key} no quedaron juntas');
    }
  }
  // Por número: ninguna con adicional antes que una de una sola mesa.
  expect(segundo.reduce(min), greaterThan(primero.reduce(max)),
      reason: '$razon por número');
  // En el dibujo: las de una sola mesa, en las filas de adelante.
  final filaMaxUna = primero.map((n) => fila[n]!).reduce(max);
  final filaMinCon = segundo.map((n) => fila[n]!).reduce(min);
  expect(filaMinCon, greaterThanOrEqualTo(filaMaxUna),
      reason: '$razon en el dibujo');
  if (ultimo.isNotEmpty) {
    expect(ultimo.reduce(min), greaterThan(segundo.reduce(max)),
        reason: '$razon las del final');
  }
}

void main() {
  final alumnos = _escuela();
  final salon = _salon(40);

  group('sin el tilde, todo sigue como siempre', () {
    test('la vista previa no dice grupos y el sorteo es el de siempre', () {
      final e = EntradaSorteoPlano(armado: salon, alumnos: alumnos);
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue);
      expect(plan.unaMesaHasta, isNull);
      expect(plan.conAdicionalDesde, isNull);
      expect(plan.hastaMesa, 29);
      expect(SorteoConPlano.primerGrupo(e), isEmpty);
    });

    test('por división el tilde no hace nada: cada bloque es de su división',
        () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        modo: ModoSorteo.bloques,
        unaMesaPrimero: true,
      );
      expect(SorteoConPlano.primerGrupo(e), isEmpty);
      final plan = SorteoConPlano.preparar(e);
      expect(plan.unaMesaHasta, isNull);
      final r = SorteoConPlano.sortear(e, random: Random(3));
      expect(SorteoConPlano.validar(e, r), isNull);
    });
  });

  group('con el tilde y "Con su familia"', () {
    EntradaSorteoPlano entrada({int? hasta}) => EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          unaMesaPrimero: true,
          hastaMesa: hasta,
        );

    test('la vista previa: una sola mesa de la 1 a la 15; con adicionales, '
        'desde la 16', () {
      final plan = SorteoConPlano.preparar(entrada());
      expect(plan.entra, isTrue, reason: plan.avisos.join(' '));
      expect(plan.unaMesaHasta, 15);
      expect(plan.conAdicionalDesde, 16);
      // Las 14 mesas de las familias con adicional, de la 16 en adelante. Una
      // familia no se parte en la pasarela: en "Fila por fila" puede quedar
      // una mesa libre entre ellas, y entonces llegan una más allá que sin el
      // tilde (sin el tilde, una de una sola mesa tapaba ese hueco).
      expect(plan.hastaMesa, inInclusiveRange(29, 31));
      expect(plan.hastaMesaMinima, plan.hastaMesa);
    });

    test('200 sorteos: lo que dijo la vista previa es lo que queda', () {
      final hasta = SorteoConPlano.preparar(entrada()).hastaMesa!;
      for (var semilla = 0; semilla < 200; semilla++) {
        final e = entrada();
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        _comprobarGrupos(salon, r, alFinal: const {}, razon: 'semilla $semilla');
        final unas = [
          for (final x in r.asignaciones.entries)
            if (!_conAdicional.contains(x.key)) ...x.value,
        ]..sort();
        expect(unas, [for (var n = 1; n <= 15; n++) n],
            reason: 'semilla $semilla');
        final con = [
          for (final x in r.asignaciones.entries)
            if (_conAdicional.contains(x.key)) ...x.value,
        ]..sort();
        expect(con.first, greaterThanOrEqualTo(16));
        expect(con.last, lessThanOrEqualTo(hasta), reason: 'semilla $semilla');
        expect(con, hasLength(14));
      }
    });

    test('es un sorteo: dentro de cada grupo no sale siempre igual', () {
      final a = SorteoConPlano.sortear(entrada(), random: Random(1));
      final b = SorteoConPlano.sortear(entrada(), random: Random(2));
      expect(jsonEncode(a.asignaciones), isNot(jsonEncode(b.asignaciones)));
    });

    test('"Usar de la mesa 1 a la 36" estira las que tienen adicional; las de '
        'una sola mesa siguen juntas adelante', () {
      final plan = SorteoConPlano.preparar(entrada(hasta: 36));
      expect(plan.unaMesaHasta, 15);
      expect(plan.hastaMesa, 36);
      for (var semilla = 0; semilla < 40; semilla++) {
        final e = entrada(hasta: 36);
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull);
        _comprobarGrupos(salon, r, alFinal: const {}, razon: 'semilla $semilla');
        final unas = [
          for (final x in r.asignaciones.entries)
            if (!_conAdicional.contains(x.key)) ...x.value,
        ]..sort();
        expect(unas.last, 15);
      }
    });

    test('con "lejos": las de la familia de 5 mesas quedan en el grupo de '
        'atrás, lejos entre sí', () {
      for (var semilla = 0; semilla < 60; semilla++) {
        final e = EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          unaMesaPrimero: true,
          separaciones: const {'c1': 2},
          distancias: const {'c1': DistanciaLejos.bienLejos},
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        final c1 = r.asignaciones['c1']!;
        expect(c1.reduce(min), greaterThan(15), reason: 'semilla $semilla');
        expect(SorteoConPlano.lejosEnElSalon(salon, c1, 2), isTrue);
      }
    });

    test('quien contrató una adicional y no la pagó va atrás, con su principal',
        () {
      const ex = ExclusionSorteo(sinMesa: {}, soloBase: {'a1'});
      for (var semilla = 0; semilla < 40; semilla++) {
        final e = EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          exclusion: ex,
          unaMesaPrimero: true,
        );
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull);
        expect(r.asignaciones['a1'], hasLength(1));
        expect(r.asignaciones['a1']!.single, greaterThan(15),
            reason: 'semilla $semilla: ${r.asignaciones['a1']}');
      }
      expect(
        SorteoConPlano.vaEnElPrimerGrupo(
          EntradaSorteoPlano(
            armado: salon,
            alumnos: alumnos,
            unaMesaPrimero: true,
          ),
          'a1',
        ),
        isFalse,
      );
    });

    test('salón por salón: si sin el tilde entra, con el tilde también; con el '
        'salón justo, las familias con adicional tapan los huecos con sus mesas '
        'una detrás de la otra (16-nov-2026)', () {
      var algunaUnaDetrasDeLaOtra = false;
      for (final (escuela, conAdicional) in [
        (alumnos, _conAdicional),
        (_escuelaJusta(), _conAdicionalJusta),
      ]) {
        for (var mesas = 25; mesas <= 40; mesas++) {
          final chico = _salon(mesas);
          final con = EntradaSorteoPlano(
            armado: chico,
            alumnos: escuela,
            unaMesaPrimero: true,
          );
          final sin = EntradaSorteoPlano(armado: chico, alumnos: escuela);
          final plan = SorteoConPlano.preparar(con);
          if (SorteoConPlano.preparar(sin).entra) {
            expect(plan.entra, isTrue,
                reason: '$mesas mesas: ${plan.avisos.join(' ')}');
          }
          if (!plan.entra) {
            expect(() => SorteoConPlano.sortear(con, random: Random(1)),
                throwsStateError);
            continue;
          }
          if (plan.unaDetrasDeLaOtra > 0) algunaUnaDetrasDeLaOtra = true;
          for (var semilla = 0; semilla < 10; semilla++) {
            final razon = '$mesas mesas, semilla $semilla';
            final r = SorteoConPlano.sortear(con, random: Random(semilla));
            expect(SorteoConPlano.validar(con, r), isNull, reason: razon);
            _comprobarGrupos(
              chico,
              r,
              alFinal: const {},
              conAdicional: conAdicional,
              unaDetrasDeLaOtra: plan.unaDetrasDeLaOtra > 0,
              razon: razon,
            );
            // Las que quedan una detrás de la otra son las que dijo la vista
            // previa: las menos posibles.
            final usan = r.asignaciones.values
                .where((m) => MesasJuntas.usaUnaDetrasDeLaOtra(chico, m))
                .length;
            expect(usan, plan.unaDetrasDeLaOtra, reason: razon);
          }
        }
      }
      expect(algunaUnaDetrasDeLaOtra, isTrue,
          reason: 'con 35 mesas para 35, en mesas seguidas no entra');
    });
  });

  group('con el tilde y "Al final"', () {
    EntradaSorteoPlano entrada({int juntas = 0}) => EntradaSorteoPlano(
          armado: salon,
          alumnos: alumnos,
          unaMesaPrimero: true,
          alFinal: _alFinal(alumnos, juntas: juntas),
        );

    test('la vista previa: una sola mesa, las principales de las demás y al '
        'final', () {
      final plan = SorteoConPlano.preparar(entrada());
      expect(plan.entra, isTrue, reason: plan.avisos.join(' '));
      expect(plan.unaMesaHasta, 15);
      expect(plan.conAdicionalDesde, 16);
      expect(plan.hastaMesa, 20);
      expect(plan.mesasAlFinal, 9);
      expect(plan.alFinalDesde, 21);
      expect(plan.alFinalHasta, 29);
    });

    test('200 sorteos: una sola mesa, después las principales, al final las '
        'adicionales', () {
      final alFinal = _alFinal(alumnos);
      for (var semilla = 0; semilla < 200; semilla++) {
        final e = entrada();
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        _comprobarGrupos(salon, r, alFinal: alFinal, razon: 'semilla $semilla');
        final principales = [
          for (final id in _conAdicional) r.asignaciones[id]!.reduce(min),
        ]..sort();
        expect(principales, [16, 17, 18, 19, 20], reason: 'semilla $semilla');
      }
    });

    test('con 1 pegada a la principal: va con ella, en el segundo grupo', () {
      final alFinal = _alFinal(alumnos, juntas: 1);
      for (var semilla = 0; semilla < 60; semilla++) {
        final e = entrada(juntas: 1);
        final r = SorteoConPlano.sortear(e, random: Random(semilla));
        expect(SorteoConPlano.validar(e, r), isNull, reason: 'semilla $semilla');
        _comprobarGrupos(salon, r, alFinal: alFinal, razon: 'semilla $semilla');
      }
    });
  });

  group('el control final', () {
    test('rechaza un resultado con una familia con adicional antes que una de '
        'una sola mesa', () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        unaMesaPrimero: true,
      );
      final bien = SorteoConPlano.sortear(e, random: Random(5));
      expect(SorteoConPlano.validar(e, bien), isNull);
      // a1 con la 1 y la 2; la familia que tenía la 1 y la que tenía la 2,
      // donde estaba a1.
      final a1 = bien.asignaciones['a1']!;
      final quien1 =
          bien.asignaciones.entries.firstWhere((x) => x.value.contains(1)).key;
      final quien2 =
          bien.asignaciones.entries.firstWhere((x) => x.value.contains(2)).key;
      final mal = {
        ...bien.asignaciones,
        'a1': [1, 2],
        quien1: [a1[0]],
        quien2: [a1[1]],
      };
      expect(
        SorteoConPlano.validar(e, ResultadoSorteoPlano(asignaciones: mal)),
        contains('una sola mesa'),
      );
      // Sin el tilde, ese mismo resultado no tiene nada de malo.
      expect(
        SorteoConPlano.validar(
          EntradaSorteoPlano(armado: salon, alumnos: alumnos),
          ResultadoSorteoPlano(asignaciones: mal),
        ),
        isNull,
      );
    });
  });

  group('con el sorteo ya hecho, "Sortear a los que faltan"', () {
    test('nadie se mueve; los nuevos completan', () {
      final e = EntradaSorteoPlano(
        armado: salon,
        alumnos: alumnos,
        unaMesaPrimero: true,
      );
      final r = SorteoConPlano.sortear(e, random: Random(7));
      final sentados = [
        for (final a in alumnos)
          _familia(
            a.id,
            extras: a.mesaExtraCantidad,
            mesas: r.asignaciones[a.id]!,
            division: a.cursoDivision ?? '5° A',
          ),
        _familia('n1'),
        _familia('n2', extras: 1),
      ];
      for (var semilla = 0; semilla < 30; semilla++) {
        final e2 = EntradaSorteoPlano(
          armado: salon,
          alumnos: sentados,
          unaMesaPrimero: true,
        );
        final r2 = SorteoConPlano.sortear(e2, random: Random(semilla));
        expect(SorteoConPlano.validar(e2, r2), isNull, reason: 'semilla $semilla');
        // Quien ya tenía todas sus mesas no aparece, o aparece con las mismas.
        for (final a in alumnos) {
          final ahora = r2.asignaciones[a.id];
          if (ahora == null) continue;
          expect(ahora, r.asignaciones[a.id],
              reason: 'semilla $semilla: ${a.id} se movió');
        }
        expect(r2.asignaciones['n1'], hasLength(1));
        expect(r2.asignaciones['n2'], hasLength(2));
        expect(
          r2.asignaciones['n2']!.reduce(min),
          greaterThan(r2.asignaciones['n1']!.single),
          reason: 'semilla $semilla',
        );
      }
    });
  });

  group('el registro', () {
    test('lleva la marca y la vuelve a leer; una versión anterior la ignora',
        () {
      final reg = SorteoMesasRegistro(
        id: 'r1',
        eventoId: _evento,
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'a1': '16, 17'},
        unaMesaPrimero: true,
        createdAt: DateTime.utc(2026, 11, 16),
      );
      final map = reg.toMap();
      expect(map['resultado'] as String, contains('"_una_primero":1'));
      final leido = SorteoMesasRegistro.fromMap(map);
      expect(leido.unaMesaPrimero, isTrue);
      expect(leido.resultado, {'a1': '16, 17'});
      final sin = SorteoMesasRegistro.fromMap(
        SorteoMesasRegistro(
          id: 'r2',
          eventoId: _evento,
          tipo: TipoRegistroSorteo.sorteo,
          resultado: const {'a1': '1'},
          createdAt: DateTime.utc(2026, 11, 16),
        ).toMap(),
      );
      expect(sin.unaMesaPrimero, isFalse);
    });
  });

  group('con Cumplimiento debido', () {
    var n = 0;
    Map<String, dynamic> pago(int mes, int dia, double monto,
        {String concepto = 'Cuota Base'}) {
      n++;
      final fecha = DateTime.utc(2026, mes, dia, 15);
      return {
        'id': 'p$n',
        'concepto': concepto,
        'monto': monto,
        'monto_gross': monto,
        'fecha_pago': fecha.toIso8601String(),
        'created_at': fecha.add(Duration(seconds: n)).toIso8601String(),
        'anulado': 0,
      };
    }

    /// Cada familia con un cumplimiento distinto: unas cancelaron, otras al
    /// día, otras pagaron tarde. Todas con sus adicionales pagas.
    Map<String, List<Map<String, dynamic>>> pagos() {
      final r = <String, List<Map<String, dynamic>>>{};
      for (var i = 0; i < alumnos.length; i++) {
        final a = alumnos[i];
        r[a.id] = [
          ...switch (i % 3) {
            0 => [pago(4, 3 + i, 270000)],
            1 => [pago(4, 30, 30000 * 7)],
            _ => [pago(5, 1 + i, 30000), pago(5, 31, 30000 * 6)],
          },
          if (a.mesaExtraPrecio > 0)
            pago(6, 1, a.mesaExtraPrecio, concepto: 'Mesa extra (1/1)'),
        ];
      }
      return r;
    }

    OrdenParaElSorteo calcular({
      required RecorridoDelOrden recorrido,
      bool alFinal = false,
      bool unaMesaPrimero = true,
    }) {
      final p = pagos();
      return OrdenEnElSalon.paraElSorteo(
        eventoId: _evento,
        armado: salon,
        config: ConfigPlano.vacia,
        alumnos: alumnos,
        pagos: p,
        hoyAr: DateTime(2026, 11, 16),
        ahora: DateTime.utc(2026, 11, 16, 18),
        exclusion: exclusionSorteo(
          candidatos: candidatosPorPago(alumnos, pagosPorAlumno(alumnos, p)),
          soloPagado: true,
        ),
        recorrido: recorrido,
        adicionalesAlFinal: alFinal,
        unaMesaPrimero: unaMesaPrimero,
        por: 'Jefe',
      );
    }

    for (final recorrido in RecorridoDelOrden.values) {
      for (final alFinal in [false, true]) {
        test('${recorrido.rotulo}, ${alFinal ? 'Al final' : 'Con su familia'}: '
            'primero las de una sola mesa, cada grupo por cumplimiento', () {
          final o = calcular(recorrido: recorrido, alFinal: alFinal);
          expect(o.sePuede, isTrue, reason: o.problema);
          final sin = calcular(
            recorrido: recorrido,
            alFinal: alFinal,
            unaMesaPrimero: false,
          );
          // El orden: las 15 de una sola mesa y después las 5 con adicional.
          final lugares = o.configAGuardar!.frente!.lugares;
          expect(o.configAGuardar!.frente!.unaMesaPrimero, isTrue);
          expect(lugares, hasLength(20));
          expect(
            [for (final l in lugares.take(15)) _conAdicional.contains(l.alumnoId)],
            everyElement(isFalse),
          );
          expect(
            [for (final l in lugares.skip(15)) _conAdicional.contains(l.alumnoId)],
            everyElement(isTrue),
          );
          expect([for (final l in lugares) l.puesto],
              [for (var i = 1; i <= 20; i++) i]);
          // Dentro de cada grupo, el mismo orden que sin el tilde.
          final ordenSin = [
            for (final l in sin.configAGuardar!.frente!.lugares) l.alumnoId,
          ];
          List<String> enElOrden(Iterable<String> ids) =>
              [for (final id in ordenSin) if (ids.contains(id)) id];
          expect(
            [for (final l in lugares.take(15)) l.alumnoId],
            enElOrden({for (final l in lugares.take(15)) l.alumnoId}),
          );
          expect(
            [for (final l in lugares.skip(15)) l.alumnoId],
            enElOrden(_conAdicional),
          );
          // Las de adicional dicen por qué están detrás.
          for (final l in lugares.skip(15)) {
            expect(l.frase, endsWith(OrdenEnElSalon.fraseConAdicional));
          }
          for (final l in lugares.take(15)) {
            expect(l.frase, isNot(contains('adicionales')));
          }
          // En el salón: las de una sola mesa, primero en el recorrido.
          final paso = MesasDelPaso.de(salon, recorrido: recorrido)!;
          int puesto(int mesa) => paso.enOrden.indexOf(mesa);
          final unas = [
            for (final e in o.lugares.entries)
              if (!_conAdicional.contains(e.key)) ...e.value,
          ];
          final con = [
            for (final e in o.lugares.entries)
              if (_conAdicional.contains(e.key)) ...e.value,
          ];
          expect(con.map(puesto).reduce(min),
              greaterThan(unas.map(puesto).reduce(max)));
          // El sorteo de verdad las entrega, y pasa los dos controles.
          final e = OrdenEnElSalon.entrada(o, armado: salon);
          for (var semilla = 0; semilla < 20; semilla++) {
            final r = SorteoConPlano.sortear(e, random: Random(semilla));
            expect(SorteoConPlano.validar(e, r), isNull);
            expect(OrdenEnElSalon.noCumple(o, r), isNull);
          }
        });
      }
    }

    test('ninguna familia queda partida en el borde de una fila: 10 '
        'cumplimientos distintos, por filas y por columnas', () {
      for (var vuelta = 0; vuelta < 10; vuelta++) {
        Map<String, List<Map<String, dynamic>>> otrosPagos() {
          final r = <String, List<Map<String, dynamic>>>{};
          for (var i = 0; i < alumnos.length; i++) {
            final a = alumnos[i];
            r[a.id] = [
              ...switch ((i + vuelta) % 3) {
                0 => [pago(4, 3 + i, 270000)],
                1 => [pago(4, 30, 30000 * 7)],
                _ => [pago(5, 1 + i, 30000), pago(5, 31, 30000 * 6)],
              },
              if (a.mesaExtraPrecio > 0)
                pago(6, 1, a.mesaExtraPrecio, concepto: 'Mesa extra (1/1)'),
            ];
          }
          return r;
        }

        for (final recorrido in RecorridoDelOrden.values) {
          final p = otrosPagos();
          final o = OrdenEnElSalon.paraElSorteo(
            eventoId: 'e$vuelta',
            armado: salon,
            config: ConfigPlano.vacia,
            alumnos: alumnos,
            pagos: p,
            hoyAr: DateTime(2026, 11, 16),
            ahora: DateTime.utc(2026, 11, 16, 18),
            exclusion: exclusionSorteo(
              candidatos: candidatosPorPago(alumnos, pagosPorAlumno(alumnos, p)),
              soloPagado: true,
            ),
            recorrido: recorrido,
            unaMesaPrimero: true,
          );
          for (final e in o.lugares.entries) {
            if (e.value.length < 2) continue;
            expect(
              SorteoConPlano.gruposEnElSalon(salon, e.value),
              hasLength(1),
              reason: 'vuelta $vuelta, ${recorrido.rotulo}: ${e.key} '
                  'quedó partida: ${e.value}',
            );
          }
        }
      }
    });

    test('sin el tilde, el orden es el de siempre', () {
      final o = calcular(
        recorrido: RecorridoDelOrden.filas,
        unaMesaPrimero: false,
      );
      expect(o.configAGuardar!.frente!.unaMesaPrimero, isFalse);
      final orden = OrdenPorCumplimiento.de(
        alumnos: alumnos,
        pagos: pagos(),
        corteAr: DateTime(2026, 11, 16),
        rng: Random(OrdenEnElSalon.semillaDe(_evento)),
        entran: {for (final a in alumnos) a.id},
      );
      expect(
        [for (final l in o.configAGuardar!.frente!.lugares) l.alumnoId],
        [for (final p in orden) p.alumno.id],
      );
    });

    test('la marca del orden se guarda y se vuelve a leer', () {
      final o = calcular(recorrido: RecorridoDelOrden.filas);
      final leida = OrdenDelPlano.fromMap(
        jsonDecode(jsonEncode(o.configAGuardar!.frente!.toMap())),
      );
      expect(leida!.unaMesaPrimero, isTrue);
      expect(
        OrdenDelPlano.fromMap(
          jsonDecode(
            jsonEncode(
              const OrdenDelPlano(prendido: true).toMap(),
            ),
          ),
        )!.unaMesaPrimero,
        isFalse,
      );
    });
  });
}
