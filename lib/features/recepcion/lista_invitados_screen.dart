import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/totem_config.dart';
import '../recepcion/providers/recepcion_provider.dart';
import '../totem/providers/totem_config_provider.dart';
import 'repositories/supabase_invitados_repository.dart';

/// La página del QR del tótem (`/lista?evento=<id>`, y también `?buscar`): el
/// invitado de un evento particular se busca por su nombre y se anota con su
/// DNI, en su celular.
///
/// **Desde la sección 8 de la 6.0.0 no baja la lista**: busca desde 3 letras
/// (`puerta_buscar`) y el DNI lo compara la nube (`puerta_checkin`). Quien no
/// tiene DNI cargado se anota en la recepción; antes entraba sin que le
/// pidieran nada. En un evento masivo no aparece nadie (en masivos el tótem
/// tampoco muestra el QR).
class ListaInvitadosScreen extends ConsumerStatefulWidget {
  final String eventoId;
  const ListaInvitadosScreen({required this.eventoId, super.key});

  static const faltanLetras =
      'Escribí al menos 3 letras de tu nombre o apellido.';
  static const noSePudoBuscar =
      'No se pudo buscar. Revisá la conexión e intentá de nuevo.';
  static const noSePudoVerificar =
      'No se pudo verificar. Revisá la conexión e intentá de nuevo.';
  static const escribiTuDni = 'Escribí tu DNI para seguir.';
  static const aLaRecepcion = 'Acercate a la recepción y te anotan ahí.';
  static const bloqueado =
      'Se probó tres veces con otro DNI. Acercate a la recepción y te anotan ahí.';
  static const enLaRecepcion = 'En este evento el ingreso es en la recepción.';
  static const noTeEncontramos = 'No te encontramos. Acercate a la recepción.';
  static const mesaPorAsignar = 'Tu mesa te la dicen en la recepción.';

  static String noEncontrado(String texto) =>
      'No encontramos "$texto". Probá con tu apellido o acercate a la recepción.';

  static String dniNoCoincide(int quedan) => quedan == 1
      ? 'Ese DNI no coincide. Te queda 1 intento.'
      : 'Ese DNI no coincide. Te quedan $quedan intentos.';

  @override
  ConsumerState<ListaInvitadosScreen> createState() =>
      _ListaInvitadosScreenState();
}

enum _Paso { buscando, dni, bienvenida, aLaRecepcion }

class _ListaInvitadosScreenState extends ConsumerState<ListaInvitadosScreen> {
  static const _fondo = Color(0xFFF2F0EB); // Gris perla
  static const _tinta = Color(0xDE000000);
  static const _tintaSuave = Color(0x8A000000);

  /// Misma config que el tótem del salón: la misma foto, saludo y color.
  late TotemConfig _cfg = TotemConfig.defaults(widget.eventoId);
  Color get _acento => _cfg.colorAcento;

  _Paso _paso = _Paso.buscando;

  // ── Buscar ─────────────────────────────────────────────────────────────────
  final _buscador = TextEditingController();
  final _focoBuscador = FocusNode();
  Timer? _espera;
  int _pedido = 0;
  bool _buscandoEnLaNube = false;
  String? _errorBusqueda;
  List<EncontradoEnLaPuerta>? _encontrados;
  String _buscado = '';

  // ── El DNI ─────────────────────────────────────────────────────────────────
  final _dni = TextEditingController();
  final _focoDni = FocusNode();
  EncontradoEnLaPuerta? _elegido;
  bool _verificando = false;
  String? _errorDni;

  // ── La bienvenida, o a la recepción ────────────────────────────────────────
  String? _mesa;
  String _porQueALaRecepcion = ListaInvitadosScreen.aLaRecepcion;

  bool get _eventoValido => widget.eventoId.length == 36;

  @override
  void dispose() {
    _espera?.cancel();
    _buscador.dispose();
    _focoBuscador.dispose();
    _dni.dispose();
    _focoDni.dispose();
    super.dispose();
  }

  // ── Buscar ─────────────────────────────────────────────────────────────────

  void _alEscribir(String texto) {
    _espera?.cancel();
    final faltan = SupabaseInvitadosRepository.letrasDe(texto) <
        SupabaseInvitadosRepository.letrasParaBuscar;
    setState(() {
      _errorBusqueda = null;
      if (faltan) {
        _pedido++;
        _encontrados = null;
        _buscandoEnLaNube = false;
      }
    });
    if (faltan) return;
    _espera = Timer(const Duration(milliseconds: 300), () => _buscar(texto));
  }

