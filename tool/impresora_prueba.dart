// Ventana de prueba de la impresora de la barra, **sin base ni nube**. Busca por
// Bluetooth, se conecta y manda papeles de prueba. Con el papel en la mano se decide
// qué tabla de acentos usar, si el QR nativo sale y qué logo se lee.
//
//   flutter run -d windows -t tool/impresora_prueba.dart
//   flutter build apk --debug -t tool/impresora_prueba.dart      (para un Android)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:arguello_events/features/barra/impresion/canal_ble.dart';
import 'package:arguello_events/features/barra/impresion/canal_universal_ble.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PruebaDeImpresora(),
    ));

class PruebaDeImpresora extends StatefulWidget {
  const PruebaDeImpresora({super.key});

  @override
  State<PruebaDeImpresora> createState() => _PruebaDeImpresoraState();
}

class _PruebaDeImpresoraState extends State<PruebaDeImpresora> {
  final _impresora = ImpresoraBluetooth(
    CanalUniversalBle(),
    recordada: const ImpresoraRecordada(),
  );
  final _encontrados = <String, DispositivoBle>{};
  final _registro = <String>[];
  StreamSubscription<DispositivoBle>? _busqueda;
  bool _ocupado = false;
  ImpresoraElegida? _elegida;

  @override
  void initState() {
    super.initState();
    _alAbrir();
  }

