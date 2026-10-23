// Arnés manual: "Tu fondo" de verdad (la escena, el shader de la imagen y los
// efectos) con una imagen inventada, **sin tocar la base de la PC ni la nube**.
// Sirve para mirarlo en una ventana de Windows y, sobre todo, en el navegador
// (el shader lee la imagen, y eso en la web se prueba aparte):
//
//   flutter run -d windows -t tool/tu_fondo_prueba.dart
//   flutter build web -t tool/tu_fondo_prueba.dart --no-web-resources-cdn
//       --output build/tu_fondo_web
//
// No corre `main.dart`: no abre la base local ni inicia sesión. Arriba, una
// barra para cambiar la animación y los efectos, pasar a horizontal y ver una
// llegada; dice si el shader anda o si va la imagen quieta.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_propio.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/features/totem/estilos/tu_fondo.dart';
import 'package:arguello_events/features/totem/services/contenido_bienvenida.dart';
import 'package:arguello_events/features/totem/services/lectura_del_fondo.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/fondo_de_prueba.dart';

/// Un evento inventado: no existe en la nube ni en la PC.
const _evento = 'deadbeef-0000-4000-8000-0000000f0d00';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final png = await pngDePrueba(ancho: 540, alto: 960);
  final lectura = await LecturaDelFondo.deBytes(png);
  // Antes de mostrar nada: la barra dice si el shader anda.
  await FondoPropio.precargar();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: _Prueba(png: png, lectura: lectura),
    ),
  );
}

class _Prueba extends StatefulWidget {
  final Uint8List png;
  final LecturaDelFondo lectura;

  const _Prueba({required this.png, required this.lectura});

  @override
  State<_Prueba> createState() => _PruebaState();
}

class _PruebaState extends State<_Prueba> {
  late final _fondo = MemoryImage(widget.png);
  late final _receta = widget.lectura.receta();
  late AnimacionFondo _animacion = _receta.animacion;
  late final _efectos = {..._receta.efectos};
  bool _apaisada = false;
  ContenidoBienvenida? _llegada;
  DateTime? _empezo;
  Timer? _temporizador;

  static const _ejemplo = ContenidoBienvenida(
    saludo: '¡Bienvenidos!',
    nombres: ['PÉREZ, JUAN MARTÍN'],
    conQuien: 'con GÓMEZ, ANA y PÉREZ, LUIS',
    mesa: '12',
    sillas: '10 sillas (8 + 2 extra)',
    musica: 'Tusa · Karol G',
  );

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  TotemConfig get _cfg => conLaLectura(
        const TotemConfig(
          eventoId: _evento,
          titulo: 'PROMOCIÓN 2026',
          subtitulo: 'Escuela Normal',
          estilo: 'tu_fondo',
          fondoUrl: 'https://prueba.test/fondo.png',
        ),
        widget.lectura,
        automatico: true,
      ).copyWith(
        fondoAutomatico: false,
        fondoAnimacion: _animacion.clave,
        fondoEfectos: [for (final e in _efectos) e.clave],
      );

  void _verLlegada() {
    _temporizador?.cancel();
    setState(() {
      _llegada = _ejemplo;
      _empezo = DateTime.now();
    });
    _temporizador = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _llegada = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ignore: invalid_use_of_visible_for_testing_member
    final conShader = FondoPropio.tieneShader;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Material(
            color: const Color(0xFF141414),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final a in AnimacionFondo.values)
                    ChoiceChip(
                      label: Text(a.nombre),
                      selected: _animacion == a,
                      onSelected: (_) => setState(() => _animacion = a),
                    ),
                  const SizedBox(width: 12),
                  for (final e in EfectoFondo.values)
                    FilterChip(
                      label: Text(e.nombre),
                      selected: _efectos.contains(e),
                      onSelected: (v) => setState(
                        () => v ? _efectos.add(e) : _efectos.remove(e),
                      ),
                    ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('Horizontal'),
                    selected: _apaisada,
                    onSelected: (v) => setState(() => _apaisada = v),
                  ),
                  FilledButton(
                    onPressed: _verLlegada,
                    child: const Text('Ver una llegada'),
                  ),
                  Text(
                    conShader ? 'con shader' : 'sin shader: la imagen quieta',
                    key: const ValueKey('estado_shader'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _apaisada ? 16 / 9 : 9 / 16,
                child: EscenaTotem(
                  estilo: EstiloTotem.tuFondo,
                  respaldo: EstiloTotem.neon,
                  cfg: _cfg,
                  fondo: _fondo,
                  llegada: _llegada,
                  claveLlegada: _empezo,
                  empezo: _empezo,
                  fin: _empezo?.add(const Duration(seconds: 7)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
