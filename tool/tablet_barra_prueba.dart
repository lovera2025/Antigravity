// La cajera de la barra en un celular o una tablet de verdad, **por el wifi de verdad**
// (etapa 9): la barra en memoria, sin base y sin nube, la impresora por Bluetooth y la
// central de la barra que se busca sola por la red, como en el salón. Al cerrar se olvida
// todo; no escribe nada en la nube.
//
//   flutter build apk --release --split-per-abi -t tool/tablet_barra_prueba.dart
//
// En la PC, la notebook: `flutter run -d windows -t tool/central_barra_prueba.dart
// --dart-define=red=todas` (BARRA → CAJAS → PRENDER LA CENTRAL; permitir en el cartel del
// cortafuegos). El celular y la PC, en el mismo wifi. En el celular: PIN 3333 (Lucía),
// PUERTO VIEJO, abrir la caja y vender. Si no la encuentra sola, tocar la línea de la
// central en VENDER y escribir la dirección que muestra la notebook.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';

import 'salon_de_barra_prueba.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nada queda guardado en el celular: ni la impresora elegida ni la central.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final celular = armarEquipo(
    id: 'celular-de-prueba',
    nombre: 'CELULAR',
    catalogo: catalogoDePrueba(),
    eventos: fiestasDePrueba(),
    red: RedDePrueba.delSalon,
    cajera: 'Lucía',
    pin: '3333',
  );
  runApp(_PruebaDelCelular(celular));
}

class _PruebaDelCelular extends StatefulWidget {
  const _PruebaDelCelular(this.equipo);

  final EquipoDePrueba equipo;

  @override
  State<_PruebaDelCelular> createState() => _PruebaDelCelularState();
}

class _PruebaDelCelularState extends State<_PruebaDelCelular> {
  Timer? _subida;
  bool _hayInternet = true;

  @override
  void initState() {
    super.initState();
    // Con "internet", cada dos segundos todo "sube" (como la cola de subida de la app).
    _subida = Timer.periodic(const Duration(seconds: 2), (_) => _subir());
  }

  @override
  void dispose() {
    _subida?.cancel();
    widget.equipo.container.dispose();
    super.dispose();
  }

  void _subir() {
    if (!_hayInternet) return;
    final e = widget.equipo;
    e.barra.subioTodo();
    if (e.container.exists(puestaAlDiaBarraProvider)) {
      unawaited(e.container.read(puestaAlDiaBarraProvider).recontar());
    }
  }

  void _cambiarInternet() {
    setState(() => _hayInternet = !_hayInternet);
    final e = widget.equipo;
    e.conexion.cambiar(_hayInternet ? AppConnectivity.online : AppConnectivity.offline);
    if (e.container.exists(puestaAlDiaBarraProvider)) {
      e.container.read(puestaAlDiaBarraProvider).conexion(_hayInternet);
    }
    _subir();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: widget.equipo.container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Prueba de la barra',
        builder: (context, nav) => Column(
          children: [
            Material(
              color: const Color(0xFFFFF3CD),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Text('PRUEBA · PIN Lucía 3333', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextButton(
                          key: const Key('prueba_internet'),
                          onPressed: _cambiarInternet,
                          child: Text(_hayInternet ? 'CORTAR INTERNET' : 'VOLVER EL INTERNET'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: nav!),
            ),
          ],
        ),
        home: const CajeraDePrueba(),
      ),
    );
  }
}
