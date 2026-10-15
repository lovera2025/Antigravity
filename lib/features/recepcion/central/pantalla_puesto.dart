import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/acciones_puerta_provider.dart';
import '../providers/recepcion_provider.dart';
import '../services/puerta_del_evento.dart';
import '../widgets/panel_puerta.dart';
import 'cliente_central.dart';

/// El celular de la puerta: la misma lista de Recepción, que marca en la
/// notebook central por el wifi del router (`ClienteCentral`).
///
/// Se abre escaneando el QR de "Sumar un celular" en la PC, o escribiendo su
/// dirección en el navegador. No se instala nada ni se pone usuario: la
/// primera vez pide un nombre ("Juli"), y el código si no vino en el QR.
class PantallaPuesto extends StatefulWidget {
  const PantallaPuesto({super.key, required this.cliente});
  final ClienteCentral cliente;

  @override
  State<PantallaPuesto> createState() => _PantallaPuestoState();
}

const _fondo = Color(0xFF141418);
const _perla = Color(0xFFE2E2E2);
const _verde = Color(0xFF4ADE80);
const _ambar = Color(0xFFFBBF24);

TextStyle _letra({double size = 14, bool negrita = false, Color? color}) =>
    GoogleFonts.outfit(
      fontSize: size,
      fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
      color: color ?? _perla,
    );

TextStyle _titulo({double size = 16, Color? color}) => TextStyle(
      fontFamily: 'TotemCartelera',
      fontWeight: FontWeight.w700,
      fontSize: size,
      letterSpacing: 1.5,
      color: color ?? _perla,
    );

class _PantallaPuestoState extends State<PantallaPuesto> {
  ClienteCentral get _c => widget.cliente;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cabeza(),
              Expanded(child: _cuerpo()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabeza() {
    final nombre = _c.nombre?.trim() ?? '';
    final conLista = _c.puerta != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.door_front_door_outlined,
                  color: _perla, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nombre.isEmpty || !conLista
                      ? 'RECEPCIÓN'
                      : 'RECEPCIÓN · ${nombre.toUpperCase()}',
                  overflow: TextOverflow.ellipsis,
                  style: _titulo(),
                ),
              ),
            ],
          ),
          if (_c.titulo != null) ...[
            const SizedBox(height: 4),
            Text(
              _c.titulo!.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _titulo(size: 11, color: Colors.white54),
            ),
          ],
          if (conLista) ...[
            const SizedBox(height: 8),
            _pastilla(),
          ],
        ],
      ),
    );
  }

  /// Si está conectado a la PC y, si no, cuántos le faltan mandar.
  Widget _pastilla() {
    final pendientes = _c.pendientes.length;
    final (texto, color) = switch (_c.estado) {
      EstadoDelPuesto.conectado when _c.seMandaron > 0 => (
          _c.seMandaron == 1
              ? 'Conectado · se mandó 1'
              : 'Conectado · se mandaron ${_c.seMandaron}',
          _verde,
        ),
      EstadoDelPuesto.conectado => ('Conectado a la PC', _verde),
      _ => (
          pendientes == 0
              ? 'Sin conexión con la PC'
              : 'Sin conexión con la PC · $pendientes por mandar',
          _ambar,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _c.estado == EstadoDelPuesto.conectado
                ? Icons.circle
                : Icons.wifi_off_rounded,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(texto, style: _letra(size: 12, color: color))),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    final puerta = _c.puerta;
    final eventoId = _c.eventoId;
    switch (_c.estado) {
      case EstadoDelPuesto.cargando:
        return const Center(child: CircularProgressIndicator(color: _perla));
      case EstadoDelPuesto.faltanDatos:
        return _Datos(cliente: _c);
      case EstadoDelPuesto.codigoMal:
        return _Datos(cliente: _c, codigoMal: true);
      case EstadoDelPuesto.frenado:
        return _mensaje(
          'Demasiados códigos equivocados.',
          'Esperá un minuto: vuelve a probar solo.',
        );
      case EstadoDelPuesto.otraPestana:
        return _mensaje(
          'Este celular se abrió en otra pestaña.',
          'Seguí en esa, o tocá abajo para usar esta.',
          boton: ('USAR ESTA', _c.reconectar),
        );
      case EstadoDelPuesto.conectando:
      case EstadoDelPuesto.conectado:
      case EstadoDelPuesto.sinConexion:
        if (puerta == null || eventoId == null) {
          return _mensaje(
            'Buscando la PC central…',
            'El celular tiene que estar en el wifi del router, el mismo de la '
                'PC.',
            cargando: true,
          );
        }
        return ProviderScope(
          overrides: [
            clienteCentralProvider.overrideWithValue(_c),
            puertaDelEventoProvider.overrideWith(
              (ref, _) => ref.watch(puertaDelCelularProvider),
            ),
            accionesPuertaProvider.overrideWith(
              (ref) => AccionesDelCelular(ref.watch(clienteCentralProvider)),
            ),
          ],
          child: Theme(
            data: ThemeData(brightness: Brightness.dark, useMaterial3: true),
            child: PanelPuerta(
              eventoId: eventoId,
              onActualizar: _c.reconectar,
            ),
          ),
        );
    }
  }

  Widget _mensaje(
    String titulo,
    String texto, {
    bool cargando = false,
    (String, VoidCallback)? boton,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cargando) ...[
                const CircularProgressIndicator(color: _perla),
                const SizedBox(height: 20),
              ],
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: _letra(size: 17, negrita: true)),
              const SizedBox(height: 8),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: _letra(size: 14, color: Colors.white60)),
              if (boton != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: boton.$2,
                  style: FilledButton.styleFrom(
                    backgroundColor: _perla,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(160, 48),
                  ),
                  child: Text(boton.$1,
                      style: _letra(
                          size: 13, negrita: true, color: Colors.black)),
                ),
              ],
            ],
          ),
        ),
      );
}

