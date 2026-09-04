// De qué bolsa salió un egreso, sin mover un peso de lo ya registrado.
//
// Hasta ahora `categoria` hacía dos trabajos: decía QUÉ se pagó (Personal,
// Proveedores, Alquiler…) y también DE DÓNDE salió, porque la única manera de
// marcar "salió de mi bolsillo" era guardarlo como `Gasto personal` con el
// prefijo `[pendiente]`. Eso no sirve para pagarle a un operador: el pago
// dejaría de ser un pago a personal, desaparecería de LIQUIDACIÓN POR OPERADOR
// y encima inflaría el "gastado a título personal" del panel MI BOLSILLO.
//
// La columna `origen_fondos` separa el rubro de la bolsa. Lo innegociable,
// trabajando sobre producción, es que sea ADITIVA: todo lo histórico queda en
// NULL y NULL tiene que comportarse exactamente como antes. Eso es lo que
// blinda el primer grupo de tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/cierre_caja/models/turno_caja.dart';
import 'package:arguello_events/features/mi_empresa/bolsa_personal_helpers.dart';
import 'package:arguello_events/models/egreso.dart';

Egreso _egreso({
  String? categoria,
  String? proveedor,
  String? origenFondos,
  double monto = 1000,
}) {
  return Egreso(
    id: '00000000-0000-0000-0000-000000000001',
    eventoId: '',
    monto: monto,
    proveedor: proveedor,
    categoria: categoria,
    origenFondos: origenFondos,
  );
}

void main() {
  group('origen_fondos NULL — nada histórico se mueve', () {
    test('un pago a personal sigue restando del negocio', () {
      expect(
        finanzasEgresoAfectaCajaEmpresa(_egreso(categoria: 'Personal')),
        isTrue,
      );
    });

    test('un pago a proveedores sigue restando del negocio', () {
      expect(
        finanzasEgresoAfectaCajaEmpresa(_egreso(categoria: 'Proveedores')),
        isTrue,
      );
    });

    test('un gasto personal [empresa] sigue restando del negocio', () {
      final e = _egreso(
        categoria: kCategoriaGastoPersonal,
        proveedor: '$kPrefijoGastoPersonalEmpresa Supermercado',
      );
      expect(finanzasEgresoAfectaCajaEmpresa(e), isTrue);
    });

    test('un gasto personal [pendiente] sigue sin restar del negocio', () {
      final e = _egreso(
        categoria: kCategoriaGastoPersonal,
        proveedor: '$kPrefijoGastoPersonalPendiente Supermercado',
      );
      expect(finanzasEgresoAfectaCajaEmpresa(e), isFalse);
    });

    test('un gasto personal legacy sin prefijo sigue sin restar del negocio', () {
      final e = _egreso(
        categoria: kCategoriaGastoPersonal,
        proveedor: 'Supermercado',
      );
      expect(finanzasEgresoAfectaCajaEmpresa(e), isFalse);
    });

    test('un retiro del dueño sigue restando del negocio', () {
      expect(
        finanzasEgresoAfectaCajaEmpresa(_egreso(categoria: kCategoriaRetiroDueno)),
        isTrue,
      );
    });
  });

  group('origen_fondos explícito', () {
    test("'negocio' resta del negocio, igual que NULL", () {
      final conColumna = _egreso(categoria: 'Personal', origenFondos: 'negocio');
      final sinColumna = _egreso(categoria: 'Personal');
      expect(
        finanzasEgresoAfectaCajaEmpresa(conColumna),
        finanzasEgresoAfectaCajaEmpresa(sinColumna),
      );
      expect(finanzasEgresoAfectaCajaEmpresa(conColumna), isTrue);
    });

    test("'bolsillo' NO resta del negocio", () {
      // La plata ya salió del negocio el día que se retiró al bolsillo.
      // Restarla otra vez acá sería contar dos veces la misma salida.
      final e = _egreso(categoria: 'Personal', origenFondos: 'bolsillo');
      expect(finanzasEgresoAfectaCajaEmpresa(e), isFalse);
    });

    test("'bolsillo' gana sobre cualquier categoría", () {
      for (final cat in ['Personal', 'Proveedores', 'Alquiler local', 'Sueldos']) {
        expect(
          finanzasEgresoAfectaCajaEmpresa(
            _egreso(categoria: cat, origenFondos: 'bolsillo'),
          ),
          isFalse,
          reason: 'con categoría $cat',
        );
      }
    });

    test('un valor desconocido se trata como negocio, no como bolsillo', () {
      // Blindaje: si alguna vez llega basura en esa columna, el default seguro
      // es restar del negocio (el comportamiento de siempre), no dejar de
      // hacerlo — un egreso que no resta en ningún lado infla el saldo.
      final e = _egreso(categoria: 'Personal', origenFondos: 'cualquier cosa');
      expect(finanzasEgresoAfectaCajaEmpresa(e), isTrue);
    });
  });

  group('Egreso.salioDelBolsillo', () {
    test('null y vacío son false', () {
      expect(_egreso().salioDelBolsillo, isFalse);
      expect(_egreso(origenFondos: '').salioDelBolsillo, isFalse);
    });

    test('tolera espacios alrededor', () {
      expect(_egreso(origenFondos: ' bolsillo ').salioDelBolsillo, isTrue);
    });
  });
}
