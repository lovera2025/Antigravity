// Ventana de prueba de la tele es el tótem (24-nov-2026): **la Tele 1 y la Tele
// 2 de verdad** (`PantallaTele`), con una fiesta inventada, sin tocar la base de
// la PC ni la nube.
//
// En Windows, las dos teles lado a lado en la misma ventana:
//
//   flutter build web -t lib/puesto_main.dart --no-web-resources-cdn -o <ruta absoluta>\build\puesto
//   flutter run -d windows -t tool/tele_prueba.dart
//
// - La Tele 1 prende la central de verdad en esta PC (127.0.0.1:8787) y sirve la
//   página del celular de `build/puesto`: los celulares se abren en el navegador
//   con el QR de su menú (OK, o un clic en la tele).
// - La Tele 2 la busca sola (en esta PC) y copia su lista.
// - Con `--dart-define=red=si` la central escucha en el wifi de esta PC (Windows
//   pregunta por el cortafuegos), para probar con un celular de verdad.
//
// Como APK, para la tele, el celular o el emulador (una tele por equipo):
//
//   set JUNIOR_APK_DE_PRUEBA=1
//   flutter build apk --release -t tool/tele_prueba.dart --dart-define=papel=principal
//
// con `papel=segunda` para la Tele 2. La app de prueba se llama "Junior Eventos ·
// prueba" y se instala al lado de la de verdad, nunca encima. Las dos usan la
// misma fiesta inventada: la Tele 2 encuentra a la Tele 1 por el wifi del router.
//
// Las preferencias van en memoria (no las del programa instalado), y la lista,
// los alumnos y el plano también: al cerrar se pierde lo marcado.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/direcciones_red.dart';
import 'package:arguello_events/features/tele/aparato_de_la_tele.dart';
import 'package:arguello_events/features/tele/giro_de_la_tele.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/features/tele/pantalla_tele.dart';
import 'package:arguello_events/features/tele/red_de_la_tele.dart';
import 'package:arguello_events/features/tele/tele_segunda_provider.dart';
import 'package:arguello_events/features/totem/repositories/totem_config_repository.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/puerta_en_memoria.dart';
import '../test/helpers/repo_totem_en_memoria.dart';
import 'raiz_del_proyecto.dart';

const _papel = String.fromEnvironment('papel');
const _red = String.fromEnvironment('red') == 'si';
const _comoAntes = String.fromEnvironment('fluida') == 'no';
// `--dart-define=fondo=quieto`: arranca con el fondo quieto (para medir).
const _fondoQuieto = String.fromEnvironment('fondo') == 'quieto';

final _familias = [
  ('PÉREZ, JUAN MARTÍN', ['GÓMEZ, ANA', 'PÉREZ, LUIS'], 'Tusa · Karol G'),
  ('ACOSTA, LUCÍA', <String>[], 'Despechá · Rosalía'),
  ('BENÍTEZ, TOMÁS', ['BENÍTEZ, SOL'], null),
  ('FERNÁNDEZ, MÍA', ['FERNÁNDEZ, JUAN'], 'Ella · Callejero Fino'),
  ('GARCÍA, BRUNO', <String>[], null),
  ('LÓPEZ, VALENTINA', ['LÓPEZ, CARLA'], null),
  ('TAMARINDO, TEO', <String>[], 'Quevedo · Bizarrap'),
  ('RODRÍGUEZ, CAMILA', ['RODRÍGUEZ, ANDREA', 'SOSA, PABLO'], null),
  ('SÁNCHEZ, THIAGO', <String>[], null),
  ('TORRES, MARTINA', ['TORRES, JULIO'], null),
  ('VERA, BENJAMÍN', <String>[], null),
  ('ZAPATA, ABRIL', ['ZAPATA, NORA'], 'Mon Amour · Zzoilo'),
];

/// El salón de la fiesta inventada: lleno, como uno de verdad (101 mesas en un
/// playón de 30 por 46 m), así se ve el camino desde el Ingreso hasta la mesa.
/// Armado como lo arma el jefe: el espacio con su Ingreso al fondo y después
/// ACOMODAR LAS MESAS. El camino sale del Ingreso.
ArmadoSalon _salon() => ArmarAMedida.acomodar(
      ArmarAMedida.vacio(
        const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8),
      ),
      cantidad: 101,
    ).armado;

/// La mesa de cada familia: repartidas por todo el salón, cerca y lejos del
/// Ingreso.
const _mesas = [8, 23, 37, 52, 66, 81, 95, 14, 45, 60, 74, 99];

