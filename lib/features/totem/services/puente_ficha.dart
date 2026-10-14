import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../models/evento.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../recepcion/providers/recepcion_provider.dart'
    show AlumnosDeLaPuerta;
import '../../recepcion/services/puerta_del_evento.dart';
import 'ficha_totem.dart';
import 'lista_de_la_pc.dart';

/// La ficha del evento ([FichaTotem]) y quién ya entró según esta PC
/// ([ListaDeLaPc]) van de la ventana principal a la del tótem.
///
/// **Los pide el tótem; la ventana principal no se los empuja.** Un mensaje
/// mandado mientras la ventana del tótem recién nace lo contesta el manejador
/// provisorio de `main.dart` y se pierde sin error. Pidiéndolos, llegan cuando
/// el tótem ya está listo para recibirlos.
///
/// Todo sale de la base de esta PC: anda sin internet.
class PuenteFichaTotem {
  PuenteFichaTotem._();

  /// La ficha del evento.
  static const metodo = 'ficha_totem';

  /// Quién ya entró, según esta PC: el tótem la pide cuando no puede leer la
  /// nube y todavía no la leyó.
  static const metodoLista = 'lista_totem';

  /// La ventana principal es siempre la 0.
  static const ventanaPrincipal = 0;

  /// En la ventana principal: contesta los pedidos del tótem.
  static void atenderEnLaVentanaPrincipal(
    Future<FichaTotem> Function(String eventoId) armar, {
    Future<ListaDeLaPc> Function(String eventoId)? lista,
  }) {
    DesktopMultiWindow.setMethodHandler(
      (call, _) => responder(call, armar, lista: lista),
    );
  }

  /// Lo que contesta la ventana principal: la ficha o la lista codificadas,
  /// o null si el pedido no es para ella o no se pudo armar (el tótem sigue
  /// con lo que tenía).
  static Future<String?> responder(
    MethodCall call,
    Future<FichaTotem> Function(String eventoId) armar, {
    Future<ListaDeLaPc> Function(String eventoId)? lista,
  }) async {
    if (call.method != metodo && call.method != metodoLista) return null;
    final eventoId = call.arguments;
    // El mismo blindaje de UUID que usan los repos.
    if (eventoId is! String || eventoId.length != 36) return null;
    try {
      if (call.method == metodoLista) {
        return lista == null ? null : (await lista(eventoId)).codificar();
      }
      return (await armar(eventoId)).codificar();
    } catch (e) {
      debugPrint('No se pudo contestar "${call.method}" al tótem: $e');
      return null;
    }
  }

  /// En la ventana del tótem: pide quién ya entró según esta PC. Null si no
  /// llegó.
  static Future<ListaDeLaPc?> pedirLista(String eventoId) async {
    try {
      final respuesta = await DesktopMultiWindow.invokeMethod(
        ventanaPrincipal,
        metodoLista,
        eventoId,
      );
      final lista = ListaDeLaPc.decodificar(respuesta);
      return lista?.eventoId == eventoId ? lista : null;
    } catch (e) {
      debugPrint('El tótem no pudo pedir la lista de la PC: $e');
      return null;
    }
  }

  /// En la ventana del tótem: pide la ficha. Null si no llegó.
  static Future<FichaTotem?> pedir(String eventoId) async {
    try {
      final respuesta = await DesktopMultiWindow.invokeMethod(
        ventanaPrincipal,
        metodo,
        eventoId,
      );
      final ficha = FichaTotem.decodificar(respuesta);
      return ficha?.eventoId == eventoId ? ficha : null;
    } catch (e) {
      debugPrint('El tótem no pudo pedir la ficha del evento: $e');
      return null;
    }
  }
}

/// La ficha de un evento con lo que hay en la base de esta PC: lo mismo que
/// ve Recepción ([PuertaDelEvento]).
///
/// De un masivo lee los alumnos y cómo repartió cada familia sus sillas, y el
/// salón de su plano ([leerPlano]). Quién entró no hace falta: eso el tótem lo
/// sabe por su cuenta. Si el plano no se puede leer, la ficha va sin él.
Future<FichaTotem> armarFichaTotem(
  String eventoId, {
  required Future<Evento?> Function(String eventoId) leerEvento,
  required Future<AlumnosDeLaPuerta> Function(String eventoId) leerAlumnos,
  Future<ArmadoSalon?> Function(String eventoId)? leerPlano,
}) async {
  final evento = await leerEvento(eventoId);
  if (evento?.modalidad != 'masivo') return FichaTotem.particular(eventoId);
  final a = await leerAlumnos(eventoId);
  ArmadoSalon? plano;
  try {
    plano = await leerPlano?.call(eventoId);
  } catch (e) {
    debugPrint('La ficha del tótem va sin plano: $e');
  }
  return FichaTotem.desdePuerta(
    eventoId,
    PuertaDelEvento.masivo(
      alumnos: a.alumnos,
      repartos: a.repartos,
      invitados: const [],
    ),
    plano: plano,
  );
}
