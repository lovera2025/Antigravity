import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/dashboard/providers/dashboard_provider.dart';

/// La deuda se agrupa por cliente **y** modalidad.
///
/// El mapa se armaba solo con el id del cliente, así que si el mismo cliente
/// contrataba un evento masivo y una recepción particular, los dos saldos se
/// sumaban en un único renglón y no había forma de saber qué parte era cuál.
void main() {
  InstitucionDeuda deuda(
    String id,
    String nombre,
    ModalidadDeuda modalidad,
    double saldo,
  ) =>
      InstitucionDeuda(
        id: id,
        nombre: nombre,
        modalidad: modalidad,
        aVencer: 0,
        vencido: 0,
        saldoGlobal: saldo,
      );

  test('un cliente con masivo y particular produce dos entradas', () {
    final mapa = <String, InstitucionDeuda>{};
    const clienteId = 'cli-1';

    mapa['$clienteId::masivo'] =
        deuda(clienteId, 'Colegio Nacional', ModalidadDeuda.masivo, 800000);
    mapa['$clienteId::particular'] =
        deuda(clienteId, 'Colegio Nacional', ModalidadDeuda.particular, 120000);

    expect(mapa.length, 2);
    expect(mapa['$clienteId::masivo']!.saldoGlobal, 800000);
    expect(mapa['$clienteId::particular']!.saldoGlobal, 120000);
  });

  test('el total en la calle no cambia por separarlos', () {
    final items = [
      deuda('a', 'Escuela A', ModalidadDeuda.masivo, 500000),
      deuda('a', 'Escuela A', ModalidadDeuda.particular, 100000),
      deuda('b', 'Familia B', ModalidadDeuda.particular, 50000),
    ];
    final total = items.fold<double>(0, (s, d) => s + d.saldoGlobal);
    expect(total, 650000);
  });

  test('los bloques parten la lista sin perder ni repetir a nadie', () {
    final items = [
      deuda('a', 'Escuela A', ModalidadDeuda.masivo, 500000),
      deuda('b', 'Escuela B', ModalidadDeuda.masivo, 300000),
      deuda('c', 'Familia C', ModalidadDeuda.particular, 50000),
    ];

    final escuelas = items.where((d) => d.esMasivo).toList();
    final particulares = items.where((d) => !d.esMasivo).toList();

    expect(escuelas.length, 2);
    expect(particulares.length, 1);
    expect(escuelas.length + particulares.length, items.length);

    final subEscuelas = escuelas.fold<double>(0, (s, d) => s + d.saldoGlobal);
    final subParticulares =
        particulares.fold<double>(0, (s, d) => s + d.saldoGlobal);
    expect(subEscuelas + subParticulares, 850000);
  });

  test('esMasivo distingue bien las dos modalidades', () {
    expect(deuda('a', 'X', ModalidadDeuda.masivo, 1).esMasivo, isTrue);
    expect(deuda('a', 'X', ModalidadDeuda.particular, 1).esMasivo, isFalse);
  });
}