/// Un salón para la prueba: su armado y las mesas de cada una de las 12
/// familias inventadas.
class _SalonDePrueba {
  const _SalonDePrueba(this.nombre, this.armado, this.mesas);
  final String nombre;
  final ArmadoSalon armado;
  final List<List<int>> mesas;
}

/// El inventado (101 mesas), por si no están los de verdad.
_SalonDePrueba _inventado() => _SalonDePrueba(
      'Inventado · 101 mesas',
      _salon(),
      [for (final m in _mesas) [m]],
    );

/// **Los salones de los eventos masivos de verdad** (25-nov-2026), sin nombres:
/// `tool/salones_de_verdad.py` los saca de una copia de la base y los deja en
/// `build/salones_prueba/salones.json`; el APK de prueba los trae adentro
/// (Gradle, con JUNIOR_APK_DE_PRUEBA=1). Las 12 familias inventadas se sientan
/// en las mesas de 12 familias de verdad, repartidas de la primera a la última
/// (la del fondo incluida): el camino más largo también se ve.
Future<List<_SalonDePrueba>> _salonesDeVerdad() async {
  String? texto;
  if (Platform.isAndroid) {
    texto = await AparatoDeLaTele.salonesDePrueba();
  } else {
    final f = File('${carpetaEnBuild('salones_prueba').path}${Platform.pathSeparator}salones.json');
    if (f.existsSync()) texto = await f.readAsString();
  }
  if (texto == null || texto.isEmpty) return const [];
  final lista = (jsonDecode(texto) as List).cast<Map<String, dynamic>>();
  return [
    for (final s in lista)
      if ((s['familias'] as List).length >= _familias.length)
        _SalonDePrueba(
          s['nombre'] as String,
          ArmadoSalon.fromJson(s['armado'] as Map<String, dynamic>),
          _repartidas([
            for (final f in s['familias'] as List) [for (final n in f as List) n as int],
          ]),
        ),
  ];
}

/// 12 de [familias], repartidas de la primera a la última.
List<List<int>> _repartidas(List<List<int>> familias) {
  final n = _familias.length;
  return [
    for (var i = 0; i < n; i++) familias[(i * (familias.length - 1) / (n - 1)).round()],
  ];
}

/// En el APK de prueba: qué es este aparato, y con qué salón. Con el control
/// de la tele se elige con las flechas y OK.
class _ElegirTele extends StatefulWidget {
  const _ElegirTele({required this.salones, required this.alElegir});
  final List<_SalonDePrueba> salones;
  final void Function(PapelDeLaTele, _SalonDePrueba) alElegir;

  @override
  State<_ElegirTele> createState() => _ElegirTeleState();
}

class _ElegirTeleState extends State<_ElegirTele> {
  var _salon = 0;

