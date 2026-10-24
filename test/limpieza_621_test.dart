// La limpieza de la 6.2.1 (23-oct-2026): lo que se sacó no vuelve y lo que
// quedó sigue en su lugar. Lee las fuentes, como `solo_modo_jefe_test.dart`:
// Mi Empresa y el menú de la nube no se pueden montar sin la base.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/cotizacion/widgets/generar_qr_dialog.dart';
import 'package:arguello_events/main.dart' show kWebBaseUrl;

String _leer(String ruta) => File(ruta).readAsStringSync();

void main() {
  group('Mi Empresa', () {
    final fuente = _leer('lib/features/mi_empresa/finanzas_view.dart');

    test('queda con FINANZAS y COBRO, sin OPERADORES ni PRESUPUESTOS', () {
      expect(fuente, contains("text: 'FINANZAS'"));
      expect(fuente, contains("text: 'COBRO'"));
      expect(fuente, isNot(contains("text: 'OPERADORES'")));
      expect(fuente, isNot(contains("text: 'PRESUPUESTOS'")));
      expect(fuente, contains('TabController(length: 2'));
      expect(fuente, isNot(contains('PresupuestosScreen')));
      expect(fuente, isNot(contains('permisos_usuario')));
    });

    test('Saneamiento pide el PIN otra vez antes de abrirse', () {
      final i = fuente.indexOf('const SmartPurgeDialog()');
      expect(i, greaterThan(0));
      final antes = fuente.substring(i - 400, i);
      expect(antes, contains('forceVerification: true'));
    });

    test('el perdón por curso reemplaza a "Restaurar mora"', () {
      expect(fuente, contains('const PerdonarMoraPorCursoDialog()'));
      expect(fuente, isNot(contains('RestaurarMoraDialog')));
      expect(
        File('lib/features/mi_empresa/widgets/restaurar_mora_dialog.dart')
            .existsSync(),
        isFalse,
      );
    });
  });

  group('Perdonar mora (por curso)', () {
    final dialogo =
        _leer('lib/features/mi_empresa/widgets/perdonar_mora_por_curso_dialog.dart');

    test('es solo el perdón: sin restaurar, sin tocar el Reg', () {
      expect(dialogo, contains("'Perdonar mora (por curso)'"));
      // El comentario de arriba cuenta qué se sacó; lo que se ve no lo nombra.
      expect(dialogo, isNot(contains("'Restaurar")));
      expect(dialogo, isNot(contains("'Individual'")));
      expect(dialogo, isNot(contains('TabBar')));
      // Mover el Reg (`created_at`) causó lo de TOÑANEZ; restaurar en masa
      // contaba dos veces la mora.
      expect(dialogo, isNot(contains('created_at')));
      expect(dialogo, isNot(contains('restaurarMoraBulk')));
      expect(dialogo, contains('perdonarMoraBulk'));
    });

    test('el repositorio ya no restaura mora en masa', () {
      final repo = _leer('lib/features/eventos/repositories/contratos_repository.dart');
      expect(repo, isNot(contains('restaurarMoraBulk')));
      expect(repo, isNot(contains('listarCandidatosRestauracionMora')));
      expect(repo, contains('Future<int> perdonarMoraBulk('));
    });
  });

  group('el QR de cotizar', () {
    test('lleva a la web de hoy, no a la de Firebase', () {
      expect(kLinkCotizar, '$kWebBaseUrl/?cotizar');
      expect(kLinkCotizar, isNot(contains('web.app')));
      // `main.dart` elige el catálogo con `contains('cotizar')`.
      expect(kLinkCotizar, contains('cotizar'));
    });

    test('sin el campo de prueba local', () {
      final qr = _leer('lib/features/cotizacion/widgets/generar_qr_dialog.dart');
      expect(qr, isNot(contains('HOST / IP')));
    });
  });

  group('el menú de la nube', () {
    final menu = _leer('lib/features/common/widgets/sync_menu_sheet.dart');

    test('sin "Verificar nube" ni "Subir y bajar"', () {
      expect(menu, isNot(contains("'Verificar nube'")));
      expect(menu, isNot(contains("'Subir y bajar'")));
      expect(menu, contains("'Subir pendientes'"));
      expect(menu, contains("'Bajar cambios'"));
    });

    test('"Pull completo forzado" solo en modo jefe', () {
      final i = menu.indexOf("'Pull completo forzado'");
      expect(i, greaterThan(0));
      expect(menu.substring(i - 300, i), contains('if (esJefe)'));
      expect(menu, contains('ref.read(esRolJefeProvider)'));
    });

    test('ya no dice que la nube es manual', () {
      expect(menu, isNot(contains('nube manual')));
    });
  });

  test('Saneamiento arranca sin nada tildado', () {
    final purga = _leer('lib/features/mi_empresa/widgets/smart_purge_dialog.dart');
    expect(purga, isNot(contains('Seleccionar todo por defecto')));
    expect(purga, contains('_selectedIds[entry.key] = <String>{};'));
  });

  test('el Centro de Comando dice EVENTOS, no NUEVO EVENTO', () {
    final dash = _leer('lib/features/dashboard/dashboard_screen.dart');
    expect(dash, isNot(contains("label: 'NUEVO EVENTO'")));
    expect(dash, contains("label: 'EVENTOS'"));
  });
}
