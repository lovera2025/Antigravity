import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'las fuentes del cierre están incluidas para trabajar sin internet',
    () async {
      final regular = await rootBundle.load(
        'assets/google_fonts/Outfit-Regular.ttf',
      );
      final bold = await rootBundle.load('assets/google_fonts/Outfit-Bold.ttf');

      expect(regular.lengthInBytes, greaterThan(10000));
      expect(bold.lengthInBytes, greaterThan(10000));
    },
  );

  test(
    'las letras del plano (Gala y Neón) están incluidas y el PDF las lee',
    () async {
      for (final archivo in const [
        'assets/google_fonts/CormorantGaramond-SemiBold.ttf',
        'assets/google_fonts/TiltNeon-Regular.ttf',
      ]) {
        final datos = await rootBundle.load(archivo);
        expect(datos.lengthInBytes, greaterThan(10000), reason: archivo);
        // El plano impreso las usa: el paquete pdf tiene que poder leerlas.
        // `Font.ttf` solo no prueba nada (no abre el archivo hasta usarlo):
        // se le pide el nombre y se arma un PDF de verdad con números, tildes
        // y el "°" de las divisiones.
        final letra = pw.Font.ttf(datos);
        expect(letra.fontName, isNotEmpty, reason: archivo);
        final pdf = pw.Document()
          ..addPage(
            pw.Page(
              build: (_) => pw.Text(
                '0123456789 ÁÉÍÓÚÑ 5° A',
                style: pw.TextStyle(font: letra, fontSize: 24),
              ),
            ),
          );
        expect((await pdf.save()).length, greaterThan(1000), reason: archivo);
      }
    },
  );
}