/// La primera vez: el nombre y, si no vino en el QR, el código de la PC.
class _Datos extends StatefulWidget {
  const _Datos({required this.cliente, this.codigoMal = false});
  final ClienteCentral cliente;
  final bool codigoMal;

  @override
  State<_Datos> createState() => _DatosState();
}

class _DatosState extends State<_Datos> {
  late final _nombre = TextEditingController(text: widget.cliente.nombre);
  final _codigo = TextEditingController();
  String? _error;

  bool get _pideCodigo =>
      widget.codigoMal ||
      !RegExp(r'^\d{4}$').hasMatch(widget.cliente.codigo ?? '');

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _empezar() async {
    final nombre = _nombre.text.trim();
    final codigo = _codigo.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Escribí tu nombre.');
      return;
    }
    if (_pideCodigo && !RegExp(r'^\d{4}$').hasMatch(codigo)) {
      setState(() => _error = 'El código son las cuatro cifras que muestra la PC.');
      return;
    }
    setState(() => _error = null);
    await widget.cliente.ponerDatos(
      nombre: nombre,
      codigo: _pideCodigo ? codigo : null,
    );
  }

  InputDecoration _campo(String pista) => InputDecoration(
        hintText: pista,
        hintStyle: _letra(size: 15, color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _perla, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.codigoMal) ...[
                Text(
                  'El código no es el de la PC.',
                  textAlign: TextAlign.center,
                  style: _letra(size: 17, negrita: true, color: _ambar),
                ),
                const SizedBox(height: 6),
                Text(
                  'Volvé a escanear el QR, o escribí el que muestra ahora la PC '
                  'en "Sumar un celular".',
                  textAlign: TextAlign.center,
                  style: _letra(size: 13, color: Colors.white60),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Text('¿Cómo te llamás?',
                    textAlign: TextAlign.center,
                    style: _letra(size: 18, negrita: true)),
                const SizedBox(height: 6),
                Text(
                  'Así la PC sabe quién ingresó a cada uno.',
                  textAlign: TextAlign.center,
                  style: _letra(size: 13, color: Colors.white60),
                ),
                const SizedBox(height: 18),
              ],
              TextField(
                controller: _nombre,
                autofocus: !widget.codigoMal,
                textCapitalization: TextCapitalization.words,
                textInputAction:
                    _pideCodigo ? TextInputAction.next : TextInputAction.go,
                style: _letra(size: 16),
                decoration: _campo('Tu nombre'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _pideCodigo ? null : _empezar(),
              ),
              if (_pideCodigo) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _codigo,
                  autofocus: widget.codigoMal,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textInputAction: TextInputAction.go,
                  style: _letra(size: 20, negrita: true),
                  decoration: _campo('Código de la PC (4 cifras)'),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _empezar(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: _letra(size: 13, color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _empezar,
                style: FilledButton.styleFrom(
                  backgroundColor: _verde,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'EMPEZAR',
                  style: _letra(size: 14, negrita: true, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El cliente del celular, para el panel de adentro.
final clienteCentralProvider = Provider<ClienteCentral>(
  (ref) => throw UnimplementedError('Solo en el celular de la puerta'),
);

/// La lista del celular, que cambia cada vez que el cliente avisa.
final puertaDelCelularProvider = Provider<AsyncValue<PuertaDelEvento>>((ref) {
  final cliente = ref.watch(clienteCentralProvider);
  void cambio() => ref.invalidateSelf();
  cliente.addListener(cambio);
  ref.onDispose(() => cliente.removeListener(cambio));
  final puerta = cliente.puerta;
  return puerta == null
      ? const AsyncValue.loading()
      : AsyncValue.data(puerta);
});