  /// Lo mismo que va a hacer VENDER: si este equipo ya tiene impresora, se conecta sola.
  Future<void> _alAbrir() async {
    final elegida = await _impresora.elegida();
    if (elegida == null) {
      _anotar('Este equipo no tiene impresora elegida: BUSCAR y CONECTAR');
      return;
    }
    setState(() {
      _elegida = elegida;
      _ocupado = true;
      _encontrados[elegida.id] = DispositivoBle(
        id: elegida.id,
        nombre: elegida.nombre.isEmpty ? 'La de este equipo' : elegida.nombre,
      );
    });
    _anotar('Recordada: ${elegida.nombre} (${elegida.id}). Conectando sola...');
    final inicio = Stopwatch()..start();
    try {
      await _impresora.canal.pedirPermisos();
    } catch (e) {
      _anotar('No pude pedir los permisos: $e');
    }
    final estado = await _impresora.reconectar();
    _anotar(estado == EstadoImpresora.lista
        ? 'Conectada sola en ${inicio.elapsedMilliseconds} ms, '
            'de a ${_impresora.tamano} bytes'
        : 'No contesta (${estado.name}): ¿está prendida y cerca?');
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _olvidar() async {
    await _impresora.olvidar();
    setState(() => _elegida = null);
    _anotar('Olvidada: este equipo ya no tiene impresora');
  }

  void _anotar(String s) {
    debugPrint('IMPRESORA: $s');
    if (mounted) setState(() => _registro.insert(0, s));
  }

  List<DispositivoBle> get _ordenados {
    final lista = _encontrados.values.toList();
    int peso(DispositivoBle d) =>
        (pareceImpresora(d.nombre) ? 0 : 2) + (d.emparejado ? 0 : 1);
    lista.sort((a, b) {
      final p = peso(a).compareTo(peso(b));
      return p != 0 ? p : a.nombre.compareTo(b.nombre);
    });
    return lista;
  }

  Future<void> _buscar() async {
    final canal = _impresora.canal;
    try {
      await canal.pedirPermisos();
      final ya = await canal.emparejados();
      setState(() {
        for (final d in ya) {
          _encontrados[d.id] = d;
        }
      });
      _anotar('Emparejados en este equipo: ${ya.length}');
    } catch (e) {
      _anotar('No pude leer los emparejados: $e');
    }
    await _busqueda?.cancel();
    _busqueda = canal.buscar().listen(
      (d) {
        if (_encontrados[d.id]?.emparejado ?? false) return;
        setState(() => _encontrados[d.id] = d);
      },
      onError: (Object e) => _anotar('Error al buscar: $e'),
    );
    _anotar('Buscando 10 segundos...');
    Timer(const Duration(seconds: 10), () async {
      await _busqueda?.cancel();
      _busqueda = null;
      _anotar('Búsqueda terminada: ${_encontrados.length} aparatos');
    });
  }

  Future<void> _conectar(DispositivoBle d) async {
    setState(() => _ocupado = true);
    await _busqueda?.cancel();
    _busqueda = null;
    final inicio = Stopwatch()..start();
    try {
      _anotar('Conectando a ${d.nombre}...');
      final ok = await _impresora.conectar(d.id, nombre: d.nombre);
      if (ok) _elegida = await _impresora.elegida();
      final c = _impresora.caracteristica;
      _anotar(ok
          ? 'Conectada en ${inicio.elapsedMilliseconds} ms. Escribe por ${c?.uuid} '
              '(${c?.escribeSinRespuesta == true ? 'sin respuesta' : 'con respuesta'}), '
              'de a ${_impresora.tamano} bytes'
          : 'Se conectó, pero no tiene por dónde escribirle');
    } catch (e) {
      _anotar('No conectó: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _mandar(String nombre, List<int> bytes) async {
    setState(() => _ocupado = true);
    final inicio = Stopwatch()..start();
    final r = await _impresora.imprimir(bytes);
    _anotar('$nombre: ${r.name}, ${bytes.length} bytes en '
        '${inicio.elapsedMilliseconds} ms');
    if (mounted) setState(() => _ocupado = false);
  }

  /// El ticket como va a salir en la app, con lo que quedó en `OpcionesEscPos.deLaPrueba`.
  Future<void> _ticket() async {
    final armador = await TicketEscPos.cargar();
    final logo = await armador.opciones.logo.cargar(rootBundle);
    await _mandar('TICKET', armador.armar(ticketDePrueba(logo: logo)));
  }

  Future<void> _acentos() async {
    final con = await TicketEscPos.cargar();
    final sin = await TicketEscPos.cargar(
      opciones: const OpcionesEscPos(conAcentos: false),
    );
    await _mandar('ACENTOS', [
      ...con.armar(const [
        TextoTicket('Con la tabla 850:', centrado: false),
        TextoTicket(lineaDeAcentos, centrado: false),
        TextoTicket('¡Gracias, salud! Caja 2 - N° 0017', centrado: false),
      ], cortar: false),
      ...sin.armar(const [
        TextoTicket('Sin acentos:', centrado: false),
        TextoTicket(lineaDeAcentos, centrado: false),
      ]),
    ]);
  }

  Future<void> _ancho() async {
    final a = await TicketEscPos.cargar();
    await _mandar('ANCHO', a.armar(const [
      TextoTicket('12345678901234567890123456789012', centrado: false),
      SeparadorTicket(),
      RenglonTicket('Un nombre de producto muy largo que no entra', r'$ 123.000'),
      RenglonTicket('2 x Fernet con coca', r'$ 12.000'),
      RenglonTicket('1 x Champán Chandon Extra Brut', r'$ 45.000'),
      SeparadorTicket(),
      RenglonTicket('TOTAL', r'$ 180.000', negrita: true),
    ]));
  }

  Future<void> _qr() async {
    final a = await TicketEscPos.cargar();
    await _mandar('QR', a.armar(const [
      TextoTicket('QR nativo:'),
      QrTicket('je:barra:prueba-0017'),
    ]));
  }

  Future<void> _logo() async {
    final a = await TicketEscPos.cargar();
    final uno = await LogoDelPapel.silueta.cargar(rootBundle);
    final otro = await LogoDelPapel.isotipo.cargar(rootBundle);
    await _mandar('LOGO', a.armar([
      const TextoTicket('2.png, silueta:'),
      if (uno != null) LogoTicket(uno),
      const TextoTicket('isotipo-ej.png, umbral:'),
      if (otro != null) LogoTicket(otro),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    // Con una impresora elegida se puede mandar aunque se haya cortado: imprimir
    // reconecta solo, que es lo que se prueba.
    final puede = _elegida != null && !_ocupado;
    Widget boton(String texto, Future<void> Function() hacer) => FilledButton(
          onPressed: puede ? hacer : null,
          child: Text(texto),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba de la impresora')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('buscar'),
                  onPressed: _ocupado ? null : _buscar,
                  child: const Text('BUSCAR'),
                ),
                boton('TICKET', _ticket),
                boton('ACENTOS', _acentos),
                boton('ANCHO', _ancho),
                boton('QR', _qr),
                boton('LOGO', _logo),
                OutlinedButton(
                  onPressed: _elegida == null || _ocupado ? null : _olvidar,
                  child: const Text('OLVIDAR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  for (final d in _ordenados)
                    ListTile(
                      dense: true,
                      title: Text(d.nombre),
                      subtitle: Text(
                        '${d.id}${d.emparejado ? ' · emparejado' : ''}',
                      ),
                      trailing: d.id == _impresora.conectadaA
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : TextButton(
                              onPressed: _ocupado ? null : () => _conectar(d),
                              child: const Text('CONECTAR'),
                            ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [for (final r in _registro) SelectableText(r)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
