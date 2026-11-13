// La prueba de punta a punta del link del delegado (6.8.0), para el navegador.
//
// Es **la página de verdad y la ventana de verdad**, hablando con el Postgres
// de prueba de `tool/delegado_sandbox/` en vez de con la nube: el cliente de
// Supabase apunta a esta misma dirección, y el servidor del sandbox contesta
// `/rest/v1/rpc/…` corriendo el SQL de la migración. No toca la base de la PC
// ni la nube de verdad.
//
//   flutter build web -t tool/link_delegado_prueba.dart \
//     --output build/link_delegado_prueba --no-web-resources-cdn
//   node tool/delegado_sandbox/servidor.mjs
//
//   http://localhost:8800/?panel                 lo que hace de programa
//   http://localhost:8801/?delegado&clave=…      un celular (8802 y 8803, otros)
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/dashboard/widgets/alertas_del_delegado.dart';
import 'package:arguello_events/features/delegado/datos/link_del_delegado.dart';
import 'package:arguello_events/features/delegado/delegado_providers.dart';
import 'package:arguello_events/features/delegado/pagina/delegado_app.dart';
import 'package:arguello_events/features/eventos/widgets/acompanantes_musica_dialog.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/models/contrato_alumno.dart';

const _fiestaId = 'aaaaaaaa-0000-4000-8000-000000000001';
const _fiesta = 'Escuela Normal · Promo 2026';

void main() {
  // Solo de la prueba: deja la pantalla legible para quien la maneja desde
  // afuera (el navegador de la app), sin tener que prenderlo a mano.
  // Con `&sinlectura` en la dirección queda como en un celular cualquiera:
  // la lectura de pantalla prendida cambia cómo se mueve una lista.
  WidgetsFlutterBinding.ensureInitialized();
  if (!Uri.base.toString().contains('sinlectura')) {
    SemanticsBinding.instance.ensureSemantics();
  }

  final aca = Uri.base.origin;
  // Sin usuario, como el celular del delegado; y con usuario, como el programa.
  // El servidor del sandbox toma por "con usuario" al que manda la clave `jefe`.
  final anonimo = SupabaseClient(aca, 'anon');
  final jefe = SupabaseClient(aca, 'jefe');

  if (Uri.base.toString().contains('delegado')) {
    runApp(
      ProviderScope(
        overrides: [supabaseProvider.overrideWithValue(anonimo)],
        child: DelegadoApp(clave: Uri.base.queryParameters['clave'] ?? ''),
      ),
    );
    return;
  }
  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(jefe),
        connectivityServiceProvider.overrideWithValue(ConnectivityService()),
      ],
      child: MaterialApp(
        title: 'Prueba del link del delegado',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        // Como el programa: los selectores de día y hora, en castellano.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es', 'AR')],
        locale: const Locale('es', 'AR'),
        home: _Programa(nube: jefe),
      ),
    ),
  );
}

/// Lo que hace de programa: las alertas del inicio, la ventana de PLANILLAS →
/// "Acompañantes y música" (la de verdad) y la grilla de la fiesta.
class _Programa extends ConsumerStatefulWidget {
  final SupabaseClient nube;
  const _Programa({required this.nube});

  @override
  ConsumerState<_Programa> createState() => _ProgramaState();
}

class _ProgramaState extends ConsumerState<_Programa> {
  List<ContratoAlumno> _grilla = const [];

  @override
  void initState() {
    super.initState();
    _leerGrilla();
  }

  Future<void> _leerGrilla() async {
    final filas = await widget.nube.rpc(
      'sandbox_grilla',
      params: {'p_evento': _fiestaId},
    ) as List;
    if (!mounted) return;
    setState(() {
      _grilla = [
        for (final f in filas.cast<Map>())
          ContratoAlumno(
            id: f['id'] as String,
            eventoId: _fiestaId,
            nombreAlumno: f['nombre'] as String,
            cantidadAcompanantes: (f['acompanantes'] as List).length,
            nombresAcompanantes: [for (final n in f['acompanantes'] as List) '$n'],
            montoTotalPactado: 0,
            saldoDeudor: 0,
            cursoDivision: f['division'] as String?,
            musicaElegida: (f['musica'] as String?)?.isEmpty ?? true
                ? null
                : f['musica'] as String,
          ),
      ];
    });
  }