  @override
  Widget build(BuildContext context) {
    final salones = widget.salones;
    final elegido = salones[_salon];
    void alElegir(PapelDeLaTele papel) => widget.alElegir(papel, elegido);
    Widget boton(PapelDeLaTele papel, String detalle, {bool primero = false}) =>
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: 420,
            child: FilledButton(
              autofocus: primero,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.all(22)),
                side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
                    ? const BorderSide(color: Color(0xFFD4AF37), width: 4)
                    : BorderSide.none),
              ),
              onPressed: () => alElegir(papel),
              child: Column(
                children: [
                  Text(papel.nombre.toUpperCase(),
                      style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(detalle, textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 16)),
                ],
              ),
            ),
          ),
        );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF14122B),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('JUNIOR EVENTOS · PRUEBA DE LA TELE',
                    style: GoogleFonts.outfit(fontSize: 22, color: Colors.white70)),
                const SizedBox(height: 6),
                Text('Una fiesta inventada: no toca la base ni la nube.',
                    style: GoogleFonts.outfit(fontSize: 16, color: Colors.white54)),
                const SizedBox(height: 14),
                // El salón: los de los eventos de verdad (sin nombres), el más
                // grande primero.
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: OutlinedButton(
                    style: ButtonStyle(
                      padding: const WidgetStatePropertyAll(EdgeInsets.all(16)),
                      side: WidgetStateProperty.resolveWith((s) => BorderSide(
                            color: s.contains(WidgetState.focused)
                                ? const Color(0xFFD4AF37)
                                : Colors.white38,
                            width: s.contains(WidgetState.focused) ? 4 : 1,
                          )),
                    ),
                    onPressed: salones.length < 2
                        ? null
                        : () => setState(() => _salon = (_salon + 1) % salones.length),
                    child: Text(
                      'Salón: ${elegido.nombre}'
                      '${salones.length < 2 ? '' : '  ·  OK para cambiar (${_salon + 1} de ${salones.length})'}',
                      style: GoogleFonts.outfit(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    boton(PapelDeLaTele.principal,
                        'Lleva la lista. Los celulares escanean su QR.', primero: true),
                    boton(PapelDeLaTele.segunda,
                        'Se engancha sola a la Tele 1 por el wifi.'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El modo tele de cada tele de la prueba: fijo, sin escribir las preferencias.
class _ModoFijo extends ModoTeleNotifier {
  _ModoFijo(this.inicial);
  final ModoTele inicial;

  @override
  ModoTele? build() => inicial;

  @override
  Future<void> poner(ModoTele? modo) async => state = modo;
}

/// El giro de cada tele de la prueba: sin escribir las preferencias del
/// programa. `--dart-define=giro=1` arranca parada (el emulador).
class _GiroDePrueba extends GiroDeLaTeleNotifier {
  @override
  int build() => Giro.normal(int.tryParse(const String.fromEnvironment('giro')) ?? 0);

  @override
  Future<void> poner(int cuartos) async => state = Giro.normal(cuartos);
}

/// La escuela de cada tele de la prueba, en memoria (25-nov-2026). Con
/// `--dart-define=escuelas=distintas` la Tele 2 arranca con la escuela B.
class _FiestaDePrueba extends FiestaDeLaTeleNotifier {
  _FiestaDePrueba(this.inicial);
  final String inicial;

  @override
  String? build() => inicial;

  @override
  Future<void> elegir(String eventoId) async => state = eventoId;
}

const _escuelas = String.fromEnvironment('escuelas');

/// La segunda escuela de la noche (25-nov-2026): otras familias, con nombres
/// inventados, sentadas en otro salón.
final _familiasB = [
  ('CEIBO, MALENA', ['CEIBO, RAÚL'], 'Tusa · Karol G'),
  ('HORNERO, BRUNO', <String>[], null),
  ('JACARANDÁ, SOFÍA', ['JACARANDÁ, IRIS'], 'Ella · Callejero Fino'),
  ('ZORZAL, TOMÁS', <String>[], null),
  ('TALA, CATALINA', ['TALA, MARIO', 'QUEBRACHO, ANA'], null),
  ('CARDENAL, LUCAS', <String>[], 'Despechá · Rosalía'),
  ('ESPINILLO, ROCÍO', <String>[], null),
  ('BENTEVEO, JOAQUÍN', ['BENTEVEO, OLGA'], null),
];

/// Una tele de la prueba: su lista, sus alumnos y su central, en memoria. Con
/// las dos escuelas de la noche: la A en [elegido] y la B en [salonB].
Widget _tele(PapelDeLaTele papel, _SalonDePrueba elegido, _SalonDePrueba salonB) {
  final salon = elegido.armado;
  final alumnos = [
    for (var i = 0; i < _familias.length; i++)
      alumnoDePrueba(
        'c${i.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
        _familias[i].$1,
        mesas: elegido.mesas[i],
        acomp: _familias[i].$2,
        musica: _familias[i].$3,
        division: i < 6 ? '5° A' : '5° B',
      ),
    for (var i = 0; i < _familiasB.length; i++)
      alumnoDePrueba(
        'b${i.toString().padLeft(7, '0')}-0000-4000-8000-000000000000',
        _familiasB[i].$1,
        mesas: salonB.mesas[i],
        acomp: _familiasB[i].$2,
        musica: _familiasB[i].$3,
        division: '6° A',
        evento: eventoParticular,
      ),
  ];
  final enAndroid = Platform.isAndroid;
  final mundo = PuertaEnMemoria(
    // A ningún lado: como sin internet.
    SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba'),
    alumnos: alumnos,
    filas: <Invitado>[],
    plano: salon,
    planosDe: {eventoParticular: salonB.armado},
  // La página del celular: en el APK, la que la app copió de sí misma; en esta
  // PC, la de `build/puesto`.
  )..paginaDelCelular =
      enAndroid ? PaginaDelCelularEnAndroid.carpeta : carpetaEnBuild('puesto');
  // La central: en el wifi en una tele de verdad (o con `red=si`); en esta PC,
  // solo acá, en el puerto de siempre.
  mundo
    ..escuchaCentral = enAndroid || _red ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4
    ..puertoCentral = kPuertoCentral;
  if (enAndroid || _red) mundo.leerDirecciones = direccionesDeEstaPc;
  mundo.invitados.hora = () => DateTime.now().toUtc();
  mundo.sillasPuerta.hora = () => DateTime.now().toUtc();

  // Las dos escuelas inventadas son hoy: cada tele arranca con la suya.
  final hoy = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final inicial = papel == PapelDeLaTele.segunda && _escuelas == 'distintas'
      ? eventoParticular
      : eventoMasivo;
  return mundo.recepcion(
    // Con "Cómo anda": la prueba es para medir. La app de verdad no lo tiene.
    // `--dart-define=fluida=no`: como antes del 25-nov, para comparar.
    const PantallaTele(conDiagnostico: true, fluida: !_comoAntes),
    elegido: eventoMasivo,
    eventos: [
      Evento(
        id: eventoMasivo,
        clienteId: 'c0000000-0000-4000-8000-000000000001',
        cliente: Cliente(id: 'c0000000-0000-4000-8000-000000000001', nombreCompleto: 'ESCUELA DEL CEIBO'),
        tipo: 'Egresados',
        fechaEvento: hoy,
        estado: EstadoEvento.confirmado,
        modalidad: 'masivo',
      ),
      Evento(
        id: eventoParticular,
        clienteId: 'c0000000-0000-4000-8000-000000000002',
        cliente: Cliente(id: 'c0000000-0000-4000-8000-000000000002', nombreCompleto: 'COLEGIO DEL HORNERO'),
        tipo: 'Egresados',
        fechaEvento: hoy,
        estado: EstadoEvento.confirmado,
        modalidad: 'masivo',
      ),
    ],
    config: {
      eventoMasivo: TotemConfig.defaults(eventoMasivo),
      eventoParticular: TotemConfig.defaults(eventoParticular),
    },
    // Girada como en la app.
    builder: (context, child) => GiroDeLaApp(child: child ?? const SizedBox.shrink()),
    extra: [
      modoTeleProvider.overrideWith(() => _ModoFijo(ModoTele(papel, fondoQuieto: _fondoQuieto))),
      giroDeLaTeleProvider.overrideWith(_GiroDePrueba.new),
      fiestaDeLaTeleProvider.overrideWith(() => _FiestaDePrueba(inicial)),
      totemConfigRepositoryProvider.overrideWithValue(RepoTotemEnMemoria()),
      // En esta PC la Tele 2 pregunta solo acá; en el wifi, a toda la red.
      if (!enAndroid && !_red)
        destinosDeLaBusquedaProvider.overrideWithValue(
          () async => [InternetAddress.loopbackIPv4],
        ),
    ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ninguna ventana de prueba abre la base de la PC: si algo se escapa, falla.
  LocalDatabase.cerrarParaLaPrueba();
  // Las preferencias, en memoria: no las del programa instalado.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  GoogleFonts.config.allowRuntimeFetching = false;
  final deVerdad = await _salonesDeVerdad();
  final salones = deVerdad.isEmpty ? [_inventado()] : deVerdad;
  // En esta PC, `--dart-define=salon=N` elige otro (1, el más grande).
  final n = int.tryParse(const String.fromEnvironment('salon')) ?? 1;
  final salon = salones[(n - 1).clamp(0, salones.length - 1)];
  // La escuela B, en el salón que sigue (25-nov-2026: dos escuelas la misma noche).
  _SalonDePrueba otroDe(_SalonDePrueba s) =>
      salones.length < 2 ? s : salones[(salones.indexOf(s) + 1) % salones.length];

  if (Platform.isAndroid) {
    await PaginaDelCelularEnAndroid.preparar();
    if (_papel.isNotEmpty) {
      runApp(_tele(
        _papel == 'segunda' ? PapelDeLaTele.segunda : PapelDeLaTele.principal,
        salon,
        otroDe(salon),
      ));
      return;
    }
    // Un solo APK para la tele y el celular: al abrir, se elige qué es.
    runApp(_ElegirTele(
      salones: salones,
      alElegir: (papel, elegido) => runApp(_tele(papel, elegido, otroDe(elegido))),
    ));
    return;
  }

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B10),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final papel in PapelDeLaTele.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Text(
                          papel == PapelDeLaTele.principal
                              ? 'TELE 1 · lleva la lista (la central en 127.0.0.1:8787)'
                              : 'TELE 2 · se engancha a la Tele 1',
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                // Cada tele con lo suyo: otro "equipo".
                                child: _tele(papel, salon, otroDe(salon)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
