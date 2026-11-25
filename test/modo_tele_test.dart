import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El modo tele (24-nov-2026): qué es este equipo en el salón y qué fiesta
/// muestra.
Evento _fiesta(String id, DateTime dia, {EstadoEvento estado = EstadoEvento.confirmado}) =>
    Evento(
      id: id,
      clienteId: 'c0000000-0000-4000-8000-000000000001',
      tipo: 'Egresados',
      fechaEvento: dia,
      estado: estado,
      modalidad: 'masivo',
    );

void main() {
  group('ModoTele', () {
    test('se guarda y se lee igual', () {
      for (final m in [
        const ModoTele(PapelDeLaTele.principal),
        const ModoTele(PapelDeLaTele.segunda, direccionAMano: '192.168.0.10:8787'),
        const ModoTele(PapelDeLaTele.principal, fondoQuieto: true),
      ]) {
        expect(ModoTele.fromJson(m.toJson()), m);
      }
    });

    test('lo que no se entiende no es un modo tele: la app abre como siempre', () {
      expect(ModoTele.fromJson(null), isNull);
      expect(ModoTele.fromJson({'papel': 'tercera'}), isNull);
      expect(ModoTele.fromJson('principal'), isNull);
    });

    test('Tele 1 y Tele 2', () {
      expect(PapelDeLaTele.principal.nombre, 'Tele 1');
      expect(PapelDeLaTele.segunda.numero, 2);
    });

    test('queda en el equipo, y salir lo borra con la fiesta elegida', () async {
      SharedPreferences.setMockInitialValues({});
      await ModoTeleGuardado.guardar(const ModoTele(PapelDeLaTele.segunda));
      await ModoTeleGuardado.elegirFiesta('f1');
      await ModoTeleGuardado.cargar();
      expect(ModoTeleGuardado.leido, const ModoTele(PapelDeLaTele.segunda));
      expect(await ModoTeleGuardado.fiestaElegida(), 'f1');
      await ModoTeleGuardado.guardar(null);
      await ModoTeleGuardado.cargar();
      expect(ModoTeleGuardado.leido, isNull);
      expect(await ModoTeleGuardado.fiestaElegida(), isNull);
    });
  });

  group('la fiesta de la tele', () {
    final sabado = DateTime(2026, 12, 12);
    final domingo = DateTime(2026, 12, 13);

    test('la de hoy', () {
      final f = FiestaDeLaTele.de(
        [_fiesta('dom', domingo), _fiesta('sab', sabado)],
        DateTime(2026, 12, 12, 21),
      );
      expect(f.fiesta?.id, 'sab');
      expect(f.todas.map((e) => e.id), ['sab', 'dom']);
    });

    test('en la oficina, el día antes: la del sábado, para ver que quedó lista', () {
      final f = FiestaDeLaTele.de([_fiesta('sab', sabado)], DateTime(2026, 12, 11, 17));
      expect(f.fiesta?.id, 'sab');
    });

    test('la de anoche sigue hasta el mediodía, y a la tarde ya no', () {
      final eventos = [_fiesta('sab', sabado), _fiesta('dom', domingo)];
      expect(
        FiestaDeLaTele.de(eventos, DateTime(2026, 12, 13, 3)).fiesta?.id,
        'sab',
      );
      expect(
        FiestaDeLaTele.de(eventos, DateTime(2026, 12, 13, 15)).fiesta?.id,
        'dom',
      );
    });

    test('dos fiestas la misma noche: pregunta con el control; elegida, va esa', () {
      final eventos = [_fiesta('a', sabado), _fiesta('b', sabado)];
      final sinElegir = FiestaDeLaTele.de(eventos, DateTime(2026, 12, 12, 20));
      expect(sinElegir.hayQueElegir, isTrue);
      expect(sinElegir.fiesta, isNull);
      expect(sinElegir.paraElegir.map((e) => e.id), ['a', 'b']);
      final elegida = FiestaDeLaTele.de(eventos, DateTime(2026, 12, 12, 20), elegida: 'b');
      expect(elegida.fiesta?.id, 'b');
    });

    test('una elegida que ya pasó no se usa', () {
      final f = FiestaDeLaTele.de(
        [_fiesta('vieja', DateTime(2026, 12, 5)), _fiesta('sab', sabado)],
        DateTime(2026, 12, 12, 20),
        elegida: 'vieja',
      );
      expect(f.fiesta?.id, 'sab');
    });

    test('sin fiestas que vengan, o canceladas: ninguna', () {
      expect(FiestaDeLaTele.de(const [], DateTime(2026, 12, 12)).ninguna, isTrue);
      expect(
        FiestaDeLaTele.de(
          [_fiesta('x', sabado, estado: EstadoEvento.cancelado)],
          DateTime(2026, 12, 12),
        ).ninguna,
        isTrue,
      );
    });
  });
}
