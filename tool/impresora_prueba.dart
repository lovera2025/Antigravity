// Ventana de prueba de la impresora de la barra, **sin base ni nube**. Busca por
// Bluetooth, se conecta y manda papeles de prueba. Con el papel en la mano se decide
// qué tabla de acentos usar, si el QR nativo sale y qué logo se lee.
//
//   flutter run -d windows -t tool/impresora_prueba.dart
//   flutter build apk --debug -t tool/impresora_prueba.dart      (para un Android)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/canal_ble.dart';
import 'package:arguello_events/features/barra/impresion/modelo_ticket.dart';
import 'package:arguello_events/features/barra/impresion/canal_universal_ble.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/widgets/elegir_vales.dart';

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
  // Una caja y dos ventas inventadas, para sacar el ticket y el cierre como van a salir
  // en la app (`ModeloTicket`). No se guardan en ningún lado.
  static final _caja = CajaBarra.abrir(
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    operadorNombre: 'Marta',
    numeroCaja: 2,
    cambioInicial: 20000,
    ahora: DateTime.now(),
  );

  static VentaBarra _venta({int numero = 17, bool mixta = false}) => VentaBarra.nueva(
        cajaBarraId: _caja.id,
        eventoId: _caja.eventoId,
        numero: numero,
        renglones: const [
          RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 2),
          RenglonVenta(productoId: 'b', nombre: 'Fernet con coca', precio: 6000, cantidad: 1),
          RenglonVenta(productoId: 'c', nombre: 'Agua sin gas', precio: 1000, cantidad: 3),
        ],
        medio: mixta ? MedioBarra.mixto : MedioBarra.efectivo,
        efectivo: mixta ? 10000 : 16000,
        transferencia: mixta ? 6000 : 0,
        recibe: 20000,
        comprobanteVisto: mixta,
        ahora: DateTime.now(),
      );

  /// El ticket de una venta como sale en la app, con lo que quedó en
  /// `OpcionesEscPos.deLaPrueba`.
  Future<void> _ticket() async {
    final armador = await TicketEscPos.cargar();
    final logo = await armador.opciones.logo.cargar(rootBundle);
    await _mandar(
      'TICKET',
      armador.armar(ModeloTicket.deVenta(_venta(), caja: _caja, fiesta: 'Puerto Viejo', logo: logo)),
    );
  }

  /// Una compra inventada de 10 cervezas, 2 fernet y 3 aguas, para probar los vales.
  static VentaBarra _ventaDeVales() => VentaBarra.nueva(
        cajaBarraId: _caja.id,
        eventoId: _caja.eventoId,
        numero: 17,
        renglones: const [
          RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 10),
          RenglonVenta(productoId: 'b', nombre: 'Fernet con coca', precio: 6000, cantidad: 2),
          RenglonVenta(productoId: 'c', nombre: 'Agua sin gas', precio: 1000, cantidad: 3),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 50000,
        ahora: DateTime.now(),
      );

  /// La pantalla de después de cobrar (`ElegirVales`), con la impresora de verdad: se
  /// elige TODO JUNTO o POR SEPARADO, y por separado cada vale se arma a mano y sale solo.
  /// Cada vez que se abre es una compra nueva.
  Future<void> _vales() async {
    final armador = await TicketEscPos.cargar();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Vales de una compra')),
        body: ElegirVales(
          venta: _ventaDeVales(),
          caja: _caja,
          fiesta: 'Puerto Viejo',
          imprimir: (lineas) async {
            final bytes = armador.armar(lineas);
            final inicio = Stopwatch()..start();
            final r = await _impresora.imprimir(bytes);
            _anotar('VALE: ${r.name}, ${bytes.length} bytes en ${inicio.elapsedMilliseconds} ms');
            return r == ResultadoImpresion.impreso;
          },
        ),
      ),
    ));
  }

  /// Un vale reimpreso por el jefe: sale con COPIA arriba y abajo.
  Future<void> _copia() async {
    final armador = await TicketEscPos.cargar();
    final venta = _ventaDeVales();
    await _mandar(
      'COPIA',
      armador.armar(ModeloTicket.deVale(
        Vale.deUnaBebida(venta.renglones.first, cantidad: 3, numero: 1),
        venta: venta,
        caja: _caja,
        fiesta: 'Puerto Viejo',
        copia: CopiaDeVale(
          numero: 1,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          hechoPor: 'Jefe',
          motivo: 'se cortó el papel',
        ),
      )),
    );
  }

  /// El papel del cierre de una caja con dos ventas, una anulada, y $ 500 de menos.
  Future<void> _cierre() async {
    final armador = await TicketEscPos.cargar();
    final ventas = [_venta(), _venta(numero: 18, mixta: true), _venta(numero: 19)];
    final anulaciones = [
      AnulacionBarra.de(ventas.last, motivo: 'se cobró dos veces', ahora: DateTime.now()),
    ];
    final cuentas = CierreDeBarra.de(_caja, ventas, anulaciones);
    final cerrada = _caja.cerrada(
      efectivoContado: cuentas.efectivoEsperado - 500,
      diferencia: -500,
      nota: 'faltó un billete de quinientos',
      ahora: DateTime.now(),
    );
    await _mandar(
      'CIERRE',
      armador.armar(ModeloTicket.deCierre(cerrada, cuentas, fiesta: 'Puerto Viejo')),
    );
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
                boton('VALES', _vales),
                boton('COPIA', _copia),
                boton('ACENTOS', _acentos),
                boton('ANCHO', _ancho),
                boton('QR', _qr),
                boton('LOGO', _logo),
                boton('CIERRE', _cierre),
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
