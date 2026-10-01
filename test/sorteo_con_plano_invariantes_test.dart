// Lo que tiene que valer SIEMPRE en un sorteo sobre el plano, sortee como
// sortee: se prueba con cientos de escuelas armadas al azar, y las reglas se
// comprueban acá, sin apoyarse en `SorteoConPlano.validar` (que es justamente
// una de las cosas bajo prueba).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/divisiones.dart';
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

List<int> _numeros(ContratoAlumno a) =>
    MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).toList();

/// Tramos de mesas seguidas **y** pegadas en el salón, calculados acá.
int _tramos(ArmadoSalon a, List<int> nums) {
  final l = [...nums]..sort();
  var tramos = l.isEmpty ? 0 : 1;
  for (var i = 1; i < l.length; i++) {
    if (l[i] != l[i - 1] + 1 || !a.pegadas(l[i - 1], l[i])) tramos++;
  }
  return tramos;
}

/// Las reglas del salón, comprobadas a mano sobre un resultado.
void comprobarReglas(
  EntradaSorteoPlano e,
  ResultadoSorteoPlano r, {
  required String razon,
}) {
  final a = e.armado;
  final porId = {for (final x in e.alumnos) x.id: x};
  final antes = {for (final x in e.alumnos) x.id: _numeros(x)};
  final fijadaPara = {
    for (final f in e.config.fijadas.entries) f.key: f.value.alumnoId,
  };
  final fijadasDe = e.config.fijadasPorAlumno;

  // Nadie con una mesa de otro: ni entre los sorteados, ni de quien no entró
  // al sorteo (bajas, familias completas).
  final duenio = <int, String>{};
  for (final x in e.alumnos) {
    if (r.asignaciones.containsKey(x.id)) continue;
    for (final n in antes[x.id]!) {
      duenio[n] = x.id;
    }
  }
  for (final entrada in r.asignaciones.entries) {
    final id = entrada.key;
    final nums = entrada.value;
    final alumno = porId[id];
    expect(alumno, isNotNull, reason: '$razon: $id no es de la fiesta');
    expect(alumno!.esBajaTemporal, isFalse, reason: '$razon: $id está de baja');
    expect(e.exclusion.sinMesa.contains(id), isFalse,
        reason: '$razon: $id no pagó la base');

    for (final n in nums) {
      expect(a.existe(n), isTrue, reason: '$razon: la $n no existe');
      expect(duenio[n], anyOf(isNull, id),
          reason: '$razon: la $n es de $id y de ${duenio[n]}');
      duenio[n] = id;
    }
    // A quien ya tenía mesa no se le saca ninguna.
    expect(nums.toSet().containsAll(antes[id]!), isTrue,
        reason: '$razon: a $id se le movió una mesa');

    // Recibe lo que le corresponde: la base, o la base más las extra.
    final debidas = e.exclusion.soloBase.contains(id)
        ? 1
        : 1 + alumno.mesaExtraCantidad;
    expect(nums.length, debidas, reason: '$razon: $id con ${nums.length} mesas');

    final suyasFijadas = fijadasDe[id] ?? const <int>[];
    for (final n in nums) {
      if (antes[id]!.contains(n)) continue;
      final para = fijadaPara[n];
      if (para != null) {
        expect(para, id, reason: '$razon: la $n estaba fijada para $para');
        continue;
      }
      expect(e.config.libres.containsKey(n), isFalse,
          reason: '$razon: la $n estaba libre a propósito');
      if (!e.usarPasto) {
        expect(a.pasto.contains(n), isFalse,
            reason: '$razon: la $n es del pasto y no se tildó');
      }
    }

    // Una familia nueva, sin fijadas ni separación pedida, queda junta.
    final nueva = antes[id]!.isEmpty && suyasFijadas.isEmpty;
    if (nueva && (e.separaciones[id] ?? 0) == 0) {
      expect(_tramos(a, nums), 1, reason: '$razon: $id quedó partida en $nums');
    }
  }
  // La red final no puede rechazar lo que el sorteo produce.
  expect(SorteoConPlano.validar(e, r), isNull, reason: razon);
}

