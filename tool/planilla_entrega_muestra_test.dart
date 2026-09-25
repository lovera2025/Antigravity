// Arnés manual: genera la planilla de entrega de entradas con un evento
// inventado, para mirar el papel sin levantar la app ni tocar la base.
//
//   flutter test tool/planilla_entrega_muestra_test.dart
//   flutter test tool/planilla_entrega_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen dos PDF, en color y en blanco y negro. Lo que se mira:
//   • una hoja acostada por división, con los títulos repetidos si sigue;
//   • egresado, mesa, VIP y generales impresos;
//   • los que ya retiraron, con sus números, sus menores y el parentesco;
//   • "Debe: no entregar" y "Sin mesa: no entregar" donde corresponde;
//   • la columna del nombre siempre en blanco: la escribe quien retira;
//   • que el renglón alcance para escribir a mano.
//
// Los nombres son inventados: la muestra nunca usa datos reales.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _nombres = [
  'ACOSTA, VALENTINA', 'BENÍTEZ, JOAQUÍN', 'CASTRO, MÍA', 'DOMÍNGUEZ, BRUNO',
  'ESPÍNDOLA, CAMILA', 'FERREYRA, LUCAS', 'GÓMEZ, SOFÍA', 'HERRERA, TOMÁS',
  'IBARRA, MARTINA', 'JUÁREZ, NICOLÁS', 'LEDESMA, CATALINA', 'MOLINA, SANTIAGO',
  'NÚÑEZ, AGUSTINA', 'ORTIZ, MATEO', 'PAREDES, EMILIA', 'QUIROGA, FACUNDO',
  'RAMÍREZ, LUCÍA', 'SOSA, IGNACIO', 'TORRES, PAULINA', 'VEGA, THIAGO',
];

ContratoAlumno _alumno(int i, String curso) {
  final extras = i % 6 == 0 ? 1 : 0;
  final sillas = i % 4 == 0 ? 2 : 0;
  final mesa = i + 1;
  final debe = i % 9 == 4;
  return ContratoAlumno(
    id: 'a$i',
    eventoId: 'muestra',
    nombreAlumno: '${_nombres[i % _nombres.length]}${i >= _nombres.length ? ' ${i ~/ _nombres.length}' : ''}',
    cantidadAcompanantes: i % 3 == 0 ? 2 : (i % 3 == 1 ? 1 : 0),
    nombresAcompanantes: const [],
    montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
    saldoDeudor: debe ? 33333.33 : 0,
    totalCuotas: 9,
    cuotasPagadas: debe ? 8 : 9,
    mesaExtraPrecio: 70000.0 * extras,
    mesaExtraCantidad: extras,
    sillasExtraCantidad: sillas,
    sillasExtraPrecioTotal: 8000.0 * sillas,
    cursoDivision: curso,
    numeroMesa: i == 7
        ? null
        : MesasExtraUtils.formatearAsignacionMesas(
            extras > 0 ? [mesa * 2, mesa * 2 + 1] : [mesa * 2],
          ),
    createdAt: DateTime(2026, 2, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final destino = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('planilla_entrega').path;

  test('planilla de entrega — dos divisiones, con entregas, deudas y sin mesa',
      () async {
    final alumnos = [
      for (var i = 0; i < 26; i++) _alumno(i, '5° A'),
      for (var i = 26; i < 44; i++) _alumno(i, '5° B'),
    ];
    final deudas = {
      for (final a in alumnos)
        a.id: RetiroEntradas.deudaDe(
          a,
          pagos: [
            {
              'monto': a.montoTotalPactado - a.saldoDeudor,
              'monto_gross': a.montoTotalPactado - a.saldoDeudor,
              'concepto': 'Cuota Base',
              'anulado': 0,
            },
          ],
          moraCobradaHistorial: 0,
          ahoraAr: DateTime(2026, 11, 20),
        ),
    };

    // Retiraron los primeros de cada división que podían.
    final retiros = <String, EntradasRetiro>{};
    var siguiente = 1001;
    for (final a in alumnos) {
      if (retiros.length >= 8) break;
      if (RetiroEntradas.bloqueo(a, deudas[a.id]!) != BloqueoRetiro.ninguno) {
        continue;
      }
      if (int.parse(a.id.substring(1)) % 5 != 0) continue;
      final e = RetiroEntradas.entradasDe(a);
      retiros[a.id] = RetiroEntradas.nuevaEntrega(
        alumno: a,
        entradas: e,
        tramos: [TramoTalonario(siguiente, siguiente + e.generales - 1)],
        menores10: retiros.length % 3,
        parentesco: ParentescoRetiro.values[retiros.length % 6],
        nombre: 'Familiar De Prueba',
        quien: 'Operador',
        ahora: DateTime.utc(2026, 11, 12, 21, 40),
      );
      siguiente += e.generales;
    }

    final evento = Evento(
      id: 'muestra',
      clienteId: 'c',
      tipo: 'Recepción',
      fechaEvento: DateTime(2026, 12, 5),
      estado: EstadoEvento.planificacion,
      modalidad: 'masivo',
      cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE MUESTRA'),
    );

    for (final bn in [false, true]) {
      final bytes = await PdfService.construirPlanillaEntregaPdf(
        evento,
        alumnos,
        retiros: retiros,
        deudas: deudas,
        blancoYNegro: bn,
        generada: DateTime(2026, 11, 12, 21, 30),
      );
      final nombre = 'Planilla_Entrega_MUESTRA${bn ? '_BN' : ''}.pdf';
      final archivo = File('$destino${Platform.pathSeparator}$nombre')
        ..writeAsBytesSync(bytes);
      stdout.writeln('── PDF en: ${archivo.path}');
      expect(archivo.lengthSync(), greaterThan(1000));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
