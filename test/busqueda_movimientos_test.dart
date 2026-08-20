import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/models/egreso.dart';
import 'package:arguello_events/features/cierre_caja/models/turno_caja.dart';
import 'package:arguello_events/features/common/utils/texto_busqueda.dart';
import 'package:arguello_events/features/mi_empresa/widgets/panel_movimientos_sheet.dart';

/// El buscador del historial y la regla que comparten todos los buscadores.
///
/// Antes cada lista hacía su propio `contains` sobre el texto crudo: "maxi
/// operador" encontraba la fila `MAXI OPERADOR` pero "operador maxi" no
/// encontraba nada, y "anotacion" no daba con "Anotación". Dos buscadores en la
/// misma pantalla con resultados distintos según cuál usaras.
void main() {
  Egreso eg({
    required String proveedor,
    String categoria = 'Gasto empresa',
    double monto = 1000,
    String medioPago = 'efectivo',
    DateTime? fecha,
  }) =>
      Egreso(
        id: proveedor,
        eventoId: '',
        monto: monto,
        proveedor: proveedor,
        categoria: categoria,
        medioPago: medioPago,
        fecha: fecha ?? DateTime.utc(2026, 8, 11, 15),
      );

  group('coincideTextoBusqueda', () {
    test('el orden de las palabras no importa', () {
      final campos = ['MAXI OPERADOR'];
      expect(coincideTextoBusqueda(campos, 'maxi operador'), isTrue);
      expect(coincideTextoBusqueda(campos, 'operador maxi'), isTrue);
    });

    test('ignora mayúsculas y tildes', () {
      expect(coincideTextoBusqueda(['Anotación'], 'anotacion'), isTrue);
      expect(coincideTextoBusqueda(['anotacion'], 'ANOTACIÓN'), isTrue);
      expect(coincideTextoBusqueda(['Señal'], 'senal'), isTrue);
    });

    test('las palabras pueden caer en campos distintos', () {
      expect(coincideTextoBusqueda(['MAXI OPERADOR', 'Personal'], 'maxi personal'),
          isTrue);
    });

    test('pide TODAS las palabras, no cualquiera', () {
      expect(coincideTextoBusqueda(['MAXI OPERADOR'], 'maxi juan'), isFalse);
    });

    test('una consulta vacía no filtra nada', () {
      expect(coincideTextoBusqueda(['lo que sea'], ''), isTrue);
      expect(coincideTextoBusqueda(['lo que sea'], '   '), isTrue);
    });

    test('sin campos con texto no coincide con nada', () {
      expect(coincideTextoBusqueda([null, '', '  '], 'maxi'), isFalse);
    });
  });

  group('coincideBusquedaMovimiento', () {
    final maxi = eg(proveedor: 'MAXI OPERADOR', categoria: 'Personal', monto: 100000);
    final alquiler = eg(proveedor: 'ALQUILER AGOSTO', categoria: 'Alquiler local');
    final feria = eg(
      proveedor: '[pendiente] Feria',
      categoria: kCategoriaGastoPersonal,
    );

    test('encuentra el caso de siempre, escrito en cualquier orden', () {
      expect(coincideBusquedaMovimiento(maxi, 'Maxi operador'), isTrue);
      expect(coincideBusquedaMovimiento(maxi, 'operador maxi'), isTrue);
      expect(coincideBusquedaMovimiento(maxi, 'MAXI'), isTrue);
    });

    test('busca sobre el texto visible, no sobre el prefijo técnico', () {
      expect(coincideBusquedaMovimiento(feria, 'feria'), isTrue);
      // Nadie escribe "pendiente" buscando un gasto de la feria.
      expect(coincideBusquedaMovimiento(feria, 'pendiente'), isFalse);
    });

    test('encuentra por categoría y por el rubro con el que se muestra', () {
      expect(coincideBusquedaMovimiento(alquiler, 'alquiler local'), isTrue);
      // Los pagos a operadores se guardan como `Personal` pero se muestran
      // agrupados en "Operadores": buscar lo que se ve tiene que funcionar.
      expect(coincideBusquedaMovimiento(maxi, 'operadores'), isTrue);
    });

    test('encuentra por monto', () {
      expect(coincideBusquedaMovimiento(maxi, '100000'), isTrue);
      expect(coincideBusquedaMovimiento(maxi, '100.000'), isTrue);
    });

    test('NO busca por medio de pago: para eso están los chips', () {
      // Si el buscador también matcheara el medio, habría dos puertas para el
      // mismo filtro y el resultado dependería de cuál usaste.
      expect(coincideBusquedaMovimiento(maxi, 'efectivo'), isFalse);
    });

    test('no devuelve lo que no tiene que ver', () {
      expect(coincideBusquedaMovimiento(alquiler, 'maxi'), isFalse);
    });
  });

  group('fechas: el movimiento de las 21:30', () {
    // 17/08 21:30 AR es 18/08 00:30 UTC. Leyendo el UTC crudo, la app mostraba
    // el día siguiente — y el editor, al ofrecer esa fecha, corría el pago un día.
    final tardeDelDiecisiete = DateTime.utc(2026, 8, 18, 0, 30);

    test('se lee como 17/08, no como 18/08', () {
      expect(ArTime.formatFechaCorta(tardeDelDiecisiete), '17/08/2026');
      expect(ArTime.formatHora(tardeDelDiecisiete), '21:30 hs');
    });

    test('abrir y guardar sin tocar la fecha no lo mueve', () {
      final ar = ArTime.toAr(tardeDelDiecisiete);
      final guardado = ArTime.arToUtc(ar);
      expect(guardado, tardeDelDiecisiete);
    });

    test('cambiar el día conserva la hora', () {
      final ar = ArTime.toAr(tardeDelDiecisiete);
      // Lo que hace el editor: reemplaza año/mes/día y deja hora y minutos.
      final movido = DateTime(2026, 8, 20, ar.hour, ar.minute, ar.second);
      final guardado = ArTime.arToUtc(movido);

      expect(ArTime.formatFechaCorta(guardado), '20/08/2026');
      expect(ArTime.formatHora(guardado), '21:30 hs');
    });
  });
}
