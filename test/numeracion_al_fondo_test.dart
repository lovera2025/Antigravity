// La numeración que termina al fondo (6.5.1, pedido del jefe el 10-nov-2026): las
// dos mitades del salón se numeran desde el escenario, y el último número queda al
// fondo, a la derecha, donde siguen las mesas que se agregan después del sorteo.
// Cuenta pura: sin base ni pantalla.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_puerto_viejo.dart';

/// El playón de la escuela del 10-nov: 30 m de frente, 46 de fondo y 39,8 de
/// profundidad, con 101 mesas.
const _playonDelJefe = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8);

const _playones = [
  _playonDelJefe,
  PlayonReal(frenteM: 25, fondoM: 25, profundidadM: 30),
  PlayonReal(frenteM: 40, fondoM: 28, profundidadM: 35),
  PlayonReal(frenteM: 18, fondoM: 60, profundidadM: 50),
];

ArmadoSalon _armar(PlayonReal p, int cantidad, FinNumeracion fin) =>
    ArmarAMedida.armar(
      OpcionesAMedida(playon: p, cantidad: cantidad, fin: fin),
    ).armado;

/// Solo los lugares, sin los números.
Set<String> _lugares(ArmadoSalon a) => {
      for (final m in a.mesas) '${m.hoja} ${m.x} ${m.y} ${m.pasto}',
    };

List<String> _mesaPorMesa(ArmadoSalon a) => [
      for (final m in a.mesas) '${m.numero} ${m.hoja} ${m.x} ${m.y}',
    ];

double _medio(ArmadoSalon a) => a.sectores
    .firstWhere((s) => s.tipo == TipoSector.escenario)
    .caja
    .centroX;

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

