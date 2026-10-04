import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/divisiones.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno alumno(
  String id, {
  int extras = 0,
  String? mesa,
  String division = '5° A',
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: baja ? '[BAJA] $id' : 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: extras > 0 ? 70000.0 * extras : 0,
      mesaExtraCantidad: extras,
      numeroMesa: mesa,
      cursoDivision: division,
    );

/// [cuantas] familias de una mesa en [division], con ids correlativos.
List<ContratoAlumno> familias(String division, int cuantas, {String pre = ''}) => [
      for (var i = 0; i < cuantas; i++)
        alumno('$pre${Divisiones.clave(division)}-${i.toString().padLeft(3, '0')}',
            division: division),
    ];

/// Mismos tamaños que las instituciones reales del test del motor.
const Map<String, Map<int, int>> _instituciones = {
  'Puerto Viejo': {1: 14, 2: 6, 5: 1},
  'Técnica Pinaroli': {1: 68, 2: 12, 3: 2},
  'Buena Vista': {1: 52, 2: 1},
  'Normal Iloza': {1: 100, 2: 16},
  'Gregoria Morales': {1: 37, 2: 2},
  'Güemez de Tejada': {1: 61, 2: 5},
  'Colegio Nacional': {1: 101, 2: 11, 3: 1},
  'Rotonda': {1: 37, 2: 5, 3: 2},
  'Sagrado Corazón': {1: 87, 2: 15},
};

/// Lo que tiene que valer siempre, sortee como sortee.
void verificar(
  EntradaSorteoPlano e,
  ResultadoSorteoPlano r, {
  required String razon,
}) {
  expect(SorteoConPlano.validar(e, r), isNull, reason: razon);
  final a = e.armado;
  final todos = <int>{};
  for (final entrada in r.asignaciones.entries) {
    for (final n in entrada.value) {
      expect(todos.add(n), isTrue, reason: '$razon: la $n salió dos veces');
      expect(a.existe(n), isTrue, reason: razon);
    }
  }
  for (final n in e.config.libres.keys) {
    expect(todos.contains(n), isFalse, reason: '$razon: la libre $n se usó');
  }
}

void main() {
  group('casilleros', () {
    test('la página 3 no tiene cortes: un casillero por mesa', () {
      final c = CasillerosPlano.de(ArmadosPredefinidos.normal2aPagina3());
      expect(c.total, 78);
      expect(c.fantasmas, isEmpty);
      expect(c.casillero(1), 1);
      expect(c.casillero(78), 78);
    });

    test('Técnica: un fantasma en cada corte, y el pasto al final', () {
      final a = ArmadosPredefinidos.tecnica1a1b();
      final c = CasillerosPlano.de(a);
      expect(c.fantasmas.length, a.cortes.length);
      expect(c.total, 150 + a.cortes.length);
      expect(c.casillero(41), c.casillero(40)! + 2);
      expect(c.casillero(131), greaterThan(c.casillero(130)!));
      expect(c.numero(c.casillero(40)! + 1), isNull);
    });

    test('las mesas del medio de las páginas 4-5 quedan sueltas', () {
      final c = CasillerosPlano.de(ArmadosPredefinidos.normal2aPaginas45());
      expect(c.fantasmas.length, 2);
      expect(c.casillero(51), c.casillero(50)! + 1);
      expect(c.casillero(50), c.casillero(49)! + 2);
    });
  });

  group('sorteo entero', () {
    test('usa de la mesa 1 en adelante, lo justo', () {
      final e = EntradaSorteoPlano(
        armado: ArmadosPredefinidos.normal2aPagina3(),
        alumnos: familias('5° A', 60),
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue);
      expect(plan.hastaMesaMinima, 60);
      final r = SorteoConPlano.sortear(e, random: Random(1));
      verificar(e, r, razon: 'entera');
      expect(r.asignaciones.values.expand((l) => l).toSet(),
          {for (var n = 1; n <= 60; n++) n});
    });

    test('ninguna familia de dos mesas queda partida por un corte', () {
      final a = ArmadosPredefinidos.tecnica1a1b();
      final alumnos = [
        for (var i = 0; i < 50; i++) alumno('d$i', extras: 1),
        ...familias('5° A', 20),
      ];
      for (var s = 0; s < 20; s++) {
        final e = EntradaSorteoPlano(armado: a, alumnos: alumnos);
        final r = SorteoConPlano.sortear(e, random: Random(s));
        verificar(e, r, razon: 'semilla $s');
        for (var i = 0; i < 50; i++) {
          final nums = r.asignaciones['d$i']!;
          expect(a.pegadas(nums[0], nums[1]), isTrue,
              reason: 'semilla $s: $nums');
        }
      }
    });

    test('sin pasto no entra; con pasto usa solo lo que falta', () {
      final a = ArmadosPredefinidos.tecnica1a1b();
      final alumnos = familias('6° A', 140);
      final sin = SorteoConPlano.preparar(
        EntradaSorteoPlano(armado: a, alumnos: alumnos),
      );
      expect(sin.entra, isFalse);
      expect(sin.necesitaPasto, isTrue);

      final e = EntradaSorteoPlano(armado: a, alumnos: alumnos, usarPasto: true);
      final r = SorteoConPlano.sortear(e, random: Random(3));
      verificar(e, r, razon: 'con pasto');
      final pasto =
          r.asignaciones.values.expand((l) => l).where(a.pasto.contains);
      expect(pasto.length, 10);
    });

    test('sin necesidad, el pasto no se usa', () {
      final a = ArmadosPredefinidos.tecnica1a1b();
      final e = EntradaSorteoPlano(
        armado: a,
        alumnos: familias('6° A', 98),
        usarPasto: true,
      );
      final r = SorteoConPlano.sortear(e, random: Random(2));
      expect(r.asignaciones.values.expand((l) => l).where(a.pasto.contains),
          isEmpty);
    });
  });

  group('sorteo por bloques', () {
    // Los tamaños de los bloques de colores del jefe en las páginas 4-5.
    List<ContratoAlumno> comoElJefe() => [
          ...familias('5° A', 24),
          ...familias('5° B', 25),
          ...familias('5° C', 3),
          ...familias('5° D', 26),
          ...familias('5° E', 20),
        ];

    EntradaSorteoPlano entrada({
      List<ContratoAlumno>? alumnos,
      List<String> orden = const ['5A', '5B', '5C', '5D', '5E'],
      ConfigPlano? config,
    }) =>
        EntradaSorteoPlano(
          armado: ArmadosPredefinidos.normal2aPaginas45(),
          config: config ??
              const ConfigPlano(libres: {50: MesaLibre(), 51: MesaLibre()}),
          alumnos: alumnos ?? comoElJefe(),
          modo: ModoSorteo.bloques,
          ordenDivisiones: orden,
        );

    test('salen exactamente los bloques del Canva del jefe', () {
      final plan = SorteoConPlano.preparar(entrada());
      expect(plan.entra, isTrue);
      expect(
        [for (final f in plan.bloques) (f.nombre, f.desde, f.hasta)],
        [
          ('5° A', 1, 24),
          ('5° B', 25, 49),
          ('5° C', 52, 54),
          ('5° D', 55, 80),
          ('5° E', 81, 100),
        ],
      );
    });

    test('cada familia queda en el bloque de su división, y la vista previa '
        'coincide con el sorteo', () {
      final e = entrada();
      final plan = SorteoConPlano.preparar(e);
      for (var s = 0; s < 10; s++) {
        final r = SorteoConPlano.sortear(e, random: Random(s));
        verificar(e, r, razon: 'semilla $s');
        expect(
          [for (final b in r.bloques) (b.desde, b.hasta)],
          [for (final f in plan.bloques) (f.desde, f.hasta)],
        );
        final division = {for (final a in e.alumnos) a.id: Divisiones.clave(a.cursoDivision)};
        for (final entrada in r.asignaciones.entries) {
          final bloque =
              r.bloques.firstWhere((b) => b.division == division[entrada.key]);
          for (final n in entrada.value) {
            expect(bloque.contiene(n), isTrue,
                reason: '${entrada.key} en $n, fuera de ${bloque.desde}-${bloque.hasta}');
          }
        }
      }
    });

    test('el orden de las divisiones decide dónde va cada bloque', () {
      final plan = SorteoConPlano.preparar(
        entrada(orden: const ['5E', '5A']),
      );
      expect(plan.bloques.first.nombre, '5° E');
      expect(plan.bloques.first.desde, 1);
      expect(plan.bloques[1].nombre, '5° A');
      expect(plan.bloques[1].desde, 21);
    });

    test('las mesas libres y las fijadas no se sortean', () {
      // Una familia menos: con la 10 libre, las 98 del jefe no entrarían.
      final alumnos = comoElJefe()..removeAt(0);
      final fijo = alumnos.firstWhere((a) => a.cursoDivision == '5° D');
      final e = entrada(
        alumnos: alumnos,
        config: ConfigPlano(
          libres: const {50: MesaLibre(), 51: MesaLibre(), 10: MesaLibre()},
          fijadas: {97: MesaFijada(alumnoId: fijo.id, motivo: 'Silla de ruedas')},
        ),
      );
      final r = SorteoConPlano.sortear(e, random: Random(5));
      verificar(e, r, razon: 'fijadas y libres');
      expect(r.asignaciones[fijo.id], [97]);
      final usados = r.asignaciones.values.expand((l) => l).toSet();
      expect(usados.contains(10), isFalse);
    });

    test('una fijada de alguien que no pagó la base queda reservada', () {
      final alumnos = comoElJefe();
      final fijo = alumnos.first;
      final e = EntradaSorteoPlano(
        armado: ArmadosPredefinidos.normal2aPaginas45(),
        config: ConfigPlano(
          fijadas: {5: MesaFijada(alumnoId: fijo.id)},
        ),
        alumnos: alumnos,
        exclusion: ExclusionSorteo(sinMesa: {fijo.id}),
        modo: ModoSorteo.bloques,
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.avisos.join(), contains('reservada'));
      final r = SorteoConPlano.sortear(e, random: Random(1));
      expect(r.asignaciones.containsKey(fijo.id), isFalse);
      expect(r.asignaciones.values.expand((l) => l), isNot(contains(5)));
    });

    test('con mesas ya repartidas y sin bloques guardados, se sortea entero',
        () {
      final alumnos = [
        ...familias('5° A', 10),
        alumno('ya', mesa: '3', division: '5° B'),
        ...familias('5° B', 10),
      ];
      final plan = SorteoConPlano.preparar(entrada(alumnos: alumnos));
      expect(plan.modo, ModoSorteo.entera);
      expect(plan.modoForzado, isTrue);
    });

    test('quien llega tarde va a un hueco de su bloque, o a la reserva', () {
      final e = entrada();
      final primero = SorteoConPlano.sortear(e, random: Random(9));
      // Se da de baja a uno de 5° A (libera su mesa) y llegan dos nuevos: uno
      // de 5° A (entra en el hueco) y uno de 5° C (su bloque está lleno).
      final liberada = primero.asignaciones['5A-000']!.single;
      final alumnos = [
        for (final a in e.alumnos)
          if (a.id != '5A-000')
            a.copyWith(
              numeroMesa: primero.asignaciones[a.id]!.join(', '),
            ),
        alumno('nuevo-a', division: '5° A'),
        alumno('nuevo-c', division: '5° C'),
      ];
      final e2 = EntradaSorteoPlano(
        armado: e.armado,
        config: e.config.copyWith(bloques: primero.bloques),
        alumnos: alumnos,
        modo: ModoSorteo.bloques,
        ordenDivisiones: e.ordenDivisiones,
      );
      final plan = SorteoConPlano.preparar(e2);
      expect(plan.entra, isFalse, reason: 'en la reserva no queda lugar');

      // Con una mesa más libre al final del salón, entra.
      final e3 = EntradaSorteoPlano(
        armado: e.armado,
        config: e.config.copyWith(bloques: primero.bloques),
        alumnos: [
          for (final a in alumnos)
            if (a.cursoDivision != '5° E' || a.id != '5E-019') a,
        ],
        modo: ModoSorteo.bloques,
        ordenDivisiones: e.ordenDivisiones,
      );
      final r = SorteoConPlano.sortear(e3, random: Random(4));
      expect(r.asignaciones['nuevo-a'], [liberada]);
      expect(r.asignaciones['nuevo-c']!.single, greaterThan(80));
      expect(r.avisos.join(), contains('no entra en su bloque'));
    });
  });

  group('la red final', () {
    test('rechaza una mesa libre, una repetida o una que no existe', () {
      final e = EntradaSorteoPlano(
        armado: ArmadosPredefinidos.normal2aPagina3(),
        config: const ConfigPlano(libres: {5: MesaLibre()}),
        alumnos: [alumno('a'), alumno('b')],
      );
      expect(
        SorteoConPlano.validar(
          e,
          const ResultadoSorteoPlano(asignaciones: {'a': [5], 'b': [6]}),
        ),
        contains('libre'),
      );
      expect(
        SorteoConPlano.validar(
          e,
          const ResultadoSorteoPlano(asignaciones: {'a': [6], 'b': [6]}),
        ),
        contains('dos veces'),
      );
      expect(
        SorteoConPlano.validar(
          e,
          const ResultadoSorteoPlano(asignaciones: {'a': [200], 'b': [6]}),
        ),
        contains('no está en el plano'),
      );
    });

    test('rechaza a una familia nueva partida por un corte', () {
      final a = ArmadosPredefinidos.tecnica1a1b();
      final e = EntradaSorteoPlano(
        armado: a,
        alumnos: [alumno('a', extras: 1)],
      );
      expect(
        SorteoConPlano.validar(
          e,
          const ResultadoSorteoPlano(asignaciones: {'a': [40, 41]}),
        ),
        contains('juntas'),
      );
    });
  });

  group('estrés con las instituciones reales', () {
    final armados = <ArmadoSalon>[
      ArmadosPredefinidos.normal2aPagina3(),
      ArmadosPredefinidos.normal2aPaginas45(),
      ArmadosPredefinidos.normal2a2b(),
      ArmadosPredefinidos.tecnica1a1b(),
    ];
    var numero = 0;
    for (final inst in _instituciones.entries) {
      // Semilla fija por escuela: `hashCode` de un texto puede cambiar entre
      // versiones de Dart, y el test tiene que dar siempre lo mismo.
      final semillaEscuela = 1000 + numero++;
      test(inst.key, () {
        final rng = Random(semillaEscuela);
        final alumnos = <ContratoAlumno>[];
        final nDiv = 3 + rng.nextInt(3);
        var i = 0;
        for (final t in inst.value.entries) {
          for (var k = 0; k < t.value; k++) {
            alumnos.add(alumno(
              'x${i++}',
              extras: t.key - 1,
              division: '5° ${String.fromCharCode(65 + rng.nextInt(nDiv))}',
            ));
          }
        }
        final necesarias = inst.value.entries
            .fold<int>(0, (s, e) => s + e.key * e.value);
        // Una familia de dos o más mesas, para que la separación pedida exista
        // de verdad (a una de una sola mesa no se le puede separar nada).
        final conExtras = alumnos.firstWhere(
          (x) => x.mesaExtraCantidad > 0,
          orElse: () => alumnos.first,
        );
        final probadas = <ModoSorteo, int>{};
        for (final a in armados) {
          final holgura = a.cantidadComunes - necesarias;
          if (holgura < 0) continue;
          for (final modo in ModoSorteo.values) {
            for (var s = 0; s < 12; s++) {
              final e = EntradaSorteoPlano(
                armado: a,
                alumnos: alumnos,
                modo: modo,
                separaciones: s.isEven ? const {} : {conExtras.id: 1},
              );
              final plan = SorteoConPlano.preparar(e);
              if (!plan.entra) {
                // Por bloques, con poca holgura, puede no entrar: cada
                // división arranca donde terminó la anterior y los cortes se
                // comen mesas. Entero tiene que entrar siempre que haya lugar.
                expect(modo, ModoSorteo.bloques,
                    reason: '${a.clave}: entero tendría que entrar '
                        '(holgura $holgura)');
                expect(holgura, lessThan(15),
                    reason: '${a.clave}: con holgura $holgura tendría que entrar');
                continue;
              }
              final r = SorteoConPlano.sortear(e, random: Random(s));
              verificar(e, r, razon: '${inst.key} ${a.clave} ${modo.name} $s');
              expect(r.asignaciones.length, alumnos.length);
              probadas[modo] = (probadas[modo] ?? 0) + 1;
            }
          }
        }
        // Los dos modos se probaron de verdad: que entero entre no alcanza.
        expect(probadas[ModoSorteo.entera] ?? 0, greaterThan(0));
        expect(probadas[ModoSorteo.bloques] ?? 0, greaterThan(0),
            reason: 'por bloques no entró en ningún armado');
      });
    }
  });

  // El pedido del 3-oct: después del sorteo, con el mismo botón, darle mesa
  // al que faltaba. Si ya no queda lugar, se agregan mesas en Personalizar →
  // Acomodar y se vuelve a sortear.
  group('sortear a los que faltan, después de acomodar el salón', () {
    for (final modo in ModoSorteo.values) {
      test('${modo.clave}: los que ya tenían mesa no se mueven, y los que '
          'faltaban van a las mesas agregadas', () {
        final armado = ArmadosPredefinidos.normal2aPaginas45();
        // El salón lleno: una familia por mesa, en cuatro divisiones.
        final cuantas = armado.cantidadComunes;
        final divisiones = ['5° A', '5° B', '5° C', '5° D'];
        final alumnos = [
          for (var i = 0; i < cuantas; i++)
            alumno('f${i.toString().padLeft(3, '0')}',
                division: divisiones[i * divisiones.length ~/ cuantas]),
        ];
        final orden = [for (final d in divisiones) Divisiones.clave(d)];
        final e1 = EntradaSorteoPlano(
          armado: armado,
          alumnos: alumnos,
          modo: modo,
          ordenDivisiones: orden,
        );
        final primero = SorteoConPlano.sortear(e1, random: Random(3));
        verificar(e1, primero, razon: 'primer sorteo');
        final sentados = [
          for (final a in alumnos)
            a.copyWith(numeroMesa: primero.asignaciones[a.id]!.join(', ')),
        ];
        final config = ConfigPlano(bloques: primero.bloques);

        // Aparecen tres familias: una terminó de pagar, otra se sumó tarde y
        // otra, con dos mesas.
        final faltaban = [
          alumno('tarde-1', division: '5° A'),
          alumno('tarde-2', division: '5° C'),
          alumno('tarde-3', extras: 1, division: '5° D'),
        ];
        final todos = [...sentados, ...faltaban];

        // Con el salón como estaba no hay lugar: avisa y no sortea.
        final sinLugar = SorteoConPlano.preparar(EntradaSorteoPlano(
          armado: armado,
          config: config,
          alumnos: todos,
          modo: modo,
          ordenDivisiones: orden,
        ));
        expect(sinLugar.entra, isFalse);

        // Se agregan cuatro mesas en Acomodar, de a una al lado de la otra.
        final sesion = SesionAcomodo(
          base: armado,
          enUso: EditarArmado.enUso(sentados, config),
          haySorteo: true,
        );
        final hoja = armado.hojas.last.id;
        var fondo = 0.0;
        for (final m in armado.mesasDeHoja(hoja)) {
          fondo = max(fondo, m.y);
        }
        final nuevas = <int>[];
        for (var i = 0; i < 4; i++) {
          nuevas.add(sesion.agregar(hoja));
        }
        // Número nuevo: siguen al más alto, ninguna reusa uno.
        final masAlto = armado.numeros.reduce(max);
        expect(nuevas, [for (var i = 1; i <= 4; i++) masAlto + i]);
        // Sin elegir dónde, quedan al fondo y cada una pegada a la anterior.
        for (final (i, n) in nuevas.indexed) {
          expect(sesion.actual.mesa(n)!.y, greaterThanOrEqualTo(fondo - 0.01),
              reason: 'la $n quedó hacia el escenario');
          if (i > 0) {
            expect(sesion.actual.pegadas(nuevas[i - 1], n), isTrue,
                reason: 'la $n no quedó al lado de la ${nuevas[i - 1]}');
          }
        }
        // Las que ya tienen familia no se sacan.
        expect(sesion.sacar(armado.numeros.first), isNotNull);
        expect(sesion.puedeGuardar, isTrue);
        final guardar = EditarArmado.paraGuardar(
          base: armado,
          nuevo: sesion.actual,
          fresco: armado,
          config: config,
          alumnos: sentados,
          enUsoVisto: sesion.enUsoAlEmpezar,
        );
        expect(guardar.sePuede, isTrue);
        final acomodado = guardar.armado!;
        // Nadie cambió de lugar en el dibujo ni de número.
        for (final m in armado.mesas) {
          expect(acomodado.mesa(m.numero)!.x, m.x);
          expect(acomodado.mesa(m.numero)!.y, m.y);
        }

        // Se vuelve a tocar SORTEO.
        final e2 = EntradaSorteoPlano(
          armado: acomodado,
          config: guardar.config!,
          alumnos: todos,
          modo: modo,
          ordenDivisiones: orden,
        );
        expect(SorteoConPlano.preparar(e2).entra, isTrue);
        final segundo = SorteoConPlano.sortear(e2, random: Random(8));
        verificar(e2, segundo, razon: 'los que faltaban');

        // Los que ya tenían mesa no figuran entre los sorteados, o figuran
        // con la misma.
        for (final a in sentados) {
          final ahora = segundo.asignaciones[a.id];
          if (ahora != null) {
            expect(ahora.join(', '), a.numeroMesa, reason: a.id);
          }
        }
        // Los que faltaban recibieron mesa, todas de las agregadas.
        final dadas = <int>[];
        for (final a in faltaban) {
          final mesas = segundo.asignaciones[a.id];
          expect(mesas, isNotNull, reason: a.id);
          dadas.addAll(mesas!);
        }
        expect(dadas.toSet(), nuevas.toSet());
        // Y la familia de dos mesas quedó con las dos pegadas.
        final dos = segundo.asignaciones['tarde-3']!;
        expect(dos.length, 2);
        expect(acomodado.pegadas(dos.first, dos.last), isTrue);
      });
    }

    test('por bloques: si en Acomodar se sacó la mesa del borde de un bloque, '
        'el que faltaba de esa división sigue yendo a un hueco de su bloque',
        () {
      final armado = ArmadosPredefinidos.normal2aPaginas45();
      final divisiones = ['5° A', '5° B', '5° C', '5° D'];
      final alumnos = [
        for (var i = 0; i < 80; i++)
          alumno('f${i.toString().padLeft(3, '0')}',
              division: divisiones[i * divisiones.length ~/ 80]),
      ];
      final orden = [for (final d in divisiones) Divisiones.clave(d)];
      final primero = SorteoConPlano.sortear(
        EntradaSorteoPlano(
          armado: armado,
          alumnos: alumnos,
          modo: ModoSorteo.bloques,
          ordenDivisiones: orden,
        ),
        random: Random(3),
      );
      final bloque = primero.bloques
          .firstWhere((b) => b.division == Divisiones.clave('5° B'));
      String familiaDe(int mesa) => primero.asignaciones.entries
          .firstWhere((e) => e.value.contains(mesa))
          .key;
      // Dos familias de 5° B dejan su mesa: la del borde del bloque y una del
      // medio.
      final hueco = bloque.desde + 3;
      final seFueron = {familiaDe(bloque.hasta), familiaDe(hueco)};
      final sentados = [
        for (final a in alumnos)
          if (!seFueron.contains(a.id))
            a.copyWith(numeroMesa: primero.asignaciones[a.id]!.join(', ')),
      ];
      final config = ConfigPlano(bloques: primero.bloques);

      // En Acomodar se saca la mesa del borde, que quedó vacía.
      final sesion = SesionAcomodo(
        base: armado,
        enUso: EditarArmado.enUso(sentados, config),
        haySorteo: true,
      );
      expect(sesion.sacar(bloque.hasta), isNull);
      final guardar = EditarArmado.paraGuardar(
        base: armado,
        nuevo: sesion.actual,
        fresco: armado,
        config: config,
        alumnos: sentados,
        enUsoVisto: sesion.enUsoAlEmpezar,
      );
      expect(guardar.sePuede, isTrue);

      // Llega una familia de 5° B y se vuelve a tocar SORTEO: va al hueco de
      // su bloque, no a la reserva de después del último.
      final e2 = EntradaSorteoPlano(
        armado: guardar.armado!,
        config: guardar.config!,
        alumnos: [...sentados, alumno('tarde', division: '5° B')],
        modo: ModoSorteo.bloques,
        ordenDivisiones: orden,
      );
      final segundo = SorteoConPlano.sortear(e2, random: Random(8));
      verificar(e2, segundo, razon: 'borde de bloque sacado');
      expect(segundo.asignaciones['tarde'], [hueco]);
    });
  });
}
