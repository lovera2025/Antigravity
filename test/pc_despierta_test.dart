// Que la notebook no se duerma mientras trabaja sola (revisión del 13-nov):
// la tele del salón y las centrales dependen de una PC que nadie toca en toda
// la noche. El aviso a Windows de verdad no corre en las pruebas.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/services/pc_despierta.dart';

void main() {
  group('PcDespierta', () {
    testWidgets('prendida, avisa en el momento y después cada 30 segundos',
        (tester) async {
      var avisos = 0;
      final pc = PcDespierta(avisar: () => avisos++);
      expect(pc.prendida, isFalse);

      pc.mantener(true);
      expect(pc.prendida, isTrue);
      expect(avisos, 1, reason: 'no espera 30 s para el primero');

      await tester.pump(const Duration(seconds: 29));
      expect(avisos, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(avisos, 2);
      await tester.pump(const Duration(minutes: 5));
      expect(avisos, 12);

      pc.mantener(false);
    });

    testWidgets('apagada, no avisa más', (tester) async {
      var avisos = 0;
      final pc = PcDespierta(avisar: () => avisos++)..mantener(true);
      pc.mantener(false);
      expect(pc.prendida, isFalse);
      await tester.pump(const Duration(minutes: 10));
      expect(avisos, 1);
    });

    testWidgets('prenderla dos veces no arma dos relojes', (tester) async {
      var avisos = 0;
      final pc = PcDespierta(avisar: () => avisos++)
        ..mantener(true)
        ..mantener(true);
      expect(avisos, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(avisos, 2);
      pc.mantener(false);
    });

    test('se avisa más seguido que el minuto que Windows deja poner', () {
      expect(kCadaCuantoSeAvisa, lessThan(const Duration(minutes: 1)));
    });
  });

  group('quién la mantiene despierta', () {
    // En Windows el archivo puede venir con \r\n.
    String leer(String ruta) =>
        File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

    test('la ventana de la tele: a la vista sí, escondida no', () {
      final f = leer('lib/features/totem/totem_display.dart');
      // Solo en su propia ventana (con `windowId`), no en la web ni en la ruta.
      final enSuVentana = f.substring(f.indexOf('if (widget.windowId != null) {'));
      expect(
        enSuVentana.substring(0, enSuVentana.indexOf('_esperarFicha();')),
        contains('..mantener(true)'),
      );
      String cuerpoDe(String firma) {
        final desde = f.indexOf(firma);
        expect(desde, isNot(-1), reason: firma);
        return f.substring(desde, f.indexOf('\n  }\n', desde));
      }

      expect(cuerpoDe('Future<void> _pausar() async {'),
          contains('_despierta?.mantener(false)'));
      expect(cuerpoDe('void _reanudar() {'),
          contains('_despierta?.mantener(true)'));
      expect(cuerpoDe('void dispose() {'),
          contains('_despierta?.mantener(false)'));
    });

    for (final (nombre, ruta) in [
      ('la central de la puerta', 'lib/features/recepcion/central/central_provider.dart'),
      ('la central de la barra', 'lib/features/barra/central/central_barra_provider.dart'),
    ]) {
      test('$nombre: prendida sí, apagada no', () {
        final f = leer(ruta);
        // Las dos centrales ya reciben algo más que la fiesta (la tele, la barra).
        final prender = f.substring(f.indexOf('Future<void> prender(String eventoId'));
        expect(
          prender.substring(0, prender.indexOf('Future<void> reanudar(')),
          contains('_despierta?.mantener(true)'),
        );
        final soltar = f.substring(f.indexOf('Future<void> _soltar() async {'));
        expect(soltar.substring(0, soltar.indexOf('\n  }\n')),
            contains('_despierta?.mantener(false)'));
      });
    }

    test('en la web no se toca nada del sistema', () {
      final f = leer('lib/core/services/pc_despierta.dart');
      expect(f, contains("if (dart.library.ffi) 'pc_despierta_windows.dart'"));
      expect(f, isNot(contains("import 'dart:ffi'")));
      expect(f, isNot(contains("import 'dart:io'")));
    });
  });
}
