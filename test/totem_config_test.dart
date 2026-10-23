// La personalización del tótem de cada evento (`totem_config.dart`): la casilla
// de la música, y que todo lo que la app manda al guardar exista en la nube.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/estilos/forma_foto.dart';
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

  group('la foto del evento (6.2.1)', () {
    test('una fila de antes: la foto, en círculo y al 100 %', () {
      for (final cfg in [
        const TotemConfig(eventoId: _ev),
        TotemConfig.fromJson({'evento_id': _ev}),
        TotemConfig.fromJson({
          'evento_id': _ev,
          'mostrar_foto': null,
          'foto_forma': null,
          'foto_tamano': null,
        }),
      ]) {
        expect(cfg.mostrarFoto, isTrue);
        expect(cfg.fotoForma, isNull);
        expect(FormaFoto.de(cfg.fotoForma), FormaFoto.circulo);
        expect(cfg.fotoTamano, 100);
      }
    });

    test('se guarda y se lee como se eligió', () {
      final cfg = const TotemConfig(eventoId: _ev).copyWith(
        mostrarFoto: false,
        fotoForma: 'corazon',
        fotoTamano: 220,
      );
      final json = cfg.toJson();
      expect(json['mostrar_foto'], isFalse);
      expect(json['foto_forma'], 'corazon');
      expect(json['foto_tamano'], 220);
      final leida = TotemConfig.fromJson(json);
      expect(leida.mostrarFoto, isFalse);
      expect(FormaFoto.de(leida.fotoForma), FormaFoto.corazon);
      expect(leida.fotoTamano, 220);
    });

    test('el tamaño no pasa de los topes, venga de donde venga', () {
      expect(
        TotemConfig.fromJson({'evento_id': _ev, 'foto_tamano': 900}).fotoTamano,
        TotemConfig.fotoTamanoMaximo,
      );
      expect(
        TotemConfig.fromJson({'evento_id': _ev, 'foto_tamano': 10}).fotoTamano,
        TotemConfig.fotoTamanoMinimo,
      );
      expect(
        TotemConfig.fromJson({'evento_id': _ev, 'foto_tamano': 'basura'})
            .fotoTamano,
        100,
      );
      expect(
        const TotemConfig(eventoId: _ev).copyWith(fotoTamano: 5000).fotoTamano,
        TotemConfig.fotoTamanoMaximo,
      );
    });

    test('una forma que esta versión no conoce se dibuja como círculo y se '
        'guarda como vino', () {
      final cfg = TotemConfig.fromJson({'evento_id': _ev, 'foto_forma': 'estrella'});
      expect(FormaFoto.de(cfg.fotoForma), FormaFoto.circulo);
      expect(cfg.toJson()['foto_forma'], 'estrella');
    });

    test('copyWith y conFondoDe no la tocan si no se la nombra', () {
      const elegida = TotemConfig(
        eventoId: _ev,
        mostrarFoto: false,
        fotoForma: 'ovalo',
        fotoTamano: 150,
        textoTamano: 130,
        ubicacionX: -40,
        ubicacionY: 80,
      );
      for (final cfg in [
        elegida.copyWith(titulo: 'OTRO'),
        elegida.conFondoDe(const TotemConfig(eventoId: _ev)),
      ]) {
        expect(cfg.mostrarFoto, isFalse);
        expect(cfg.fotoForma, 'ovalo');
        expect(cfg.fotoTamano, 150);
        expect(cfg.textoTamano, 130);
        expect(cfg.ubicacionX, -40);
        expect(cfg.ubicacionY, 80);
      }
    });

    test('las frases y dónde van: vacías, como siempre; y con sus topes', () {
      final vieja = TotemConfig.fromJson({'evento_id': _ev});
      expect(vieja.textoTamano, 100);
      expect(vieja.ubicacionX, 0);
      expect(vieja.ubicacionY, 0);
      final cfg = const TotemConfig(eventoId: _ev)
          .copyWith(textoTamano: 160, ubicacionX: 100, ubicacionY: -60);
      final leida = TotemConfig.fromJson(cfg.toJson());
      expect(leida.textoTamano, 160);
      expect(leida.ubicacionX, 100);
      expect(leida.ubicacionY, -60);
      final pasada = TotemConfig.fromJson({
        'evento_id': _ev,
        'texto_tamano': 999,
        'ubicacion_x': -500,
        'ubicacion_y': 'basura',
      });
      expect(pasada.textoTamano, TotemConfig.textoTamanoMaximo);
      expect(pasada.ubicacionX, -100);
      expect(pasada.ubicacionY, 0);
    });

    test('cada forma tiene su clave, su nombre y su medida', () {
      expect(FormaFoto.values.map((f) => f.clave).toSet(), hasLength(FormaFoto.values.length));
      for (final f in FormaFoto.values) {
        expect(FormaFoto.de(f.clave), f);
        expect(f.nombre, isNotEmpty);
        final m = f.medida(100);
        expect(m.width, greaterThan(0));
        expect(m.height, greaterThan(0));
        // El contorno queda dentro de su lugar.
        final caja = f.camino(Offset.zero & m).getBounds();
        expect(caja.left, greaterThanOrEqualTo(-0.01), reason: f.clave);
        expect(caja.top, greaterThanOrEqualTo(-0.01), reason: f.clave);
        expect(caja.right, lessThanOrEqualTo(m.width + 0.01), reason: f.clave);
        expect(caja.bottom, lessThanOrEqualTo(m.height + 0.01), reason: f.clave);
      }
      expect(FormaFoto.de(null), FormaFoto.circulo);
      expect(FormaFoto.de(''), FormaFoto.circulo);
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
      File('supabase/migrations/20261023200000_totem_config_foto.sql')
          .readAsStringSync(),
    ].join('\n').toLowerCase();
    // `updated_by` y `updated_at` los pone el repositorio y el disparador.
    for (final clave in const TotemConfig(eventoId: _ev).toJson().keys) {
      expect(sql, contains(RegExp('\\b$clave\\b')), reason: clave);
    }
    expect(sql, contains('add column if not exists mostrar_musica boolean'));
    expect(sql, contains('add column if not exists estilo text'));
    // Las de la foto (6.2.1), con su tipo y su vuelta atrás escrita arriba.
    const deLaFoto = {
      'mostrar_foto': 'boolean',
      'foto_forma': 'text',
      'foto_tamano': 'smallint',
      'texto_tamano': 'smallint',
      'ubicacion_x': 'smallint',
      'ubicacion_y': 'smallint',
    };
    for (final MapEntry(key: col, value: tipo) in deLaFoto.entries) {
      expect(sql, contains('add column if not exists $col $tipo;'), reason: col);
      expect(sql, contains('drop column if exists $col;'), reason: col);
    }
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
    for (final archivo in const [
      'supabase/migrations/20261023120000_totem_config_tu_fondo.sql',
      'supabase/migrations/20261023200000_totem_config_foto.sql',
    ]) {
      final sentencias = File(archivo)
          .readAsStringSync()
          .toLowerCase()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(sentencias, isNot(contains('not null')), reason: archivo);
      expect(sentencias, isNot(contains('check')), reason: archivo);
      expect(sentencias, isNot(contains('default')), reason: archivo);
    }
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

    testWidgets('la de la foto dice qué hace y cambia al tocarla',
        (tester) async {
      var valor = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CasillaFotoTotem(
                valor: valor,
                onChanged: (v) => setState(() => valor = v),
              ),
            ),
          ),
        ),
      );
      expect(find.text(CasillaFotoTotem.titulo), findsOneWidget);
      expect(find.text(CasillaFotoTotem.explicacion), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(valor, isFalse);
    });
  });
}
