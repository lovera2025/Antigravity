import 'dart:convert';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

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

/// Lo que depende de la impresora. Lo fija la prueba con el papel en la mano.
class OpcionesEscPos {
  /// Con qué tabla salen los acentos. Null: se imprimen sin acentos.
  final String? tablaCaracteres;

  const OpcionesEscPos({this.tablaCaracteres = 'CP1252'});
}

/// Convierte el texto en lo que la impresora puede escribir, y **nunca tira**: el nombre
/// de un producto con un emoji no puede frenar una venta. Sin tabla, además, saca los
/// acentos: con otra tabla saldrían letras raras.
String textoParaPapel(String texto, {required bool conAcentos}) {
  const sinAcento = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
    '¿': '?', '¡': '!', '°': 'o', '·': '-',
  };
  final salida = StringBuffer();
  for (final runa in texto.runes) {
    final letra = String.fromCharCode(runa);
    if (!conAcentos && sinAcento.containsKey(letra)) {
      salida.write(sinAcento[letra]);
    } else if (runa <= 0xFF && (conAcentos || runa < 0x80)) {
      salida.write(letra);
    } else {
      salida.write('?');
    }
  }
  return salida.toString();
}

/// Arma los bytes ESC/POS de un papel de 58 mm: 32 letras por renglón.
class TicketEscPos {
  final CapabilityProfile perfil;
  final OpcionesEscPos opciones;

  const TicketEscPos(this.perfil, {this.opciones = const OpcionesEscPos()});

  static Future<TicketEscPos> cargar({
    OpcionesEscPos opciones = const OpcionesEscPos(),
  }) async =>
      TicketEscPos(await CapabilityProfile.load(), opciones: opciones);

  List<int> armar(List<LineaTicket> lineas, {bool cortar = true}) {
    final g = Generator(PaperSize.mm58, perfil);
    final conAcentos = opciones.tablaCaracteres != null;
    String t(String s) => textoParaPapel(s, conAcentos: conAcentos);
    final bytes = <int>[...g.reset()];
    if (conAcentos) bytes.addAll(g.setGlobalCodeTable(opciones.tablaCaracteres));
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
          bytes.addAll(g.row([
            PosColumn(
              text: t(l.izquierda),
              width: 8,
              styles: PosStyles(bold: l.negrita),
            ),
            PosColumn(
              text: t(l.derecha),
              width: 4,
              styles: PosStyles(align: PosAlign.right, bold: l.negrita),
            ),
          ]));
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

/// Para que los tests puedan buscar un texto en los bytes.
String bytesComoTexto(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);
