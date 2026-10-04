// Personalizar → Colores y textos, la cuenta: el color de cada división, el
// título y los textos de los sectores, sin tocar nada más del plano.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/colores_y_textos.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _alumno(String id, List<int> mesas, String division) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa: MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

void main() {
  final armado = ArmadosPredefinidos.normal2aPagina3();
  final alumnos = [
    _alumno('a', [1], '5° A'),
    _alumno('b', [10], '5° B'),
    _alumno('c', [20], '6° A'),
  ];

  PlanoDeLaFiesta plano(ConfigPlano config) => PlanoDeLaFiesta.desde(
        armado: armado,
        config: config,
        alumnos: alumnos,
      );

  group('los colores de las divisiones', () {
    test('sin elegir nada, cada división lleva el color de su lugar', () {
      final p = plano(ConfigPlano.vacia);
      expect(p.estado.divisiones, ['5A', '5B', '6A']);
      expect(p.colores, [0, 1, 2]);
      for (final e in EstiloPlano.values) {
        // Es el mismo tema de fábrica: no se arma otro.
        expect(identical(p.tema(e), TemaPlano.de(e)), isTrue, reason: e.name);
      }
    });

    test('la que eligió color lleva ese; las demás, el de su lugar', () {
      final p = plano(const ConfigPlano(colores: {'5B': 6}));
      expect(p.colores, [0, 6, 2]);
      for (final e in EstiloPlano.values) {
        final base = TemaPlano.de(e);
        final tema = p.tema(e);
        expect(tema.colorDivision(0), base.divisiones[0], reason: e.name);
        expect(tema.colorDivision(1), base.divisiones[6], reason: e.name);
        expect(tema.colorDivision(2), base.divisiones[2], reason: e.name);
        // Lo que no es de las divisiones queda igual.
        expect(tema.fondo, base.fondo);
        expect(tema.conflicto, base.conflicto);
        expect(tema.fuente, base.fuente);
        expect(tema.sillas, base.sillas);
        expect(tema.escalaMesa, base.escalaMesa);
      }
    });

    test('en Arquitecto, el número de la mesa sigue al color de su división',
        () {
      final tema = plano(const ConfigPlano(colores: {'5A': 3})).tema(
        EstiloPlano.arquitecto,
      );
      expect(tema.colorDivision(0), TemaPlano.arquitecto.divisiones[3]);
      expect(
        tema.numeroDeDivision(0),
        TemaPlano.arquitecto.numeroDivision![3],
      );
    });

    test('un color de una división que la fiesta no tiene no molesta', () {
      expect(plano(const ConfigPlano(colores: {'9Z': 4})).colores, [0, 1, 2]);
    });

    test('un índice fuera de la paleta da la vuelta, no rompe', () {
      final tema = TemaPlano.gala.conColores(const [8, 17, -1]);
      expect(tema.colorDivision(0), TemaPlano.gala.divisiones[0]);
      expect(tema.colorDivision(1), TemaPlano.gala.divisiones[1]);
      expect(tema.colorDivision(2), TemaPlano.gala.divisiones[7]);
      // Sin división, el borde neutro de siempre.
      expect(tema.colorDivision(null), TemaPlano.gala.mesaBorde);
    });

    test('con más divisiones que colores, cada una conserva el suyo', () {
      final indices = [for (var i = 0; i < 11; i++) i == 9 ? 0 : i];
      final tema = TemaPlano.neon.conColores(indices);
      expect(tema.divisiones.length, 11);
      expect(tema.colorDivision(9), TemaPlano.neon.divisiones[0]);
      expect(tema.colorDivision(10), TemaPlano.neon.divisiones[2]);
    });
  });

  group('lo que se guarda', () {
    const config = ConfigPlano(
      libres: {7: MesaLibre(motivo: 'columna')},
      ordenDivisiones: ['5B', '5A'],
      colores: {'5A': 2},
      titulo: 'Egresados',
      medidas: MedidasPlano(lugarMesaM: 2.3),
    );

    test('lo guardado, leído, es igual a sí mismo', () {
      final guardado = ColoresYTextos.de(config);
      expect(guardado.colores, {'5A': 2});
      expect(guardado.titulo, 'Egresados');
      expect(guardado.subtitulo, '');
      expect(guardado.igualA(config), isTrue);
    });

    test('cualquier cambio deja de ser igual', () {
      expect(
        const ColoresYTextos(colores: {'5A': 3}, titulo: 'Egresados')
            .igualA(config),
        isFalse,
      );
      expect(
        const ColoresYTextos(colores: {'5A': 2, '5B': 1}, titulo: 'Egresados')
            .igualA(config),
        isFalse,
      );
      expect(
        const ColoresYTextos(colores: {'5A': 2}, titulo: 'Otra').igualA(config),
        isFalse,
      );
      expect(
        const ColoresYTextos(
          colores: {'5A': 2},
          titulo: 'Egresados',
          subtitulo: 'Costa Surubí',
        ).igualA(config),
        isFalse,
      );
      expect(
        ColoresYTextos(
          colores: const {'5A': 2},
          titulo: 'Egresados',
          sectores: [(sector: armado.sectores.first, texto: 'Otro')],
        ).igualA(config),
        isFalse,
      );
    });

    test('cambia los colores y los títulos, y nada más del plano', () {
      final cambio = const ColoresYTextos(
        colores: {'5A': 5, '6A': 0},
        titulo: '  Egresados 2026 ',
        subtitulo: 'Costa Surubí',
      ).aplicar(armado, config);
      expect(cambio.sePuede, isTrue);
      // Sin textos de sectores, el armado no se toca.
      expect(cambio.armado, isNull);
      final c = cambio.config!;
      expect(c.colores, {'5A': 5, '6A': 0});
      expect(c.titulo, 'Egresados 2026');
      expect(c.subtitulo, 'Costa Surubí');
      expect(c.libres.keys, [7]);
      expect(c.libres[7]!.motivo, 'columna');
      expect(c.ordenDivisiones, ['5B', '5A']);
      expect(c.medidas, const MedidasPlano(lugarMesaM: 2.3));
      // Y vuelve igual después de pasar por la base.
      final leido = ConfigPlano.fromJson(c.toJson());
      expect(leido.colores, c.colores);
      expect(leido.titulo, 'Egresados 2026');
      expect(leido.medidas, c.medidas);
    });

    test('si la otra PC eligió un color o cambió el título mientras tanto, no '
        'se le pisa: no se guarda nada', () {
      const cambio = ColoresYTextos(colores: {'5A': 5}, titulo: 'Egresados');
      // Lo que se veía al elegir es lo que hay: se guarda.
      expect(cambio.aplicar(armado, config, visto: config).sePuede, isTrue);
      // La otra PC cambió un color.
      final conOtroColor = config.copyWith(colores: const {'5A': 1, '5B': 3});
      final pisaria = cambio.aplicar(armado, conOtroColor, visto: config);
      expect(pisaria.sePuede, isFalse);
      expect(pisaria.problema, contains('cambió los colores o el título'));
      // Si cambió otra cosa del plano (las medidas), no molesta.
      final conOtrasMedidas =
          config.copyWith(medidas: const MedidasPlano(lugarMesaM: 2.6));
      final sigue = cambio.aplicar(armado, conOtrasMedidas, visto: config);
      expect(sigue.sePuede, isTrue);
      expect(sigue.config!.medidas, const MedidasPlano(lugarMesaM: 2.6));
    });

    test('borrar el título lo saca, no deja uno vacío', () {
      final c = const ColoresYTextos(colores: {'5A': 2})
          .aplicar(armado, config)
          .config!;
      expect(c.titulo, isNull);
      expect(c.toJson(), isNot(contains('titulo')));
    });
  });

  group('los textos de los sectores', () {
    final escenario =
        armado.sectores.firstWhere((s) => s.tipo == TipoSector.escenario);

    test('cambia solo el texto de ese sector: ni lugar, ni mesas', () {
      final cambio = ColoresYTextos(
        sectores: [(sector: escenario, texto: ' Escenario Mayor ')],
      ).aplicar(armado, ConfigPlano.vacia);
      expect(cambio.sePuede, isTrue);
      final nuevo = cambio.armado!;
      expect(nuevo.clave, armado.clave);
      expect(nuevo.numeros, armado.numeros);
      expect(nuevo.cortes, armado.cortes);
      expect(nuevo.sectores.length, armado.sectores.length);
      for (final (i, s) in nuevo.sectores.indexed) {
        final antes = armado.sectores[i];
        expect(s.caja, antes.caja);
        expect(s.tipo, antes.tipo);
        expect(
          s.texto,
          identical(antes, escenario) ? 'Escenario Mayor' : antes.texto,
        );
      }
      for (final m in armado.mesas) {
        expect(nuevo.mesa(m.numero)!.x, m.x);
        expect(nuevo.mesa(m.numero)!.y, m.y);
      }
    });

    test('si el sector ya no está como se lo vio, no se guarda nada', () {
      // La otra PC lo corrió mientras tanto.
      final corrido = armado.copyWith(sectores: [
        for (final s in armado.sectores)
          identical(s, escenario)
              ? s.copyWith(caja: s.caja.mover(40, 0))
              : s,
      ]);
      final cambio = ColoresYTextos(
        colores: const {'5A': 4},
        sectores: [(sector: escenario, texto: 'Escenario Mayor')],
      ).aplicar(corrido, ConfigPlano.vacia);
      expect(cambio.sePuede, isFalse);
      expect(cambio.problema, contains('El salón guardado cambió'));
      // Ni los colores: es todo o nada.
      expect(cambio.config, isNull);
    });

    test('la firma cambia con lo que la pestaña muestra, y con nada más', () {
      String firma(ConfigPlano c, [List<SectorPlano>? s]) =>
          ColoresYTextos.firmaDe(c, s ?? armado.sectores);
      const base = ConfigPlano(colores: {'5A': 2}, titulo: 'Egresados');
      expect(firma(base), firma(base));
      expect(
        firma(base),
        firma(base.copyWith(libres: const {3: MesaLibre()})),
      );
      expect(
        firma(base),
        firma(base.copyWith(medidas: const MedidasPlano(lugarMesaM: 2.4))),
      );
      expect(firma(base), isNot(firma(base.copyWith(titulo: 'Otra'))));
      expect(
        firma(base),
        isNot(firma(base.copyWith(colores: const {'5A': 3}))),
      );
      expect(
        firma(base),
        isNot(firma(base, [
          for (final s in armado.sectores)
            identical(s, escenario) ? s.copyWith(texto: 'Otro') : s,
        ])),
      );
    });
  });

  test('los colores de la paleta son colores de verdad en los tres estilos',
      () {
    for (final e in EstiloPlano.values) {
      final tema = TemaPlano.de(e);
      expect(tema.divisiones.toSet().length, tema.divisiones.length,
          reason: '${e.name}: ningún color repetido');
      expect(tema.divisiones, isNot(contains(tema.conflicto)));
      expect(tema.divisiones.every((Color c) => c.a == 1), isTrue);
    }
  });
}
