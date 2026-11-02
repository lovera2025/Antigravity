// Arnés manual: la impresora térmica de la barra (Global 58 mm, Bluetooth)
// desde un Android, **sin tocar la base de la PC ni la nube**. Es la prueba
// previa al módulo de barra: si esto imprime bien, el módulo imprime.
//
//   flutter run -d <android> -t tool/impresora_prueba.dart
//   flutter build apk --debug -t tool/impresora_prueba.dart   (para instalar
//       el APK a mano: build/app/outputs/flutter-apk/app-debug.apk)
//
// Antes: prender la impresora y emparejarla en Ajustes → Bluetooth del Android
// (PIN 0000 o 1234). Acá se la elige entre las emparejadas, se conecta y se
// mandan las pruebas, de a una:
//   - TICKET: un ticket de barra como el que va a salir (encabezado, renglones,
//     total, medio de pago, número y QR);
//   - ACENTOS: la misma línea con la tabla CP1252, sin tabla y sin acentos,
//     para ver cuál sale bien;
//   - ANCHO: cuántas letras entran por renglón, en letra normal, doble y chica;
//   - QR: el QR nativo solo, grande (si no sale, va como imagen en el módulo).
// Abajo queda el registro de lo que contestó la impresora. No corre
// `main.dart`: no abre la base ni inicia sesión.
//
// Escrito sin compilar (el contenedor remoto no tiene Flutter): `flutter
// analyze` en la PC dice si alguna firma de los dos paquetes cambió.

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFD4AF37),
        brightness: Brightness.dark,
      ),
      home: const _Prueba(),
    ),
  );
}

// ── Los bytes ESC/POS de cada prueba (puros: el módulo los va a reusar) ──────

/// Un generador para papel de 58 mm con el perfil genérico.
Future<Generator> _generador() async {
  final perfil = await CapabilityProfile.load();
  return Generator(PaperSize.mm58, perfil);
}

String _pesos(int monto) {
  final s = monto.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '\$ $b';
}

