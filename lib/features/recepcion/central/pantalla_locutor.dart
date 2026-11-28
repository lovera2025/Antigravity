import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/lista_del_locutor.dart';
import 'cliente_locutor.dart';

const _fondo = Color(0xFF141418);
const _tarjeta = Color(0xFF1E1E24);
const _perla = Color(0xFFE2E2E2);
const _gris = Color(0xFF9A9AA6);
const _verde = Color(0xFF4ADE80);
const _ambar = Color(0xFFFBBF24);

/// **La pantalla del locutor** (28-nov-2026; `docs/SPEC_locutor_2026-11-18.md`): la
/// lista de la noche para leerla en voz alta, de quien está arriba de la tarima. Solo
/// mira: no tiene un solo botón que cambie algo en la puerta.
///
/// Oscura, en Outfit (viene con la página: sin internet no hay otra letra), el egresado
/// grande y sus acompañantes debajo. Lo cambiado en Recepción llega solo y se marca
/// NUEVO hasta tocarlo (o media hora). Sin conexión se sigue viendo lo último.
class PantallaLocutor extends StatefulWidget {
  const PantallaLocutor({super.key, required this.cliente});
  final ClienteLocutor cliente;

  @override
  State<PantallaLocutor> createState() => _PantallaLocutorState();
}