void main() {
  group('sin pedir nada, todo sigue como siempre', () {
    test('armar, acomodar y ordenar dan la serpentina de siempre', () {
      for (final p in _playones) {
        final siempre =
            ArmarAMedida.armar(OpcionesAMedida(playon: p, cantidad: 80)).armado;
        expect(
          _mesaPorMesa(_armar(p, 80, FinNumeracion.escenario)),
          _mesaPorMesa(siempre),
        );
        expect(
          ArmarAMedida.ordenarNumeros(siempre).cambio,
          isEmpty,
          reason: 'un salón recién armado ya está en orden',
        );
      }
    });

    test('Puerto Viejo se ordena igual que antes: un solo salto, en la 17', () {
      final r = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;
      expect(r.cortes, {17});
    });
  });

  group('terminando al fondo', () {
    test('el playón del jefe con 101 mesas: la 101 queda al fondo, a la derecha',
        () {
      final u = _armar(_playonDelJefe, 101, FinNumeracion.escenario);
      final f = _armar(_playonDelJefe, 101, FinNumeracion.fondo);
      expect(f.numeros, [for (var n = 1; n <= 101; n++) n]);
      expect(_lugares(f), _lugares(u), reason: 'ninguna mesa cambia de lugar');

      final cx = _medio(f);
      final ultima = f.mesa(101)!;
      final masAlFondo =
          f.mesas.map((m) => m.y).reduce((a, b) => a > b ? a : b);
      expect(ultima.x > cx, isTrue, reason: 'la 101 va a la derecha');
      expect(ultima.y, masAlFondo, reason: 'la 101 va en la última fila');

      // En la serpentina de siempre, la 101 queda en la primera fila.
      final alFrente = u.mesas.map((m) => m.y).reduce((a, b) => a < b ? a : b);
      expect(u.mesa(101)!.y, alFrente);
      expect(u.mesa(101)!.x > _medio(u), isTrue);
    });

    test('primero toda la izquierda, después toda la derecha, y las dos desde '
        'el escenario', () {
      for (final p in _playones) {
        final f = _armar(p, 90, FinNumeracion.fondo);
        final cx = _medio(f);
        final izq = [for (final m in f.mesas) if (m.x < cx) m];
        final der = [for (final m in f.mesas) if (m.x >= cx) m];
        expect(izq, isNotEmpty);
        expect(der, isNotEmpty);
        final ultimoDeLaIzquierda =
            izq.map((m) => m.numero).reduce((a, b) => a > b ? a : b);
        expect(
          der.every((m) => m.numero > ultimoDeLaIzquierda),
          isTrue,
          reason: 'la derecha sigue a la izquierda ($p)',
        );
        for (final lado in [izq, der]) {
          for (final a in lado) {
            for (final b in lado) {
              if (a.y < b.y - 0.01) {
                expect(
                  a.numero < b.numero,
                  isTrue,
                  reason: 'la fila de adelante se numera antes: '
                      '${a.numero} y ${b.numero}',
                );
              }
            }
          }
        }
        expect(f.mesa(1)!.x < cx, isTrue);
        expect(f.mesas.last.x >= cx, isTrue);
      }
    });

    test('los números seguidos de cada fila son mesas vecinas', () {
      final f = _armar(_playonDelJefe, 101, FinNumeracion.fondo);
      final cx = _medio(f);
      for (var n = 1; n < 101; n++) {
        final a = f.mesa(n)!, b = f.mesa(n + 1)!;
        final mismoLado = (a.x < cx) == (b.x < cx);
        if (!mismoLado) {
          expect(f.cortes, contains(n), reason: 'el paso de un lado al otro');
        }
      }
      // El paso de un lado al otro es el único salto obligado; alguno más puede
      // quedar donde el playón se ensancha, como en la serpentina de siempre.
      final u = _armar(_playonDelJefe, 101, FinNumeracion.escenario);
      expect(f.cortes.length, lessThanOrEqualTo(u.cortes.length + 2));
    });

    test('armar, acomodar y ordenar dan lo mismo, mesa por mesa', () {
      for (final p in _playones) {
        final u = _armar(p, 80, FinNumeracion.escenario);
        final f = _armar(p, 80, FinNumeracion.fondo);

        // Ordenar los números de la serpentina de siempre da el armado al fondo.
        final ordenado =
            ArmarAMedida.ordenarNumeros(u, fin: FinNumeracion.fondo).armado;
        expect(_mesaPorMesa(ordenado), _mesaPorMesa(f), reason: '$p');
        expect(ordenado.ultimoNumero, 80);

        // Y de vuelta.
        final deVuelta =
            ArmarAMedida.ordenarNumeros(f, fin: FinNumeracion.escenario).armado;
        expect(_mesaPorMesa(deVuelta), _mesaPorMesa(u), reason: '$p');

        // Un salón ya numerado al fondo no cambia.
        expect(
          ArmarAMedida.ordenarNumeros(f, fin: FinNumeracion.fondo).cambio,
          isEmpty,
        );

        // ACOMODAR LAS MESAS sobre el mismo playón: la misma cuenta.
        final lugar = ArmarAMedida.lugarDe(u)!;
        final acomodadoU = ArmarAMedida.acomodar(u, cantidad: 80, lugarM: lugar)
            .armado;
        if (_mesaPorMesa(acomodadoU).join('|') == _mesaPorMesa(u).join('|')) {
          final acomodadoF = ArmarAMedida.acomodar(
            u,
            cantidad: 80,
            lugarM: lugar,
            fin: FinNumeracion.fondo,
          ).armado;
          expect(_mesaPorMesa(acomodadoF), _mesaPorMesa(f), reason: '$p');
        }
      }
    });

    test('Puerto Viejo: del 1 al 35, la izquierda primero y la 35 al fondo', () {
      final a = armadoDePuertoViejo();
      final r =
          ArmarAMedida.ordenarNumeros(a, fin: FinNumeracion.fondo).armado;
      expect(r.numeros, [for (var n = 1; n <= 35; n++) n]);
      expect(_lugares(r), _lugares(a));
      final cx = _medio(a);
      for (final m in r.mesas) {
        expect(m.x < cx, m.numero <= 17, reason: 'la mesa ${m.numero}');
      }
      final masAlFondo = [for (final m in r.mesas) if (m.x >= cx) m.y]
          .reduce((x, y) => x > y ? x : y);
      // Las mesas de una fila corrida a mano no están a la misma altura exacta.
      expect(r.mesa(35)!.y, closeTo(masAlFondo, 0.01));
    });

    test('las del pasto siguen al final', () {
      final a = _armar(_playonDelJefe, 40, FinNumeracion.escenario);
      final conPasto = a.copyWith(mesas: [
        for (final m in a.mesas)
          m.numero <= 3 ? m.copyWith(pasto: true) : m,
      ]);
      final r = ArmarAMedida.ordenarNumeros(
        conPasto,
        fin: FinNumeracion.fondo,
      ).armado;
      expect(r.pasto, {38, 39, 40});
    });
  });

  group('se guarda en la config del plano', () {
    test('la serpentina de siempre no escribe la clave; al fondo, sí', () {
      expect(
        jsonDecode(ConfigPlano.vacia.toJson()) as Map,
        isNot(contains('numeracion')),
      );
      final c = const ConfigPlano(numeracion: FinNumeracion.fondo);
      expect((jsonDecode(c.toJson()) as Map)['numeracion'], 'fondo');
      expect(ConfigPlano.fromJson(c.toJson()).numeracion, FinNumeracion.fondo);
      expect(
        c.copyWith(titulo: 'Fiesta').numeracion,
        FinNumeracion.fondo,
        reason: 'cambiar otra cosa no la pierde',
      );
    });

    test('una clave que no se entiende es la serpentina de siempre', () {
      for (final v in ['"otra"', '7', 'null', '{"a":1}']) {
        expect(
          ConfigPlano.fromJson('{"numeracion":$v}').numeracion,
          FinNumeracion.escenario,
        );
      }
    });

    test('la clave no queda duplicada entre las que no se conocen', () {
      final c = ConfigPlano.fromJson('{"numeracion":"fondo","nueva":1}');
      expect(c.otras.keys, ['nueva']);
      final m = jsonDecode(c.toJson()) as Map;
      expect(m['numeracion'], 'fondo');
      expect(m['nueva'], 1);
    });
  });

  group('al guardar el salón', () {
    final puertoViejo = armadoDePuertoViejo();

    CambioDeConfig guardar(
      ArmadoSalon base, {
      ConfigPlano config = ConfigPlano.vacia,
      List<ContratoAlumno> alumnos = const [],
      FinNumeracion? fin,
      bool leidoDeLaNube = true,
    }) =>
        EditarArmado.paraGuardar(
          base: base,
          nuevo: base,
          fresco: base,
          config: config,
          alumnos: alumnos,
          enUsoVisto: EditarArmado.enUso(alumnos, config),
          leidoDeLaNube: leidoDeLaNube,
          fin: fin,
        );

    test('eligiendo al fondo, los números quedan así y la config lo recuerda',
        () {
      final r = guardar(puertoViejo, fin: FinNumeracion.fondo);
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.config!.numeracion, FinNumeracion.fondo);
      expect(
        _mesaPorMesa(r.armado!),
        _mesaPorMesa(
          ArmarAMedida.ordenarNumeros(puertoViejo, fin: FinNumeracion.fondo)
              .armado,
        ),
      );
      expect(
        EditarArmado.firma(r.armado!),
        EditarArmado.firma(
          EditarArmado.comoSeGuarda(
            puertoViejo,
            puertoViejo,
            ordenar: true,
            fin: FinNumeracion.fondo,
          ),
        ),
        reason: 'lo que la pantalla compara después es lo guardado',
      );
    });

    test('guardar de nuevo sin elegir nada respeta lo guardado', () {
      final una = guardar(puertoViejo, fin: FinNumeracion.fondo);
      final otra = guardar(una.armado!, config: una.config!);
      expect(otra.config!.numeracion, FinNumeracion.fondo);
      expect(EditarArmado.firma(otra.armado!), EditarArmado.firma(una.armado!));
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
        fin: FinNumeracion.fondo,
      );
      expect(r.sePuede, isTrue, reason: r.problema);
      final antes = puertoViejo.mesa(fijada)!;
      final ahora = r.armado!.mesas.firstWhere(
        (m) => m.hoja == antes.hoja && m.x == antes.x && m.y == antes.y,
      );
      expect(r.config!.fijadas.keys, [ahora.numero]);
      expect(r.config!.fijadas[ahora.numero]!.alumnoId, 'sosa');
    });

    test('con familias con mesa no cambia ningún número', () {
      final r = guardar(
        puertoViejo,
        alumnos: [_alumno('sosa', mesas: [3])],
        fin: FinNumeracion.fondo,
      );
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(_mesaPorMesa(r.armado!), _mesaPorMesa(puertoViejo));
    });

    test('sin internet no se ordena, pero queda elegido para la próxima', () {
      final r = guardar(
        puertoViejo,
        fin: FinNumeracion.fondo,
        leidoDeLaNube: false,
      );
      expect(_mesaPorMesa(r.armado!), _mesaPorMesa(puertoViejo));
      expect(r.config!.numeracion, FinNumeracion.fondo);
      final despues = guardar(r.armado!, config: r.config!);
      expect(
        _mesaPorMesa(despues.armado!),
        _mesaPorMesa(
          ArmarAMedida.ordenarNumeros(puertoViejo, fin: FinNumeracion.fondo)
              .armado,
        ),
      );
    });
  });

  group('en Acomodar', () {
    final guardado = ArmarAMedida.ordenarNumeros(armadoDePuertoViejo()).armado;

    test('elegir al fondo deja guardar aunque no se haya movido nada', () {
      final s = SesionAcomodo(base: guardado);
      expect(s.puedeGuardar, isFalse);
      expect(s.motivoSinFin, isNull);
      s.elegirFin(FinNumeracion.fondo);
      expect(s.fin, FinNumeracion.fondo);
      expect(s.cambioElFin, isTrue);
      expect(s.faltaOrdenar, isTrue);
      expect(s.puedeGuardar, isTrue);
      expect(
        s.avisos((_) => 0).join(' '),
        contains('con el último al fondo'),
      );
      // Volver a lo guardado es no haber cambiado nada.
      s.elegirFin(FinNumeracion.escenario);
      expect(s.puedeGuardar, isFalse);
    });

    test('descartar vuelve a lo guardado', () {
      final s = SesionAcomodo(base: guardado)..elegirFin(FinNumeracion.fondo);
      s.descartar();
      expect(s.fin, FinNumeracion.escenario);
      expect(s.puedeGuardar, isFalse);
    });

    test('un salón guardado al fondo abre así y no pide ordenar', () {
      final alFondo =
          ArmarAMedida.ordenarNumeros(guardado, fin: FinNumeracion.fondo).armado;
      final s = SesionAcomodo(base: alFondo, fin: FinNumeracion.fondo);
      expect(s.faltaOrdenar, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('con familias con mesa no se puede elegir, y se dice por qué', () {
      final s = SesionAcomodo(base: guardado, haySorteo: true);
      expect(s.motivoSinFin, contains('familias con mesa'));
      s.elegirFin(FinNumeracion.fondo);
      expect(s.fin, FinNumeracion.escenario);
      expect(s.puedeGuardar, isFalse);
    });

    test('un armado del Canva trae su numeración', () {
      final s = SesionAcomodo(base: ArmadosPredefinidos.todos.first);
      expect(s.motivoSinFin, contains('Canva'));
      s.elegirFin(FinNumeracion.fondo);
      expect(s.fin, FinNumeracion.escenario);
    });

    test('ACOMODAR LAS MESAS numera como se eligió', () {
      final vacio = ArmarAMedida.vacio(_playonDelJefe);
      final s = SesionAcomodo(base: vacio)..elegirFin(FinNumeracion.fondo);
      s.acomodar(60);
      expect(
        _mesaPorMesa(s.actual),
        _mesaPorMesa(
          ArmarAMedida.acomodar(vacio, cantidad: 60, fin: FinNumeracion.fondo)
              .armado,
        ),
      );
      expect(s.faltaOrdenar, isFalse);
      final cx = _medio(s.actual);
      expect(s.actual.mesa(60)!.x > cx, isTrue);
    });
  });

  test('un salón numerado al fondo no avisa que los números no siguen el salón',
      () {
    final alFondo = ArmarAMedida.ordenarNumeros(
      armadoDePuertoViejo(),
      fin: FinNumeracion.fondo,
    ).armado;
    final plano = PlanoDeLaFiesta.desde(
      armado: alFondo,
      config: const ConfigPlano(numeracion: FinNumeracion.fondo),
      alumnos: const [],
    );
    expect(
      plano.avisos.where((a) => a.texto.contains('no siguen el salón')),
      isEmpty,
    );
  });
}