/// Sortea y comprueba, o comprueba que no se puede. Devuelve el resultado.
ResultadoSorteoPlano? sortearYComprobar(
  EntradaSorteoPlano e,
  int semilla, {
  required String razon,
}) {
  final plan = SorteoConPlano.preparar(e);
  if (!plan.entra) {
    expect(
      () => SorteoConPlano.sortear(e, random: Random(semilla)),
      throwsStateError,
      reason: '$razon: la vista previa dijo que no entra',
    );
    return null;
  }
  // Si la vista previa dijo que entra, el sorteo no puede tirar.
  final r = SorteoConPlano.sortear(e, random: Random(semilla));
  comprobarReglas(e, r, razon: razon);
  if (plan.modo == ModoSorteo.bloques && e.config.bloques.isEmpty) {
    // El primer sorteo por bloques: los bloques son los que se mostraron, y
    // cada familia nueva sin fijadas está en el de su división.
    expect(
      [for (final b in r.bloques) (b.division, b.desde, b.hasta)],
      [
        for (final f in plan.bloques)
          if (f.desde != null) (f.clave, f.desde, f.hasta),
      ],
      reason: '$razon: los bloques no son los de la vista previa',
    );
    final division = {
      for (final x in e.alumnos) x.id: Divisiones.clave(x.cursoDivision),
    };
    for (final entrada in r.asignaciones.entries) {
      final tieneFijadas =
          e.config.fijadasPorAlumno.containsKey(entrada.key);
      if (tieneFijadas || _numeros(e.alumnos.firstWhere((x) => x.id == entrada.key)).isNotEmpty) {
        continue;
      }
      final bloque =
          r.bloques.firstWhere((b) => b.division == division[entrada.key]);
      for (final n in entrada.value) {
        expect(bloque.contiene(n), isTrue,
            reason: '$razon: ${entrada.key} en la $n, fuera de su bloque');
      }
    }
  }
  return r;
}