class _PantallaLocutorState extends State<PantallaLocutor> with WidgetsBindingObserver {
  ClienteLocutor get _c => widget.cliente;
  final _buscar = TextEditingController();
  final _codigo = TextEditingController();
  final _scroll = ScrollController();
  String? _institucion;
  var _soloCambiadas = false;
  var _letra = 1.0;
  StreamSubscription<List<FamiliaDelLocutor>>? _escucha;
  List<FamiliaDelLocutor>? _aviso;
  Timer? _sacarAviso;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _escucha = _c.cambios.listen((f) {
      if (!mounted) return;
      _sacarAviso?.cancel();
      setState(() => _aviso = f);
      _sacarAviso = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _aviso = null);
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.alVolverALaVista();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_escucha?.cancel());
    _sacarAviso?.cancel();
    _buscar.dispose();
    _codigo.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TextStyle _outfit(double tam, {FontWeight peso = FontWeight.w400, Color color = _perla}) =>
      GoogleFonts.outfit(fontSize: tam * _letra, fontWeight: peso, color: color, height: 1.15);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) => Scaffold(
          backgroundColor: _fondo,
          body: SafeArea(child: _cuerpo()),
        ),
      );

  Widget _cuerpo() {
    if (_c.estado == EstadoDelLocutor.pideCodigo ||
        (_c.estado == EstadoDelLocutor.codigoMal && !_c.hayLista)) {
      return _pedirCodigo();
    }
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _arriba(),
            if (_c.estado != EstadoDelLocutor.conectado) _franja(),
            if (_c.hayLista && !_c.lista.estaVacia) _filtros(),
            Expanded(child: _lista()),
          ],
        ),
        // El aviso flota: no corre la lista bajo el dedo.
        if (_aviso != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              key: const Key('locutor_aviso'),
              color: _verde,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  'Cambió: ${_aviso!.map((f) => f.alumno.nombre).join(' · ')}',
                  style: _outfit(15, peso: FontWeight.w700, color: Colors.black),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pedirCodigo() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Locutor', style: _outfit(28, peso: FontWeight.w700), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  _c.estado == EstadoDelLocutor.codigoMal
                      ? 'Ese código no es el del locutor de esta noche. Pedí el de Recepción → CELULARES → SUMAR AL LOCUTOR.'
                      : 'Escribí el código del locutor que muestra Recepción (CELULARES → SUMAR AL LOCUTOR).',
                  key: const Key('locutor_pide_codigo'),
                  style: _outfit(15, color: _gris),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('locutor_codigo'),
                  controller: _codigo,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: _outfit(30, peso: FontWeight.w700),
                  decoration: const InputDecoration(counterText: '', hintText: '0000'),
                  onSubmitted: (v) => unawaited(_c.ponerCodigo(v)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('locutor_entrar'),
                  onPressed: () => unawaited(_c.ponerCodigo(_codigo.text)),
                  child: const Text('ENTRAR'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _arriba() {
    final (texto, color) = switch (_c.estado) {
      EstadoDelLocutor.conectado when _c.esperando => ('Conectado · esperando la lista de la PC', _verde),
      EstadoDelLocutor.conectado => ('Conectado', _verde),
      EstadoDelLocutor.conectando => ('Conectando…', _ambar),
      _ => ('Sin conexión', _ambar),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _c.titulo ?? 'Locutor',
              style: _outfit(18, peso: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            key: const Key('locutor_pastilla'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(20)),
            child: Text(texto, style: GoogleFonts.outfit(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            key: const Key('locutor_menos'),
            tooltip: 'Letra más chica',
            onPressed: _letra <= 0.8 ? null : () => setState(() => _letra -= 0.1),
            icon: const Icon(Icons.text_decrease, color: _perla),
          ),
          IconButton(
            key: const Key('locutor_mas'),
            tooltip: 'Letra más grande',
            onPressed: _letra >= 1.6 ? null : () => setState(() => _letra += 0.1),
            icon: const Icon(Icons.text_increase, color: _perla),
          ),
        ],
      ),
    );
  }

  Widget _franja() {
    final texto = switch (_c.estado) {
      EstadoDelLocutor.otraPestana => 'La lista se abrió en otra pestaña: seguí allá.',
      EstadoDelLocutor.frenado => 'Demasiados códigos equivocados: esperá un minuto.',
      EstadoDelLocutor.codigoMal => 'Cambiaron el código del locutor: escaneá el QR nuevo de Recepción.',
      EstadoDelLocutor.conectando when !_c.hayLista => 'Buscando la PC por el wifi del salón…',
      _ => 'Sin conexión con la PC${_desde()}. Se ve lo último que llegó y vuelve sola. '
          'Si la notebook se reinició, que abran Recepción en esa fiesta.',
    };
    return Container(
      key: const Key('locutor_franja'),
      color: const Color(0xFF3A2E0B),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(texto, style: _outfit(13, color: _ambar)),
    );
  }

  String _desde() {
    final d = _c.sinConexionDesde?.toLocal();
    if (d == null) return '';
    String dos(int n) => n.toString().padLeft(2, '0');
    return ' desde las ${dos(d.hour)}:${dos(d.minute)}';
  }

  Widget _filtros() {
    final instituciones = [for (final i in _c.lista.instituciones) i.nombre];
    final cambiadas = _c.lista.cambiadas;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('locutor_buscar'),
            controller: _buscar,
            onChanged: (_) => setState(() {}),
            style: _outfit(16),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: _gris),
              hintText: 'Buscar (nombre, apodo o acompañante)',
              hintStyle: _outfit(14, color: _gris),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Primero CAMBIADOS: es lo que más se usa, y en un celular angosto entra.
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    key: const Key('locutor_cambiadas'),
                    label: Text('CAMBIADOS ($cambiadas)'),
                    selected: _soloCambiadas,
                    onSelected: (v) => setState(() => _soloCambiadas = v),
                  ),
                ),
                if (instituciones.length > 1)
                  for (final i in [null, ...instituciones])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(i ?? 'Todas'),
                        selected: _institucion == i,
                        onSelected: (_) => setState(() => _institucion = i),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    if (!_c.hayLista) {
      return Center(child: Text('Esperando la lista de la PC…', style: _outfit(16, color: _gris)));
    }
    if (_c.lista.estaVacia) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Esta fiesta no tiene lista para el locutor: es de los eventos masivos, con los alumnos cargados.',
            key: const Key('locutor_sin_lista'),
            style: _outfit(16, color: _gris),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final buscadas = {for (final f in _c.lista.buscar(_buscar.text)) f.id};
    final filas = <Widget>[];
    for (final i in _c.lista.instituciones) {
      if (_institucion != null && i.nombre != _institucion) continue;
      final deLaInstitucion = <Widget>[];
      for (final d in i.divisiones) {
        final familias = [
          for (final f in d.familias)
            if (buscadas.contains(f.id) && (!_soloCambiadas || f.cambiada)) f,
        ];
        if (familias.isEmpty) continue;
        deLaInstitucion.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(d.nombre, style: _outfit(15, peso: FontWeight.w700, color: _gris)),
        ));
        for (final f in familias) {
          deLaInstitucion.add(_familia(f));
        }
      }
      if (deLaInstitucion.isEmpty) continue;
      filas
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
          child: Text(i.nombre, style: _outfit(17, peso: FontWeight.w700, color: _ambar)),
        ))
        ..addAll(deLaInstitucion);
    }
    if (filas.isEmpty) {
      return Center(child: Text('Nadie con eso.', style: _outfit(16, color: _gris)));
    }
    return ListView(
      key: const Key('locutor_lista'),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 80),
      children: filas,
    );
  }

  Widget _familia(FamiliaDelLocutor f) {
    final nueva = _c.esNueva(f);
    return Padding(
      key: ValueKey('locutor_familia_${f.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: _tarjeta,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _c.visto(f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(f.alumno.nombre, style: _outfit(26, peso: FontWeight.w700))),
                    // El lugar del NUEVO está siempre: no mueve el nombre cuando aparece.
                    SizedBox(
                      width: 74,
                      child: nueva
                          ? Container(
                              key: Key('locutor_nuevo_${f.id}'),
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration:
                                  BoxDecoration(color: _verde, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                'NUEVO',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
                if (f.alumno.cambiado)
                  Text('cargado: ${f.alumno.cargado}', style: _outfit(13, color: _gris)),
                for (final a in f.acompanantes) ...[
                  const SizedBox(height: 4),
                  Text(a.nombre, style: _outfit(19)),
                  if (a.cambiado && a.cargado.isNotEmpty)
                    Text('cargado: ${a.cargado}', style: _outfit(12, color: _gris)),
                ],
                if (f.sinNombre > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    f.sinNombre == 1 ? '+ 1 acompañante sin nombre' : '+ ${f.sinNombre} acompañantes sin nombre',
                    style: _outfit(14, color: _gris),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
