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
//
// Las sillas de la noche (6.4.0): las familias de número par tienen sus 2 extra
// del contrato (ya en el tope); las impares, lugar para 2. Para probar el
// candado: sumar desde dos celulares a la vez a una familia con un lugar, el
// mismo vale dos veces, quitar con motivo, y el reloj de los segundos desde el
// celular. Las sillas quedan en memoria: al cerrar se pierden.
//
// Las preferencias van en memoria (no las del programa instalado) y Personalizar
// tótem guarda en memoria. Para las capturas de la 6.9.0, con `--dart-define`:
// - `red=local`: la central escucha solo en esta PC (sin el cartel del
//   cortafuegos; los celulares de verdad no llegan). CELULARES, cambiar a la
//   fiesta "· particular" y CELULARES otra vez: "Los celulares están con otra
//   fiesta";
// - `tele=masivo`: arranca con el tótem "abierto" en el evento masivo (una
//   ventana de mentira, no se abre nada). Elegir "· particular": "El tótem está
//   con otra fiesta" (PASAR EL TÓTEM · SOLO MIRAR ACÁ);
// - `personalizar=cambio`: en Personalizar (la paleta), GUARDAR dice que lo de la
//   nube ya no es lo que se abrió; `personalizar=sin_internet`, que no pudo;
// - `sillas=2`: la línea de arriba cuenta 2 sillas de la noche sin subir.
// "Actualizar la lista" (Más) dice que no pudo: acá no hay nube.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/kiosk_launcher.dart';
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/direcciones_red.dart';
import 'package:arguello_events/features/recepcion/recepcion_unified_screen.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/totem/repositories/totem_config_repository.dart';
import 'package:arguello_events/models/invitado.dart';

import '../test/helpers/puerta_en_memoria.dart';
import '../test/helpers/repo_totem_en_memoria.dart';
import 'raiz_del_proyecto.dart';

const _redLocal = String.fromEnvironment('red') == 'local';
const _teleEn = String.fromEnvironment('tele');
const _personalizar = String.fromEnvironment('personalizar');
const _sillas = int.fromEnvironment('sillas');

/// La tele del salón, de mentira: el tótem "abierto" sin abrir ninguna ventana.
class _TeleDeMentira implements VentanasTotem {
  final _abiertas = <int>[];

  @override
  Future<dynamic> invocar(int id, String metodo, [dynamic args]) async => null;

  @override
  Future<List<int>> abiertas() async => List.of(_abiertas);

  @override
  Future<int> crear(String argumentos, {required Size tamanio, required String titulo}) async {
    _abiertas.add(1);
    return 1;
  }

  @override
  Future<void> mostrar(int id) async {}

  @override
  Future<void> esconder(int id) async {}
}

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
  // Ninguna ventana de prueba abre la base de la PC: si algo se escapa, falla.
  LocalDatabase.cerrarParaLaPrueba();
  // Las preferencias, en memoria: no las del programa instalado.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
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
  )..paginaDelCelular = carpetaEnBuild('puesto');
  if (!_redLocal) {
    mundo
      ..escuchaCentral = InternetAddress.anyIPv4
      ..puertoCentral = kPuertoCentral
      ..leerDirecciones = direccionesDeEstaPc;
  }
  mundo.sinInternet.sillasSinSubir = _sillas;
  mundo.invitados.hora = () => DateTime.now().toUtc();
  mundo.sillasPuerta.hora = () => DateTime.now().toUtc();

  if (_teleEn.isNotEmpty) {
    // ignore: invalid_use_of_visible_for_testing_member
    KioskLauncher.ventanas = _TeleDeMentira();
    await KioskLauncher.launch(_teleEn == 'particular' ? eventoParticular : eventoMasivo);
  }

  runApp(mundo.recepcion(
    const RecepcionUnifiedScreen(),
    elegido: eventoMasivo,
    extra: [
      totemConfigRepositoryProvider.overrideWithValue(RepoTotemEnMemoria()
        ..cambioEnLaNube = _personalizar == 'cambio'
        ..fallar = _personalizar == 'sin_internet'),
    ],
  ));
}
