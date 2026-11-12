// La numeración fila por fila (6.6.1, pedido del jefe el 11-nov-2026): con las
// otras dos la pasarela corta la numeración en dos mitades; él quiere los números
// de corrido por el salón entero, cada fila de una punta a la otra, para que las
// mesas principales queden en las filas de adelante y las adicionales al fondo.
// Cuenta pura: sin base ni pantalla.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/plano/services/numeracion_recordada.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_puerto_viejo.dart';

/// El playón de Costa Surubí, el de las escuelas de noviembre.
const _playonDelJefe = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39);

const _playones = [
  _playonDelJefe,
  PlayonReal(frenteM: 25, fondoM: 25, profundidadM: 30),
  PlayonReal(frenteM: 40, fondoM: 28, profundidadM: 35),
  PlayonReal(frenteM: 18, fondoM: 60, profundidadM: 50),
];

const _filas = FinNumeracion.filas;

ArmadoSalon _armar(PlayonReal p, int cantidad, FinNumeracion fin) =>
    ArmarAMedida.armar(
      OpcionesAMedida(playon: p, cantidad: cantidad, fin: fin),
    ).armado;

Set<String> _lugares(ArmadoSalon a) => {
      for (final m in a.mesas) '${m.hoja} ${m.x} ${m.y} ${m.pasto}',
    };

List<String> _mesaPorMesa(ArmadoSalon a) => [
      for (final m in a.mesas) '${m.numero} ${m.hoja} ${m.x} ${m.y}',
    ];

/// Las mesas de una hoja, fila por fila desde el escenario (de menor a mayor
/// `y`), cada fila de izquierda a derecha.
List<List<MesaPlano>> _filasDe(ArmadoSalon a, String hoja) {
  final mesas = a.mesasDeHoja(hoja)..sort((x, y) => x.y.compareTo(y.y));
  final filas = <List<MesaPlano>>[];
  for (final m in mesas) {
    if (filas.isNotEmpty && (m.y - filas.last.first.y).abs() < a.radio) {
      filas.last.add(m);
    } else {
      filas.add([m]);
    }
  }
  for (final f in filas) {
    f.sort((x, y) => x.x.compareTo(y.x));
  }
  return filas;
}

/// Lo que define "fila por fila": cada fila es un tramo de números seguidos,
/// de una punta a la otra; la fila de adelante se numera entera antes que la
/// de atrás; y dos filas seguidas van en sentidos opuestos.
void _esperarFilaPorFila(ArmadoSalon a, {String? motivo}) {
  for (final h in a.hojas) {
    final filas = _filasDe(a, h.id);
    bool? anteriorCreciente;
    int? ultimoDeLaAnterior;
    for (final fila in filas) {
      final nums = [for (final m in fila) m.numero];
      final ordenados = [...nums]..sort();
      expect(
        ordenados.last - ordenados.first,
        nums.length - 1,
        reason: 'la fila es un tramo seguido: $nums ${motivo ?? ''}',
      );
      final creciente = nums.first < nums.last;
      expect(
        nums,
        creciente ? ordenados : ordenados.reversed.toList(),
        reason: 'la fila va de una punta a la otra: $nums ${motivo ?? ''}',
      );
      if (ultimoDeLaAnterior != null) {
        expect(
          ordenados.first,
          ultimoDeLaAnterior + 1,
          reason: 'la fila de atrás sigue a la de adelante ${motivo ?? ''}',
        );
      }
      if (anteriorCreciente != null && nums.length > 1) {
        expect(
          creciente,
          !anteriorCreciente,
          reason: 'cada fila vuelve para el otro lado ${motivo ?? ''}',
        );
      }
      if (nums.length > 1) anteriorCreciente = creciente;
      ultimoDeLaAnterior = ordenados.last;
    }
  }
}