/// Un renglón de la cuenta: "2 x Cerveza lata" a la izquierda y el importe a
/// la derecha. Las columnas suman 12, como pide el generador.
List<int> _renglon(Generator g, int cantidad, String nombre, int importe) =>
    g.row([
      PosColumn(text: '$cantidad x $nombre', width: 8),
      PosColumn(
        text: _pesos(importe),
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

/// El ticket de barra, como va a salir en la fiesta.
Future<List<int>> _ticketDePrueba() async {
  final g = await _generador();
  final b = <int>[];
  b.addAll(g.reset());
  b.addAll(g.text(
    'JUNIOR EVENTOS',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ),
  ));
  b.addAll(g.text(
    'BARRA',
    styles: const PosStyles(align: PosAlign.center, bold: true),
  ));
  b.addAll(g.text(
    'Colegio Buena Vista - 12/12/2026',
    styles: const PosStyles(align: PosAlign.center),
  ));
  b.addAll(g.text(
    'Caja 2 - Marta - 23:41',
    styles: const PosStyles(align: PosAlign.center),
  ));
  b.addAll(g.hr());
  b.addAll(_renglon(g, 2, 'Cerveza lata', 7000));
  b.addAll(_renglon(g, 1, 'Fernet', 6000));
  b.addAll(_renglon(g, 1, 'Agua', 2000));
  b.addAll(g.hr());
  b.addAll(g.row([
    PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
    PosColumn(
      text: _pesos(15000),
      width: 6,
      styles: const PosStyles(align: PosAlign.right, bold: true),
    ),
  ]));
  b.addAll(g.text('Efectivo'));
  b.addAll(g.hr());
  b.addAll(g.text(
    'Ticket N 0001',
    styles: const PosStyles(align: PosAlign.center, bold: true),
  ));
  b.addAll(g.qrcode('JE-BARRA-PRUEBA-0001', size: QRSize.size5));
  b.addAll(g.text(
    'Gracias, salud!',
    styles: const PosStyles(align: PosAlign.center),
  ));
  b.addAll(g.feed(3));
  b.addAll(g.cut());
  return b;
}

/// La misma línea tres veces: con la tabla CP1252 (la que corresponde a cómo
/// codifica el generador), sin tabla (lo que trae la impresora de fábrica) y
/// sin acentos. Una de las tres tiene que salir bien.
Future<({List<int> bytes, List<String> notas})> _acentos() async {
  final g = await _generador();
  final b = <int>[];
  final notas = <String>[];
  const linea = 'áéíóúñ ÁÉÍÓÚÑ ü ¿¡ \$ 1/2';
  b.addAll(g.reset());
  try {
    b.addAll(g.setGlobalCodeTable('CP1252'));
    b.addAll(g.text('1 CP1252: $linea'));
  } catch (e) {
    notas.add('El perfil no tiene la tabla CP1252: $e');
  }
  b.addAll(g.reset());
  b.addAll(g.text('2 Sin tabla: $linea'));
  b.addAll(g.text('3 Sin acentos: aeioun AEIOUN u ?! \$ 1/2'));
  b.addAll(g.feed(3));
  return (bytes: b, notas: notas);
}

/// Reglas para contar cuántas letras entran por renglón.
Future<List<int>> _ancho() async {
  final g = await _generador();
  final b = <int>[];
  b.addAll(g.reset());
  b.addAll(g.text('Normal (se corta donde no entra):'));
  b.addAll(g.text('123456789012345678901234567890123456789012345678'));
  b.addAll(g.text('Doble ancho:'));
  b.addAll(g.text(
    '12345678901234567890',
    styles: const PosStyles(width: PosTextSize.size2),
  ));
  b.addAll(g.text('Letra chica (fuente B):'));
  b.addAll(g.text(
    '123456789012345678901234567890123456789012345678',
    styles: const PosStyles(fontType: PosFontType.fontB),
  ));
  b.addAll(g.hr());
  b.addAll(g.feed(3));
  return b;
}

/// El QR nativo solo, grande, con su texto debajo.
Future<List<int>> _qr() async {
  final g = await _generador();
  final b = <int>[];
  b.addAll(g.reset());
  b.addAll(g.text('QR nativo:', styles: const PosStyles(align: PosAlign.center)));
  b.addAll(g.qrcode('JE-BARRA-PRUEBA-0001', size: QRSize.size6));
  b.addAll(g.text(
    'JE-BARRA-PRUEBA-0001',
    styles: const PosStyles(align: PosAlign.center),
  ));
  b.addAll(g.feed(3));
  return b;
}

// ── La pantalla ─────────────────────────────────────────────────────────────

class _Prueba extends StatefulWidget {
  const _Prueba();

  @override
  State<_Prueba> createState() => _PruebaState();
}

class _PruebaState extends State<_Prueba> {
  List<BluetoothInfo> _emparejadas = const [];
  BluetoothInfo? _elegida;
  bool _conectada = false;
  bool _ocupada = false;
  bool _bluetoothPrendido = false;
  final List<String> _registro = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _anotar(String texto) {
    final t = TimeOfDay.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    setState(() => _registro.insert(0, '$hh:$mm  $texto'));
  }

  Future<void> _cargar() async {
    setState(() => _ocupada = true);
    try {
      _bluetoothPrendido = await PrintBluetoothThermal.bluetoothEnabled;
      _anotar(_bluetoothPrendido ? 'Bluetooth prendido' : 'Bluetooth apagado');
      final permiso = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      _anotar(permiso
          ? 'Permiso de dispositivos cercanos: dado'
          : 'Sin permiso de dispositivos cercanos: la app lo pide al conectar; '
              'si no aparece el cartel, dárselo en Ajustes → Apps → Junior '
              'Eventos → Permisos');
      final lista = await PrintBluetoothThermal.pairedBluetooths;
      setState(() => _emparejadas = lista);
      _anotar(lista.isEmpty
          ? 'No hay dispositivos emparejados: emparejá la impresora en '
              'Ajustes → Bluetooth (PIN 0000 o 1234) y tocá ACTUALIZAR'
          : '${lista.length} emparejado(s)');
      _conectada = await PrintBluetoothThermal.connectionStatus;
    } catch (e) {
      _anotar('Error al leer el Bluetooth: $e');
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
  }

  Future<void> _conectar(BluetoothInfo d) async {
    setState(() => _ocupada = true);
    try {
      _anotar('Conectando a ${d.name} (${d.macAdress})…');
      final ok = await PrintBluetoothThermal.connect(
        macPrinterAddress: d.macAdress,
      );
      setState(() {
        _conectada = ok;
        _elegida = ok ? d : null;
      });
      _anotar(ok
          ? 'Conectada a ${d.name}'
          : 'No se pudo conectar: ¿está prendida y emparejada? ¿La tiene '
              'agarrada otra app (RawBT)?');
    } catch (e) {
      _anotar('Error al conectar: $e');
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
  }

  Future<void> _desconectar() async {
    setState(() => _ocupada = true);
    try {
      final ok = await PrintBluetoothThermal.disconnect;
      setState(() {
        _conectada = !ok && _conectada;
        if (ok) _elegida = null;
      });
      _anotar(ok ? 'Desconectada' : 'No se pudo desconectar');
    } catch (e) {
      _anotar('Error al desconectar: $e');
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
  }

  Future<void> _imprimir(
    String nombre,
    Future<List<int>> Function() armar, {
    List<String> notas = const [],
  }) async {
    setState(() => _ocupada = true);
    try {
      if (!await PrintBluetoothThermal.connectionStatus) {
        setState(() => _conectada = false);
        _anotar('La impresora no está conectada: conectala de nuevo');
        return;
      }
      final bytes = await armar();
      for (final n in notas) {
        _anotar(n);
      }
      _anotar('$nombre: mandando ${bytes.length} bytes…');
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      _anotar(ok
          ? '$nombre: la impresora los recibió (mirá el papel)'
          : '$nombre: la impresora NO los recibió');
    } catch (e) {
      _anotar('$nombre: error: $e');
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
  }

  Future<void> _imprimirAcentos() async {
    final r = await _acentos();
    await _imprimir('ACENTOS', () async => r.bytes, notas: r.notas);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final puede = _conectada && !_ocupada;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impresora de la barra · prueba'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _ocupada ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  _conectada ? Icons.print : Icons.print_disabled,
                  color: _conectada ? Colors.greenAccent : tema.disabledColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _conectada
                        ? 'Conectada: ${_elegida?.name ?? ''}'
                        : _bluetoothPrendido
                            ? 'Elegí la impresora de la lista'
                            : 'Prendé el Bluetooth del Android',
                    style: tema.textTheme.titleMedium,
                  ),
                ),
                if (_ocupada)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 150,
            child: _emparejadas.isEmpty
                ? const Center(
                    child: Text('Sin dispositivos emparejados'),
                  )
                : ListView(
                    children: [
                      for (final d in _emparejadas)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.bluetooth,
                            color: _elegida?.macAdress == d.macAdress
                                ? Colors.greenAccent
                                : null,
                          ),
                          title: Text(d.name),
                          subtitle: Text(d.macAdress),
                          onTap: _ocupada ? null : () => _conectar(d),
                        ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: puede
                      ? () => _imprimir('TICKET', _ticketDePrueba)
                      : null,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('TICKET'),
                ),
                FilledButton.tonal(
                  onPressed: puede ? _imprimirAcentos : null,
                  child: const Text('ACENTOS'),
                ),
                FilledButton.tonal(
                  onPressed: puede ? () => _imprimir('ANCHO', _ancho) : null,
                  child: const Text('ANCHO'),
                ),
                FilledButton.tonal(
                  onPressed: puede ? () => _imprimir('QR', _qr) : null,
                  child: const Text('QR'),
                ),
                OutlinedButton(
                  onPressed: puede ? _desconectar : null,
                  child: const Text('DESCONECTAR'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _registro.length,
              itemBuilder: (_, i) => Text(
                _registro[i],
                style: tema.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
