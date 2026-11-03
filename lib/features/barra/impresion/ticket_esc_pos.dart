import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'tabla_850.dart';

/// Una línea de lo que se imprime. La misma lista va a servir para el PDF del ticket.
sealed class LineaTicket {
  const LineaTicket();
}

class TituloTicket extends LineaTicket {
  final String texto;
  const TituloTicket(this.texto);
}

class TextoTicket extends LineaTicket {
  final String texto;
  final bool centrado;
  final bool negrita;
  const TextoTicket(this.texto, {this.centrado = true, this.negrita = false});
}

/// Izquierda y derecha en el mismo renglón: "2 x Cerveza" y "$ 7.000".
class RenglonTicket extends LineaTicket {
  final String izquierda;
  final String derecha;
  final bool negrita;
  const RenglonTicket(this.izquierda, this.derecha, {this.negrita = false});
}

class SeparadorTicket extends LineaTicket {
  const SeparadorTicket();
}

class QrTicket extends LineaTicket {
  final String dato;
  const QrTicket(this.dato);
}

class LogoTicket extends LineaTicket {
  final img.Image imagen;
  const LogoTicket(this.imagen);
}

/// Cuál logo va arriba del ticket y cómo se pasa a negro, que es lo único que imprime
/// el papel térmico.
enum LogoDelPapel {
  /// `2.png`: blanco y magenta sobre transparente, todo en negro.
  silueta('assets/icons/2.png'),

  /// `isotipo-ej.png`: negro y magenta sobre fondo claro, lo oscuro en negro.
  isotipo('assets/icons/isotipo-ej.png');

  final String asset;
  const LogoDelPapel(this.asset);

  img.Image? paraPapel(Uint8List png, {int ancho = 240}) => switch (this) {
        LogoDelPapel.silueta => LogoParaPapel.silueta(png, ancho: ancho),
        LogoDelPapel.isotipo => LogoParaPapel.umbral(png, ancho: ancho),
      };

  /// Null si el archivo no está o no se puede leer: el ticket sale sin logo.
  Future<img.Image?> cargar(AssetBundle bundle) async {
    try {
      final datos = await bundle.load(asset);
      return paraPapel(datos.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}

/// Lo que depende de la impresora. Lo fija la prueba con el papel en la mano.
class OpcionesEscPos {
  /// Con la tabla 850 (`tabla_850.dart`). False: se imprimen sin acentos, que se leen
  /// en cualquier impresora.
  final bool conAcentos;

  final LogoDelPapel logo;

  const OpcionesEscPos({
    this.conAcentos = true,
    this.logo = LogoDelPapel.isotipo,
  });

  /// Lo que dio la TP-POS58 con el papel en la mano, el 3-nov-2026: los acentos van con
  /// la tabla 850 (con la 1252 salían letras raras); el QR nativo se lee con el celular;
  /// las 32 letras entran justas en un renglón; y el isotipo se lee mejor que la silueta
  /// de `2.png`. Es lo que usa la app.
  static const deLaPrueba = OpcionesEscPos(
    conAcentos: true,
    logo: LogoDelPapel.isotipo,
  );
}

/// Convierte el texto en lo que la impresora puede escribir, y **nunca tira**: el nombre
/// de un producto con un emoji no puede frenar una venta. Sin acentos los cambia por la
/// letra sola: "Café" sale "Cafe".
String textoParaPapel(String texto, {required bool conAcentos}) {
  const sinAcento = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
    '¿': '?', '¡': '!', '°': 'o', 'º': 'o', 'ª': 'a', '·': '-',
  };
  final salida = StringBuffer();
  for (final runa in texto.runes) {
    final letra = String.fromCharCode(runa);
    if (!conAcentos && sinAcento.containsKey(letra)) {
      salida.write(sinAcento[letra]);
    } else if (runa < 0x80 || (conAcentos && entraEnLa850(letra))) {
      salida.write(letra);
    } else {
      salida.write('?');
    }
  }
  return salida.toString();
}

/// Cuántas letras entran en un renglón de 58 mm. Se vio en el papel el 3-nov-2026: las
/// 32 cifras de la prueba ANCHO entran justas.
const letrasPorRenglon = 32;

/// Los renglones de un [RenglonTicket]: el importe a la derecha del primero y el nombre
/// partido por palabras, sin pisarlo. Una palabra que no entra sola se corta. Así un
/// producto de nombre largo no queda "product / o".
List<String> renglonesDe(
  String izquierda,
  String derecha, {
  int letras = letrasPorRenglon,
}) {
  final der = derecha.trim();
  final lugar = der.isEmpty ? letras : letras - der.length - 1;
  if (lugar < 1) {
    return [
      ...partirPorPalabras(izquierda.trim(), letras),
      der.length > letras ? der.substring(0, letras) : der.padLeft(letras),
    ];
  }
  final partes = partirPorPalabras(izquierda.trim(), lugar);
  return [
    if (der.isEmpty) partes.first else partes.first.padRight(letras - der.length) + der,
    ...partes.skip(1),
  ];
}

/// [texto] en renglones de hasta [ancho] letras, partido por palabras. Nunca vacía:
/// sin texto da un renglón en blanco.
List<String> partirPorPalabras(String texto, int ancho) {
  final renglones = <String>[];
  var actual = '';
  for (var palabra in texto.split(RegExp(r'\s+'))) {
    while (palabra.length > ancho) {
      if (actual.isNotEmpty) {
        renglones.add(actual);
        actual = '';
      }
      renglones.add(palabra.substring(0, ancho));
      palabra = palabra.substring(ancho);
    }
    if (palabra.isEmpty) continue;
    if (actual.isEmpty) {
      actual = palabra;
    } else if (actual.length + 1 + palabra.length <= ancho) {
      actual = '$actual $palabra';
    } else {
      renglones.add(actual);
      actual = palabra;
    }
  }
  if (actual.isNotEmpty || renglones.isEmpty) renglones.add(actual);
  return renglones;
}

/// Arma los bytes ESC/POS de un papel de 58 mm: [letrasPorRenglon] letras por renglón.
class TicketEscPos {
  final CapabilityProfile perfil;
  final OpcionesEscPos opciones;

  const TicketEscPos(this.perfil, {this.opciones = OpcionesEscPos.deLaPrueba});

  static Future<TicketEscPos> cargar({
    OpcionesEscPos opciones = OpcionesEscPos.deLaPrueba,
  }) async =>
      TicketEscPos(await CapabilityProfile.load(), opciones: opciones);

  List<int> armar(List<LineaTicket> lineas, {bool cortar = true}) {
    final conAcentos = opciones.conAcentos;
    final g = Generator(
      PaperSize.mm58,
      perfil,
      codec: conAcentos ? tabla850 : latin1,
    );
    String t(String s) => textoParaPapel(s, conAcentos: conAcentos);
    final bytes = <int>[...g.reset()];
    if (conAcentos) bytes.addAll(g.setGlobalCodeTable('CP850'));
    for (final l in lineas) {
      switch (l) {
        case TituloTicket():
          bytes.addAll(g.text(
            t(l.texto),
            styles: const PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2,
            ),
          ));
        case TextoTicket():
          bytes.addAll(g.text(
            t(l.texto),
            styles: PosStyles(
              align: l.centrado ? PosAlign.center : PosAlign.left,
              bold: l.negrita,
            ),
          ));
        case RenglonTicket():
          for (final r in renglonesDe(t(l.izquierda), t(l.derecha))) {
            bytes.addAll(g.text(r, styles: PosStyles(bold: l.negrita)));
          }
        case SeparadorTicket():
          bytes.addAll(g.hr());
        case QrTicket():
          bytes.addAll(g.qrcode(l.dato, size: QRSize.size5));
        case LogoTicket():
          bytes.addAll(g.imageRaster(l.imagen));
      }
    }
    bytes.addAll(g.feed(3));
    if (cortar) bytes.addAll(g.cut());
    return bytes;
  }
}

/// El logo como lo necesita el papel térmico, que solo imprime negro.
class LogoParaPapel {
  LogoParaPapel._();

