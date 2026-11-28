import 'sonido_de_la_pagina_otros.dart' if (dart.library.js_interop) 'sonido_de_la_pagina_web.dart' as sonido;

/// **El aviso con sonido de la página del iPhone** (28-nov-2026): cuando una cajera pide
/// el OK del cierre. En el iPhone el navegador no deja sonar nada hasta que la persona
/// toca la pantalla una vez: [desbloquear] se llama con el primer toque (ENTRAR), y desde
/// ahí [sonar] suena. Fuera del navegador no hace nada.
abstract final class SonidoDeLaPagina {
  static void desbloquear() => sonido.desbloquear();
  static void sonar() => sonido.sonar();
}