ContratoAlumno _alumno(
  String id, {
  List<int> mesas = const [],
  int extras = 0,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

void main() {
  group('fila por fila', () {
    test('el playón del jefe con 80 mesas: cada fila cruza la pasarela', () {
      final u = _armar(_playonDelJefe, 80, FinNumeracion.escenario);
      final f = _armar(_playonDelJefe, 80, _filas);
      expect(f.numeros, [for (var n = 1; n <= 80; n++) n]);
      expect(_lugares(f), _lugares(u), reason: 'ninguna mesa cambia de lugar');
      _esperarFilaPorFila(f);

      // La primera fila tiene mesas a los dos lados del escenario con números
      // seguidos: con las otras numeraciones, la derecha arranca mucho después.
      final cx = f.sectores
          .firstWhere((s) => s.tipo == TipoSector.escenario)
          .caja
          .centroX;
      final primera = _filasDe(f, f.hojas.first.id).first;
      expect(primera.any((m) => m.x < cx), isTrue);
      expect(primera.any((m) => m.x > cx), isTrue);
      expect(
        [for (final m in primera) m.numero]..sort(),
        [for (var n = 1; n <= primera.length; n++) n],
        reason: 'la primera fila son los primeros números',
      );
      expect(f.mesa(1)!.x < cx, isTrue, reason: 'el 1, a la izquierda');

      // El último número queda en la última fila, al fondo.
      final masAlFondo = f.mesas.map((m) => m.y).reduce(max);
      expect(f.mesa(80)!.y, masAlFondo);
    });

    test('en cualquier playón y con cualquier cantidad', () {
      for (final p in _playones) {
        for (final n in [12, 45, 80, 101]) {
          _esperarFilaPorFila(_armar(p, n, _filas), motivo: '($p, $n mesas)');
        }
      }
    });

    test('armar, acomodar y ordenar dan lo mismo, mesa por mesa', () {
      for (final p in _playones) {
        final u = _armar(p, 80, FinNumeracion.escenario);
        final f = _armar(p, 80, _filas);

        final ordenado = ArmarAMedida.ordenarNumeros(u, fin: _filas).armado;
        expect(_mesaPorMesa(ordenado), _mesaPorMesa(f), reason: '$p');
        expect(ordenado.ultimoNumero, 80);

        // Y de vuelta a la serpentina de siempre.
        final deVuelta =
            ArmarAMedida.ordenarNumeros(f, fin: FinNumeracion.escenario).armado;
        expect(_mesaPorMesa(deVuelta), _mesaPorMesa(u), reason: '$p');

        // Un salón ya numerado fila por fila no cambia.
        expect(ArmarAMedida.ordenarNumeros(f, fin: _filas).cambio, isEmpty);

        // ACOMODAR LAS MESAS sobre el mismo playón: la misma cuenta.
        final lugar = ArmarAMedida.lugarDe(u)!;
        final acomodadoU =
            ArmarAMedida.acomodar(u, cantidad: 80, lugarM: lugar).armado;
        if (_mesaPorMesa(acomodadoU).join('|') == _mesaPorMesa(u).join('|')) {
          final acomodadoF = ArmarAMedida.acomodar(
            u,
            cantidad: 80,
            lugarM: lugar,
            fin: _filas,
          ).armado;
          expect(_mesaPorMesa(acomodadoF), _mesaPorMesa(f), reason: '$p');
        }
      }
    });

    test('Puerto Viejo: del 1 al 35, sin mover ninguna mesa', () {
      final a = armadoDePuertoViejo();
      final r = ArmarAMedida.ordenarNumeros(a, fin: _filas).armado;
      expect(r.numeros, [for (var n = 1; n <= 35; n++) n]);
      expect(_lugares(r), _lugares(a));
    });

    test('las del pasto siguen al final', () {
      final a = _armar(_playonDelJefe, 40, FinNumeracion.escenario);
      final conPasto = a.copyWith(mesas: [
        for (final m in a.mesas) m.numero <= 3 ? m.copyWith(pasto: true) : m,
      ]);
      final r = ArmarAMedida.ordenarNumeros(conPasto, fin: _filas).armado;
      expect(r.pasto, {38, 39, 40});
    });

    test('el cruce de la pasarela es un corte: una familia con dos mesas nunca '
        'queda a los dos lados', () {
      final f = _armar(_playonDelJefe, 80, _filas);
      final alumnos = [
        for (var i = 0; i < 30; i++) _alumno('f$i', extras: 1),
      ];
      for (var semilla = 0; semilla < 20; semilla++) {
        final entrada = EntradaSorteoPlano(armado: f, alumnos: alumnos);
        final r = SorteoConPlano.sortear(entrada, random: Random(semilla));
        expect(SorteoConPlano.validar(entrada, r), isNull);
        for (final nums in r.asignaciones.values) {
          expect(nums, hasLength(2));
          expect(f.pegadas(nums[0], nums[1]), isTrue, reason: '$nums');
        }
      }
    });
  });

  group('se guarda en la config del plano', () {
    test('escribe su clave y vuelve igual', () {
      const c = ConfigPlano(numeracion: _filas);
      expect((jsonDecode(c.toJson()) as Map)['numeracion'], 'filas');
      expect(ConfigPlano.fromJson(c.toJson()).numeracion, _filas);
      expect(c.eligioNumeracion, isTrue);
      expect(c.copyWith(titulo: 'Fiesta').numeracion, _filas);
    });

    test('con el momento de la elección, vuelve con los dos', () {
      final el = DateTime.utc(2026, 11, 11, 23);
      final c = ConfigPlano(numeracion: _filas, numeracionEl: el);
      final vuelta = ConfigPlano.fromJson(c.toJson());
      expect(vuelta.numeracion, _filas);
      expect(vuelta.numeracionEl, el);
    });

    test('queda recordada para las fiestas que vienen', () {
      final r = NumeracionRecordada.de([
        ConfigPlano(
          numeracion: FinNumeracion.fondo,
          numeracionEl: DateTime.utc(2026, 11, 11, 20),
        ),
        ConfigPlano(
          numeracion: _filas,
          numeracionEl: DateTime.utc(2026, 11, 12, 13),
        ),
        ConfigPlano.vacia,
      ]);
      expect(r?.fin, _filas);
    });
  });

  group('al guardar el salón', () {
    final puertoViejo = armadoDePuertoViejo();

    CambioDeConfig guardar(
      ArmadoSalon base, {
      ConfigPlano config = ConfigPlano.vacia,
      List<ContratoAlumno> alumnos = const [],
      FinNumeracion? fin,
    }) =>
        EditarArmado.paraGuardar(
          base: base,
          nuevo: base,
          fresco: base,
          config: config,
          alumnos: alumnos,
          enUsoVisto: EditarArmado.enUso(alumnos, config),
          leidoDeLaNube: true,
          fin: fin,
        );

    test('eligiendo fila por fila, los números quedan así y la config lo '
        'recuerda', () {
      final r = guardar(puertoViejo, fin: _filas);
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.config!.numeracion, _filas);
      expect(
        _mesaPorMesa(r.armado!),
        _mesaPorMesa(ArmarAMedida.ordenarNumeros(puertoViejo, fin: _filas).armado),
      );
      // Guardar de nuevo sin elegir nada respeta lo guardado.
      final otra = guardar(r.armado!, config: r.config!);
      expect(otra.config!.numeracion, _filas);
      expect(EditarArmado.firma(otra.armado!), EditarArmado.firma(r.armado!));
    });

    test('una mesa fijada sigue a su mesa, no a su número', () {
      const fijada = 20;
      final config = ConfigPlano(
        fijadas: {fijada: const MesaFijada(alumnoId: 'sosa')},
      );
      final r = guardar(
        puertoViejo,
        config: config,
        alumnos: [_alumno('sosa')],
        fin: _filas,
      );
      expect(r.sePuede, isTrue, reason: r.problema);
      final antes = puertoViejo.mesa(fijada)!;
      final ahora = r.armado!.mesas.firstWhere(
        (m) => m.hoja == antes.hoja && m.x == antes.x && m.y == antes.y,
      );
      expect(r.config!.fijadas.keys, [ahora.numero]);
    });

    test('con familias con mesa no cambia ningún número', () {
      final r = guardar(
        puertoViejo,
        alumnos: [
          _alumno('sosa', mesas: [3]),
        ],
        fin: _filas,
      );
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(_mesaPorMesa(r.armado!), _mesaPorMesa(puertoViejo));
    });
  });

  group('en Acomodar', () {
    final guardado = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;

    test('elegir fila por fila deja guardar aunque no se haya movido nada', () {
      final s = SesionAcomodo(base: guardado);
      expect(s.puedeGuardar, isFalse);
      s.elegirFin(_filas);
      expect(s.fin, _filas);
      expect(s.faltaOrdenar, isTrue);
      expect(s.puedeGuardar, isTrue);
      expect(s.avisos((_) => 0).join(' '), contains('fila por fila'));
    });

    test('un salón guardado fila por fila abre así y no pide ordenar', () {
      final porFilas = ArmarAMedida.ordenarNumeros(guardado, fin: _filas).armado;
      final s = SesionAcomodo(base: porFilas, fin: _filas);
      expect(s.faltaOrdenar, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('con familias con mesa o en un armado del Canva no se puede elegir',
        () {
      final conSorteo = SesionAcomodo(base: guardado, haySorteo: true)
        ..elegirFin(_filas);
      expect(conSorteo.fin, FinNumeracion.escenario);
      final canva = SesionAcomodo(base: ArmadosPredefinidos.todos.first)
        ..elegirFin(_filas);
      expect(canva.fin, FinNumeracion.escenario);
    });

    test('ACOMODAR LAS MESAS numera como se eligió', () {
      final vacio = ArmarAMedida.vacio(_playonDelJefe);
      final s = SesionAcomodo(base: vacio)..elegirFin(_filas);
      s.acomodar(80);
      expect(
        _mesaPorMesa(s.actual),
        _mesaPorMesa(
          ArmarAMedida.acomodar(vacio, cantidad: 80, fin: _filas).armado,
        ),
      );
      expect(s.faltaOrdenar, isFalse);
      _esperarFilaPorFila(s.actual);
    });
  });

  test('un salón numerado fila por fila no avisa que los números no siguen el '
      'salón', () {
    final porFilas =
        ArmarAMedida.ordenarNumeros(armadoDePuertoViejo(), fin: _filas).armado;
    final plano = PlanoDeLaFiesta.desde(
      armado: porFilas,
      config: const ConfigPlano(numeracion: _filas),
      alumnos: const [],
    );
    expect(
      plano.avisos.where((a) => a.texto.contains('no siguen el salón')),
      isEmpty,
    );
  });

  test('la mesa que llega después del sorteo recibe el número que sigue', () {
    final salon = _armar(_playonDelJefe, 80, _filas);
    final alumnos = [
      for (var n = 1; n <= 80; n++)
        if (n != 9) _alumno('f$n', mesas: [n]),
      _alumno('tarde', extras: 1, mesas: [9]),
    ];
    final plan = MesasNuevasAlFondo.planear(
      armado: salon,
      config: const ConfigPlano(numeracion: _filas),
      alumnos: alumnos,
      pedidos: SorteoMesasMotor.pedidos(alumnos),
      llegada: const {},
      por: 'Jefe',
      ahora: DateTime.utc(2026, 11, 12, 12),
    );
    expect(plan.porAlumno, {
      'tarde': [81],
    });
    expect(
      {
        for (final m in plan.armado.mesas)
          if (m.numero <= 80) '${m.numero} ${m.hoja} ${m.x} ${m.y}',
      },
      _mesaPorMesa(salon).toSet(),
      reason: 'ninguna otra mesa se mueve ni cambia de número',
    );
  });
}
