import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../core/database/local_database.dart';
import '../../../core/utils/ar_time.dart';

/// Lo que se hace después de que un cobro quedó guardado en la PC (6.5.0).
///
/// El 9-nov-2026 el usuario contó que a veces, al CONFIRMAR PAGO, el modal del
/// cobro quedaba abierto con el pago ya hecho: tenía que cerrarlo él y al rato
/// salía el recibo. Era la subida a la nube: el modal la esperaba antes de
/// cerrarse, y con internet lento se quedaba en GUARDANDO. Y si algo de lo de
/// después fallaba, el cartel decía "No se pudo guardar el cobro. Reintentá"
/// con el cobro ya guardado: reintentar lo cobraba dos veces.
///
/// Ahora el modal se cierra apenas vuelve `registrarPagosLote`
/// ([cerrarRuta]) y lo de después corre acá, cada paso por su lado: uno que
/// falla o tarda no frena a los demás ni dice que el cobro no se guardó. Lo que
/// falla queda escrito en `cobros_despues_de_guardar.txt`, junto a la base.
class PasoDespuesDeGuardar {
  /// Cómo se dice en el archivo: "la subida a la nube", "el recibo".
  final String nombre;
  final FutureOr<void> Function() hacer;

  const PasoDespuesDeGuardar(this.nombre, this.hacer);
}

/// Un paso que falló, con su error.
class FallaDespuesDeGuardar {
  final String paso;
  final Object error;

  const FallaDespuesDeGuardar(this.paso, this.error);
}

/// Dónde se anota lo que falló. En la app, el archivo junto a la base; en las
/// pruebas, una lista.
typedef AnotarFallas = Future<void> Function(
  String alumno,
  List<FallaDespuesDeGuardar> fallas,
);

class DespuesDeGuardarCobro {
  DespuesDeGuardarCobro._();

  static const archivo = 'cobros_despues_de_guardar.txt';

  /// Corre [pasos] en orden, cada uno en su propio `try`: el que falla no corta
  /// al siguiente. Devuelve los que fallaron, ya anotados. **Nunca lanza.**
  static Future<List<FallaDespuesDeGuardar>> correr({
    required String alumno,
    required List<PasoDespuesDeGuardar> pasos,
    AnotarFallas? anotar,
  }) async {
    final fallas = <FallaDespuesDeGuardar>[];
    for (final p in pasos) {
      try {
        await p.hacer();
      } catch (e) {
        debugPrint('Cobro de $alumno, después de guardar, ${p.nombre}: $e');
        fallas.add(FallaDespuesDeGuardar(p.nombre, e));
      }
    }
    if (fallas.isNotEmpty) {
      try {
        await (anotar ?? anotarEnLaPc)(alumno, fallas);
      } catch (e) {
        debugPrint('No pude anotar lo que falló después del cobro: $e');
      }
    }
    return fallas;
  }

  /// Agrega el bloque al archivo, en la carpeta de la base (Documentos\Junior
  /// Eventos), como `revision_mora.txt`.
  static Future<void> anotarEnLaPc(
    String alumno,
    List<FallaDespuesDeGuardar> fallas,
  ) async {
    final base = File(await LocalDatabase.dbPath);
    final destino = File('${base.parent.path}${Platform.pathSeparator}$archivo');
    await destino.writeAsString(
      textoDe(alumno, fallas, ArTime.nowAr()),
      mode: FileMode.append,
      flush: true,
    );
  }

  /// El bloque que se agrega al archivo, aparte para poder probarlo.
  static String textoDe(
    String alumno,
    List<FallaDespuesDeGuardar> fallas,
    DateTime ahoraAr,
  ) {
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = '${dos(ahoraAr.day)}/${dos(ahoraAr.month)}/${ahoraAr.year} '
        '${dos(ahoraAr.hour)}:${dos(ahoraAr.minute)}:${dos(ahoraAr.second)}';
    final b = StringBuffer()
      ..writeln('$cuando · cobro de $alumno, ya guardado en esta PC. Después '
          'falló:');
    for (final f in fallas) {
      b.writeln('  ${f.paso}: ${f.error}');
    }
    b.writeln();
    return b.toString();
  }
}

/// Cierra [ruta] (el modal del cobro), y solo esa.
///
/// `Navigator.pop` cierra la de arriba de todo, que no siempre es la del cobro:
/// si mientras se guardaba se abrió otra ventana encima, se cerraba esa y el
/// modal del cobro quedaba abierto. Si [ruta] está arriba, se cierra con
/// [resultado]; si quedó tapada, se saca sin tocar la de encima. Si ya se
/// cerró, no hace nada.
void cerrarRuta(Route<dynamic>? ruta, {Object? resultado}) {
  if (ruta == null || !ruta.isActive) return;
  final navegador = ruta.navigator;
  if (navegador == null) return;
  if (ruta.isCurrent) {
    navegador.pop(resultado);
  } else {
    navegador.removeRoute(ruta);
  }
}
