// La personalización del tótem de cada evento (`totem_config.dart`): la casilla
// de la música, y que todo lo que la app manda al guardar exista en la nube.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/widgets/totem_config_sheet.dart';
import 'package:arguello_events/models/totem_config.dart';

const _ev = 'e0000000-0000-4000-8000-00000000000a';

void main() {
  group('la música', () {
    test('viene prendida', () {
      expect(const TotemConfig(eventoId: _ev).mostrarMusica, isTrue);
      expect(TotemConfig.defaults(_ev).mostrarMusica, isTrue);
    });

    test('una fila de antes de la 6.0.0, sin la columna, cuenta como prendida',
        () {
      expect(TotemConfig.fromJson({'evento_id': _ev}).mostrarMusica, isTrue);
      expect(
        TotemConfig.fromJson({'evento_id': _ev, 'mostrar_musica': null})
            .mostrarMusica,
        isTrue,
      );
    });

    test('apagada se guarda y se lee apagada', () {
      final cfg = const TotemConfig(eventoId: _ev).copyWith(mostrarMusica: false);
      expect(cfg.toJson()['mostrar_musica'], isFalse);
      expect(TotemConfig.fromJson(cfg.toJson()).mostrarMusica, isFalse);
    });

    test('copyWith no la toca si no se la nombra', () {
      final apagada = const TotemConfig(eventoId: _ev, mostrarMusica: false);
      expect(apagada.copyWith(titulo: 'OTRO').mostrarMusica, isFalse);
    });
  });

  group('la apariencia', () {
    test('vacía: la del tipo de evento', () {
      expect(TotemConfig.fromJson({'evento_id': _ev}).estilo, isNull);
      expect(TotemConfig.fromJson({'evento_id': _ev, 'estilo': '  '}).estilo,
          isNull);
    });

    test('se guarda y se lee', () {
      final cfg = const TotemConfig(eventoId: _ev).copyWith(estilo: 'gala');
      expect(cfg.toJson()['estilo'], 'gala');
      expect(TotemConfig.fromJson(cfg.toJson()).estilo, 'gala');
    });

    test('copyWith la conserva, y limpiarEstilo vuelve a la del tipo', () {
      const gala = TotemConfig(eventoId: _ev, estilo: 'gala');
      expect(gala.copyWith(titulo: 'OTRO').estilo, 'gala');
      expect(gala.copyWith(limpiarEstilo: true).estilo, isNull);
    });
  });

  // Guardar Personalizar es un upsert con todo lo de `toJson`: una clave sin
  // su columna en la nube hace fallar el guardado. Las columnas salen de los
  // SQL versionados.
  test('cada cosa que se guarda tiene su columna en la nube', () {
    final sql = [
      File('supabase/migracion_totem_config.sql').readAsStringSync(),
      File('supabase/migrations/20261014120000_totem_config_estilo_y_musica.sql')
          .readAsStringSync(),
    ].join('\n').toLowerCase();
    // `updated_by` y `updated_at` los pone el repositorio y el disparador.
    for (final clave in const TotemConfig(eventoId: _ev).toJson().keys) {
      expect(sql, contains(RegExp('\\b$clave\\b')), reason: clave);
    }
    expect(sql, contains('add column if not exists mostrar_musica boolean'));
    expect(sql, contains('add column if not exists estilo text'));
  });

  group('la casilla en Personalizar', () {
    testWidgets('dice qué hace y cambia al tocarla', (tester) async {
      var valor = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CasillaMusicaTotem(
                valor: valor,
                onChanged: (v) => setState(() => valor = v),
              ),
            ),
          ),
        ),
      );
      expect(find.text(CasillaMusicaTotem.titulo), findsOneWidget);
      expect(find.text(CasillaMusicaTotem.explicacion), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(valor, isFalse);
    });
  });
}
