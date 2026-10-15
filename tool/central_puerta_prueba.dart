// Arnés manual de la sección 7: la Recepción de verdad con un evento masivo
// inventado, para probar "Sumar un celular" con un celular de verdad **sin
// tocar la base de la PC ni la nube**.
//
//   flutter build web -t lib/puesto_main.dart --no-web-resources-cdn -o <ruta absoluta>\build\puesto
//   flutter run -d windows -t tool/central_puerta_prueba.dart
//
// No corre `main.dart`: no abre la base local (así la v73 no migra nada), no
// inicia sesión y la nube apunta a ningún lado. La lista de la puerta, los
// alumnos y la vista del tótem van en memoria (los mismos reemplazos que las
// pruebas, `test/helpers/puerta_en_memoria.dart`). La central sí es la de
// verdad: escucha en el wifi de esta PC (Windows pregunta por el cortafuegos la
// primera vez) y sirve la página de `build/puesto`.
//
// CELULARES (arriba a la derecha) abre la ventana con el QR. El celular tiene
// que estar en el mismo wifi que la PC.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/direcciones_red.dart';
import 'package:arguello_events/features/recepcion/recepcion_unified_screen.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/invitado.dart';

import '../test/helpers/puerta_en_memoria.dart';

final _familias = [
  ('PÉREZ, JUAN MARTÍN', ['GÓMEZ, ANA', 'PÉREZ, LUIS'], 'Tusa · Karol G'),
  ('ACOSTA, LUCÍA', <String>[], 'Despechá · Rosalía'),
  ('BENÍTEZ, TOMÁS', ['BENÍTEZ, SOL'], null),
  ('FERNÁNDEZ, MÍA', ['FERNÁNDEZ, JUAN'], 'Ella · Callejero Fino'),
  ('GARCÍA, BRUNO', <String>[], null),
  ('LÓPEZ, VALENTINA', ['LÓPEZ, CARLA'], null),
  ('MARTÍNEZ, LAUTARO', <String>[], 'Quevedo · Bizarrap'),
  ('RODRÍGUEZ, CAMILA', ['RODRÍGUEZ, ANDREA', 'SOSA, PABLO'], null),
  ('SÁNCHEZ, THIAGO', <String>[], null),
  ('TORRES, MARTINA', ['TORRES, JULIO'], null),
  ('VERA, BENJAMÍN', <String>[], null),
  ('ZAPATA, ABRIL', ['ZAPATA, NORA'], 'Mon Amour · Zzoilo'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final alumnos = [
    for (var i = 0; i < _familias.length; i++)
      alumnoDePrueba(
        'c${i.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
        _familias[i].$1,
        mesas: [10 + i],
        sillas: i.isEven ? 2 : 0,
        acomp: _familias[i].$2,
        musica: _familias[i].$3,
        division: i < 6 ? '5° A' : '5° B',
      ),
  ];
  // La primera familia ya entró.
  final yaAdentro = idInvitadoPuerta(alumnos.first.id, 0);
  final mundo = PuertaEnMemoria(
    // A ningún lado: como sin internet.
    SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba'),
    alumnos: alumnos,
    filas: [
      Invitado(
        id: yaAdentro,
        eventoId: eventoMasivo,
        nombreCompleto: alumnos.first.nombreAlumno,
        dni: '',
        estadoIngreso: EstadoIngreso.ingresado,
        updatedAt: DateTime.now().toUtc(),
      ),
    ],
  )
    ..escuchaCentral = InternetAddress.anyIPv4
    ..puertoCentral = kPuertoCentral
    ..leerDirecciones = direccionesDeEstaPc
    ..paginaDelCelular = Directory('build${Platform.pathSeparator}puesto');
  mundo.invitados.hora = () => DateTime.now().toUtc();

  runApp(mundo.recepcion(
    const RecepcionUnifiedScreen(),
    elegido: eventoMasivo,
  ));
}
