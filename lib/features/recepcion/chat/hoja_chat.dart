import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../common/utils/cortes_pantalla.dart';
import 'aviso_del_celular.dart';
import 'chat_del_puesto.dart';
import 'mensaje_de_puesto.dart';

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

String _hora(DateTime t) {
  final h = t.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(h.hour)}:${dos(h.minute)}';
}

/// El botón del chat de la puerta (6.5.0), con el número de lo sin leer.
class BotonChat extends StatelessWidget {
  const BotonChat({super.key, required this.chat, this.color = _perla});

  final ChatDelPuesto chat;
  final Color color;

  static const ayuda = 'Chat de la puerta';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: chat,
        builder: (context, _) {
          final sinLeer = chat.sinLeer;
          return Badge(
            isLabelVisible: sinLeer > 0,
            label: Text('$sinLeer', key: const ValueKey('chat_sin_leer')),
            backgroundColor: Colors.redAccent,
            offset: const Offset(-4, 4),
            child: IconButton(
              key: const ValueKey('boton_chat'),
              tooltip: ayuda,
              onPressed: () => abrirChat(context, chat),
              icon: Icon(Icons.forum_outlined, color: color),
            ),
          );
        },
      );
}

/// Abre el chat: la lista de a quién hablarle o, con [conversacion], esa.
Future<void> abrirChat(
  BuildContext context,
  ChatDelPuesto chat, {
  String? conversacion,
}) {
  final tam = MediaQuery.sizeOf(context);
  final hoja = HojaChat(chat: chat, inicial: conversacion);
  return showDialog<void>(
    context: context,
    builder: (_) => CortesPantalla.esCelular(tam.width)
        ? Dialog.fullscreen(backgroundColor: _fondo, child: hoja)
        : Dialog(
            backgroundColor: _fondo,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: _perla.withValues(alpha: 0.15)),
            ),
            child: SizedBox(
              width: math.min(920, tam.width - 48),
              height: math.min(680, tam.height - 48),
              child: hoja,
            ),
          ),
  );
}

/// El chat de la puerta (6.5.0, pedido del usuario el 9-nov): primero se elige
/// **a quién** se le habla, una recepcionista o Todos, y después se escribe.
/// Se adapta solo: en la PC, la lista a la izquierda y la conversación a la
/// derecha; en el celular, una pantalla y la otra.
class HojaChat extends StatefulWidget {
  const HojaChat({super.key, required this.chat, this.inicial});

  final ChatDelPuesto chat;

  /// La conversación que se abre (desde el aviso). Null: la lista.
  final String? inicial;

  static const titulo = 'CHAT DE LA PUERTA';
  static const elegir = 'Elegí a quién le hablás: lo ven la PC y los celulares '
      'conectados a la notebook. Dura la noche.';

  @override
  State<HojaChat> createState() => _HojaChatState();
}

