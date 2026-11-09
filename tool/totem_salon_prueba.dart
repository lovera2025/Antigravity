// La noche de un evento masivo ya sorteado, en una ventana: Recepción con la
// lista a la izquierda y el tótem de esta PC a la derecha, con el salón de la
// Normal (el de `ArmadosPredefinidos.normal2aPagina3`). Al tocar "Ingresar" en
// una familia, el tótem hace lo de la noche: el nombre salta en grande, se
// acomoda en la pista, la mesa se enciende y se dibuja el camino desde el
// Ingreso. Para mirar la animación y los tiempos de verdad, que las muestras
// (fotos quietas) no muestran.
//
//   flutter run -d windows -t tool/totem_salon_prueba.dart
//
// Sin la base de la PC ni la nube: la lista, los alumnos y el plano van en
// memoria, con los mismos reemplazos que las pruebas
// (`test/helpers/puerta_en_memoria.dart`), y la hora es la de verdad.
// --dart-define=estilo=gala (neon, cristal, poster, gala) cambia la apariencia.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/recepcion/recepcion_unified_screen.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/puerta_en_memoria.dart';

const _estilo = String.fromEnvironment('estilo');

final _familias = [
  ('PÉREZ, JUAN MARTÍN', ['GÓMEZ, ANA', 'PÉREZ, LUIS'], 'Tusa · Karol G', 12),
  ('ACOSTA, LUCÍA', <String>[], 'Despechá · Rosalía', 3),
  ('BENÍTEZ, TOMÁS', ['BENÍTEZ, SOL'], null, 26),
  ('FERNÁNDEZ, MÍA', ['FERNÁNDEZ, JUAN'], 'Ella · Callejero Fino', 47),
  ('GARCÍA, BRUNO', <String>[], null, 53),
  ('LÓPEZ, VALENTINA', ['LÓPEZ, CARLA'], null, 74),
  ('MARTÍNEZ, LAUTARO', <String>[], 'Quevedo · Bizarrap', 31),
  ('RODRÍGUEZ, CAMILA', ['RODRÍGUEZ, ANDREA', 'SOSA, PABLO'], null, 60),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await cargarFuentesTotem();

  final alumnos = [
    for (var i = 0; i < _familias.length; i++)
      alumnoDePrueba(
        'c${i.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
        _familias[i].$1,
        mesas: [_familias[i].$4],
        acomp: _familias[i].$2,
        musica: _familias[i].$3,
        division: i < 4 ? '5° A' : '5° B',
      ),
  ];
  final mundo = PuertaEnMemoria(
    // A ningún lado: como sin internet.
    SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba'),
    alumnos: alumnos,
    plano: ArmadosPredefinidos.normal2aPagina3(),
  );
  mundo.invitados.hora = () => DateTime.now().toUtc();
  mundo.sillasPuerta.hora = () => DateTime.now().toUtc();

  runApp(mundo.recepcion(
    const RecepcionUnifiedScreen(),
    elegido: eventoMasivo,
    config: {
      eventoMasivo: TotemConfig(
        eventoId: eventoMasivo,
        titulo: 'PROMOCIÓN 2026',
        subtitulo: 'Escuela Normal',
        estilo: _estilo.isEmpty ? null : _estilo,
      ),
    },
  ));
}