void main() {
  final armados = <String, ArmadoSalon>{
    'página 3': ArmadosPredefinidos.normal2aPagina3(),
    'páginas 4-5': ArmadosPredefinidos.normal2aPaginas45(),
    '2A + 2B': ArmadosPredefinidos.normal2a2b(),
    'Técnica': ArmadosPredefinidos.tecnica1a1b(),
    // A medida del playón: sin pasto, con el borde del hormigón y, a 2,5 m,
    // con su propia distancia para decidir qué mesas están pegadas.
    'a medida, 2 m': ArmarAMedida.armar(
      const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 150),
    ).armado,
    'a medida, 2,5 m, dos hojas': ArmarAMedida.armar(
      const OpcionesAMedida(
        playon: PlayonReal.costaSurubi,
        cantidad: 150,
        lugarM: 2.5,
        partirEnFila: 6,
      ),
    ).armado,
  };

  group('mesas fijadas', () {
    final a = ArmadosPredefinidos.normal2aPagina3();

    test('una fijada que el plano no tiene no rompe: se avisa y no se usa', () {
      // El salón se achicó después de fijarla. Antes esto tiraba al abrir el
      // diálogo, y el sorteo de esa fiesta no se podía ni mirar.
      final e = EntradaSorteoPlano(
        armado: a,
        config: const ConfigPlano(fijadas: {97: MesaFijada(alumnoId: 'x')}),
        alumnos: [alumno('x'), alumno('y')],
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue);
      expect(plan.avisos.join(), contains('no está en el plano'));
      final r = sortearYComprobar(e, 1, razon: 'fijada inexistente')!;
      expect(r.asignaciones['x'], hasLength(1));
      expect(a.existe(r.asignaciones['x']!.single), isTrue);
    });

    test('una fijada sobre la mesa de otra familia no se da dos veces', () {
      final e = EntradaSorteoPlano(
        armado: a,
        config: const ConfigPlano(fijadas: {5: MesaFijada(alumnoId: 'nuevo')}),
        alumnos: [alumno('nuevo'), alumno('ya', mesa: '5')],
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.avisos.join(), contains('ya la tiene'));
      final r = sortearYComprobar(e, 2, razon: 'fijada ajena')!;
      expect(r.asignaciones['nuevo'], isNot(contains(5)));
    });

    test('la fijada de quien ya tiene mesa y compró otra: se le da esa', () {
      final e = EntradaSorteoPlano(
        armado: a,
        config: const ConfigPlano(fijadas: {13: MesaFijada(alumnoId: 'g')}),
        alumnos: [alumno('g', extras: 1, mesa: '12'), alumno('otro')],
      );
      for (var s = 0; s < 10; s++) {
        final r = sortearYComprobar(e, s, razon: 'fijada para completar $s')!;
        expect(r.asignaciones['g'], [12, 13]);
      }
    });

    test('una familia con todas sus mesas fijadas se sortea sin más (entero)',
        () {
      final e = EntradaSorteoPlano(
        armado: a,
        config: const ConfigPlano(
          fijadas: {
            40: MesaFijada(alumnoId: 'f'),
            41: MesaFijada(alumnoId: 'f'),
          },
        ),
        alumnos: [alumno('f', extras: 1)],
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue);
      expect(plan.hastaMesaMinima, isNotNull,
          reason: 'sin "hasta qué mesa" el diálogo dejaba SORTEAR apagado');
      final r = sortearYComprobar(e, 3, razon: 'todas fijadas')!;
      expect(r.asignaciones['f'], [40, 41]);
    });

    test('una fijada del pasto vale aunque no se tilde el pasto', () {
      final t = ArmadosPredefinidos.tecnica1a1b();
      final e = EntradaSorteoPlano(
        armado: t,
        config: const ConfigPlano(fijadas: {131: MesaFijada(alumnoId: 'p')}),
        alumnos: [alumno('p'), alumno('q')],
      );
      final r = sortearYComprobar(e, 4, razon: 'fijada en el pasto')!;
      expect(r.asignaciones['p'], [131]);
      expect(t.pasto.contains(r.asignaciones['q']!.single), isFalse);
    });

    test('la fijada de una familia de baja queda reservada, con aviso', () {
      final e = EntradaSorteoPlano(
        armado: a,
        config: const ConfigPlano(fijadas: {7: MesaFijada(alumnoId: 'b')}),
        alumnos: [alumno('b', baja: true), alumno('c')],
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.avisos.join(), contains('de baja'));
      final r = sortearYComprobar(e, 5, razon: 'fijada de baja')!;
      expect(r.asignaciones.containsKey('b'), isFalse);
      expect(r.asignaciones['c'], isNot(contains(7)));
    });
  });

  group('a quien ya tiene mesa no se le mueve', () {
    final t = ArmadosPredefinidos.tecnica1a1b();

    test('el que compró una mesa después la recibe pegada a la suya', () {
      for (var s = 0; s < 20; s++) {
        final e = EntradaSorteoPlano(
          armado: t,
          alumnos: [
            alumno('compro', extras: 1, mesa: '20'),
            alumno('completo', mesa: '5'),
            alumno('baja', mesa: '21', baja: true),
            alumno('nuevo'),
          ],
        );
        final r = sortearYComprobar(e, s, razon: 'completar $s')!;
        expect(r.asignaciones['compro'], contains(20));
        // La 21 es de una familia de baja: conserva su lugar. Le toca la 19.
        expect(r.asignaciones['compro'], [19, 20]);
        expect(r.asignaciones.containsKey('completo'), isFalse);
        expect(r.asignaciones.containsKey('baja'), isFalse);
      }
    });
  });

  group('usar de la mesa 1 a la N', () {
    final a = ArmadosPredefinidos.normal2aPagina3();
    final alumnos = [for (var i = 0; i < 20; i++) alumno('h$i')];

    test('con una N mayor que la mínima, se reparte en todo ese tramo', () {
      final e = EntradaSorteoPlano(armado: a, alumnos: alumnos, hastaMesa: 70);
      final plan = SorteoConPlano.preparar(e);
      expect(plan.hastaMesaMinima, 20);
      expect(plan.hastaMesa, 70);
      final usadas = <int>{};
      for (var s = 0; s < 30; s++) {
        final r = sortearYComprobar(e, s, razon: 'hasta 70 · $s')!;
        usadas.addAll(r.asignaciones.values.expand((l) => l));
      }
      expect(usadas.every((n) => n <= 70), isTrue);
      expect(usadas.any((n) => n > 20), isTrue,
          reason: 'con 70 mesas para 20 familias, alguna cae después de la 20');
    });

    test('una N que el salón no tiene se ignora: vale la mínima', () {
      // El diálogo no deja sortear así (marca el campo en rojo); si igual
      // llega, no se inventa una mesa.
      final e = EntradaSorteoPlano(armado: a, alumnos: alumnos, hastaMesa: 200);
      expect(SorteoConPlano.preparar(e).hastaMesa, 20);
      final r = sortearYComprobar(e, 1, razon: 'hasta 200')!;
      expect(r.asignaciones.values.expand((l) => l).every((n) => n <= 20), isTrue);
    });
  });

  group('la red final', () {
    final t = ArmadosPredefinidos.tecnica1a1b();

    String? red(
      EntradaSorteoPlano e,
      Map<String, List<int>> asignaciones,
    ) =>
        SorteoConPlano.validar(e, ResultadoSorteoPlano(asignaciones: asignaciones));

    test('rechaza una mesa fijada para otra familia', () {
      final e = EntradaSorteoPlano(
        armado: t,
        config: const ConfigPlano(fijadas: {9: MesaFijada(alumnoId: 'b')}),
        alumnos: [alumno('a'), alumno('b')],
      );
      expect(red(e, {'a': [9], 'b': [10]}), contains('fijada para otra'));
      expect(red(e, {'a': [10], 'b': [9]}), isNull);
    });

    test('rechaza una mesa del pasto si no se pidió usarlo', () {
      final alumnos = [alumno('a')];
      expect(
        red(EntradaSorteoPlano(armado: t, alumnos: alumnos), {'a': [131]}),
        contains('pasto'),
      );
      expect(
        red(
          EntradaSorteoPlano(armado: t, alumnos: alumnos, usarPasto: true),
          {'a': [131]},
        ),
        isNull,
      );
    });

    test('rechaza a una familia nueva que no quedó junta', () {
      final e = EntradaSorteoPlano(armado: t, alumnos: [alumno('a', extras: 1)]);
      expect(red(e, {'a': [10, 30]}), contains('juntas'));
      // Seguidas en el número pero con un corte en el medio: tampoco.
      expect(t.pegadas(40, 41), isFalse);
      expect(red(e, {'a': [40, 41]}), contains('juntas'));
      expect(red(e, {'a': [10, 11]}), isNull);
    });

    test('con una separación pedida, las mesas pueden ir separadas', () {
      final e = EntradaSorteoPlano(
        armado: t,
        alumnos: [alumno('a', extras: 1)],
        separaciones: const {'a': 1},
      );
      expect(red(e, {'a': [10, 30]}), isNull);
      // Y también a los dos lados de un corte (antes lo rechazaba siempre).
      expect(red(e, {'a': [40, 41]}), isNull);
    });

    test('rechaza dar una mesa que ya era de otra familia', () {
      final e = EntradaSorteoPlano(
        armado: t,
        alumnos: [alumno('a'), alumno('b', mesa: '12')],
      );
      expect(red(e, {'a': [12]}), contains('ya era de otra familia'));
    });

    test('rechaza sacarle una mesa a quien ya la tenía', () {
      final e = EntradaSorteoPlano(
        armado: t,
        alumnos: [alumno('a', extras: 1, mesa: '12')],
      );
      expect(red(e, {'a': [13, 14]}), contains('se le sacó'));
      expect(red(e, {'a': [12, 13]}), isNull);
    });

    test('dos familias con el mismo número cargado de antes no traban el sorteo',
        () {
      // Es un problema viejo (lo avisa la pantalla), no de este sorteo. Frenar
      // por eso dejaba sin sortear a toda la escuela.
      final e = EntradaSorteoPlano(
        armado: t,
        alumnos: [
          alumno('a', extras: 1, mesa: '12'),
          alumno('b', extras: 1, mesa: '12'),
        ],
      );
      expect(red(e, {'a': [11, 12], 'b': [12, 13]}), isNull);
    });
  });

  group('los que llegan tarde a un sorteo por bloques', () {
    final a = ArmadosPredefinidos.normal2aPaginas45();
    // Los bloques del jefe, ya guardados.
    const bloques = [
      BloqueDivision('5A', 1, 24),
      BloqueDivision('5B', 25, 49),
      BloqueDivision('5C', 52, 54),
      BloqueDivision('5D', 55, 80),
      BloqueDivision('5E', 81, 100),
    ];
    String divisionDe(int n) => n <= 24
        ? '5° A'
        : n <= 49
            ? '5° B'
            : n <= 54
                ? '5° C'
                : n <= 80
                    ? '5° D'
                    : '5° E';

    /// El salón lleno, con una familia por mesa, salvo los [huecos].
    List<ContratoAlumno> lleno(Set<int> huecos) => [
          for (final m in a.mesas)
            if (!huecos.contains(m.numero) && m.numero != 50 && m.numero != 51)
              alumno('s${m.numero}',
                  mesa: '${m.numero}', division: divisionDe(m.numero)),
        ];

    EntradaSorteoPlano entrada(List<ContratoAlumno> alumnos) => EntradaSorteoPlano(
          armado: a,
          config: const ConfigPlano(
            libres: {50: MesaLibre(), 51: MesaLibre()},
            bloques: bloques,
          ),
          alumnos: alumnos,
          modo: ModoSorteo.bloques,
        );

    test('la vista previa y el sorteo dicen lo mismo, con cualquier azar', () {
      // Cuatro huecos seguidos en el bloque de 5° A. Llega una familia de 5° A
      // (1 mesa) y una de 5° C con 3 mesas, que no entra en su bloque ni
      // después del último: necesita 3 seguidas de esos huecos. Si la de 5° A
      // cae en el medio, no quedan. Antes la vista previa podía decir "entra" y
      // el sorteo tirar, o apagar SORTEAR pudiendo entrar.
      final e = entrada([
        ...lleno({7, 8, 9, 10}),
        alumno('tarde-a', division: '5° A'),
        alumno('tarde-c', extras: 2, division: '5° C'),
      ]);
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue, reason: 'hay un reparto en el que entran');
      for (var s = 0; s < 200; s++) {
        final r = sortearYComprobar(e, s, razon: 'tarde, semilla $s')!;
        expect(r.asignaciones['tarde-a']!.single, anyOf(7, 10));
        expect(
          r.asignaciones['tarde-c'],
          anyOf(equals([8, 9, 10]), equals([7, 8, 9])),
        );
        expect(r.bloques, bloques, reason: 'los bloques guardados no cambian');
      }
    });

    test('si de ninguna forma entran, la vista previa lo dice y no se sortea',
        () {
      final e = entrada([
        ...lleno({7, 8, 9}),
        alumno('tarde-a', division: '5° A'),
        alumno('tarde-c', extras: 2, division: '5° C'),
      ]);
      expect(SorteoConPlano.preparar(e).entra, isFalse);
      expect(() => SorteoConPlano.sortear(e, random: Random(1)), throwsStateError);
    });

    test('con lugar después del último bloque, van ahí y se avisa', () {
      // Técnica: bloques guardados hasta la 80, y de la 81 a la 130 vacío.
      final t = ArmadosPredefinidos.tecnica1a1b();
      final sentados = [
        for (var n = 1; n <= 80; n++)
          alumno('s$n', mesa: '$n', division: n <= 40 ? '6° A' : '6° B'),
      ];
      final e = EntradaSorteoPlano(
        armado: t,
        config: const ConfigPlano(
          bloques: [BloqueDivision('6A', 1, 40), BloqueDivision('6B', 41, 80)],
        ),
        alumnos: [...sentados, alumno('tarde', extras: 1, division: '6° A')],
        modo: ModoSorteo.bloques,
      );
      final plan = SorteoConPlano.preparar(e);
      expect(plan.entra, isTrue);
      expect(plan.avisos.join(), contains('después del último bloque'));
      expect(plan.bloques.single.enReserva, isTrue);
      for (var s = 0; s < 20; s++) {
        final r = sortearYComprobar(e, s, razon: 'reserva $s')!;
        expect(r.asignaciones['tarde']!.every((n) => n > 80), isTrue);
      }
    });
  });

  group('cientos de escuelas al azar', () {
    /// Una escuela armada al azar sobre [a], sin nadie sentado todavía.
    EntradaSorteoPlano escuela(ArmadoSalon a, Random r, ModoSorteo modo) {
      final comunes = a.cantidadComunes;
      // Entre el 55 % y el 100 % del salón, para que a veces no entre.
      final objetivo = (comunes * (0.55 + r.nextDouble() * 0.45)).round();
      final nDiv = 2 + r.nextInt(4);
      final alumnos = <ContratoAlumno>[];
      var mesas = 0;
      var i = 0;
      while (mesas < objetivo) {
        final extras = switch (r.nextInt(12)) { 0 => 2, 1 || 2 => 1, _ => 0 };
        final division = r.nextInt(25) == 0
            ? ''
            : '5° ${String.fromCharCode(65 + r.nextInt(nDiv))}';
        alumnos.add(alumno('n${i++}', extras: extras, division: division));
        mesas += 1 + extras;
      }
      // Algunas mesas libres a propósito y algunas fijadas (la familia entera).
      final numeros = [for (final m in a.mesas) if (!m.pasto) m.numero]
        ..shuffle(r);
      final libres = {
        for (final n in numeros.take(r.nextInt(4))) n: const MesaLibre(),
      };
      final fijadas = <int, MesaFijada>{};
      final conUna = alumnos.where((x) => x.mesaExtraCantidad == 0).toList()
        ..shuffle(r);
      for (final x in conUna.take(r.nextInt(3))) {
        final n = numeros.firstWhere(
          (n) => !libres.containsKey(n) && !fijadas.containsKey(n),
        );
        fijadas[n] = MesaFijada(alumnoId: x.id, motivo: 'Silla de ruedas');
      }
      // Lo que deja afuera el pago, y las separaciones pedidas.
      final sinMesa = <String>{};
      final soloBase = <String>{};
      final separaciones = <String, int>{};
      for (final x in alumnos) {
        if (fijadas.values.any((f) => f.alumnoId == x.id)) continue;
        final dado = r.nextInt(40);
        if (dado == 0) {
          sinMesa.add(x.id);
        } else if (dado == 1 && x.mesaExtraCantidad > 0) {
          soloBase.add(x.id);
        } else if (dado == 2 && x.mesaExtraCantidad > 0) {
          separaciones[x.id] = 1;
        }
      }
      return EntradaSorteoPlano(
        armado: a,
        config: ConfigPlano(libres: libres, fijadas: fijadas),
        alumnos: alumnos,
        exclusion: ExclusionSorteo(sinMesa: sinMesa, soloBase: soloBase),
        separaciones: separaciones,
        modo: modo,
        ordenDivisiones:
            Divisiones.ordenNatural(alumnos.map((x) => Divisiones.clave(x.cursoDivision)))
              ..shuffle(r),
        usarPasto: r.nextInt(3) == 0,
      );
    }

    /// La misma escuela un mes después: los sorteados ya tienen su mesa, unos
    /// se dieron de baja, otros compraron una mesa y llegaron familias nuevas.
    EntradaSorteoPlano unMesDespues(
      EntradaSorteoPlano e,
      ResultadoSorteoPlano r,
      Random rng,
    ) {
      var k = 0;
      final alumnos = <ContratoAlumno>[
        for (final x in e.alumnos)
          () {
            final nums = r.asignaciones[x.id];
            if (nums == null) return x;
            final dado = rng.nextInt(20);
            final sentado = x.copyWith(numeroMesa: nums.join(', '));
            if (dado == 0) {
              return sentado.copyWith(nombreAlumno: '[BAJA] ${x.id}');
            }
            if (dado == 1) {
              // Compró una mesa más: el sorteo se la tiene que completar.
              return sentado.copyWith(
                mesaExtraCantidad: x.mesaExtraCantidad + 1,
                mesaExtraPrecio: 70000.0 * (x.mesaExtraCantidad + 1),
              );
            }
            return sentado;
          }(),
        for (var j = 0; j < 1 + rng.nextInt(4); j++)
          alumno(
            'tarde${k++}',
            extras: rng.nextInt(4) == 0 ? 1 : 0,
            division: e.alumnos[rng.nextInt(e.alumnos.length)].cursoDivision ?? '',
          ),
      ];
      return EntradaSorteoPlano(
        armado: e.armado,
        config: e.config.copyWith(bloques: r.bloques),
        alumnos: alumnos,
        // Lo que quedó afuera por el pago sigue afuera; los nuevos entran.
        exclusion: e.exclusion,
        modo: e.modo,
        ordenDivisiones: e.ordenDivisiones,
        usarPasto: e.usarPasto,
      );
    }

    for (final armado in armados.entries) {
      for (final modo in ModoSorteo.values) {
        test('${armado.key}, ${modo.name}: las reglas del salón se cumplen',
            () {
          var sorteados = 0;
          var segundaVuelta = 0;
          var noEntraron = 0;
          for (var semilla = 0; semilla < 60; semilla++) {
            final rng = Random(7000 + semilla);
            final e = escuela(armado.value, rng, modo);
            final razon = '${armado.key} ${modo.name} #$semilla';
            final r = sortearYComprobar(e, semilla, razon: razon);
            if (r == null) {
              noEntraron++;
              continue;
            }
            sorteados++;
            final e2 = unMesDespues(e, r, rng);
            final r2 = sortearYComprobar(e2, semilla + 1, razon: '$razon (tarde)');
            if (r2 != null) segundaVuelta++;
          }
          // Que el test pruebe de verdad las dos cosas: sorteos que entran (la
          // mayoría) y la segunda vuelta con los que llegan tarde.
          expect(sorteados, greaterThan(20), reason: 'entraron $sorteados de 60');
          expect(segundaVuelta, greaterThan(5),
              reason: 'segunda vuelta: $segundaVuelta');
          expect(noEntraron, lessThan(40), reason: 'no entraron: $noEntraron');
        });
      }
    }
  });
}