  Future<void> _buscar(String texto) async {
    final pedido = ++_pedido;
    setState(() {
      _buscandoEnLaNube = true;
      _errorBusqueda = null;
    });
    try {
      final r = await ref
          .read(supabaseInvitadosRepositoryProvider)
          .buscar(widget.eventoId, texto);
      // Mientras tanto se siguió escribiendo: esta respuesta ya no va.
      if (!mounted || pedido != _pedido) return;
      setState(() {
        _buscandoEnLaNube = false;
        _encontrados = r;
        _buscado = texto.trim();
      });
    } catch (e) {
      debugPrint('La página del QR no pudo buscar: $e');
      if (!mounted || pedido != _pedido) return;
      setState(() {
        _buscandoEnLaNube = false;
        _errorBusqueda = ListaInvitadosScreen.noSePudoBuscar;
      });
    }
  }

  void _elegir(EncontradoEnLaPuerta e) {
    _focoBuscador.unfocus();
    if (e.ingresado) {
      setState(() {
        _elegido = e;
        _mesa = e.mesa;
        _paso = _Paso.bienvenida;
      });
      return;
    }
    if (!e.tieneDni) {
      _aLaRecepcion(e, ListaInvitadosScreen.aLaRecepcion);
      return;
    }
    _dni.clear();
    setState(() {
      _elegido = e;
      _errorDni = null;
      _paso = _Paso.dni;
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _focoDni.requestFocus();
    });
  }

  void _aLaRecepcion(EncontradoEnLaPuerta e, String porQue) {
    setState(() {
      _elegido = e;
      _porQueALaRecepcion = porQue;
      _paso = _Paso.aLaRecepcion;
    });
  }

  void _volverABuscar({bool limpiar = false}) {
    setState(() {
      _paso = _Paso.buscando;
      _elegido = null;
      _errorDni = null;
      if (limpiar) {
        _buscador.clear();
        _encontrados = null;
      }
    });
    // Lo que se ve de la búsqueda puede estar viejo (alguien entró).
    if (!limpiar && _buscado.isNotEmpty) _buscar(_buscado);
  }

  // ── El DNI ─────────────────────────────────────────────────────────────────

  Future<void> _ingresar() async {
    final e = _elegido;
    if (e == null || _verificando) return;
    final dni = _dni.text.trim();
    if (dni.isEmpty) {
      setState(() => _errorDni = ListaInvitadosScreen.escribiTuDni);
      return;
    }
    setState(() {
      _verificando = true;
      _errorDni = null;
    });
    final IngresoConDni r;
    try {
      r = await ref
          .read(supabaseInvitadosRepositoryProvider)
          .ingresarConDni(invitadoId: e.id, dni: dni);
    } catch (err) {
      debugPrint('La página del QR no pudo verificar el DNI: $err');
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _errorDni = ListaInvitadosScreen.noSePudoVerificar;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _verificando = false);
    switch (r.resultado) {
      case ResultadoIngreso.ok:
      case ResultadoIngreso.yaIngresado:
        setState(() {
          _mesa = r.invitado?.numeroMesa ?? e.mesa;
          _paso = _Paso.bienvenida;
        });
      case ResultadoIngreso.dniIncorrecto:
        _dni.clear();
        setState(() => _errorDni =
            ListaInvitadosScreen.dniNoCoincide(r.quedan ?? 1));
        _focoDni.requestFocus();
      case ResultadoIngreso.bloqueado:
        _aLaRecepcion(e, ListaInvitadosScreen.bloqueado);
      case ResultadoIngreso.sinDni:
        _aLaRecepcion(e, ListaInvitadosScreen.aLaRecepcion);
      case ResultadoIngreso.masivo:
        _aLaRecepcion(e, ListaInvitadosScreen.enLaRecepcion);
      case ResultadoIngreso.noEncontrado:
        _aLaRecepcion(e, ListaInvitadosScreen.noTeEncontramos);
    }
  }

  // ── Lo que se ve ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Si el jefe cambia la foto o el saludo, el celular lo refleja.
    _cfg = ref.watch(totemConfigValueProvider(widget.eventoId));

    final cuerpo = !_eventoValido
        ? _eventoQueNoSirve()
        : switch (_paso) {
            _Paso.buscando => _buscando(),
            _Paso.dni => _pidiendoElDni(),
            _Paso.bienvenida => _bienvenida(),
            _Paso.aLaRecepcion => _aLaRecepcionVista(),
          };

