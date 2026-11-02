// Los números del salón se ordenan solos al guardar, antes del sorteo (etapa 2 de
// docs/PLAN_NUMEROS_EN_ORDEN_2026-10-29.md). Cuenta pura: sin base ni pantalla.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/salon_puerto_viejo.dart';

ContratoAlumno _alumno(
  String id, {
  List<int> mesas = const [],
  bool baja = false,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${baja ? '[BAJA] ' : ''}${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

CambioDeConfig _guardar(
  ArmadoSalon base, {
  ArmadoSalon? nuevo,
  ArmadoSalon? fresco,
  ConfigPlano config = ConfigPlano.vacia,
  List<ContratoAlumno> alumnos = const [],
  bool rehecho = false,
  bool leidoDeLaNube = true,
}) =>
    EditarArmado.paraGuardar(
      base: base,
      nuevo: nuevo ?? base,
      fresco: fresco ?? base,
      config: config,
      alumnos: alumnos,
      enUsoVisto: EditarArmado.enUso(alumnos, config),
      rehecho: rehecho,
      leidoDeLaNube: leidoDeLaNube,
    );

/// El lugar de una mesa de [a].
String _lugar(ArmadoSalon a, int numero) {
  final m = a.mesa(numero)!;
  return '${m.hoja} ${m.x} ${m.y}';
}

/// La mesa de [a] que está donde estaba [numero] en [antes].
int _numeroEnElMismoLugar(ArmadoSalon antes, int numero, ArmadoSalon a) =>
    a.mesas
        .firstWhere((m) => '${m.hoja} ${m.x} ${m.y}' == _lugar(antes, numero))
        .numero;

void main() {
  final puertoViejo = armadoDePuertoViejo();

  group('sin familias con mesa', () {
    test('se ordena: del 1 al N, con un solo salto y sin mover ninguna mesa', () {
      final r = _guardar(puertoViejo);
      expect(r.sePuede, isTrue, reason: r.problema);
      final a = r.armado!;
      expect(a.numeros, [for (var n = 1; n <= 35; n++) n]);
      expect(a.cortes, {17});
      for (final m in puertoViejo.mesas) {
        expect(
          () => _numeroEnElMismoLugar(puertoViejo, m.numero, a),
          returnsNormally,
          reason: 'la mesa ${m.numero} se movió',
        );
      }
    });

    test('un alumno sin mesa no frena nada', () {
      final r = _guardar(puertoViejo, alumnos: [_alumno('sosa')]);
      expect(r.armado!.cortes, {17});
    });

    test('guardarlo otra vez no cambia nada', () {
      final una = _guardar(puertoViejo).armado!;
      final otra = _guardar(una).armado!;
      expect(EditarArmado.firma(otra), EditarArmado.firma(una));
    });

    test('lo que la pantalla compara después es lo guardado', () {
      expect(
        EditarArmado.firma(_guardar(puertoViejo).armado!),
        EditarArmado.firma(
          EditarArmado.comoSeGuarda(puertoViejo, puertoViejo, ordenar: true),
        ),
      );
    });

    test('ultimoNumero vuelve a N: no hay número impreso con una familia', () {
      final sinLaUltima = EditarArmado.sacar(puertoViejo, 35);
      final a = _guardar(puertoViejo, nuevo: sinLaUltima).armado!;
      expect(a.numeros, [for (var n = 1; n <= 34; n++) n]);
      expect(a.ultimoNumero, 34);
      expect(SesionAcomodo(base: a).agregar('A'), 35);
    });

    test('la mesa que se sacó se informa con su número de antes', () {
      final r = _guardar(puertoViejo, nuevo: EditarArmado.sacar(puertoViejo, 5));
      expect(r.mesas, [5]);
      expect(r.armado!.numeros, [for (var n = 1; n <= 34; n++) n]);
    });

    test('vaciar no ordena nada y deja el número anotado', () {
      final r = _guardar(
        puertoViejo,
        nuevo: puertoViejo.copyWith(mesas: const []),
        rehecho: true,
      );
      expect(r.armado!.mesas, isEmpty);
      expect(r.armado!.ultimoNumero, 35);
    });

    test('un salón que ya está en orden queda igual, sin tocar lo configurado',
        () {
      final enOrden = _guardar(puertoViejo).armado!;
      const config = ConfigPlano(
        fijadas: {99: MesaFijada(alumnoId: 'sosa')},
        bloques: [BloqueDivision('5A', 1, 20)],
      );
      final r = _guardar(enOrden, config: config);
      expect(identical(r.armado, enOrden), isTrue);
      expect(r.config!.fijadas.keys, [99]);
      expect(r.config!.bloques.single.mesas, isNull);
    });
  });

  group('lo que apunta a un número sigue a su mesa', () {
    test('una fijada queda fijada en la misma mesa, con otro número', () {
      const config = ConfigPlano(
        fijadas: {15: MesaFijada(alumnoId: 'sosa', motivo: 'Silla de ruedas')},
      );
      final r = _guardar(puertoViejo, config: config);
      final numero = _numeroEnElMismoLugar(puertoViejo, 15, r.armado!);
      expect(numero, isNot(15));
      expect(r.config!.fijadas.keys, [numero]);
      expect(r.config!.fijadas[numero]!.alumnoId, 'sosa');
      expect(r.config!.fijadas[numero]!.motivo, 'Silla de ruedas');
    });

    test('una libre, también', () {
      const config = ConfigPlano(libres: {5: MesaLibre(motivo: 'columna')});
      final r = _guardar(puertoViejo, config: config);
      final numero = _numeroEnElMismoLugar(puertoViejo, 5, r.armado!);
      expect(numero, isNot(5));
      expect(r.config!.libres[numero]!.motivo, 'columna');
    });

    test('un bloque, con su lista exacta de mesas', () {
      final config = ConfigPlano(
        bloques: [BloqueDivision.deMesas('5A', const [5, 6, 7, 8])],
      );
      final r = _guardar(puertoViejo, config: config);
      final b = r.config!.bloques.single;
      expect(b.division, '5A');
      expect(b.mesas, [
        for (final n in [5, 6, 7, 8])
          _numeroEnElMismoLugar(puertoViejo, n, r.armado!),
      ]..sort());
      expect(b.desde, b.mesas!.first);
      expect(b.hasta, b.mesas!.last);
    });

    test('un bloque guardado como rango pasa a ser su lista', () {
      const config = ConfigPlano(bloques: [BloqueDivision('5A', 5, 8)]);
      final r = _guardar(puertoViejo, config: config);
      expect(r.config!.bloques.single.mesas, hasLength(4));
    });

    test('dos fijadas no se pisan al cambiar de número', () {
      // La 1 y la 4 se reparten números que estaban usados por la otra.
      const config = ConfigPlano(
        fijadas: {
          1: MesaFijada(alumnoId: 'a'),
          4: MesaFijada(alumnoId: 'b'),
          8: MesaFijada(alumnoId: 'c'),
        },
      );
      final r = _guardar(puertoViejo, config: config);
      expect(r.config!.fijadas, hasLength(3));
      for (final (viejo, id) in [(1, 'a'), (4, 'b'), (8, 'c')]) {
        final nuevo = _numeroEnElMismoLugar(puertoViejo, viejo, r.armado!);
        expect(r.config!.fijadas[nuevo]!.alumnoId, id);
      }
    });

    test('un número sin mesa no cae en la mesa de otro', () {
      const config = ConfigPlano(fijadas: {90: MesaFijada(alumnoId: 'x')});
      final r = _guardar(puertoViejo, config: config);
      expect(r.config!.fijadas, isEmpty);
    });

    test('rehecho: se quitan, como siempre, y no se traducen', () {
      const config = ConfigPlano(
        fijadas: {3: MesaFijada(alumnoId: 'x')},
        libres: {12: MesaLibre()},
        bloques: [BloqueDivision('5A', 1, 20)],
      );
      final r = _guardar(puertoViejo, config: config, rehecho: true);
      expect(r.config!.fijadas, isEmpty);
      expect(r.config!.libres, isEmpty);
      expect(r.config!.bloques, isEmpty);
    });

    test('lo demás de la configuración no se toca', () {
      const config = ConfigPlano(colores: {'5A': 2}, titulo: 'Promo 2026');
      final r = _guardar(puertoViejo, config: config);
      expect(r.config!.colores, {'5A': 2});
      expect(r.config!.titulo, 'Promo 2026');
    });
  });

  group('cuándo no se ordena', () {
    void sinTocar(CambioDeConfig r) {
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.armado!.numeros, puertoViejo.numeros);
      for (final n in puertoViejo.numeros) {
        expect(_lugar(r.armado!, n), _lugar(puertoViejo, n));
      }
    }

    test('con una familia con mesa, ningún número se toca', () {
      sinTocar(_guardar(puertoViejo, alumnos: [_alumno('gomez', mesas: [12])]));
    });

    test('tampoco con una familia de baja que conserva su mesa', () {
      final baja = _alumno('gomez', mesas: [12], baja: true);
      expect(baja.esBajaTemporal, isTrue);
      sinTocar(_guardar(puertoViejo, alumnos: [baja]));
    });

    test('una fijada sola no cuenta como familia con mesa', () {
      const config = ConfigPlano(fijadas: {12: MesaFijada(alumnoId: 'sosa')});
      final r = _guardar(puertoViejo, config: config);
      expect(r.armado!.cortes, {17});
    });

    test('con familias, lo fijado y lo libre quedan con su número', () {
      const config = ConfigPlano(
        fijadas: {15: MesaFijada(alumnoId: 'sosa')},
        libres: {5: MesaLibre()},
      );
      final r = _guardar(
        puertoViejo,
        config: config,
        alumnos: [_alumno('gomez', mesas: [12])],
      );
      expect(r.config!.fijadas.keys, [15]);
      expect(r.config!.libres.keys, [5]);
    });

    test('en un armado del Canva, nada: trae la numeración del jefe', () {
      for (final canva in ArmadosPredefinidos.todos) {
        final r = _guardar(canva);
        expect(identical(r.armado, canva), isTrue, reason: canva.clave);
      }
    });

    test('sin internet no: esta PC no puede saber si la otra sorteó', () {
      sinTocar(_guardar(puertoViejo, leidoDeLaNube: false));
    });

    test('el sorteo deshecho: el próximo guardado vuelve a ordenar', () {
      final sentada = [_alumno('gomez', mesas: [12])];
      final conSorteo = _guardar(puertoViejo, alumnos: sentada).armado!;
      expect(conSorteo.cortes, hasLength(13));
      // Deshacer deja a la familia sin mesa; el salón no cambió.
      expect(_guardar(conSorteo).armado!.cortes, {17});
    });
  });

  group('una PC atrasada no pisa a la otra', () {
    test('si la otra ya lo ordenó, esta no guarda sobre lo viejo', () {
      final deLaOtra = _guardar(puertoViejo).armado!;
      final m = puertoViejo.mesa(20)!;
      final r = _guardar(
        puertoViejo,
        nuevo: EditarArmado.mover(puertoViejo, 20, m.x, m.y + 24),
        fresco: deLaOtra,
      );
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('El salón guardado cambió'));
    });

    test('si la otra sorteó mientras tanto, no se guarda ni se ordena', () {
      final r = EditarArmado.paraGuardar(
        base: puertoViejo,
        nuevo: puertoViejo,
        fresco: puertoViejo,
        config: ConfigPlano.vacia,
        alumnos: [_alumno('gomez', mesas: [12])],
        enUsoVisto: const {},
      );
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('cambiaron las mesas de las familias'));
    });
  });

  group('la sesión de Acomodar lo avisa antes', () {
    test('un salón mezclado se puede guardar sin tocar nada', () {
      final s = SesionAcomodo(base: puertoViejo);
      expect(s.hayCambios, isFalse);
      expect(s.faltaOrdenar, isTrue);
      expect(s.puedeGuardar, isTrue);
      expect(
        s.avisos((_) => 0).last,
        'Los números se ordenan al guardar: quedan del 1 al 35. Ninguna mesa '
        'se mueve.',
      );
    });

    test('un salón en orden no avisa ni deja guardar sin cambios', () {
      final s = SesionAcomodo(base: _guardar(puertoViejo).armado!);
      expect(s.faltaOrdenar, isFalse);
      expect(s.puedeGuardar, isFalse);
      expect(s.avisos((_) => 0), isNot(contains(contains('se ordenan'))));
    });

    test('con familias con mesa no avisa, y no deja guardar sin cambios', () {
      final s = SesionAcomodo(base: puertoViejo, haySorteo: true);
      expect(s.faltaOrdenar, isFalse);
      expect(s.puedeGuardar, isFalse);
    });

    test('si la otra PC sorteó mientras tanto, deja de avisar', () {
      final s = SesionAcomodo(base: puertoViejo);
      expect(s.faltaOrdenar, isTrue);
      s.ponerAlDia(enUso: const {12: 'la tiene GOMEZ'}, ocupantes: const [], haySorteo: true);
      expect(s.faltaOrdenar, isFalse);
    });

    test('correr una mesa fuera de orden lo avisa', () {
      final base = _guardar(puertoViejo).armado!;
      final s = SesionAcomodo(base: base);
      final o = base.mesa(35)!;
      s.empezarArrastre();
      s.arrastrarMesa(1, o.x, o.y + base.aUnidades(9));
      s.terminarArrastre();
      expect(s.hayCambios, isTrue);
      expect(s.faltaOrdenar, isTrue);
    });

    test('en un armado del Canva no', () {
      final s = SesionAcomodo(base: ArmadosPredefinidos.todos.first);
      expect(s.faltaOrdenar, isFalse);
    });

    test('lo que sale de ACOMODAR ya está en orden', () {
      final vacio = ArmarAMedida.vacio(ArmarAMedida.playonDe(puertoViejo)!);
      final s = SesionAcomodo(base: vacio);
      s.acomodar(35);
      expect(s.faltaOrdenar, isFalse);
    });
  });
}
