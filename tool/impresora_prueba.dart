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
  final _impresora = ImpresoraBluetooth(CanalUniversalBle());
  final _encontrados = <String, DispositivoBle>{};
  final _registro = <String>[];
  StreamSubscription<DispositivoBle>? _busqueda;
  bool _ocupado = false;

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
      final ok = await _impresora.conectar(d.id);
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

  Future<void> _ticket() async {
    final datos = await rootBundle.load('assets/icons/2.png');
    final logo = LogoParaPapel.silueta(datos.buffer.asUint8List());
    final armador = await TicketEscPos.cargar();
    await _mandar('TICKET', armador.armar(ticketDePrueba(logo: logo)));
  }

  Future<void> _acentos() async {
    final con = await TicketEscPos.cargar();
    final sin = await TicketEscPos.cargar(
      opciones: const OpcionesEscPos(tablaCaracteres: null),
    );
    await _mandar('ACENTOS', [
      ...con.armar(const [
        TextoTicket('Con la tabla CP1252:', centrado: false),
        TextoTicket(lineaDeAcentos, centrado: false),
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
    final dos = await rootBundle.load('assets/icons/2.png');
    final iso = await rootBundle.load('assets/icons/isotipo-ej.png');
    final uno = LogoParaPapel.silueta(dos.buffer.asUint8List());
    final otro = LogoParaPapel.umbral(iso.buffer.asUint8List());
    await _mandar('LOGO', a.armar([
      const TextoTicket('2.png, silueta:'),
      if (uno != null) LogoTicket(uno),
      const TextoTicket('isotipo-ej.png, umbral:'),
      if (otro != null) LogoTicket(otro),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final conectada = _impresora.conectadaA != null && !_ocupado;
    Widget boton(String texto, Future<void> Function() hacer) => FilledButton(
          onPressed: conectada ? hacer : null,
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