class _HojaChatState extends State<HojaChat> {
  ChatDelPuesto get _chat => widget.chat;
  String? _abierta;
  final _texto = TextEditingController();
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _abierta = widget.inicial;
    // Después del cuadro: avisar mientras se arma la pantalla no se puede (el
    // número del botón se redibuja).
    final chat = _chat;
    final abierta = _abierta;
    WidgetsBinding.instance.addPostFrameCallback((_) => chat.abrir(abierta));
  }

  @override
  void dispose() {
    final chat = _chat;
    WidgetsBinding.instance.addPostFrameCallback((_) => chat.abrir(null));
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _elegir(String? conversacion) {
    setState(() => _abierta = conversacion);
    _chat.abrir(conversacion);
    if (conversacion != null) _foco.requestFocus();
  }

  void _mandar() {
    final a = _abierta;
    if (a == null) return;
    if (_chat.mandar(_texto.text, a) != null) {
      _texto.clear();
      setState(() {});
    }
    _foco.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _chat,
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) {
            final ancho = c.maxWidth >= 600;
            // En la PC se abre con Todos, así no queda la mitad vacía.
            if (ancho && _abierta == null) {
              _abierta = kTodos;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _chat.abrir(kTodos));
            }
            if (ancho) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 280, child: _lista(conCerrar: false)),
                  VerticalDivider(
                    width: 1,
                    color: _perla.withValues(alpha: 0.12),
                  ),
                  Expanded(child: _conversacion(_abierta!, conVolver: false)),
                ],
              );
            }
            final a = _abierta;
            return a == null
                ? _lista(conCerrar: true)
                : _conversacion(a, conVolver: true);
          },
        ),
      );

  Widget _lista({required bool conCerrar}) {
    final conversaciones = _chat.conversaciones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  HojaChat.titulo,
                  style: _letra(size: 15, negrita: true),
                ),
              ),
              if (conCerrar)
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: _perla),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text(
            HojaChat.elegir,
            style: _letra(size: 12, color: Colors.white54),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final c in conversaciones) _filaDeConversacion(c),
              if (conversaciones.length == 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Text(
                    'Todavía no hay otro puesto conectado. Se suma desde '
                    'CELULARES, en la PC.',
                    style: _letra(size: 12, color: Colors.white38),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filaDeConversacion(ConversacionDelPuesto c) {
    final elegida = c.id == _abierta;
    final ultimo = c.ultimo;
    return Material(
      color: elegida ? _perla.withValues(alpha: 0.08) : Colors.transparent,
      child: ListTile(
        key: ValueKey('conversacion_${c.id}'),
        onTap: () => _elegir(c.id),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _perla.withValues(alpha: 0.1),
              child: c.esTodos
                  ? const Icon(Icons.groups_rounded, color: _perla, size: 20)
                  : Text(
                      c.nombre.isEmpty ? '?' : c.nombre[0].toUpperCase(),
                      style: _letra(negrita: true),
                    ),
            ),
            if (!c.esTodos)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.conectado ? _verde : Colors.white24,
                    border: Border.all(color: _fondo, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(c.nombre, style: _letra(negrita: c.sinLeer > 0)),
        subtitle: Text(
          ultimo == null
              ? (c.esTodos ? 'Para todos los puestos' : 'Sin mensajes')
              : '${ultimo.de == _chat.yo ? 'Vos' : ultimo.deNombre}: '
                  '${ultimo.texto}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _letra(size: 12, color: Colors.white54),
        ),
        trailing: c.sinLeer > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${c.sinLeer}',
                  style: _letra(size: 12, negrita: true, color: Colors.white),
                ),
              )
            : null,
      ),
    );
  }

  Widget _conversacion(String id, {required bool conVolver}) {
    final c = _chat.conversaciones.where((x) => x.id == id).firstOrNull;
    final nombre = c?.nombre ?? id;
    final mensajes = _chat.de(id);
    final puede = _chat.puedeMandar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(conVolver ? 4 : 18, 10, 6, 6),
          child: Row(
            children: [
              if (conVolver)
                IconButton(
                  key: const ValueKey('volver_a_la_lista'),
                  tooltip: 'A quién le hablo',
                  onPressed: () => _elegir(null),
                  icon: const Icon(Icons.arrow_back_rounded, color: _perla),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      id == kTodos ? 'Todos' : nombre,
                      style: _letra(size: 16, negrita: true),
                    ),
                    Text(
                      id == kTodos
                          ? 'Lo ven todos los puestos'
                          : c?.conectado ?? false
                              ? 'Conectado'
                              : 'Sin conexión: lo ve al volver',
                      style: _letra(size: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: _perla),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: _perla.withValues(alpha: 0.12)),
        Expanded(
          child: mensajes.isEmpty
              ? Center(
                  child: Text(
                    id == kTodos
                        ? 'Escribí algo para todos los puestos.'
                        : 'Escribile a $nombre.',
                    style: _letra(size: 13, color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: mensajes.length,
                  itemBuilder: (_, i) =>
                      _burbuja(mensajes[mensajes.length - 1 - i], id),
                ),
        ),
        if (!puede)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Text(
              'Sin conexión con la PC: no se puede mandar hasta que vuelva.',
              style: _letra(size: 12, color: _ambar),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('texto_del_chat'),
                  controller: _texto,
                  focusNode: _foco,
                  enabled: puede,
                  maxLength: kLargoDelMensaje,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  style: _letra(size: 15),
                  decoration: InputDecoration(
                    hintText: id == kTodos
                        ? 'Para todos'
                        : 'Para $nombre',
                    hintStyle: _letra(size: 15, color: Colors.white38),
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _mandar(),
                  onTapOutside: kIsWeb ? (_) {} : null,
                  onTapUpOutside: kIsWeb ? (_) => _foco.unfocus() : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('enviar_chat'),
                onPressed:
                    puede && _texto.text.trim().isNotEmpty ? _mandar : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _verde,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(
                  'ENVIAR',
                  style: _letra(size: 12, negrita: true, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _burbuja(MensajeDePuesto m, String conversacion) {
    final mio = m.de == _chat.yo;
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        decoration: BoxDecoration(
          color: mio
              ? _verde.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              mio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              '${mio ? 'Vos' : m.deNombre} · ${_hora(m.hora)}',
              style: _letra(size: 11, color: Colors.white54),
            ),
            Text(m.texto, style: _letra(size: 14)),
          ],
        ),
      ),
    );
  }
}

/// La línea de arriba de la lista de la puerta cuando llega un mensaje con esa
/// conversación cerrada: "Juli, a vos: ¿alguien vio a GÓMEZ?". Suena en la PC y
/// vibra en el celular. Tocarla abre esa conversación. Se va a los 6 s.
class AvisoDelChat extends StatefulWidget {
  const AvisoDelChat({super.key, required this.chat});

  final ChatDelPuesto chat;

  static const dura = Duration(seconds: 6);

  @override
  State<AvisoDelChat> createState() => _AvisoDelChatState();
}

class _AvisoDelChatState extends State<AvisoDelChat> {
  StreamSubscription<MensajeNuevo>? _escucha;
  MensajeNuevo? _ultimo;
  Timer? _borrar;

  @override
  void initState() {
    super.initState();
    _escuchar();
  }

  @override
  void didUpdateWidget(AvisoDelChat old) {
    super.didUpdateWidget(old);
    if (!identical(old.chat, widget.chat)) {
      unawaited(_escucha?.cancel());
      _escuchar();
    }
  }

  void _escuchar() {
    _escucha = widget.chat.nuevos.listen((n) {
      if (!mounted) return;
      unawaited(avisarMensajeNuevo());
      _borrar?.cancel();
      setState(() => _ultimo = n);
      _borrar = Timer(AvisoDelChat.dura, () {
        if (mounted) setState(() => _ultimo = null);
      });
    });
  }

  @override
  void dispose() {
    unawaited(_escucha?.cancel());
    _borrar?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _ultimo;
    if (n == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Material(
        color: _ambar.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const ValueKey('aviso_del_chat'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _borrar?.cancel();
            setState(() => _ultimo = null);
            unawaited(abrirChat(context, widget.chat, conversacion: n.conversacion));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, color: _ambar, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${n.quien}: ',
                          style: _letra(size: 13, negrita: true, color: _ambar),
                        ),
                        TextSpan(
                          text: n.mensaje.texto,
                          style: _letra(size: 13, color: _ambar),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'RESPONDER',
                  style: _letra(size: 11, negrita: true, color: _ambar),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