  /// Todo lo que no es transparente va en negro. Para un logo claro sobre fondo
  /// transparente, como `2.png`, que en papel blanco desaparecería.
  static img.Image? silueta(Uint8List png, {int ancho = 240}) {
    final chica = _leer(png, ancho);
    return chica == null ? null : _aBlancoYNegro(chica, (p) => p.a > 128);
  }

  /// Lo oscuro va en negro. Para una imagen con fondo claro, como `isotipo-ej.png`.
  static img.Image? umbral(Uint8List png, {int ancho = 240, int corte = 160}) {
    final chica = _leer(png, ancho);
    return chica == null
        ? null
        : _aBlancoYNegro(chica, (p) => p.luminance < corte && p.a > 128);
  }

  /// Null si la imagen está rota: un logo dañado deja el ticket sin logo, no sin
  /// ticket. El paquete tira en vez de devolver null.
  static img.Image? _leer(Uint8List png, int ancho) {
    try {
      final original = img.decodeImage(png);
      return original == null ? null : img.copyResize(original, width: ancho);
    } catch (_) {
      return null;
    }
  }

  static img.Image _aBlancoYNegro(img.Image i, bool Function(img.Pixel) negro) {
    final salida = img.Image(width: i.width, height: i.height);
    for (final p in i) {
      final v = negro(p) ? 0 : 255;
      salida.setPixelRgb(p.x, p.y, v, v, v);
    }
    return salida;
  }
}

/// Lo que se manda para probar la impresora: un ticket como el que va a salir, con datos
/// inventados.
List<LineaTicket> ticketDePrueba({img.Image? logo}) => [
      if (logo != null) LogoTicket(logo),
      const TituloTicket('JUNIOR EVENTOS'),
      const TextoTicket('BARRA', negrita: true),
      const TextoTicket('Puerto Viejo'),
      const TextoTicket('04/12/2026 - 23:41'),
      const TextoTicket('Caja 2 - Marta'),
      const SeparadorTicket(),
      const RenglonTicket('2 x Cerveza lata', r'$ 7.000'),
      const RenglonTicket('1 x Fernet con coca', r'$ 6.000'),
      const RenglonTicket('3 x Agua', r'$ 3.000'),
      const SeparadorTicket(),
      const RenglonTicket('TOTAL', r'$ 16.000', negrita: true),
      const RenglonTicket('Efectivo', ''),
      const RenglonTicket('Recibe', r'$ 20.000'),
      const RenglonTicket('Vuelto', r'$ 4.000'),
      const SeparadorTicket(),
      const TextoTicket('Caja 2 - N° 0017', negrita: true),
      const QrTicket('je:barra:prueba-0017'),
      const TextoTicket('¡Gracias, salud!'),
    ];

/// La línea de letras para ver cómo salen los acentos con cada tabla.
const lineaDeAcentos = 'áéíóúñ ÁÉÍÓÚÑ ü ¿¡ N° \$ 1/2';

/// Para que los tests puedan buscar un texto en los bytes, con los acentos de la tabla 850.
String bytesComoTexto(List<int> bytes) => tabla850.decode(bytes);
