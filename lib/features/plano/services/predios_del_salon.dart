import 'dart:convert';

import '../../../core/utils/uuid_utils.dart';
import '../../../models/predio.dart';
import '../modelo/armado_salon.dart';
import '../modelo/medidas_salon.dart';
import 'armar_a_medida.dart';

/// Lo que decide GUARDAR COMO PREDIO, Renombrar y Borrar (6.1.0), sin
/// pantalla ni base: devuelve el predio como tiene que quedar, o por qué no.
class PrediosDelSalon {
  PrediosDelSalon._();

  /// El de fábrica: es la tarjeta "Salón vacío", y su nombre no se usa.
  static const nombreDeFabrica = 'Costa Surubí';

  static const largoMaximo = 40;

  /// El nombre como se guarda: sin espacios de más.
  static String limpiar(String nombre) =>
      nombre.trim().replaceAll(RegExp(r'\s+'), ' ');

  static const _sinTildes = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  };

  /// Para comparar: "buena vista", "Buena  Vista" y "BUENA VISTA" son el
  /// mismo nombre, y "Costa Surubi" es el de fábrica.
  static String _comparable(String nombre) => limpiar(nombre)
      .toLowerCase()
      .split('')
      .map((c) => _sinTildes[c] ?? c)
      .join();

  static bool mismoNombre(String a, String b) => _comparable(a) == _comparable(b);

  /// El guardado que tiene ese nombre (sin contar [exceptoId]), o null.
  static Predio? conElNombre(
    String nombre,
    Iterable<Predio> guardados, {
    String? exceptoId,
  }) {
    for (final p in guardados) {
      if (p.id != exceptoId && !p.borrado && mismoNombre(p.nombre, nombre)) {
        return p;
      }
    }
    return null;
  }

  /// Por qué no sirve el nombre, o null si sirve. Que ya exista no frena
  /// guardar (se reemplaza, avisando); renombrar sí ([exceptoId] es el que se
  /// renombra).
  static String? problemaDelNombre(
    String nombre,
    Iterable<Predio> guardados, {
    String? exceptoId,
    bool renombrando = false,
  }) {
    final limpio = limpiar(nombre);
    if (limpio.isEmpty) return 'Escribí el nombre del predio.';
    if (limpio.length > largoMaximo) {
      return 'El nombre es muy largo: hasta $largoMaximo letras.';
    }
    if (mismoNombre(limpio, nombreDeFabrica)) {
      return '"$nombreDeFabrica" es el de fábrica: elegí otro nombre.';
    }
    if (renombrando) {
      final otro = conElNombre(limpio, guardados, exceptoId: exceptoId);
      if (otro != null) return 'Ya hay un predio "${otro.nombre}".';
    }
    return null;
  }

  /// Por qué el salón de [armado] no se puede guardar como predio, o null si
  /// se puede. Hace falta el borde del playón en cada hoja: con un armado del
  /// Canva, ACOMODAR LAS MESAS no andaría en la otra fiesta.
  static String? problemaDelSalon(ArmadoSalon armado) {
    final conBorde = armado.hojas.isNotEmpty &&
        armado.hojas.every((h) => h.contorno != null);
    if (!conBorde || ArmarAMedida.playonDe(armado) == null) {
      return 'Este armado es del Canva: para guardar un predio, armá el '
          'espacio desde Salón vacío o A medida.';
    }
    return null;
  }

  /// GUARDAR COMO PREDIO: el espacio de [armado], sin mesas, con las medidas
  /// del playón ([playon]). Si ya hay uno con ese nombre se reemplaza: queda
  /// su id, así "Volver al armado original" de las fiestas que salieron de él
  /// vuelve a este. Las fiestas que lo usaron no cambian: tienen su copia.
  static ({Predio? predio, Predio? reemplaza, String? problema}) guardarComo({
    required String nombre,
    required ArmadoSalon armado,
    required PlayonReal playon,
    required Iterable<Predio> guardados,
    required String? hechoPor,
    required DateTime ahora,
    String? idNuevo,
  }) {
    final problema =
        problemaDelNombre(nombre, guardados) ?? problemaDelSalon(armado);
    if (problema != null) {
      return (predio: null, reemplaza: null, problema: problema);
    }
    final limpio = limpiar(nombre);
    final reemplaza = conElNombre(limpio, guardados);
    final id = reemplaza?.id ?? idNuevo ?? UuidUtils.generate();
    final espacio =
        ArmarAMedida.espacioParaPredio(armado, id: id, nombre: limpio);
    final predio = reemplaza != null
        ? reemplaza.copyWith(
            nombre: limpio,
            espacio: espacio,
            playon: playon,
            hechoPor: hechoPor,
            ahora: ahora,
          )
        : Predio(
            id: id,
            nombre: limpio,
            armadoJson: jsonEncode(espacio.toJson()),
            playon: playon,
            hechoPor: hechoPor,
            createdAt: ahora,
            updatedAt: ahora,
          );
    return (predio: predio, reemplaza: reemplaza, problema: null);
  }

  /// Renombrar: cambia el nombre en la lista. Las fiestas que lo usaron no
  /// cambian.
  static ({Predio? predio, String? problema}) renombrar(
    Predio predio,
    String nombre, {
    required Iterable<Predio> guardados,
    required String? hechoPor,
    required DateTime ahora,
  }) {
    final problema = problemaDelNombre(
      nombre,
      guardados,
      exceptoId: predio.id,
      renombrando: true,
    );
    if (problema != null) return (predio: null, problema: problema);
    final limpio = limpiar(nombre);
    final espacio = predio.espacioONull;
    return (
      predio: predio.copyWith(
        nombre: limpio,
        espacio: espacio == null
            ? null
            : ArmarAMedida.espacioParaPredio(espacio, id: predio.id, nombre: limpio),
        hechoPor: hechoPor,
        ahora: ahora,
      ),
      problema: null,
    );
  }

  /// Borrar: deja de aparecer en Estilo y armado. La fila queda, marcada.
  static Predio borrar(
    Predio predio, {
    required String? hechoPor,
    required DateTime ahora,
  }) =>
      predio.copyWith(borradoAt: ahora, hechoPor: hechoPor, ahora: ahora);

  /// El salón con que arranca una fiesta que elige [predio]: su espacio, sin
  /// mesas, con la distancia entre mesas de la fiesta. Null si su espacio no
  /// se puede leer.
  static ArmadoSalon? salonDe(Predio predio, {required double lugarM}) {
    final espacio = predio.espacioONull;
    if (espacio == null) return null;
    return ArmarAMedida.desdePredio(
      espacio,
      nombre: predio.nombre,
      lugarM: lugarM,
    );
  }
}