    return Scaffold(
      backgroundColor: _fondo,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: cuerpo,
          ),
        ),
      ),
    );
  }

  TextStyle _titulo(double tamano, {Color? color}) => GoogleFonts.oswald(
        fontSize: tamano,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: color ?? _tinta,
      );

  TextStyle _texto(double tamano, {Color? color, bool negrita = false}) =>
      GoogleFonts.outfit(
        fontSize: tamano,
        fontWeight: negrita ? FontWeight.w700 : FontWeight.w400,
        color: color ?? _tinta,
        height: 1.4,
      );

  Widget _encabezado() => Column(
        children: [
          Text(
            _cfg.titulo,
            textAlign: TextAlign.center,
            style: _titulo(22),
          ),
          const SizedBox(height: 4),
          Text(
            'ENCONTRÁ TU LUGAR',
            style: _titulo(12, color: _acento).copyWith(letterSpacing: 3),
          ),
        ],
      );

  Widget _eventoQueNoSirve() {
    final viejo = widget.eventoId.length > 36;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2_rounded, size: 56, color: _tintaSuave),
          const SizedBox(height: 20),
          Text(
            viejo
                ? 'Este QR es de una versión anterior.\nPedí el QR nuevo en la recepción.'
                : 'No se especificó un evento válido.\nEscaneá el QR del tótem nuevamente.',
            textAlign: TextAlign.center,
            style: _texto(15, color: _tintaSuave),
          ),
        ],
      ),
    );
  }

  Widget _buscando() {
    final encontrados = _encontrados;
    final Widget debajo;
    if (_errorBusqueda != null) {
      debajo = _mensaje(
        _errorBusqueda!,
        icono: Icons.wifi_off_rounded,
        accion: TextButton(
          onPressed: () => _buscar(_buscador.text),
          child: Text('REINTENTAR', style: _texto(13, color: _acento, negrita: true)),
        ),
      );
    } else if (SupabaseInvitadosRepository.letrasDe(_buscador.text) <
        SupabaseInvitadosRepository.letrasParaBuscar) {
      debajo = _mensaje(ListaInvitadosScreen.faltanLetras,
          icono: Icons.search_rounded);
    } else if (encontrados == null) {
      debajo = Padding(
        padding: const EdgeInsets.only(top: 32),
        child: CircularProgressIndicator(color: _acento, strokeWidth: 2),
      );
    } else if (encontrados.isEmpty) {
      debajo = _mensaje(ListaInvitadosScreen.noEncontrado(_buscado),
          icono: Icons.person_search_rounded);
    } else {
      debajo = Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          itemCount: encontrados.length,
          itemBuilder: (_, i) => _Encontrado(
            encontrado: encontrados[i],
            acento: _acento,
            onTap: () => _elegir(encontrados[i]),
          ),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _encabezado(),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            key: const ValueKey('buscador'),
            controller: _buscador,
            focusNode: _focoBuscador,
            autofocus: true,
            onChanged: _alEscribir,
            textCapitalization: TextCapitalization.words,
            style: _texto(16),
            // En la web de un celular, Flutter suelta el teclado al apoyar el
            // dedo afuera y eso se comía el toque en un nombre. Se suelta al
            // levantarlo (como en `PanelPuerta`).
            onTapOutside: kIsWeb ? (_) {} : null,
            onTapUpOutside: kIsWeb ? (_) => _focoBuscador.unfocus() : null,
            decoration: InputDecoration(
              hintText: 'Escribí tu nombre',
              hintStyle: _texto(15, color: _tintaSuave),
              prefixIcon: Icon(Icons.search_rounded, color: _acento),
              suffixIcon: _buscandoEnLaNube && encontrados != null
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: _acento, strokeWidth: 2),
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x14000000)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x14000000)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _acento, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        debajo,
      ],
    );
  }

  Widget _mensaje(String texto, {required IconData icono, Widget? accion}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(36, 32, 36, 0),
        child: Column(
          children: [
            Icon(icono, size: 40, color: const Color(0x42000000)),
            const SizedBox(height: 12),
            Text(texto,
                textAlign: TextAlign.center,
                style: _texto(14, color: _tintaSuave)),
            if (accion != null) ...[const SizedBox(height: 8), accion],
          ],
        ),
      );

  Widget _pidiendoElDni() {
    final e = _elegido!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
      child: Column(
        children: [
          _encabezado(),
          const SizedBox(height: 32),
          Text('¿Sos vos?', style: _texto(14, color: _tintaSuave)),
          const SizedBox(height: 4),
          Text(e.nombre,
              textAlign: TextAlign.center,
              style: _texto(20, color: _acento, negrita: true)),
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('dni'),
            controller: _dni,
            focusNode: _focoDni,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            maxLength: 11,
            textAlign: TextAlign.center,
            style: _titulo(26).copyWith(letterSpacing: 4),
            onChanged: (_) {
              if (_errorDni != null) setState(() => _errorDni = null);
            },
            onSubmitted: (_) => _ingresar(),
            onTapOutside: kIsWeb ? (_) {} : null,
            onTapUpOutside: kIsWeb ? (_) => _focoDni.unfocus() : null,
            decoration: InputDecoration(
              hintText: 'Tu DNI',
              hintStyle: _texto(18, color: _tintaSuave),
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x14000000)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: _errorDni != null
                      ? Colors.redAccent
                      : const Color(0x14000000),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: _errorDni != null ? Colors.redAccent : _acento,
                  width: 2,
                ),
              ),
            ),
          ),
          if (_errorDni != null) ...[
            const SizedBox(height: 10),
            Text(_errorDni!,
                textAlign: TextAlign.center,
                style: _texto(13, color: const Color(0xFFC62828), negrita: true)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('ingresar'),
              onPressed: _verificando ? null : _ingresar,
              style: FilledButton.styleFrom(
                backgroundColor: _acento,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _verificando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2),
                    )
                  : Text('INGRESAR', style: _titulo(16, color: Colors.black)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _verificando ? null : () => _volverABuscar(),
            child: Text('No soy yo, buscar de nuevo',
                style: _texto(13, color: _tintaSuave)),
          ),
        ],
      ),
    );
  }

  Widget _bienvenida() {
    final e = _elegido!;
    final foto = _cfg.imagenUrl;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
      child: Column(
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _acento.withValues(alpha: 0.12),
              border: Border.all(color: _acento.withValues(alpha: 0.6), width: 2),
            ),
            child: foto != null
                ? ClipOval(
                    child: Image.network(
                      foto,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.celebration_rounded, color: _acento, size: 56),
                    ),
                  )
                : Icon(Icons.celebration_rounded, color: _acento, size: 56),
          ),
          const SizedBox(height: 24),
          Text(_cfg.mensajeBienvenida.toUpperCase(),
              textAlign: TextAlign.center, style: _titulo(34)),
          const SizedBox(height: 10),
          Text(e.nombre,
              textAlign: TextAlign.center,
              style: _texto(22, color: _acento, negrita: true)),
          const SizedBox(height: 22),
          if (_mesa != null && _mesa!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x14000000)),
              ),
              child: Column(
                children: [
                  Text('TU MESA ES LA',
                      style: _titulo(11, color: _tintaSuave)
                          .copyWith(letterSpacing: 2)),
                  Text(_mesa!, style: _titulo(52)),
                ],
              ),
            )
          else
            Text(ListaInvitadosScreen.mesaPorAsignar,
                textAlign: TextAlign.center,
                style: _texto(14, color: _tintaSuave)),
          const SizedBox(height: 24),
          Text('¡Que disfrutes la fiesta!',
              style: _texto(14, color: _tintaSuave)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => _volverABuscar(limpiar: true),
            child: Text('Volver', style: _texto(13, color: _tintaSuave)),
          ),
        ],
      ),
    );
  }

  Widget _aLaRecepcionVista() {
    final e = _elegido!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
      child: Column(
        children: [
          _encabezado(),
          const Spacer(),
          const Icon(Icons.how_to_reg_rounded, size: 48, color: _tintaSuave),
          const SizedBox(height: 12),
          Text(e.nombre,
              textAlign: TextAlign.center, style: _texto(18, negrita: true)),
          const SizedBox(height: 6),
          Text(_porQueALaRecepcion,
              textAlign: TextAlign.center,
              style: _texto(15, color: _tintaSuave)),
          const Spacer(),
          OutlinedButton(
            onPressed: () => _volverABuscar(limpiar: true),
            style: OutlinedButton.styleFrom(
              foregroundColor: _tinta,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: Text('Buscar de nuevo', style: _texto(14)),
          ),
        ],
      ),
    );
  }
}

/// Un nombre que encontró la búsqueda.
class _Encontrado extends StatelessWidget {
  final EncontradoEnLaPuerta encontrado;
  final Color acento;
  final VoidCallback onTap;

  const _Encontrado({
    required this.encontrado,
    required this.acento,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mesa = encontrado.mesa;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x14000000)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        encontrado.nombre,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xDE000000),
                        ),
                      ),
                      Text(
                        mesa == null || mesa.trim().isEmpty
                            ? 'Mesa por asignar'
                            : 'Mesa $mesa',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0x8A000000),
                        ),
                      ),
                    ],
                  ),
                ),
                if (encontrado.ingresado)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'Ya ingresó',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded,
                      color: acento.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