  Future<void> _actualizar() async {
    ref.invalidate(avisosDelDelegadoProvider);
    await _leerGrilla();
  }

  /// PLANILLAS → "Acompañantes y música". Con [traer], como llegando desde la
  /// alerta: directo en la revisión.
  Future<void> _abrir({bool traer = false}) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AcompanantesMusicaDialog(
        eventoId: _fiestaId,
        institucion: _fiesta,
        alumnos: _grilla,
        onGuardarArchivo: (_, _) async => false,
        onElegirArchivo: () async => null,
        // Guarda en la grilla de mentira, con la misma regla del programa:
        // del alumno, solo acompañantes y música, y solo lo que cambia.
        onImportar: (cambios) async {
          await widget.nube.rpc(
            'sandbox_guardar',
            params: {
              'p_evento': _fiestaId,
              'p_datos': [
                for (final c in cambios)
                  {
                    'alumno_id': c.alumno.id,
                    if (c.acompanantes != null) 'acompanantes': c.acompanantes,
                    if (c.musica != null) 'musica': c.musica,
                  },
              ],
            },
          );
          return null;
        },
        link: ref.read(linkDelDelegadoProvider),
        urlDelLink: (clave) =>
            '${Uri.base.origin.replaceFirst(':8800', ':8801')}/?delegado&clave=$clave',
        traerAlAbrir: traer,
        onTrajo: () => ref.invalidate(avisosDelDelegadoProvider),
      ),
    );
    await _actualizar();
  }

  @override
  Widget build(BuildContext context) {
    final avisos = ref.watch(avisosDelDelegadoProvider).value ??
        const <AvisoDelDelegado>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba: lo que hace de programa'),
        actions: [
          TextButton(
            key: const Key('prueba_actualizar'),
            onPressed: _actualizar,
            child: const Text('ACTUALIZAR'),
          ),
          TextButton(
            key: const Key('prueba_reiniciar'),
            onPressed: () async {
              await widget.nube.rpc(
                'sandbox_reiniciar',
                params: const <String, dynamic>{},
              );
              await _actualizar();
            },
            child: const Text('EMPEZAR DE NUEVO'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('ALERTAS', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (avisos.isEmpty)
            const Text(
              'Todo bajo control: no hay nada para traer.',
              key: Key('prueba_sin_alertas'),
            )
          else
            // La alerta de verdad. En el programa abre la fiesta; acá, que no
            // hay fiesta que abrir, abre la misma ventana en la revisión.
            GestureDetector(
              key: const Key('prueba_alerta'),
              onTap: () => _abrir(traer: true),
              child: const AbsorbPointer(child: AlertasDelDelegado()),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              key: const Key('prueba_planillas'),
              onPressed: _abrir,
              icon: const Icon(Icons.music_note_outlined),
              label: const Text('PLANILLAS → Acompañantes y música'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'LA GRILLA DE $_fiesta'.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Table(
            key: const Key('prueba_grilla'),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(3),
              3: FlexColumnWidth(4),
            },
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: Theme.of(context).dividerColor),
            ),
            children: [
              const TableRow(
                children: [
                  _Celda('Alumno', titulo: true),
                  _Celda('División', titulo: true),
                  _Celda('Acompañantes', titulo: true),
                  _Celda('Música', titulo: true),
                ],
              ),
              for (final a in _grilla)
                TableRow(
                  children: [
                    _Celda(a.nombreAlumno),
                    _Celda(a.cursoDivision ?? ''),
                    _Celda(a.nombresAcompanantes.join(' · ')),
                    _Celda(a.musicaElegida ?? ''),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Celda extends StatelessWidget {
  final String texto;
  final bool titulo;
  const _Celda(this.texto, {this.titulo = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 13,
            fontWeight: titulo ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
}
