import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/cambios_de_mesa.dart';
import 'package:arguello_events/features/plano/services/divisiones.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/sesion_acomodo.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// ACOMODAR LAS MESAS y VACIAR EL SALÓN (6.1.0, etapa 4 de
/// `docs/PLAN_SALON_PRIMERO_2026-10-16.md`), sin pantalla: la sesión de
/// Acomodar, lo que se guarda, y el recorrido entero con el sorteo.
ContratoAlumno _alumno(String id, {String division = '5° A', List<int>? mesas}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e1',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 0,
      mesaExtraCantidad: 0,
      numeroMesa:
          mesas == null ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

List<ContratoAlumno> _familias(String division, int cuantas) => [
      for (var i = 0; i < cuantas; i++)
        _alumno('${Divisiones.clave(division)}-$i', division: division),
    ];

void main() {
  /// Un playón rectangular de 30 × 40 m, vacío, con una pista de 8 × 8 m en el
  /// medio.
  ArmadoSalon conPista() {
    final v = ArmarAMedida.vacio(
      const PlayonReal(frenteM: 30, fondoM: 30, profundidadM: 40),
    );
    final b = v.hojas.first.contorno!.puntos;
    final x0 = b.map((p) => p.x).reduce(min);
    final y0 = b.map((p) => p.y).reduce(min);
    return v.copyWith(sectores: [
      ...v.sectores,
      SectorPlano(
        tipo: TipoSector.pista,
        texto: 'Pista',
        hoja: 'A',
        caja: RectPlano(
          x0 + v.aUnidades(11),
          y0 + v.aUnidades(14),
          v.aUnidades(8),
          v.aUnidades(8),
        ),
      ),
    ]);
  }

  /// Ninguna mesa pisa la pista (con su despeje).
  void sinPisarLaPista(ArmadoSalon a) {
    final p = a.sectores.firstWhere((s) => s.tipo == TipoSector.pista).caja;
    final despeje = a.aUnidades(ArmarAMedida.despejeSectorM);
    for (final m in a.mesas) {
      final dx = max(max(p.x - m.x, 0.0), m.x - p.derecha);
      final dy = max(max(p.y - m.y, 0.0), m.y - p.abajo);
      expect(sqrt(dx * dx + dy * dy), greaterThanOrEqualTo(a.radio + despeje - 1e-6),
          reason: 'la mesa ${m.numero} pisa la pista');
    }
  }

  group('ACOMODAR LAS MESAS', () {
    test('las pone alrededor de lo armado, numeradas de 1, y se deshace', () {
      final base = conPista();
      final s = SesionAcomodo(base: base);
      expect(s.motivoSinAcomodar(60), isNull);
      final r = s.acomodar(60)!;
      expect(r.puestas, 60);
      expect(r.faltan, 0);
      expect(s.actual.numeros, [for (var n = 1; n <= 60; n++) n]);
      sinPisarLaPista(s.actual);
      // Es la misma cuenta que la del salón primero, mesa por mesa.
      final cuenta = ArmarAMedida.acomodar(base, cantidad: 60).armado;
      for (final m in cuenta.mesas) {
        final n = s.actual.mesa(m.numero)!;
        expect((n.x, n.y), (m.x, m.y), reason: 'mesa ${m.numero}');
      }
      expect(s.rehecho, isTrue);
      expect(s.puedeGuardar, isTrue);
      s.deshacer();
      expect(s.actual.mesas, isEmpty);
      expect(s.rehecho, isFalse);
    });

    test('a la distancia que se le pida', () {
      final s = SesionAcomodo(base: conPista());
      s.acomodar(20, lugarM: 2.5);
      expect(s.actual.distanciaM(1, 2), closeTo(2.5, 1e-9));
    });

    test('si no entran todas, dice cuántas faltan', () {
      final chico = ArmarAMedida.vacio(
        const PlayonReal(frenteM: 10, fondoM: 10, profundidadM: 10),
      );
      final r = SesionAcomodo(base: chico).acomodar(60)!;
      expect(r.faltan, greaterThan(0));
      expect(r.puestas, r.capacidad);
    });

    test('otra vez: reemplaza lo corrido a mano, que vuelve con Deshacer', () {
      final s = SesionAcomodo(base: conPista());
      s.acomodar(30);
      final antes = s.actual.mesa(5)!;
      s.empezarArrastre();
      s.arrastrarMesa(5, antes.x + s.actual.aUnidades(1), antes.y);
      s.terminarArrastre();
      final corrida = s.actual.mesa(5)!;
      expect(corrida.x, isNot(antes.x));
      // Lo corrido a mano sigue siendo un salón rehecho.
      expect(s.rehecho, isTrue);
      s.acomodar(30);
      expect(s.actual.mesa(5)!.x, antes.x);
      s.deshacer();
      expect(s.actual.mesa(5)!.x, corrida.x);
    });

    test('DESCARTAR vuelve al guardado, que no está rehecho', () {
      final s = SesionAcomodo(base: conPista());
      s.acomodar(30);
      s.descartar();
      expect(s.rehecho, isFalse);
      expect(s.actual.mesas, isEmpty);
      s.deshacer();
      expect(s.rehecho, isTrue);
      expect(s.actual.mesas, hasLength(30));
    });

    test('apagado con familias sentadas, en un armado del Canva y sin '
        'alumnos, con el motivo', () {
      expect(
        SesionAcomodo(base: conPista(), haySorteo: true).motivoSinAcomodar(60),
        'Ya hay familias con mesa: deshacé el sorteo primero.',
      );
      final canva = SesionAcomodo(base: ArmadosPredefinidos.normal2a2b());
      expect(canva.motivoSinAcomodar(60), contains('del Canva'));
      expect(canva.acomodar(60), isNull);
      expect(canva.hayCambios, isFalse);
      expect(SesionAcomodo(base: conPista()).motivoSinAcomodar(0),
          contains('no hay alumnos cargados'));
    });
  });

  group('VACIAR EL SALÓN', () {
    test('saca las mesas y deja el espacio: el borde, los sectores y lo que '
        'miden', () {
      final s = SesionAcomodo(base: conPista());
      s.acomodar(40);
      final lleno = s.actual;
      expect(s.vaciar(), isNull);
      expect(s.actual.mesas, isEmpty);
      expect(s.actual.sectores, lleno.sectores);
      expect(s.actual.hojas.first.contorno!.puntos,
          lleno.hojas.first.contorno!.puntos);
      expect(s.rehecho, isTrue);
      expect(s.puedeGuardar, isFalse); // Es el mismo salón vacío del principio.
      s.deshacer();
      expect(s.actual.mesas, hasLength(40));
    });

    test('un salón guardado con mesas, vaciado, se puede guardar', () {
      final lleno = ArmarAMedida.acomodar(conPista(), cantidad: 40).armado;
      final s = SesionAcomodo(base: lleno);
      expect(s.vaciar(), isNull);
      expect(s.bloqueos, isEmpty);
      expect(s.puedeGuardar, isTrue);
    });

    test('vaciado, una mesa fijada no frena volver al armado original: al '
        'guardar se quita', () {
      final lleno = ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 40),
      ).armado;
      final s = SesionAcomodo(
        base: lleno,
        enUso: const {5: 'está fijada para PEREZ'},
      );
      expect(s.vaciar(), isNull);
      expect(s.motivoSinOriginal, isNull);
      // Sin rehacer, la fijada sí frena si el original no tiene su mesa.
      final sinRehacer = SesionAcomodo(
        base: lleno,
        enUso: const {99: 'está fijada para PEREZ'},
      );
      expect(sinRehacer.motivoSinOriginal, contains('La mesa 99'));
    });

    test('apagado con familias sentadas, en un armado del Canva y si ya está '
        'vacío', () {
      final lleno = ArmarAMedida.acomodar(conPista(), cantidad: 40).armado;
      final sentados = SesionAcomodo(base: lleno, haySorteo: true);
      expect(sentados.vaciar(), contains('deshacé el sorteo'));
      expect(sentados.actual.mesas, hasLength(40));
      expect(SesionAcomodo(base: ArmadosPredefinidos.normal2a2b()).motivoSinVaciar,
          contains('del Canva'));
      expect(SesionAcomodo(base: conPista()).motivoSinVaciar,
          'El salón ya está vacío.');
    });
  });

  group('al guardar lo rehecho', () {
    final lleno = ArmarAMedida.acomodar(conPista(), cantidad: 40).armado;
    final config = ConfigPlano(
      fijadas: const {3: MesaFijada(alumnoId: 'x', motivo: 'Silla de ruedas')},
      libres: const {12: MesaLibre()},
      bloques: const [BloqueDivision('5A', 1, 20)],
      colores: const {'5A': 2},
      titulo: 'Promo 2026',
    );
    final alumnos = [_alumno('x')];
    final visto = EditarArmado.enUso(alumnos, config);

    CambioDeConfig guardar(ArmadoSalon nuevo,
            {bool rehecho = true, ArmadoSalon? fresco, List<ContratoAlumno>? de}) =>
        EditarArmado.paraGuardar(
          base: lleno,
          nuevo: nuevo,
          fresco: fresco ?? lleno,
          config: config,
          alumnos: de ?? alumnos,
          enUsoVisto: de == null ? visto : EditarArmado.enUso(de, config),
          rehecho: rehecho,
        );

    test('vaciado: se quitan las fijadas, las libres y los bloques; los '
        'colores y el título quedan', () {
      final r = guardar(lleno.copyWith(mesas: const []));
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.armado!.mesas, isEmpty);
      expect(r.config!.fijadas, isEmpty);
      expect(r.config!.libres, isEmpty);
      expect(r.config!.bloques, isEmpty);
      expect(r.config!.colores, {'5A': 2});
      expect(r.config!.titulo, 'Promo 2026');
      // El número más alto que tuvo queda anotado: no se vuelve a dar.
      expect(r.armado!.ultimoNumero, 40);
    });

    test('acomodado de nuevo, igual: los números quedaron en otro lugar', () {
      final r = guardar(ArmarAMedida.acomodar(lleno, cantidad: 35).armado);
      expect(r.sePuede, isTrue, reason: r.problema);
      expect(r.config!.fijadas, isEmpty);
      expect(r.config!.libres, isEmpty);
    });

    test('sin rehacer, una fijada sigue frenando que se saque su mesa', () {
      final r = guardar(EditarArmado.sacar(lleno, 3), rehecho: false);
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('La mesa 3 no se puede sacar'));
    });

    test('una familia con mesa frena, aunque esté rehecho', () {
      final sentada = [_alumno('x'), _alumno('y', mesas: [7])];
      final r = guardar(lleno.copyWith(mesas: const []), de: sentada);
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('La mesa 7 no se puede sacar'));
    });

    test('una PC atrasada no pisa el salón que la otra cambió', () {
      final otro = EditarArmado.sacar(lleno, 40);
      final r = guardar(lleno.copyWith(mesas: const []), fresco: otro);
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('cambió mientras lo acomodabas'));
    });
  });

  // Lo que hace el jefe de punta a punta: arma el espacio, acomoda, sortea por
  // división, deshace el sorteo, vacía y acomoda otra vez.
  test('acomodar, sortear por división, deshacer, vaciar y acomodar otra vez',
      () {
    final alumnos = [..._familias('5° A', 30), ..._familias('5° B', 30)];
    final s = SesionAcomodo(base: conPista());
    s.acomodar(60);
    final acomodado = s.actual;

    final e = EntradaSorteoPlano(
      armado: acomodado,
      alumnos: alumnos,
      modo: ModoSorteo.bloques,
    );
    final r = SorteoConPlano.sortear(e, random: Random(1));
    expect(SorteoConPlano.validar(e, r), isNull);
    expect(r.asignaciones.length, 60);

    // Con las familias sentadas, ni acomodar ni vaciar.
    final sentada = SesionAcomodo(base: acomodado, haySorteo: true);
    expect(sentada.acomodar(60), isNull);
    expect(sentada.vaciar(), isNotNull);

    // Se deshizo el sorteo: nadie tiene mesa. Se vacía y se acomoda otra vez,
    // y da lo mismo, mesa por mesa.
    final otraVez = SesionAcomodo(base: acomodado);
    expect(otraVez.vaciar(), isNull);
    expect(otraVez.actual.mesas, isEmpty);
    otraVez.acomodar(60);
    for (final m in acomodado.mesas) {
      final n = otraVez.actual.mesa(m.numero)!;
      expect((n.x, n.y), (m.x, m.y), reason: 'mesa ${m.numero}');
    }
    sinPisarLaPista(otraVez.actual);
    final e2 = EntradaSorteoPlano(
      armado: otraVez.actual,
      alumnos: alumnos,
      modo: ModoSorteo.bloques,
    );
    expect(SorteoConPlano.validar(e2, SorteoConPlano.sortear(e2, random: Random(2))),
        isNull);
  });
}
