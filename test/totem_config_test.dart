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

  group('"Tu fondo"', () {
    const conFondo = TotemConfig(
      eventoId: _ev,
      estilo: 'tu_fondo',
      fondoUrl: 'https://x.test/totem/e/fondo.jpg?v=1',
      fondoAutomatico: false,
      fondoAnimacion: 'ondular',
      fondoEfectos: ['titileo', 'bruma'],
      fondoIntensidad: 30,
      fondoIntensidadEfectos: 70,
      fondoOscurecer: 20,
      fondoPaleta: [Color(0xFF9CC3FF), Color(0xFFFFCE8C), Color(0xFF193770)],
      fondoFoco: Offset(0.75, 0.19),
      fondoLetras: 'moderna',
      fondoLuz: 15,
    );

    test('una fila de antes, sin las columnas: sin fondo y lo de siempre', () {
      final vieja = TotemConfig.fromJson({'evento_id': _ev, 'estilo': 'gala'});
      expect(vieja.fondoUrl, isNull);
      expect(vieja.fondoAutomatico, isTrue);
      expect(vieja.fondoAnimacion, isNull);
      expect(vieja.fondoEfectos, isNull);
      expect(vieja.fondoIntensidad, TotemConfig.intensidadPorDefecto);
      expect(vieja.fondoIntensidadEfectos,
          TotemConfig.intensidadEfectosPorDefecto);
      expect(vieja.fondoOscurecer, TotemConfig.oscurecerPorDefecto);
      expect(vieja.fondoPaleta, isNull);
      expect(vieja.fondoFoco, isNull);
      expect(vieja.fondoLetras, isNull);
      expect(vieja.fondoLuz, isNull);
      // Y las columnas vacías dan lo mismo.
      final vacias = TotemConfig.fromJson({
        'evento_id': _ev,
        for (final k in conFondo.toJson().keys)
          if (k.startsWith('fondo_')) k: null,
      }).toJson();
      final deVieja = vieja.toJson();
      for (final k in deVieja.keys.where((k) => k.startsWith('fondo_'))) {
        expect(vacias[k], deVieja[k], reason: k);
      }
    });

    test('ida y vuelta, también por la caché', () {
      final json = conFondo.toJson();
      expect(json['fondo_efectos'], 'titileo,bruma');
      expect(json['fondo_paleta'], '#9CC3FF,#FFCE8C,#193770');
      expect(json['fondo_foco'], '0.750,0.190');
      final leida = TotemConfig.fromJson(json);
      expect(leida.toJson(), json);
      expect(leida.fondoPaleta, conFondo.fondoPaleta);
      expect(leida.fondoFoco, const Offset(0.75, 0.19));
    });

    test('sin efectos se guarda vacío, que no es lo mismo que nunca elegidos',
        () {
      final sin = conFondo.copyWith(fondoEfectos: const []);
      expect(sin.toJson()['fondo_efectos'], '');
      expect(TotemConfig.fromJson(sin.toJson()).fondoEfectos, isEmpty);
    });

    test('lo que esta versión no conoce se guarda como vino', () {
      final nueva = TotemConfig.fromJson({
        'evento_id': _ev,
        'fondo_animacion': 'remolino',
        'fondo_efectos': 'destellos,confeti',
        'fondo_letras': 'gotica',
      });
      expect(nueva.toJson()['fondo_animacion'], 'remolino');
      expect(nueva.toJson()['fondo_efectos'], 'destellos,confeti');
      expect(nueva.toJson()['fondo_letras'], 'gotica');
    });

    test('fuera de rango se acota y la basura no rompe nada', () {
      final rara = TotemConfig.fromJson({
        'evento_id': _ev,
        'fondo_intensidad': 250,
        'fondo_intensidad_efectos': -4,
        'fondo_oscurecer': 95,
        'fondo_luz': 300,
        'fondo_paleta': '#FFF,rojo,#000000',
        'fondo_foco': 'mitad',
        'fondo_url': '   ',
      });
      expect(rara.fondoIntensidad, 100);
      expect(rara.fondoIntensidadEfectos, 0);
      expect(rara.fondoOscurecer, TotemConfig.oscurecerMaximo);
      expect(rara.fondoLuz, 100);
      expect(rara.fondoPaleta, isNull);
      expect(rara.fondoFoco, isNull);
      expect(rara.fondoUrl, isNull);
      expect(
        TotemConfig.leerFoco('1.4,-0.2'),
        const Offset(1, 0),
      );
      expect(const TotemConfig(eventoId: _ev).copyWith(fondoOscurecer: 99)
          .fondoOscurecer, TotemConfig.oscurecerMaximo);
    });

    test('quitar el fondo deja la receta, y conFondoDe la copia entera', () {
      final sin = conFondo.copyWith(limpiarFondo: true);
      expect(sin.fondoUrl, isNull);
      expect(sin.fondoAnimacion, 'ondular');
      final otra = const TotemConfig(eventoId: _ev, titulo: 'OTRO')
          .conFondoDe(conFondo);
      expect(otra.titulo, 'OTRO');
      final a = otra.toJson(), b = conFondo.toJson();
      for (final k in b.keys.where((k) => k.startsWith('fondo_'))) {
        expect(a[k], b[k], reason: k);
      }
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
      File('supabase/migrations/20261023120000_totem_config_tu_fondo.sql')
          .readAsStringSync(),
    ].join('\n').toLowerCase();
    // `updated_by` y `updated_at` los pone el repositorio y el disparador.
    for (final clave in const TotemConfig(eventoId: _ev).toJson().keys) {
      expect(sql, contains(RegExp('\\b$clave\\b')), reason: clave);
    }
    expect(sql, contains('add column if not exists mostrar_musica boolean'));
    expect(sql, contains('add column if not exists estilo text'));
    // Las de "Tu fondo", con su tipo y su vuelta atrás escrita arriba.
    const tipos = {
      'fondo_url': 'text',
      'fondo_automatico': 'boolean',
      'fondo_animacion': 'text',
      'fondo_efectos': 'text',
      'fondo_intensidad': 'smallint',
      'fondo_intensidad_efectos': 'smallint',
      'fondo_oscurecer': 'smallint',
      'fondo_paleta': 'text',
      'fondo_foco': 'text',
      'fondo_letras': 'text',
      'fondo_luz': 'smallint',
    };
    expect(
      const TotemConfig(eventoId: _ev)
          .toJson()
          .keys
          .where((k) => k.startsWith('fondo_'))
          .toSet(),
      tipos.keys.toSet(),
    );
    for (final MapEntry(key: col, value: tipo) in tipos.entries) {
      expect(sql, contains('add column if not exists $col $tipo;'), reason: col);
      expect(sql, contains('drop column if exists $col;'), reason: col);
    }
    // Sin NOT NULL ni CHECK: una fila vieja nunca hace fallar un guardado.
    final fondo = File(
      'supabase/migrations/20261023120000_totem_config_tu_fondo.sql',
    ).readAsStringSync().toLowerCase();
    final sentencias = fondo
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');
    expect(sentencias, isNot(contains('not null')));
    expect(sentencias, isNot(contains('check')));
    expect(sentencias, isNot(contains('default')));
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
