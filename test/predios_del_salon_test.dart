import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/predios_del_salon.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/models/predio.dart';

/// Los predios con nombre (6.1.0): qué se guarda, con qué nombre, y con qué
/// arranca la fiesta que elige uno. Cuentas puras, sin base.
void main() {
  final ahora = DateTime.utc(2026, 10, 20, 12);
  const idA = 'd0000000-0000-4000-8000-00000000000a';
  const idB = 'd0000000-0000-4000-8000-00000000000b';

  /// El espacio del jefe: el playón, el escenario, el Ingreso y una pista.
  ArmadoSalon espacioDelJefe() {
    final vacio = ArmarAMedida.vacio(PlayonReal.costaSurubi);
    return vacio.copyWith(sectores: [
      ...vacio.sectores,
      SectorPlano(
        tipo: TipoSector.pista,
        texto: 'Pista',
        hoja: 'A',
        // En el medio del playón, unos 3 × 3 m.
        caja: const RectPlano(1192, 800, 150, 150),
      ),
    ]);
  }

  ({Predio? predio, Predio? reemplaza, String? problema}) guardar(
    String nombre, {
    ArmadoSalon? armado,
    List<Predio> guardados = const [],
    String id = idA,
    PlayonReal playon = PlayonReal.costaSurubi,
  }) =>
      PrediosDelSalon.guardarComo(
        nombre: nombre,
        armado: armado ?? espacioDelJefe(),
        playon: playon,
        guardados: guardados,
        hechoPor: 'Jefe',
        ahora: ahora,
        idNuevo: id,
      );

  String mesas(ArmadoSalon a) =>
      jsonEncode([for (final m in a.mesas) m.toJson()]);

  group('el nombre', () {
    test('vacío o muy largo, no', () {
      expect(guardar('   ').problema, 'Escribí el nombre del predio.');
      expect(guardar('x' * 41).problema, contains('muy largo'));
      expect(guardar('x' * 40).problema, isNull);
    });

    test('"Costa Surubí" es el de fábrica, escrito como sea', () {
      for (final n in ['Costa Surubí', 'costa surubi', '  COSTA   SURUBÍ ']) {
        expect(guardar(n).problema, contains('es el de fábrica'), reason: n);
      }
    });

    test('se guarda sin espacios de más', () {
      expect(guardar('  Buena    Vista ').predio!.nombre, 'Buena Vista');
    });
  });

  group('GUARDAR COMO PREDIO', () {
    test('guarda el espacio sin mesas, con su clave y sus medidas', () {
      const medido = PlayonReal(frenteM: 31, fondoM: 45.5, profundidadM: 40);
      final r = guardar('Buena Vista', playon: medido);
      expect(r.problema, isNull);
      expect(r.reemplaza, isNull);
      final p = r.predio!;
      expect(p.id, idA);
      expect(p.playon, medido);
      expect(p.hechoPor, 'Jefe');
      final e = p.espacioONull!;
      expect(e.clave, 'predio@$idA');
      expect(e.nombre, 'Buena Vista');
      expect(e.mesas, isEmpty);
      expect(e.sectores.map((s) => s.texto),
          ['Escenario', 'Ingreso', 'Pista']);
      expect(jsonEncode(e.hojas.map((h) => h.toJson()).toList()),
          jsonEncode(espacioDelJefe().hojas.map((h) => h.toJson()).toList()));
    });

    test('con las mesas puestas, igual guarda solo el espacio', () {
      final conMesas = ArmarAMedida.acomodar(espacioDelJefe(), cantidad: 60);
      expect(conMesas.armado.mesas, isNotEmpty);
      final e = guardar('Buena Vista', armado: conMesas.armado.copyWith(ultimoNumero: 70))
          .predio!
          .espacioONull!;
      expect(e.mesas, isEmpty);
      expect(e.ultimoNumero, isNull, reason: 'los números son de cada fiesta');
      expect(e.lugarOriginalM, isNull,
          reason: 'la distancia entre mesas no va con el predio');
      expect(e.distanciaPegadas, isNull);
    });

    test('un armado del Canva no se guarda: no tiene el borde del playón', () {
      final r = guardar('Buena Vista', armado: ArmadosPredefinidos.normal2aPagina3());
      expect(r.predio, isNull);
      expect(r.problema, contains('del Canva'));
    });

    test('con un nombre que ya está, lo reemplaza y queda su id', () {
      final viejo = guardar('Buena Vista').predio!;
      final nuevoEspacio = ArmarAMedida.vacio(
        const PlayonReal(frenteM: 20, fondoM: 20, profundidadM: 25),
      );
      final r = PrediosDelSalon.guardarComo(
        nombre: 'BUENA vista',
        armado: nuevoEspacio,
        playon: const PlayonReal(frenteM: 20, fondoM: 20, profundidadM: 25),
        guardados: [viejo],
        hechoPor: 'Operario',
        ahora: ahora.add(const Duration(days: 5)),
        idNuevo: idB,
      );
      expect(r.reemplaza?.id, idA);
      expect(r.predio!.id, idA);
      expect(r.predio!.nombre, 'BUENA vista');
      expect(r.predio!.createdAt, viejo.createdAt);
      expect(r.predio!.updatedAt, ahora.add(const Duration(days: 5)));
      expect(r.predio!.playon.frenteM, 20);
      expect(r.predio!.espacioONull!.clave, 'predio@$idA');
      expect(r.predio!.espacioONull!.sectores.length, 2);
    });

    test('uno borrado no se reemplaza: el nombre queda libre para otro', () {
      final borrado = PrediosDelSalon.borrar(
        guardar('Buena Vista').predio!,
        hechoPor: 'Jefe',
        ahora: ahora,
      );
      final r = guardar('Buena Vista', guardados: [borrado], id: idB);
      expect(r.reemplaza, isNull);
      expect(r.predio!.id, idB);
    });
  });

  group('Renombrar y Borrar', () {
    final a = guardar('Buena Vista').predio!;
    final b = guardar('Arenas', id: idB).predio!;

    test('renombrar cambia el nombre y el del espacio, no el id', () {
      final r = PrediosDelSalon.renombrar(a, 'Buena Vista II',
          guardados: [a, b], hechoPor: 'Jefe', ahora: ahora);
      expect(r.problema, isNull);
      expect(r.predio!.id, idA);
      expect(r.predio!.nombre, 'Buena Vista II');
      expect(r.predio!.espacioONull!.nombre, 'Buena Vista II');
      expect(r.predio!.espacioONull!.clave, 'predio@$idA');
    });

    test('no con el nombre de otro, pero sí con el suyo en otra letra', () {
      expect(
        PrediosDelSalon.renombrar(a, 'arenas',
                guardados: [a, b], hechoPor: null, ahora: ahora)
            .problema,
        'Ya hay un predio "Arenas".',
      );
      expect(
        PrediosDelSalon.renombrar(a, 'BUENA VISTA',
                guardados: [a, b], hechoPor: null, ahora: ahora)
            .problema,
        isNull,
      );
      expect(
        PrediosDelSalon.renombrar(a, 'Costa Surubi',
                guardados: [a, b], hechoPor: null, ahora: ahora)
            .problema,
        contains('de fábrica'),
      );
    });

    test('borrar lo marca, sin perder lo guardado', () {
      final borrado = PrediosDelSalon.borrar(a, hechoPor: 'Jefe', ahora: ahora);
      expect(borrado.borrado, isTrue);
      expect(borrado.borradoAt, ahora);
      expect(borrado.armadoJson, a.armadoJson);
      expect(borrado.nombre, a.nombre);
    });
  });

  group('la fiesta que elige un predio', () {
    final predio = guardar('Buena Vista').predio!;

    test('arranca con su espacio, sin mesas, y la distancia de la fiesta', () {
      final s = PrediosDelSalon.salonDe(predio, lugarM: 2.4)!;
      expect(s.clave, 'predio@$idA');
      expect(ArmarAMedida.idDePredio(s), idA);
      expect(s.nombre, 'Buena Vista');
      expect(s.mesas, isEmpty);
      expect(s.lugarOriginalM, 2.4);
      expect(ArmarAMedida.lugarDe(s), 2.4);
      expect(s.sectores.map((x) => x.texto), ['Escenario', 'Ingreso', 'Pista']);
    });

    test('tiene el borde del playón: Medidas lo lee', () {
      final s = PrediosDelSalon.salonDe(predio, lugarM: 2)!;
      final p = ArmarAMedida.playonDe(s)!;
      expect(p.frenteM, closeTo(PlayonReal.costaSurubi.frenteM, 0.01));
      expect(p.fondoM, closeTo(PlayonReal.costaSurubi.fondoM, 0.01));
      expect(p.profundidadM, closeTo(PlayonReal.costaSurubi.profundidadM, 0.01));
    });

    test('ACOMODAR LAS MESAS pone las mismas que en el espacio del que salió',
        () {
      for (final lugar in [2.0, 2.3]) {
        final desdeElPredio = ArmarAMedida.acomodar(
          PrediosDelSalon.salonDe(predio, lugarM: lugar)!,
          cantidad: 90,
        );
        final enElOriginal =
            ArmarAMedida.acomodar(espacioDelJefe(), cantidad: 90, lugarM: lugar);
        expect(desdeElPredio.puestas, enElOriginal.puestas);
        expect(mesas(desdeElPredio.armado), mesas(enElOriginal.armado),
            reason: 'a $lugar m');
        expect(desdeElPredio.armado.clave, 'predio@$idA',
            reason: 'acomodar no le cambia la clave');
      }
    });

    group('Volver al armado original', () {
      ArmadoSalon conMesas() => ArmarAMedida.acomodar(
            PrediosDelSalon.salonDe(predio, lugarM: 2.2)!,
            cantidad: 50,
          ).armado;

      test('vuelve al predio como está guardado hoy, sin mesas', () {
        // Después de que la fiesta lo eligió, el jefe agrandó la pista y lo
        // guardó de nuevo con el mismo nombre.
        final hoy = PrediosDelSalon.guardarComo(
          nombre: 'Buena Vista',
          armado: ArmarAMedida.vacio(
            const PlayonReal(frenteM: 32, fondoM: 46, profundidadM: 39),
          ),
          playon: const PlayonReal(frenteM: 32, fondoM: 46, profundidadM: 39),
          guardados: [predio],
          hechoPor: 'Jefe',
          ahora: ahora,
        ).predio!;
        final s = SesionAcomodo(base: conMesas(), predios: [hoy]);
        expect(s.motivoSinOriginal, isNull);
        expect(s.volverAlOriginal(), isNull);
        expect(s.actual.mesas, isEmpty);
        expect(s.actual.clave, 'predio@$idA');
        expect(ArmarAMedida.playonDe(s.actual)!.frenteM, closeTo(32, 0.01));
        expect(s.actual.lugarOriginalM, 2.2,
            reason: 'la distancia sigue siendo la de la fiesta');
        expect(s.puedeDeshacer, isTrue);
      });

      test('si el predio se borró, apagado con el motivo', () {
        final borrado =
            PrediosDelSalon.borrar(predio, hechoPor: 'Jefe', ahora: ahora);
        for (final predios in [<Predio>[], [borrado]]) {
          final s = SesionAcomodo(base: conMesas(), predios: predios);
          expect(
            s.motivoSinOriginal,
            'El predio "Buena Vista" se borró o todavía no llegó a esta PC: no '
            'hay a qué volver.',
          );
          expect(s.volverAlOriginal(), isNotNull);
          expect(s.actual.mesas, hasLength(50), reason: 'no cambió nada');
        }
      });

      test('cuando el predio llega, ya se puede', () {
        final s = SesionAcomodo(base: conMesas());
        expect(s.motivoSinOriginal, isNotNull);
        s.predios = [predio];
        expect(s.motivoSinOriginal, isNull);
      });
    });

    test('un armado que no salió de un predio no tiene id de predio', () {
      expect(ArmarAMedida.idDePredio(ArmarAMedida.vacio(PlayonReal.costaSurubi)),
          isNull);
      expect(ArmarAMedida.idDePredio(ArmadosPredefinidos.normal2aPagina3()),
          isNull);
    });
  });
}
