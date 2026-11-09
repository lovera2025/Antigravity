import 'package:flutter/services.dart';

/// En la PC: el mismo sonido de "pagó: ya podés entregar".
Future<void> avisarMensajeNuevo() async {
  try {
    await SystemSound.play(SystemSoundType.alert);
  } catch (_) {}
}
